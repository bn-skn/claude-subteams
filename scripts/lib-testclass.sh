#!/usr/bin/env bash
# shellcheck disable=SC2034  # TC_* globals are the library interface, read by the sourcing script
# lib-testclass.sh — shared rules for project test suites (sourced, never executed).
# Sourced by scripts/discover-tests.sh, hooks/pre-commit-gate and (Task 5)
# hooks/subagent-rails. Sourcing has no side effects: it only defines TC_* values
# and tc_* functions, sets no shell options and runs no commands.
#
# What lives here (one place of truth, IMPL-PLAN 1.50.0 §5.2-§5.4):
#   - docs-class (TC_NEUTRAL_RE + prose formats) — shared with the review gate;
#   - contract v1 reader (CLAUDE.md wins over AGENTS.md; marker only at column 0
#     and outside fenced code blocks; `none` marker = declined);
#   - glob matching (`**` aware) and file classification into ui/code/test/docs
#     and per-suite groups;
#   - git trees: index tree and working-tree snapshot via a TEMP index (the real
#     index is never written), changed files, drift (numstat + A/D/R/binary);
#   - receipt store: ${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/receipts/
#     <sha1 of canonical git-common-dir>/, atomic writes, purge after 14 days;
#   - the receipt predicates the commit gate reuses (suite receipt valid for a
#     tree; ui/te receipt + evidence + drift within the small-change threshold).
# Requirements: bash (3.2-compatible syntax), git, coreutils; jq for anything that
# parses JSON (tc_contract_marker works without it — the gate's cheap path).
# Globs: rooted at the repo root (git `:(glob)` semantics): `*`/`?` never cross
# `/`; `**/` = zero or more dirs; trailing `/**` = everything inside; `{a,b}`
# alternation (not nested). File names containing a newline are not supported.

TC_MAX_BYTES=1048576          # 1 MB cap for any project file we read
TC_MAX_LINES=10               # built-in small-change ceiling (R9); contract may only lower it
TC_MAX_FILES=2
TC_RECEIPT_TTL_DAYS=14

# Docs-class (moved from hooks/pre-commit-gate, behaviour unchanged): neutral
# repo metadata / lockfiles at the ROOT, .DS_Store anywhere, and prose/data text
# formats (.md always; .txt/.csv/.rst/.adoc — operator decision 15.07). Not
# docs: .html (site code), .yaml/.json (behaviour-bearing configs). Exception
# inside .txt: requirements/constraints .txt are dependency manifests.
TC_NEUTRAL_RE='^(\.gitignore|\.editorconfig|\.gitattributes|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|go\.sum|poetry\.lock|uv\.lock|composer\.lock)$|(^|/)\.DS_Store$'
TC_DOCS_EXT_RE='\.(md|txt|csv|rst|adoc)$'
TC_REQ_TXT_RE='(^|/)[^/]*(requirements|constraints)[^/]*\.txt$'   # matched case-insensitively

# Defaults for projects without a contract (and for --init-contract drafts).
TC_DEFAULT_UI_GLOBS='["**/*.html","**/*.htm","**/*.css","**/*.scss","**/*.sass","**/*.less","**/*.vue","**/*.svelte","**/*.astro","**/*.jsx","**/*.tsx"]'
TC_DEFAULT_TEST_GLOBS='["**/*.test.*","**/*.spec.*","**/test/**","**/tests/**","**/__tests__/**","**/e2e/**","**/*_test.go","**/test_*.py","**/*_test.py"]'
TC_DEFAULT_CODE_GLOBS='["**/*.ts","**/*.mts","**/*.cts","**/*.js","**/*.mjs","**/*.cjs","**/*.py","**/*.go","**/*.rs","**/*.java","**/*.kt","**/*.rb","**/*.php","**/*.cs","**/*.swift","**/*.c","**/*.h","**/*.cc","**/*.cpp","**/*.sh"]'

TC_ERR=""
TC_WARN=""                    # non-fatal note for the caller to print (e.g. a skipped symlink)

# ---------------------------------------------------------------- small utils

tc_sha1() { # stdin -> lowercase hex sha1
  if command -v sha1sum >/dev/null 2>&1; then sha1sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 1 | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl sha1 | sed 's/^.*= *//'
  else return 1; fi
}

tc_realpath() { # <path> -> canonical absolute path (path must exist)
  local p="$1" d b n=0 l
  if command -v realpath >/dev/null 2>&1; then realpath "$p" 2>/dev/null && return 0; fi
  readlink -f "$p" 2>/dev/null && return 0
  while [ -L "$p" ] && [ "$n" -lt 40 ]; do          # manual fallback (old macOS)
    l=$(readlink -- "$p") || return 1
    case "$l" in /*) p="$l" ;; *) p="$(dirname -- "$p")/$l" ;; esac
    n=$((n+1))
  done
  d=$(cd -P -- "$(dirname -- "$p")" 2>/dev/null && pwd) || return 1
  b=$(basename -- "$p")
  case "$b" in .|..) (cd -P -- "$d/$b" && pwd) ;; *) printf '%s/%s\n' "${d%/}" "$b" ;; esac
}

tc_inside_root() { # <root> <path> -> 0 if the path resolves to root or below it
  local r p
  r=$(tc_realpath "$1") || return 1
  p=$(tc_realpath "$2") || return 1
  [ "$p" = "$r" ] && return 0
  case "$p" in "${r%/}"/*) return 0 ;; esac
  return 1
}

tc_safe_file() { # <root> <path> -> 0 if a regular file inside root and <= 1 MB; else 1 + TC_ERR
  local size
  [ -f "$2" ] || { TC_ERR="$2: not a regular file"; return 1; }
  tc_inside_root "$1" "$2" || { TC_ERR="$2: resolves outside the project root (symlink), not read"; return 1; }
  size=$(wc -c < "$2" | tr -d ' ')
  [ "${size:-0}" -le "$TC_MAX_BYTES" ] || { TC_ERR="$2: larger than 1 MB, not read"; return 1; }
  return 0
}

# ----------------------------------------------------------------- docs-class

tc_is_docs_class() { # <path> -> 0 if neutral metadata or prose (review/test gates skip it)
  local f="$1" had=0 rc=0
  [[ $f =~ $TC_NEUTRAL_RE ]] && return 0
  [[ $f =~ $TC_DOCS_EXT_RE ]] || return 1
  shopt -q nocasematch && had=1
  shopt -s nocasematch
  [[ $f =~ $TC_REQ_TXT_RE ]] && rc=1
  [ "$had" -eq 1 ] || shopt -u nocasematch
  return "$rc"
}

# ---------------------------------------------------------------------- globs

tc_glob_to_ere() { # <glob> -> TC_RE (anchored ERE)
  local g="$1" out="" i=0 n c prev nxt brace=0
  n=${#g}
  while [ "$i" -lt "$n" ]; do
    c="${g:$i:1}"
    case "$c" in
      '*')
        if [ "${g:$i:2}" = "**" ]; then
          prev=""; [ "$i" -gt 0 ] && prev="${g:$((i-1)):1}"
          nxt="${g:$((i+2)):1}"
          if { [ "$i" -eq 0 ] || [ "$prev" = / ]; } && [ "$nxt" = / ]; then
            out="$out(.*/)?"; i=$((i+3)); continue          # **/  or  /**/
          elif { [ "$i" -eq 0 ] || [ "$prev" = / ]; } && [ $((i+2)) -eq "$n" ]; then
            out="$out.*"; i=$((i+2)); continue              # trailing /**  or bare **
          fi
          out="${out}[^/]*"; i=$((i+2)); continue             # a**b behaves like a*b
        fi
        out="${out}[^/]*" ;;
      '?') out="${out}[^/]" ;;
      '{') out="$out("; brace=$((brace+1)) ;;
      '}') if [ "$brace" -gt 0 ]; then out="$out)"; brace=$((brace-1)); else out="$out\\}"; fi ;;
      ',') if [ "$brace" -gt 0 ]; then out="$out|"; else out="$out,"; fi ;;
      [.+\(\)\|^\$\[\]\\]) out="$out\\$c" ;;
      *) out="$out$c" ;;
    esac
    i=$((i+1))
  done
  while [ "$brace" -gt 0 ]; do out="$out)"; brace=$((brace-1)); done
  TC_RE="^${out}\$"
}

tc_globs_re() { # <glob>... -> TC_RE (alternation of all; "" when no globs = matches nothing)
  local acc="" g
  for g in "$@"; do
    [ -n "$g" ] || continue
    tc_glob_to_ere "$g"; acc="${acc:+$acc|}($TC_RE)"
  done
  TC_RE="$acc"
}

tc_re_match() { # <string> <re>; empty re never matches
  [ -n "$2" ] && [[ $1 =~ $2 ]]
}

# ------------------------------------------------------------- contract v1

# awk state machine over a markdown file. Output: first line = state
# (v1 | none | absent | error:no-fence | error:unclosed), then (full mode, v1)
# the fenced JSON body. Fences: ``` or ~~~ (>= 3, up to 3 leading spaces),
# closed by the same char with >= the opening length — so a 4-backtick fence
# around a documentation example hides the marker inside it.
# shellcheck disable=SC2016  # awk program, $0 etc. are awk's
TC_CONTRACT_AWK='
function isopen(line,   s, i, c, k) {
  s = line; i = 0
  while (i < 3 && substr(s, 1, 1) == " ") { s = substr(s, 2); i++ }
  c = substr(s, 1, 1)
  if (c != "`" && c != "~") return 0
  k = 0; while (substr(s, k + 1, 1) == c) k++
  if (k < 3) return 0
  if (c == "`" && index(substr(s, k + 1), "`") > 0) return 0
  FCH = c; FLEN = k; return 1
}
function isclose(line,   s, i, k) {
  s = line; i = 0
  while (i < 3 && substr(s, 1, 1) == " ") { s = substr(s, 2); i++ }
  k = 0; while (substr(s, k + 1, 1) == FCH) k++
  if (k < FLEN) return 0
  return (substr(s, k + 1) ~ /^[ \t]*$/)
}
BEGIN { st = "absent"; body = ""; done = 0; infence = 0; mode_await = 0; injson = 0 }
done { next }
{ sub(/\r$/, "") }
injson { if (isclose($0)) { st = "v1"; done = 1; next } body = body $0 "\n"; next }
mode_await {
  if ($0 ~ /^[ \t]*$/) next
  if (isopen($0)) { injson = 1; mode_await = 0; next }
  st = "error:no-fence"; done = 1; next
}
infence { if (isclose($0)) infence = 0; next }
isopen($0) { infence = 1; next }
/^<!-- subteams:test-suites v1 -->[ \t]*$/ {
  if (mode == "marker") { st = "v1"; done = 1; next }
  mode_await = 1; next
}
/^<!-- subteams:test-suites none -->[ \t]*$/ { st = "none"; done = 1; next }
END {
  if (!done && injson) st = "error:unclosed"
  if (!done && mode_await) st = "error:no-fence"
  print st
  if (st == "v1" && mode != "marker") printf "%s", body
}'

# Validates the contract body and prints the normalized form (defaults filled,
# small_change clamped to the built-in ceiling). Errors -> jq error() message.
# shellcheck disable=SC2016  # jq program
TC_CONTRACT_JQ='
def strarr($k):
  if has($k) then
    (.[$k] | if type == "array" and all(.[]; type == "string" and length > 0 and (test("[\t\n\r]") | not))
             then . else error("\($k) must be an array of non-empty strings") end)
  else null end;
def relok: type == "string" and length > 0 and (startswith("/") | not) and all(split("/")[]; . != "..")
  and (explode | all(. >= 32 and . != 127));
def suite:
  if type != "object" then error("each suite must be an object") else . end
  | if (.name | type) != "string" then error("suite name must be a string")
    elif (.name | test("^[A-Za-z0-9_@][A-Za-z0-9_.:/@+~-]*$") | not) then error("suite name has unsafe characters (allowed: letters, digits, _ . : / @ + ~ -): \(.name)")
    else . end
  | if (.cmd | type) != "string" or (.cmd | length) == 0 then error("suite \(.name): cmd must be a non-empty string")
    elif (.cmd | explode | any(. < 32 or . == 127)) then error("suite \(.name): cmd must be one line without control characters")
    else . end
  | if has("cwd") and ((.cwd | relok) | not) then error("suite \(.name): cwd must be a relative path without ..") else . end
  | if has("run") and ((.run | IN("auto","opt-in","live")) | not) then error("suite \(.name): run must be auto|opt-in|live") else . end
  | if has("kind") and ((.kind | IN("unit","integration","e2e")) | not) then error("suite \(.name): kind must be unit|integration|e2e") else . end
  | {name, cmd, cwd: (.cwd // "."), kind: (.kind // "unit"), run: (.run // "auto"),
     paths: strarr("paths"), source: "contract"};
def lim($k; $max):
  if has($k) then (.[$k] | if type == "number" and . >= 0 and . == floor then [., $max] | min
                          else error("small_change.\($k) must be a non-negative integer") end)
  else $max end;
if length != 1 then error("expected exactly one JSON value in the contract block") else .[0] end
| if type != "object" then error("contract must be a JSON object") else . end
| if has("suites") and (.suites | type) != "array" then error("suites must be an array") else . end
| ([(.suites // [])[] | suite]) as $s
| if ([$s[].name] | length) != ([$s[].name] | unique | length) then error("suite names must be unique") else . end
| if has("app") and (.app | type) != "object" then error("app must be an object") else . end
| if has("app") and (.app | has("start")) and ((.app.start | IN("playwright-webServer","none")) | not)
    then error("app.start must be playwright-webServer|none") else . end
| if has("app") and (.app | has("url")) and ((.app.url | type) != "string" or (.app.url | test("^https?://") | not))
    then error("app.url must be an http(s) URL") else . end
| if has("small_change") and (.small_change | type) != "object" then error("small_change must be an object") else . end
| {suites: $s,
   ui_globs: (strarr("ui_globs") // []), ui_exclude: (strarr("ui_exclude") // []),
   code_globs: strarr("code_globs"), test_globs: (strarr("test_globs") // []),
   app: (.app // null),
   small_change: ((.small_change // {}) | {max_lines: lim("max_lines"; $ml), max_files: lim("max_files"; $mf)}),
   small_change_clamped: ((.small_change // {}) | ((.max_lines // 0) > $ml or (.max_files // 0) > $mf))}'

tc__contract_text() { # <root> <head|index|worktree> <name> -> TC__TEXT; rc 0 found, 1 absent, 2 unsafe/oversized
  # Runs in the caller's shell (not in $(…)) so TC_ERR / TC_WARN reach the caller.
  local root="$1" src="$2" name="$3" spec size
  TC__TEXT=""
  case "$src" in
    head|index)
      [ "$src" = head ] && spec="HEAD:$name" || spec=":0:$name"
      [ "$(git -C "$root" cat-file -t "$spec" 2>/dev/null)" = blob ] || return 1
      size=$(git -C "$root" cat-file -s "$spec" 2>/dev/null) || return 1
      [ "$size" -le "$TC_MAX_BYTES" ] || { TC_ERR="$name ($src) is larger than 1 MB"; return 2; }
      TC__TEXT=$(git -C "$root" cat-file blob "$spec") || return 1 ;;
    worktree)
      [ -e "$root/$name" ] || [ -L "$root/$name" ] || return 1
      if ! tc_inside_root "$root" "$root/$name"; then   # e.g. a symlink into dotfiles: not read
        TC_WARN="$name resolves outside the project root (symlink) — not read"; return 1
      fi
      tc_safe_file "$root" "$root/$name" || return 2
      TC__TEXT=$(cat -- "$root/$name") || return 2 ;;
    *) TC_ERR="unknown contract source: $src"; return 2 ;;
  esac
}

# tc_contract_marker <root> <head|index|worktree> — cheap path, NO jq (awk only).
# Prints v1 | none | absent | error and returns 0 | 4 | 1 | 2. "v1" only says a
# marker is present; it does not validate the JSON (tc_contract_load does).
tc_contract_marker() {
  local root="$1" src="$2" name text rc st
  for name in CLAUDE.md AGENTS.md; do
    tc__contract_text "$root" "$src" "$name"; rc=$?; text="$TC__TEXT"
    [ "$rc" -eq 1 ] && continue
    [ "$rc" -eq 0 ] || { echo error; return 2; }
    st=$(printf '%s\n' "$text" | awk -v mode=marker "$TC_CONTRACT_AWK")
    case "$st" in
      v1) echo v1; return 0 ;;
      none) echo none; return 4 ;;
      error*) echo error; return 2 ;;
    esac
  done
  echo absent; return 1
}

# tc_contract_load <root> <head|index|worktree>
# Sets TC_CONTRACT_STATE (v1|none|absent|error), TC_CONTRACT_FILE, TC_CONTRACT_JSON
# (normalized, compact), TC_CONTRACT_SHA (sha1 of the canonical raw JSON), TC_ERR.
# Returns 0 v1, 1 absent, 4 declined (`none`), 2 malformed/unsafe, 3 jq missing.
# CLAUDE.md wins: its marker (v1, none or broken) never falls through to AGENTS.md.
tc_contract_load() {
  local root="$1" src="$2" name text rc out st body norm raw
  TC_CONTRACT_STATE=absent; TC_CONTRACT_FILE=""; TC_CONTRACT_JSON=""; TC_CONTRACT_SHA=""; TC_ERR=""
  for name in CLAUDE.md AGENTS.md; do
    tc__contract_text "$root" "$src" "$name"; rc=$?; text="$TC__TEXT"
    [ "$rc" -eq 1 ] && continue
    if [ "$rc" -ne 0 ]; then TC_CONTRACT_STATE=error; TC_CONTRACT_FILE="$name"; return 2; fi
    out=$(printf '%s\n' "$text" | awk -v mode=full "$TC_CONTRACT_AWK"; echo x); out="${out%x}"
    st="${out%%$'\n'*}"; body="${out#*$'\n'}"
    case "$st" in
      absent) continue ;;
      none) TC_CONTRACT_STATE=none; TC_CONTRACT_FILE="$name"; return 4 ;;
      error:*)
        TC_CONTRACT_STATE=error; TC_CONTRACT_FILE="$name"
        TC_ERR="$name ($src): contract marker is not followed by a closed fenced JSON block (${st#error:})"
        return 2 ;;
    esac
    TC_CONTRACT_FILE="$name"
    if ! command -v jq >/dev/null 2>&1; then
      TC_CONTRACT_STATE=error; TC_ERR="jq is required to read the test contract in $name"; return 3
    fi
    if ! norm=$(printf '%s' "$body" | jq -cs --argjson ml "$TC_MAX_LINES" --argjson mf "$TC_MAX_FILES" "$TC_CONTRACT_JQ" 2>&1); then
      TC_CONTRACT_STATE=error
      TC_ERR="$name ($src): invalid test contract: $(printf '%s\n' "$norm" | head -1 | sed 's/^jq: error ([^)]*): //')"
      return 2
    fi
    raw=$(printf '%s' "$body" | jq -cS . 2>/dev/null)
    TC_CONTRACT_JSON="$norm"; TC_CONTRACT_SHA=$(printf '%s' "$raw" | tc_sha1)
    TC_CONTRACT_STATE=v1
    return 0
  done
  return 1
}

tc_cmd_sha() { # <cwd> <cmd> -> sha1 binding a suite receipt to the exact command + cwd
  printf '%s\n%s' "$1" "$2" | tc_sha1
}

tc_threshold() { # <config json> -> TC_TH_LINES TC_TH_FILES (never above the built-in ceiling)
  local v
  v=$(printf '%s' "$1" | jq -r --argjson ml "$TC_MAX_LINES" --argjson mf "$TC_MAX_FILES" \
      '[([(.small_change.max_lines // $ml), $ml] | min), ([(.small_change.max_files // $mf), $mf] | min)] | @tsv' 2>/dev/null)
  TC_TH_LINES="${v%%$'\t'*}"; TC_TH_FILES="${v#*$'\t'}"
  case "$TC_TH_LINES$TC_TH_FILES" in ''|*[!0-9]*) TC_TH_LINES=$TC_MAX_LINES; TC_TH_FILES=$TC_MAX_FILES ;; esac
}

# ------------------------------------------------------------- classification

# tc_groups_load <config json> — config = normalized contract, or the heuristic
# object {suites, ui_globs, ui_exclude, test_globs, code_globs:null}. Compiles
# every glob once. Sets TC_RE_UI, TC_RE_UIX, TC_RE_TEST, TC_RE_CODE,
# TC_HAS_CODE_GLOBS and per-suite TC_S_NAME[i] TC_S_ANY[i] TC_S_RUN[i]
# TC_S_KIND[i] TC_S_RE[i] (index = position in .suites). Returns 1 on bad JSON.
tc_groups_load() {
  local lines k a b c d e i gl
  local ui=() uix=() te=() co=()
  TC_RE_UI=""; TC_RE_UIX=""; TC_RE_TEST=""; TC_RE_CODE=""; TC_HAS_CODE_GLOBS=0
  TC_S_NAME=(); TC_S_ANY=(); TC_S_RUN=(); TC_S_KIND=(); TC_S_RE=(); TC__S_GLOBS=()
  lines=$(printf '%s' "$1" | jq -r '
    ((.ui_globs // [])[] | "ui\t\(.)"),
    ((.ui_exclude // [])[] | "uix\t\(.)"),
    ((.test_globs // [])[] | "test\t\(.)"),
    (if .code_globs == null then "hascode\t0" else ("hascode\t1", (.code_globs[] | "code\t\(.)")) end),
    ((.suites // []) | to_entries[] | .key as $i | .value
      | ("suite\t\($i)\t\(.name)\t\(if .paths == null then 1 else 0 end)\t\(.run // "auto")\t\(.kind // "unit")"),
        ((.paths // [])[] | "spath\t\($i)\t\(.)"))' 2>/dev/null) || return 1
  while IFS=$'\t' read -r k a b c d e; do
    case "$k" in
      ui) ui+=("$a") ;;
      uix) uix+=("$a") ;;
      test) te+=("$a") ;;
      code) co+=("$a") ;;
      hascode) TC_HAS_CODE_GLOBS="$a" ;;
      suite) TC_S_NAME[a]="$b"; TC_S_ANY[a]="$c"; TC_S_RUN[a]="$d"; TC_S_KIND[a]="$e"; TC__S_GLOBS[a]="" ;;
      spath) TC__S_GLOBS[a]="${TC__S_GLOBS[a]:-}${TC__S_GLOBS[a]:+$'\037'}$b" ;;
    esac
  done <<< "$lines"
  tc_globs_re ${ui[@]+"${ui[@]}"};   TC_RE_UI="$TC_RE"
  tc_globs_re ${uix[@]+"${uix[@]}"}; TC_RE_UIX="$TC_RE"
  tc_globs_re ${te[@]+"${te[@]}"};   TC_RE_TEST="$TC_RE"
  tc_globs_re ${co[@]+"${co[@]}"};   TC_RE_CODE="$TC_RE"
  for i in ${TC_S_NAME[@]+"${!TC_S_NAME[@]}"}; do
    IFS=$'\037' read -r -a gl <<< "${TC__S_GLOBS[i]:-}"
    tc_globs_re ${gl[@]+"${gl[@]}"}; TC_S_RE[i]="$TC_RE"
  done
  return 0
}

# tc_classify <path> — sets TC_C_DOCS TC_C_TEST TC_C_UI TC_C_CODE (0/1).
#   test = test_globs; ui = ui_globs − ui_exclude − test; code = code_globs − test,
#   or (no code_globs) non-docs files outside ui_globs and test_globs.
tc_classify() {
  local f="$1" inui=0
  TC_C_DOCS=0; TC_C_TEST=0; TC_C_UI=0; TC_C_CODE=0; TC__C_FILE="$f"
  tc_is_docs_class "$f" && TC_C_DOCS=1
  tc_re_match "$f" "$TC_RE_TEST" && TC_C_TEST=1
  tc_re_match "$f" "$TC_RE_UI" && inui=1
  if [ "$TC_C_TEST" -eq 0 ]; then
    [ "$inui" -eq 1 ] && ! tc_re_match "$f" "$TC_RE_UIX" && TC_C_UI=1
    if [ "$TC_HAS_CODE_GLOBS" = 1 ]; then
      tc_re_match "$f" "$TC_RE_CODE" && TC_C_CODE=1
    elif [ "$TC_C_DOCS" -eq 0 ] && [ "$inui" -eq 0 ]; then
      TC_C_CODE=1
    fi
  fi
  return 0
}

tc_in_suite() { # <path> <suite index> -> 0 if the file makes the suite required (no paths: any non-docs file)
  if [ "${TC_S_ANY[$2]:-0}" = 1 ]; then
    if [ "${TC__C_FILE:-}" = "$1" ]; then [ "$TC_C_DOCS" -eq 0 ]; else ! tc_is_docs_class "$1"; fi
  else tc_re_match "$1" "${TC_S_RE[$2]:-}"; fi
}

tc_in_group() { # <path> <ui|code|test|docs|suite:N>
  case "$2" in
    suite:*) tc_in_suite "$1" "${2#suite:}"; return ;;
  esac
  tc_classify "$1"
  case "$2" in
    ui) [ "$TC_C_UI" -eq 1 ] ;; code) [ "$TC_C_CODE" -eq 1 ] ;;
    test) [ "$TC_C_TEST" -eq 1 ] ;; docs) [ "$TC_C_DOCS" -eq 1 ] ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------------------ git trees

tc_has_head() { git -C "$1" rev-parse --verify -q 'HEAD^{commit}' >/dev/null 2>&1; }

tc_empty_tree() { git -C "$1" hash-object -t tree --stdin </dev/null 2>/dev/null; }

tc_is_tree() { [ -n "$2" ] && git -C "$1" cat-file -e "$2^{tree}" 2>/dev/null; }

tc__index_path() { # <repo> -> absolute path of this worktree's index
  local p
  p=$(git -C "$1" rev-parse --git-path index 2>/dev/null) || return 1
  case "$p" in /*) printf '%s\n' "$p" ;; *) printf '%s/%s\n' "$1" "$p" ;; esac
}

# tc_index_tree <repo> — tree of the real index (what `git commit` would record),
# computed on a COPY so the real index (and its lock) is never touched.
tc_index_tree() {
  local repo="$1" tmp real rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/tc-idx.XXXXXX") || return 1
  real=$(tc__index_path "$repo") || { rm -rf "$tmp"; return 1; }
  if [ -f "$real" ]; then cp "$real" "$tmp/index" || { rm -rf "$tmp"; return 1; }; fi
  GIT_INDEX_FILE="$tmp/index" git -C "$repo" write-tree 2>/dev/null; rc=$?
  rm -rf "$tmp"; return "$rc"
}

# tc_snapshot_tree <repo> — git tree of the WORKING TREE (new, deleted, renamed
# files; .gitignore respected) via a temp index: start from a copy of the real
# index (or `read-tree HEAD` when there is none), then `add -A`, `write-tree`.
# Why a copy and not always `read-tree HEAD`: the copy keeps force-added ignored
# files and skip-worktree (sparse) entries, exactly as the commit tree will, and
# reuses the stat cache (no rehash of every file).
# Writes blob/tree objects into the repo's object store; never writes the index.
tc_snapshot_tree() {
  local repo="$1" tmp real rc
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/tc-snap.XXXXXX") || return 1
  real=$(tc__index_path "$repo") || { rm -rf "$tmp"; return 1; }
  if [ -f "$real" ]; then
    cp "$real" "$tmp/index" || { rm -rf "$tmp"; return 1; }
    # assume-unchanged entries would hide on-disk edits from `add -A`: clear the
    # bit in the COPY (skip-worktree stays: sparse files absent on disk are not deletions).
    GIT_INDEX_FILE="$tmp/index" git -C "$repo" ls-files -v -z 2>/dev/null \
      | while IFS= read -r -d '' e; do case "$e" in [a-z]' '*) printf '%s\0' "${e#? }" ;; esac; done \
      | GIT_INDEX_FILE="$tmp/index" git -C "$repo" update-index -z --no-assume-unchanged --stdin >/dev/null 2>&1
  elif tc_has_head "$repo"; then
    GIT_INDEX_FILE="$tmp/index" git -C "$repo" read-tree HEAD 2>/dev/null || { rm -rf "$tmp"; return 1; }
  fi
  GIT_INDEX_FILE="$tmp/index" git -C "$repo" add -A >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$tmp/index" git -C "$repo" write-tree 2>/dev/null
  rc=$?
  rm -rf "$tmp"; return "$rc"
}

tc_changed_files() { # <repo> <tree-ish a> <tree-ish b> -> paths that differ (renames as delete+add)
  git -c core.quotePath=false -C "$1" diff --name-only --no-renames -z "$2" "$3" -- 2>/dev/null | tr '\0' '\n'
  return "${PIPESTATUS[0]}"
}

# tc_drift <repo> <tree a> <tree b> <group> — accumulated drift of one group.
# Sets TC_DRIFT_LINES (added+deleted), TC_DRIFT_FILES, TC_DRIFT_ADDED,
# TC_DRIFT_DELETED, TC_DRIFT_RENAMED, TC_DRIFT_BINARY (0/1). rc 1 = git error.
tc_drift() {
  local repo="$1" a="$2" b="$3" grp="$4" st p1 p2 rec ad dl
  TC_DRIFT_LINES=0; TC_DRIFT_FILES=0; TC_DRIFT_ADDED=0; TC_DRIFT_DELETED=0; TC_DRIFT_RENAMED=0; TC_DRIFT_BINARY=0
  tc_is_tree "$repo" "$a" && tc_is_tree "$repo" "$b" || return 1
  while IFS= read -r -d '' st; do
    case "$st" in
      R*|C*)
        IFS= read -r -d '' p1; IFS= read -r -d '' p2
        if tc_in_group "$p1" "$grp" || tc_in_group "$p2" "$grp"; then TC_DRIFT_RENAMED=1; fi ;;
      *)
        IFS= read -r -d '' p1
        tc_in_group "$p1" "$grp" || continue
        case "$st" in A) TC_DRIFT_ADDED=1 ;; D) TC_DRIFT_DELETED=1 ;; esac ;;
    esac
  done < <(git -C "$repo" diff --name-status -M -z "$a" "$b" -- 2>/dev/null)
  while IFS= read -r -d '' rec; do
    ad="${rec%%$'\t'*}"; rec="${rec#*$'\t'}"; dl="${rec%%$'\t'*}"; p1="${rec#*$'\t'}"
    tc_in_group "$p1" "$grp" || continue
    TC_DRIFT_FILES=$((TC_DRIFT_FILES+1))
    if [ "$ad" = - ] || [ "$dl" = - ]; then TC_DRIFT_BINARY=1; else TC_DRIFT_LINES=$((TC_DRIFT_LINES+ad+dl)); fi
  done < <(git -C "$repo" diff --numstat --no-renames -z "$a" "$b" -- 2>/dev/null)
  return 0
}

tc_drift_json() { # prints the last tc_drift result as JSON
  printf '{"lines":%s,"files":%s,"added":%s,"deleted":%s,"renamed":%s,"binary":%s}\n' \
    "$TC_DRIFT_LINES" "$TC_DRIFT_FILES" \
    "$([ "$TC_DRIFT_ADDED" -eq 1 ] && echo true || echo false)" "$([ "$TC_DRIFT_DELETED" -eq 1 ] && echo true || echo false)" \
    "$([ "$TC_DRIFT_RENAMED" -eq 1 ] && echo true || echo false)" "$([ "$TC_DRIFT_BINARY" -eq 1 ] && echo true || echo false)"
}

# ------------------------------------------------------------------- receipts

tc_repo_id() { # <repo> -> sha1 of the canonical git-common-dir (worktrees of one repo share it)
  local gcd
  gcd=$(cd "$1" 2>/dev/null && d=$(git rev-parse --git-common-dir 2>/dev/null) && cd -P -- "$d" 2>/dev/null && pwd) || return 1
  [ -n "$gcd" ] || return 1
  printf '%s' "$gcd" | tc_sha1
}

tc_receipt_dir() { # <repo> -> receipt directory (not created)
  local id
  id=$(tc_repo_id "$1") || return 1
  [ -n "$id" ] || return 1
  printf '%s/claude-subteams/receipts/%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}" "$id"
}

tc_receipt_purge() { # <receipt dir> — drop receipts (and stray temp files) older than 14 days
  find "$1" -maxdepth 1 -type f \( -name '*.json' -o -name '.tmp*' \) -mtime +"$TC_RECEIPT_TTL_DAYS" -exec rm -f {} + 2>/dev/null
  return 0
}

# tc_receipt_write <repo> <json object with .type> — atomic (temp file + mv in the
# same dir), then purge. Sets TC_RECEIPT_PATH and prints it; on failure rc 1 +
# TC_ERR (call it directly, not inside $(…), to keep TC_ERR).
tc_receipt_write() {
  local repo="$1" json="$2" dir type ts name tmp
  TC_RECEIPT_PATH=""
  dir=$(tc_receipt_dir "$repo") || { TC_ERR="not a git repository: $repo"; return 1; }
  type=$(printf '%s' "$json" | jq -r 'if type == "object" and (.type | type) == "string" and (.type | test("^[a-z][a-z0-9_-]*$")) then .type else empty end' 2>/dev/null)
  [ -n "$type" ] || { TC_ERR="receipt must be a JSON object with a simple .type"; return 1; }
  (umask 077; mkdir -p -- "$dir") 2>/dev/null || { TC_ERR="cannot create $dir"; return 1; }
  ts=$(date +%s)
  name=$(printf '%010d-%s-%s-%s.json' "$ts" "$type" "$$" "$RANDOM")
  tmp=$(mktemp "$dir/.tmp.XXXXXX") || { TC_ERR="cannot write in $dir"; return 1; }
  if printf '%s\n' "$json" > "$tmp" && mv -f -- "$tmp" "$dir/$name"; then
    tc_receipt_purge "$dir"
    TC_RECEIPT_PATH="$dir/$name"
    printf '%s\n' "$dir/$name"
    return 0
  fi
  rm -f -- "$tmp"; TC_ERR="cannot write receipt in $dir"; return 1
}

tc_receipt_list() { # <repo> -> receipt file paths, one per line (unsorted)
  local dir f
  dir=$(tc_receipt_dir "$1") || return 1
  [ -d "$dir" ] || return 0
  for f in "$dir"/*.json; do [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f"; done
  return 0
}

tc_receipt_read() { # <file> -> its JSON (compact) or rc 1
  [ -f "$1" ] && [ ! -L "$1" ] && jq -ce 'select(type == "object")' "$1" 2>/dev/null
}

# tc_receipts_load <repo> -> JSON lines (one receipt per line, plus ._file).
# Receipt kind = .type; a shot receipt written without .type but with
# "kind":"shot" is normalized to type "shot".
tc_receipts_load() {
  local files=() f out
  while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(tc_receipt_list "$1")
  [ "${#files[@]}" -gt 0 ] || return 0
  local prog='select(type == "object") | (if (.type == null and .kind == "shot") then .type = "shot" else . end) | . + {_file: input_filename}'
  if out=$(jq -c "$prog" "${files[@]}" 2>/dev/null); then
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
  fi
  for f in "${files[@]}"; do jq -c "$prog" "$f" 2>/dev/null; done
  return 0
}

# --------------------------------------------------------- receipt predicates

# tc_suite_check <repo> <receipts jsonl file> <tree> <suite index> <contract_sha> <cmd_sha>
# The NEWEST receipt of this suite that ran the same command (cmd_sha) under the
# same contract (contract_sha), was not dirty and whose tree has the same content
# as <tree> for the suite's files decides: exit 0 -> valid. Sets TC_SC_OK (0/1),
# TC_SC_REASON, TC_SC_FILE. Requires tc_groups_load.
tc_suite_check() {
  local repo="$1" rfile="$2" tree="$3" i="$4" csha="$5" msha="$6"
  local name="${TC_S_NAME[$4]}" te ex dirty rc rm rt f n=0 why="" diff p hit
  TC_SC_OK=0; TC_SC_REASON="no receipt for suite $name"; TC_SC_FILE=""
  while IFS=$'\037' read -r te ex dirty rc rm rt f; do
    [ -n "$f" ] || continue
    n=$((n+1)); [ "$n" -le 30 ] || break
    if [ "$rc" != "$csha" ]; then why="${why:-receipt is for another version of the test contract}"; continue; fi
    if [ "$rm" != "$msha" ]; then why="${why:-receipt ran a different command}"; continue; fi
    if [ "$dirty" = 1 ]; then why="${why:-files changed while the suite ran (dirty)}"; continue; fi
    tc_is_tree "$repo" "$rt" || { why="${why:-receipt tree missing}"; continue; }
    diff=$(tc_changed_files "$repo" "$rt" "$tree") || { why="${why:-git diff failed}"; continue; }
    hit=0
    while IFS= read -r p; do [ -n "$p" ] && tc_in_suite "$p" "$i" && { hit=1; break; }; done <<< "$diff"
    if [ "$hit" -eq 1 ]; then why="${why:-content changed since the last run ($p)}"; continue; fi
    TC_SC_FILE="$f"
    if [ "$ex" = 0 ]; then TC_SC_OK=1; TC_SC_REASON="passed on this content"
    else TC_SC_REASON="last run on this content failed (exit $ex)"; fi
    return 0
  done < <(jq -r --arg n "$name" 'select(.type == "suite" and .suite == $n)
      | [(.t_end // 0 | tostring), (.exit // "" | tostring), (if .dirty == true then "1" else "0" end),
         (.contract_sha // ""), (.cmd_sha // ""), (.tree // ""), ._file] | join("\u001f")' "$rfile" 2>/dev/null \
      | sort -t "$(printf '\037')" -k1,1nr)
  [ -n "$why" ] && TC_SC_REASON="$why"
  return 0
}

# tc_agent_check <repo> <receipts jsonl> <tree> <ui|code> <th_lines> <th_files> <e2e_req 0|1> <head tree>
# Requires tc_groups_load. Evidence is judged here, at check time, from the
# receipts written during the agent's [t_start, t_end] (a status alone is never
# believed):
#   ui pass      >= 2 shots AND, if <e2e_req> (a `run: auto` e2e suite whose paths
#                cover a UI file of this commit — computed by tc_requirements),
#                >= 1 e2e suite receipt with exit 0;
#   ui degraded  ONLY with a required e2e suite (<e2e_req> = 1) that has an e2e
#                receipt with exit 0 in the interval, AND the agent stated why the
#                live review was not performed (.reason_stated, recorded by
#                hooks/subagent-rails). No required e2e -> degraded never counts
#                (nothing was checked; that is `blocked` in substance);
#   te pass      >= 1 suite receipt with exit 0;
#   issues-found a negative verdict: valid as it is, and it shadows older passes.
# Not valid (skipped, never shadow a valid receipt): pass/degraded without that
# evidence (e.g. a monkey-mode pass), blocked / unknown statuses, receipts without
# a sane interval.
# Drift base (R9, accumulated) = the NEWEST of {the most recent valid agent
# receipt, the group's anchor}. An anchor (type `anchor`, group, tree = HEAD's tree
# at that time) is written by the commit gate when a group first passes under the
# small-change threshold WITHOUT any agent receipt; later small commits do not move
# it, so a series of small commits still runs into the threshold. Neither receipt
# nor anchor -> the base is <head tree> and, if the change is small, TC_AC_ANCHOR
# is set to that tree (the gate writes it on allow; `status` only reports it).
# Residual: anchors are purged after 14 days like every receipt — a series spread
# over more than 14 days restarts from HEAD.
# Then: drift from the base to <tree> within the threshold, no added/deleted/
# renamed/binary files. Sets TC_AC_OK, TC_AC_REASON, TC_AC_FILE, TC_AC_STATUS,
# TC_AC_BASE (receipt|anchor|head), TC_AC_ANCHOR (tree to anchor, or "") + TC_DRIFT_*.
# Reasons never name the threshold numbers.
tc_agent_check() {
  local repo="$1" rfile="$2" tree="$3" grp="$4" thl="$5" thf="$6" e2e_req="${7:-0}" htree="${8:-}" type who i auto=0
  local st rt f e2e suites shots rs ts te n=0 skipped="" chosen=0 okst=0 base cte=0 v at ats af
  if [ "$grp" = ui ]; then type=ui; who="ui-tester"; else type=te; who="test-engineer"; fi
  for i in ${TC_S_NAME[@]+"${!TC_S_NAME[@]}"}; do [ "${TC_S_RUN[i]:-}" = auto ] && auto=1; done
  TC_AC_OK=0; TC_AC_REASON=""; TC_AC_FILE=""; TC_AC_STATUS=""; TC_AC_BASE=""; TC_AC_ANCHOR=""
  while IFS=$'\037' read -r st rt f e2e suites shots rs ts te; do
    [ -n "$f" ] || continue
    n=$((n+1)); [ "$n" -le 30 ] || break
    if [ "$ts" -le 0 ] || [ "$te" -lt "$ts" ]; then skipped="${skipped:-a $who receipt without a valid time interval}"; continue; fi
    case "$type:$st" in
      ui:pass)
        if [ "$shots" -ge 2 ] && { [ "$e2e_req" -eq 0 ] || [ "$e2e" -ge 1 ]; }; then okst=1
        else skipped="${skipped:-a $who pass without evidence (needs >= 2 screenshots$([ "$e2e_req" -eq 1 ] && echo ' and a run of the e2e suite covering these UI files with exit 0') during its run) does not count}"; continue; fi ;;
      ui:degraded)
        if [ "$e2e_req" -eq 1 ] && [ "$e2e" -ge 1 ] && [ "$rs" = 1 ]; then okst=1
        elif [ "$e2e_req" -eq 0 ]; then skipped="${skipped:-a $who degraded result does not count when no required e2e suite covers these UI files (nothing was checked — screenshots are the only evidence, so it needs a pass)}"; continue
        else skipped="${skipped:-a $who degraded result without a run of the covering e2e suite with exit 0 or without a stated reason does not count}"; continue; fi ;;
      te:pass)
        if [ "$suites" -ge 1 ]; then okst=1
        else skipped="${skipped:-a $who pass without a suite run with exit 0 during its run does not count}"; continue; fi ;;
      ui:issues-found|te:issues-found) okst=0 ;;
      *) skipped="${skipped:-a $who run without a verdict (status '$st') does not count}"; continue ;;
    esac
    chosen=1; cte="$te"; break
  done < <(jq -rs --arg t "$type" '
      [.[] | select(.type == "suite" and .exit == 0)] as $ok
      | [.[] | select(.type == "shot")] as $shots
      | [.[] | select(.type == $t)] | sort_by(.t_end // 0) | reverse | .[:30][]
      | ((.t_start // 0) | if type == "number" then floor else 0 end) as $s
      | ((.t_end // 0) | if type == "number" then floor else 0 end) as $e
      | def inside: ((.t_start // 0) >= $s and (.t_end // 0) <= $e);
        [(.status // "" | tostring), (.tree // "" | tostring), ._file,
         ([$ok[] | select(.kind == "e2e" and inside)] | length | tostring),
         ([$ok[] | select(inside)] | length | tostring),
         ([$shots[] | select((.ts // 0) >= $s and (.ts // 0) <= $e)] | length | tostring),
         (if .reason_stated == true then "1" else "0" end), ($s | tostring), ($e | tostring)]
        | join("\u001f")' "$rfile" 2>/dev/null)
  v=$(jq -rs --arg g "$grp" '[.[] | select(.type == "anchor" and .group == $g and (.tree | type) == "string")]
        | sort_by(.ts // 0) | last // empty | [.tree, ((.ts // 0) | floor | tostring), ._file] | join("\u001f")' "$rfile" 2>/dev/null)
  at=""; ats=0; af=""
  [ -n "$v" ] && IFS=$'\037' read -r at ats af <<< "$v"
  if [ "$chosen" -eq 1 ] && { [ -z "$at" ] || [ "$cte" -ge "$ats" ]; }; then
    TC_AC_STATUS="$st"; TC_AC_FILE="$f"; base="$rt"; TC_AC_BASE=receipt
    [ "$okst" -eq 1 ] || TC_AC_REASON="the latest $who verdict on this work is issues-found — fix and re-run $who"
  elif [ -n "$at" ]; then
    base="$at"; TC_AC_BASE=anchor; TC_AC_FILE="$af"; okst=1
  else
    base="${htree:-$(tc_empty_tree "$repo")}"; TC_AC_BASE="head"; okst=1
  fi
  tc_drift "$repo" "$base" "$tree" "$grp" || { TC_AC_REASON="${TC_AC_REASON:-cannot compare with the last $who check / anchor (its tree is missing) — run $who}"; TC_AC_OK=0; return 0; }
  [ "$okst" -eq 1 ] || return 0
  if [ "$TC_DRIFT_ADDED$TC_DRIFT_DELETED$TC_DRIFT_RENAMED$TC_DRIFT_BINARY" != 0000 ] \
     || [ "$TC_DRIFT_LINES" -gt "$thl" ] || [ "$TC_DRIFT_FILES" -gt "$thf" ]; then
    if [ "$TC_AC_BASE" = receipt ]; then
      TC_AC_REASON="changed since the $who check beyond the small-change threshold (counted from that check, across commits; added/deleted/renamed/binary files always count) — re-run $who"
    else
      TC_AC_REASON="no valid $who check of this content and the change is not small (counted from the $([ "$TC_AC_BASE" = anchor ] && echo 'anchor of the last small changes, across commits' || echo 'last commit')${skipped:+; $skipped}) — run $who"
    fi
    if [ "$type" = te ] && [ "$auto" -eq 0 ]; then
      TC_AC_REASON="$TC_AC_REASON. NOTE: the config has no run:auto suite, so test-engineer cannot produce evidence (a suite run with exit 0) — add a suite to the contract"
    fi
    return 0
  fi
  TC_AC_OK=1
  case "$TC_AC_BASE" in
    receipt) TC_AC_REASON="checked (drift within the small-change threshold)" ;;
    anchor) TC_AC_REASON="small change since the anchor (accumulated across commits, within the threshold)" ;;
    head) TC_AC_REASON="small change, no $who check needed (an anchor is created on commit)"; TC_AC_ANCHOR="$base" ;;
  esac
  return 0
}

# ------------------------------------------------------- config + requirements

# tc_config_resolve <repo> — the contract `run`, `status`, the commit gate and
# subagent-rails use: HEAD first; no contract in HEAD -> the STAGED one ("new
# contract" mode: checked, but the gate only warns). The working tree never counts.
# Sets TC_CFG_STATE (v1 | new | declined | none), TC_CFG_JSON, TC_CFG_SHA (none
# without a contract), TC_CFG_FILE, TC_CFG_WHERE (head|index — where it was read /
# broke). Returns 0 contract (v1/new), 1 none/declined (the caller falls back to
# discovery heuristics), 2 broken or unsafe (TC_ERR), 3 jq missing (TC_ERR).
tc_config_resolve() {
  local repo="$1" rc
  TC_CFG_STATE=none; TC_CFG_JSON=""; TC_CFG_SHA=none; TC_CFG_FILE=""; TC_CFG_WHERE="head"
  tc_contract_load "$repo" head; rc=$?
  case "$rc" in
    0) TC_CFG_STATE=v1; TC_CFG_JSON="$TC_CONTRACT_JSON"; TC_CFG_SHA="$TC_CONTRACT_SHA"; TC_CFG_FILE="$TC_CONTRACT_FILE"; return 0 ;;
    4) TC_CFG_STATE=declined; TC_CFG_FILE="$TC_CONTRACT_FILE"; return 1 ;;
    2|3) TC_CFG_FILE="$TC_CONTRACT_FILE"; return "$rc" ;;
  esac
  TC_CFG_WHERE=index
  tc_contract_load "$repo" index; rc=$?
  case "$rc" in
    0) TC_CFG_STATE=new; TC_CFG_JSON="$TC_CONTRACT_JSON"; TC_CFG_SHA="$TC_CONTRACT_SHA"; TC_CFG_FILE="$TC_CONTRACT_FILE"; return 0 ;;
    2|3) TC_CFG_FILE="$TC_CONTRACT_FILE"; return "$rc" ;;
  esac
  return 1
}

tc_bool() { [ "$1" -eq 1 ] && echo true || echo false; }

# tc_requirements <repo> <tree> <base tree-ish> <config json> <contract_sha>
# THE decision — one place for the commit gate (hooks/pre-commit-gate enforces it
# with a contract, warns without) and `subteams-tests status` (reports it).
# Files = diff <base>..<tree>. Required:
#   - every `run: auto` suite with a touched file (its paths; no paths = any
#     non-docs file): a valid suite receipt for exactly this content (tc_suite_check);
#     opt-in / live suites are never required;
#   - ui-tester when the ui group is touched, test-engineer when the code group is
#     (tc_agent_check: evidence + accumulated drift).
# Sets TC_REQ_OK (1 = nothing missing), TC_REQ_MISSING (one item per line; no
# threshold numbers), TC_REQ_JSON ({tree, base, files, suites, agents, ok,
# missing}). rc 1 = could not evaluate (TC_ERR) — callers with a contract deny.
tc_requirements() {
  local repo="$1" tree="$2" base="$3" cfg="$4" csha="$5"
  local flist rfile i name req f v cwd cmd msha rows="" uit=0 cot=0 ag_ui ag_te files_json e2e_req=0 htree warns=""
  TC_REQ_OK=0; TC_REQ_MISSING=""; TC_REQ_JSON=""; TC_REQ_ANCHORS=""; TC_REQ_WARN=""
  tc_is_tree "$repo" "$tree" || { TC_ERR="not a tree: $tree"; return 1; }
  flist=$(tc_changed_files "$repo" "$base" "$tree") || { TC_ERR="git diff $base..$tree failed"; return 1; }
  tc_groups_load "$cfg" || { TC_ERR="cannot read the suites/globs of the test config"; return 1; }
  rfile=$(mktemp "${TMPDIR:-/tmp}/tc-req.XXXXXX") || { TC_ERR="cannot create a temp file"; return 1; }
  tc_receipts_load "$repo" > "$rfile"
  tc_threshold "$cfg"
  htree=$(git -C "$repo" rev-parse "$base^{tree}" 2>/dev/null) || htree=$(tc_empty_tree "$repo")
  if [ "$(printf '%s' "$cfg" | jq -r '.small_change_clamped // false' 2>/dev/null)" = true ]; then
    TC_REQ_WARN="small_change in the test contract is above the built-in ceiling — clamped to $TC_MAX_LINES lines / $TC_MAX_FILES files"
  fi
  TC_REQ_OK=1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    tc_classify "$f"; [ "$TC_C_CODE" -eq 1 ] && cot=1
    [ "$TC_C_UI" -eq 1 ] || continue
    uit=1
    # e2e evidence is required only from a run:auto e2e suite that covers a UI file
    # of THIS commit (no paths = covers everything) — otherwise ui-tester honestly
    # not running an unrelated suite would loop forever.
    if [ "$e2e_req" -eq 0 ]; then
      for i in ${TC_S_NAME[@]+"${!TC_S_NAME[@]}"}; do
        [ "${TC_S_KIND[i]}" = e2e ] && [ "${TC_S_RUN[i]}" = auto ] && tc_in_suite "$f" "$i" && { e2e_req=1; break; }
      done
    fi
  done <<< "$flist"
  for i in ${TC_S_NAME[@]+"${!TC_S_NAME[@]}"}; do
    name="${TC_S_NAME[i]}"; req=false
    while IFS= read -r f; do [ -n "$f" ] && tc_in_suite "$f" "$i" && { req=true; break; }; done <<< "$flist"
    if [ "${TC_S_RUN[i]}" != auto ]; then
      rows="$rows$(jq -nc --arg n "$name" --arg r "${TC_S_RUN[i]}" --argjson q "$req" '{name: $n, run: $r, required: false, touched: $q, ok: null, reason: "\($r): not required by the gate"}')"$'\n'
      continue
    fi
    if [ "$req" = false ]; then
      rows="$rows$(jq -nc --arg n "$name" '{name: $n, run: "auto", required: false, touched: false, ok: null, reason: "not affected by these changes"}')"$'\n'
      continue
    fi
    v=$(printf '%s' "$cfg" | jq -r --argjson i "$i" '.suites[$i] | [(.cwd // "."), .cmd] | join("\u001f")')
    IFS=$'\037' read -r cwd cmd <<< "$v"
    msha=$(tc_cmd_sha "$cwd" "$cmd")
    tc_suite_check "$repo" "$rfile" "$tree" "$i" "$csha" "$msha"
    rows="$rows$(jq -nc --arg n "$name" --argjson ok "$(tc_bool "$TC_SC_OK")" --arg why "$TC_SC_REASON" --arg f "$TC_SC_FILE" \
      '{name: $n, run: "auto", required: true, touched: true, ok: $ok, reason: $why, receipt: (if $f == "" then null else $f end)}')"$'\n'
    if [ "$TC_SC_OK" -ne 1 ]; then
      TC_REQ_OK=0; TC_REQ_MISSING="$TC_REQ_MISSING${TC_REQ_MISSING:+$'\n'}suite $name: $TC_SC_REASON — run: subteams-tests run $name"
    fi
  done
  tc__req_agent "$repo" "$rfile" "$tree" ui "$uit" "$e2e_req" "$htree"; ag_ui="$TC__AG_JSON"
  [ "$TC_AC_OK" -eq 1 ] || { TC_REQ_OK=0; TC_REQ_MISSING="$TC_REQ_MISSING${TC_REQ_MISSING:+$'\n'}ui-tester: $TC_AC_REASON"; }
  [ -n "${TC_AC_ANCHOR:-}" ] && TC_REQ_ANCHORS="${TC_REQ_ANCHORS}ui $TC_AC_ANCHOR"$'\n'
  tc__req_agent "$repo" "$rfile" "$tree" code "$cot" 0 "$htree"; ag_te="$TC__AG_JSON"
  [ "$TC_AC_OK" -eq 1 ] || { TC_REQ_OK=0; TC_REQ_MISSING="$TC_REQ_MISSING${TC_REQ_MISSING:+$'\n'}test-engineer: $TC_AC_REASON"; }
  [ -n "${TC_AC_ANCHOR:-}" ] && TC_REQ_ANCHORS="${TC_REQ_ANCHORS}code $TC_AC_ANCHOR"$'\n'
  rm -f "$rfile"
  files_json=$(printf '%s\n' "$flist" | jq -R . | jq -sc 'map(select(length > 0))')
  TC_REQ_JSON=$(printf '%s' "$rows" | jq -sc --arg tree "$tree" --arg base "$base" --argjson files "$files_json" \
    --argjson ui "$ag_ui" --argjson te "$ag_te" --argjson ok "$(tc_bool "$TC_REQ_OK")" --arg missing "$TC_REQ_MISSING" \
    --arg warn "$TC_REQ_WARN" \
    '{tree: $tree, base: $base, files: $files, suites: ., agents: {"ui-tester": $ui, "test-engineer": $te}, ok: $ok,
      missing: ($missing | split("\n") | map(select(length > 0))), warnings: (if $warn == "" then [] else [$warn] end)}') || { TC_ERR="cannot build the requirements JSON"; return 1; }
  return 0
}

# tc__req_agent <repo> <rfile> <tree> <ui|code> <touched 0/1> -> TC__AG_JSON,
# TC_AC_OK / TC_AC_REASON (runs in the caller's shell: call it directly, not in $(…)).
tc__req_agent() { # … <e2e_req> <head tree>
  TC_AC_ANCHOR=""
  if [ "$5" -eq 0 ]; then TC_AC_OK=1; TC_AC_REASON=""; TC__AG_JSON='{"touched":false,"ok":null}'; return 0; fi
  tc_agent_check "$1" "$2" "$3" "$4" "$TC_TH_LINES" "$TC_TH_FILES" "$6" "$7"
  TC__AG_JSON=$(jq -nc --argjson ok "$(tc_bool "$TC_AC_OK")" --arg why "$TC_AC_REASON" --arg st "$TC_AC_STATUS" \
    --arg f "$TC_AC_FILE" --argjson drift "$(tc_drift_json)" --arg b "$TC_AC_BASE" --arg anc "$TC_AC_ANCHOR" \
    --argjson e2e "$(tc_bool "$6")" \
    '{touched: true, ok: $ok, reason: $why, status: (if $st == "" then null else $st end),
      receipt: (if $f == "" then null else $f end), drift_base: $b, drift: $drift,
      anchor_on_commit: (if $anc == "" then null else $anc end)}
     + (if $e2e then {e2e_required: true} else {} end)')
}

# tc_anchor_write <repo> <ui|code> <tree> — the drift anchor (see tc_agent_check).
# Written ONLY by the commit gate when it allows a commit (TC_REQ_ANCHORS).
tc_anchor_write() {
  local now; now=$(date +%s)
  tc_receipt_write "$1" "{\"type\":\"anchor\",\"group\":\"$2\",\"tree\":\"$3\",\"ts\":$now,\"t_end\":$now}" >/dev/null
}
