#!/usr/bin/env bash
# shellcheck disable=SC2034  # TC_* globals are the library interface, read by the sourcing script
# lib-testclass.sh — shared rules for project test suites (sourced, never executed).
# Sourced by scripts/discover-tests.sh, hooks/pre-commit-gate, hooks/subagent-rails,
# hooks/session-start (and bin/subteams-browser for shot receipts: tc_receipt_write). Sourcing has no side effects: it only defines TC_* values
# and tc_* functions, sets no shell options and runs no commands.
#
# What lives here (one place of truth, IMPL-PLAN 1.50.0 §5.2-§5.4):
#   - docs-class (TC_NEUTRAL_RE + prose formats) — shared with the review gate;
#   - contract v1 reader (CLAUDE.md wins over AGENTS.md; marker only at column 0
#     and outside fenced code blocks; `none` marker = declined);
#   - glob matching (`**` aware) and file classification into ui/code/test/docs
#     and per-suite groups;
#   - git trees: index tree and working-tree snapshot via a TEMP index (the real
#     index is never written), changed files, drift (A/D/R/binary + line counts of
#     the group's files; files untracked at receipt time ignored), unstaged files;
#   - the commit tree a `git commit` statement will record (tc_ct_*: -a, <paths>,
#     -o, -i, replayed add/rm — on a temp index; used by hooks/lib-commitscan.sh);
#   - receipt store: <tc_cache_root>/claude-subteams/receipts/
#     <sha1 of canonical git-common-dir>/, atomic writes, purge after 14 days, and
#     the global recent index _recent.log (which store got which receipt when);
#   - the receipt predicates the commit gate reuses (suite receipt valid for a
#     tree, flaky detection; ui/te receipt + evidence + minimal drift within the
#     small-change threshold, branch-bound anchors), all batched per evaluation.
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

tc__contract_text() { # <root> <head|index|worktree|rev:REV> <name> -> TC__TEXT; rc 0 found, 1 absent, 2 unsafe/oversized
  # Runs in the caller's shell (not in $(…)) so TC_ERR / TC_WARN reach the caller.
  # rev:REV — the contract of a given commit (the gate reads HEAD^ for --amend).
  local root="$1" src="$2" name="$3" spec size
  TC__TEXT=""
  case "$src" in
    head|index|rev:?*)
      case "$src" in head) spec="HEAD:$name" ;; index) spec=":0:$name" ;; *) spec="${src#rev:}:$name" ;; esac
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
#   Without code_globs, a file in ui_globs with a script extension (logic inside a
#   component: TC_UI_SCRIPT_RE) is BOTH ui and code — it needs test-engineer too;
#   pure markup / styles stay ui only.
TC_UI_SCRIPT_RE='\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte|astro)$'
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
    elif [ "$TC_C_DOCS" -eq 0 ] && { [ "$inui" -eq 0 ] || [[ $f =~ $TC_UI_SCRIPT_RE ]]; }; then
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
tc_index_tree() (               # subshell body: its own trap removes the temp dir on a kill
  repo="$1"; tmp=""
  trap '[ -n "$tmp" ] && rm -rf "$tmp"' EXIT; trap 'exit 143' TERM; trap 'exit 130' INT
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/tc-idx.XXXXXX") || exit 1
  real=$(tc__index_path "$repo") || exit 1
  if [ -f "$real" ]; then cp "$real" "$tmp/index" || exit 1; fi
  GIT_INDEX_FILE="$tmp/index" git -C "$repo" write-tree 2>/dev/null
)

# tc_snapshot_tree <repo> — git tree of the WORKING TREE (new, deleted, renamed
# files; .gitignore respected) via a temp index: start from a copy of the real
# index (or `read-tree HEAD` when there is none), then `add -A`, `write-tree`.
# Why a copy and not always `read-tree HEAD`: the copy keeps force-added ignored
# files and skip-worktree (sparse) entries, exactly as the commit tree will, and
# reuses the stat cache (no rehash of every file).
# Writes blob/tree objects into the repo's object store; never writes the index.
tc_snapshot_tree() (            # subshell body: its own trap removes the temp dir on a kill
  repo="$1"; tmp=""
  trap '[ -n "$tmp" ] && rm -rf "$tmp"' EXIT; trap 'exit 143' TERM; trap 'exit 130' INT
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/tc-snap.XXXXXX") || exit 1
  real=$(tc__index_path "$repo") || exit 1
  if [ -f "$real" ]; then
    cp "$real" "$tmp/index" || exit 1
    # assume-unchanged entries would hide on-disk edits from `add -A`: clear the
    # bit in the COPY (skip-worktree stays: sparse files absent on disk are not deletions).
    GIT_INDEX_FILE="$tmp/index" git -C "$repo" ls-files -v -z 2>/dev/null \
      | while IFS= read -r -d '' e; do case "$e" in [a-z]' '*) printf '%s\0' "${e#? }" ;; esac; done \
      | GIT_INDEX_FILE="$tmp/index" git -C "$repo" update-index -z --no-assume-unchanged --stdin >/dev/null 2>&1
  elif tc_has_head "$repo"; then
    GIT_INDEX_FILE="$tmp/index" git -C "$repo" read-tree HEAD 2>/dev/null || exit 1
  fi
  GIT_INDEX_FILE="$tmp/index" git -C "$repo" add -A >/dev/null 2>&1 \
    && GIT_INDEX_FILE="$tmp/index" git -C "$repo" write-tree 2>/dev/null
)

# tc_tmp_cleanup — removes the temp dirs an evaluation in THIS shell may hold (the
# commit-tree temp index, the requirements work dir). Callers (the commit gate)
# trap it on EXIT / INT / TERM so a hook killed by its timeout leaves nothing.
tc_tmp_cleanup() {
  [ -n "${TC_CT_DIR:-}" ] && rm -rf "$TC_CT_DIR"; TC_CT_DIR=""
  [ -n "${TC__WORK:-}" ] && rm -rf "$TC__WORK"; TC__WORK=""
  return 0
}

tc_changed_files() { # <repo> <tree-ish a> <tree-ish b> -> paths that differ (renames as delete+add)
  git -c core.quotePath=false -C "$1" diff --name-only --no-renames -z "$2" "$3" -- 2>/dev/null | tr '\0' '\n'
  return "${PIPESTATUS[0]}"
}

# Files that were only UNTRACKED when a receipt was taken (the snapshot includes
# every non-ignored file of the working tree; the commit tree does not) must not
# count as changes: only paths present in the commit tree or in the base (HEAD)
# tree matter. tc_dcommit_set <repo> <base tree> <commit tree> records the files
# the commit itself deletes (D base->commit); a path missing from the commit tree
# is relevant only if it is in that set. Without a set (TC__DFILTER=0) nothing is
# filtered. Accepted residual: tests ran with the extra untracked files present.
TC__DFILTER=0; TC__WORK=""
# Per-evaluation work dir (tc_requirements creates and removes it): the D-set
# (dcommit) and per-group membership caches (memb.<group>: "<0|1>\t<path>"), so
# each path is classified in bash once per evaluation, however many candidate
# receipts are compared; the per-candidate work is git + awk.
tc_dcommit_set() { # <repo> <base tree> <commit tree>; rc 1 = git error (filter off)
  local tmp
  TC__DFILTER=0
  [ -n "$TC__WORK" ] && [ -d "$TC__WORK" ] || return 1
  tmp="$TC__WORK/dcommit.z"
  git -c core.quotePath=false -C "$1" diff --name-only --no-renames --diff-filter=D -z "$2" "$3" -- > "$tmp" 2>/dev/null || return 1
  tr '\0' '\n' < "$tmp" > "$TC__WORK/dcommit" || return 1
  TC__DFILTER=1
}

tc__memb_file() { # <group> -> path of its membership cache (created empty if needed)
  local f
  if [ -n "$TC__WORK" ] && [ -d "$TC__WORK" ]; then f="$TC__WORK/memb.${1//[!A-Za-z0-9]/_}"
  else f=$(mktemp "${TMPDIR:-/tmp}/tc-memb.XXXXXX") || return 1; fi
  if [ ! -f "$f" ]; then
    # paths claimed by another live instance (tc_requirements: TC__WORK/foreign) are
    # outside every group: they are not part of this commit and do not count
    if [ -n "$TC__WORK" ] && [ -s "$TC__WORK/foreign" ]; then awk '{ print "0\t" $0 }' "$TC__WORK/foreign" > "$f"; else : > "$f"; fi
  fi
  printf '%s\n' "$f"
}
tc__memb_ensure() { # <group> <paths file, one per line> <memb file> — classify the paths not seen yet
  local p
  awk -v mf="$3" 'FILENAME == mf { seen[substr($0, 3)] = 1; next }
    !($0 in seen) { seen[$0] = 1; print }' "$3" "$2" \
  | while IFS= read -r p; do
      if tc_in_group "$p" "$1"; then printf '1\t%s\n' "$p"; else printf '0\t%s\n' "$p"; fi
    done >> "$3"
}

# tc_drift <repo> <tree a> <tree b> <group> [<max files>] — accumulated drift of one group.
# Sets TC_DRIFT_LINES (added+deleted), TC_DRIFT_FILES, TC_DRIFT_ADDED,
# TC_DRIFT_DELETED, TC_DRIFT_RENAMED, TC_DRIFT_BINARY (0/1). rc 1 = git error:
# git output goes to temp files and its exit code is checked (a failure inside a
# process substitution used to be lost and read as "no drift"); callers treat
# rc 1 as "not small" (fail-closed). Paths only present in <a> that the commit
# does not delete are ignored (tc_dcommit_set); a "rename" from such a path is an
# addition. Line counts (the expensive part: a blob diff) are computed only for
# the group's files. With <max files>, a drift that is already NOT small by its
# file set (added/deleted/renamed, or more files than that) returns at once with
# TC_DRIFT_CAPPED=1 and TC_DRIFT_LINES=0 — for ranking candidate receipts.
# Requires tc_groups_load.
tc_drift() {
  local repo="$1" a="$2" b="$3" grp="$4" cap="${5:-}" tmp memb dc=/dev/null v p
  local -a P
  TC_DRIFT_CAPPED=0; TC_DRIFT_LINES=0; TC_DRIFT_FILES=0; TC_DRIFT_ADDED=0; TC_DRIFT_DELETED=0; TC_DRIFT_RENAMED=0; TC_DRIFT_BINARY=0
  tc_is_tree "$repo" "$a" && tc_is_tree "$repo" "$b" || return 1
  tmp=$(mktemp -d "${TC__WORK:-${TMPDIR:-/tmp}}/tc-drift.XXXXXX") || return 1
  if ! git -c core.quotePath=false -C "$repo" diff --name-status -M -z "$a" "$b" -- > "$tmp/ns" 2>/dev/null \
     || ! tr '\0' '\n' < "$tmp/ns" > "$tmp/ns.l"; then
    rm -rf "$tmp"; return 1
  fi
  memb=$(tc__memb_file "$grp") || { rm -rf "$tmp"; return 1; }
  awk 'w == 0 { w = ($0 ~ /^[RC]/) ? 2 : 1; next } { print; w-- }' "$tmp/ns.l" > "$tmp/paths"
  tc__memb_ensure "$grp" "$tmp/paths" "$memb"
  [ "$TC__DFILTER" = 1 ] && dc="$TC__WORK/dcommit"
  # first line: "<added> <deleted> <renamed> <files>"; then the group's files to line-count
  v=$(awk -v filt="$TC__DFILTER" -v dcf="$dc" -v mf="$memb" '
    FILENAME == dcf { d[$0] = 1; next }
    FILENAME == mf { m[substr($0, 3)] = substr($0, 1, 1); next }
    {
      if (want == 0) { st = $0; want = (st ~ /^[RC]/) ? 2 : 1; got = 0; next }
      p[++got] = $0; if (got < want) next
      want = 0; c = substr(st, 1, 1)
      if (c == "R" || c == "C") {
        old = (c == "R" && filt == 1 && !(p[1] in d)) ? 0 : 1      # 0: the old path was merely untracked
        if (!old) { if (m[p[2]] == "1") { ad = 1; out[++n] = p[2] } }
        else if (m[p[1]] == "1" || m[p[2]] == "1") {
          rn = 1
          if (c == "R" && m[p[1]] == "1") out[++n] = p[1]
          if (m[p[2]] == "1") out[++n] = p[2]
        }
        next
      }
      if (c == "D" && filt == 1 && !(p[1] in d)) next
      if (m[p[1]] != "1") next
      if (c == "A") ad = 1; else if (c == "D") de = 1
      out[++n] = p[1]
    }
    END { printf "%d %d %d %d\n", ad, de, rn, n; for (i = 1; i <= n; i++) print out[i] }' "$dc" "$memb" "$tmp/ns.l") \
    || { rm -rf "$tmp"; [ -n "$TC__WORK" ] || rm -f "$memb"; return 1; }
  [ -n "$TC__WORK" ] || rm -f "$memb"
  read -r TC_DRIFT_ADDED TC_DRIFT_DELETED TC_DRIFT_RENAMED TC_DRIFT_FILES <<< "${v%%$'\n'*}"
  [ -n "$TC_DRIFT_FILES" ] || { rm -rf "$tmp"; return 1; }
  if [ -n "$cap" ] && { [ "$TC_DRIFT_ADDED$TC_DRIFT_DELETED$TC_DRIFT_RENAMED" != 000 ] || [ "$TC_DRIFT_FILES" -gt "$cap" ]; }; then
    TC_DRIFT_CAPPED=1; rm -rf "$tmp"; return 0
  fi
  if [ "$TC_DRIFT_FILES" -gt 0 ]; then
    P=()
    while IFS= read -r p; do P+=(":(literal)$p"); done <<< "${v#*$'\n'}"
    if ! git -c core.quotePath=false -C "$repo" diff --numstat --no-renames -z "$a" "$b" -- "${P[@]}" > "$tmp/num" 2>/dev/null \
       || ! v=$(tr '\0' '\n' < "$tmp/num" | awk -F'\t' '{ if ($1 == "-" || $2 == "-") bin = 1; else lines += $1 + $2 }
                END { printf "%d %d\n", lines, bin }'); then
      rm -rf "$tmp"; return 1
    fi
    read -r TC_DRIFT_LINES TC_DRIFT_BINARY <<< "$v"
  fi
  rm -rf "$tmp"
  return 0
}

# tc__drift_batch <repo> <tree> <group> <max files> <big> — candidate trees on stdin.
# Prints "<candidate> <score>" for candidates whose drift is settled by the file set
# alone: -1 = tree missing / git failed, <big> = not small (added / deleted / more
# than <max files> files of the group). Candidates that may be small are not
# printed (the caller computes them exactly). One cat-file, one diff-tree --stdin.
tc__drift_batch() {
  local repo="$1" tree="$2" grp="$3" thf="$4" big="$5" tmp memb dc=/dev/null t ty
  tmp=$(mktemp -d "${TC__WORK:-${TMPDIR:-/tmp}}/tc-db.XXXXXX") || return 0
  cat > "$tmp/c"
  git -C "$repo" cat-file --batch-check='%(objectname) %(objecttype)' < "$tmp/c" > "$tmp/types" 2>/dev/null || { rm -rf "$tmp"; return 0; }
  while read -r t ty; do
    if [ "$ty" = tree ]; then printf '%s %s\n' "$t" "$tree" >> "$tmp/pairs"; else printf '%s -1\n' "$t"; fi
  done < "$tmp/types"
  if [ -s "$tmp/pairs" ]; then
    memb=$(tc__memb_file "$grp") || { rm -rf "$tmp"; return 0; }
    [ "$TC__DFILTER" = 1 ] && dc="$TC__WORK/dcommit"
    if git -c core.quotePath=false -C "$repo" diff-tree --stdin -r --no-renames --name-status -z < "$tmp/pairs" > "$tmp/z" 2>/dev/null \
       && tr '\0' '\n' < "$tmp/z" | awk -v filt="$TC__DFILTER" -v dcf="$dc" '
            FILENAME == dcf { d[$0] = 1; next }
            w == 0 && /^[0-9a-f]+ [0-9a-f]+$/ { split($0, h, " "); cur = h[1]; next }
            w == 0 { st = $0; w = 1; next }
            { w = 0; if (st == "D" && filt == 1 && !($0 in d)) next; print cur "\t" substr(st, 1, 1) "\t" $0 }' "$dc" - > "$tmp/rp"; then
      cut -f3- "$tmp/rp" > "$tmp/paths"
      tc__memb_ensure "$grp" "$tmp/paths" "$memb"
      awk -F'\t' -v mf="$memb" -v rpf="$tmp/rp" -v thf="$thf" -v big="$big" '
        FILENAME == mf { mm[substr($0, 3)] = substr($0, 1, 1); next }
        FILENAME == rpf { p = substr($0, length($1) + length($2) + 3); if (mm[p] != "1") next
                          n[$1]++; if ($2 == "A" || $2 == "D") fl[$1] = 1; next }
        { split($0, h, " "); c = h[1]; if (fl[c] || n[c] > thf) print c " " big }' "$memb" "$tmp/rp" "$tmp/pairs"
    else
      awk '{ print $1 " -1" }' "$tmp/pairs"
    fi
    [ -n "$TC__WORK" ] || rm -f "$memb"
  fi
  rm -rf "$tmp"
}

# tc_unstaged <repo> <commit tree> -> tracked paths whose WORKING-TREE content differs
# from the commit tree (unstaged hunks, partial staging, unstaged deletions). A
# receipt snapshots the working tree, so for these files re-running alone never
# makes it match the commit. Read-only (GIT_OPTIONAL_LOCKS=0: no index refresh).
tc_unstaged() {
  [ "${TC_NO_UNSTAGED:-0}" = 1 ] && return 0
  GIT_OPTIONAL_LOCKS=0 git -c core.quotePath=false -C "$1" diff --name-only --no-renames --diff-filter=MTD "$2" -- 2>/dev/null
}

# tc__unstaged_hint — what to do about a file whose working-tree content is not
# what the commit takes (a receipt snapshots the working tree, so re-running alone
# never matches the commit).
tc__unstaged_hint() {
  printf 'add it to this commit, or revert/finish that edit, then re-run'
  [ "${CLAUDE_SUBTEAMS_MULTI_INSTANCE:-0}" = 1 ] && printf ' (if another instance owns it, have it claim the file: coord.sh claim --id <its id> <path>)'
  return 0
}

# tc_large_untracked <repo> -> "path (N MB)" for untracked, non-ignored files over
# 10 MB (each content snapshot hashes them: slow receipts and gate). Max 5 lines.
tc_large_untracked() {
  local p sz
  git -c core.quotePath=false -C "$1" ls-files -o --exclude-standard 2>/dev/null | sed 's#^#./#' \
    | (cd "$1" 2>/dev/null && tr '\n' '\0' | xargs -0 sh -c 'find "$@" -maxdepth 0 -type f -size +10240k -print' sh 2>/dev/null) \
    | head -n 5 | while IFS= read -r p; do
        sz=$(wc -c < "$1/$p" 2>/dev/null | tr -d ' ')
        printf '%s (%s MB)\n' "${p#./}" "$(( ${sz:-0} / 1048576 ))"
      done
}

# ------------------------------------------------------------ commit tree (B14)
# The tree a `git commit` statement WILL record, computed on a temp index exactly
# as git builds it (builtin/commit.c prepare_index) — the real index, the working
# tree and HEAD are never written:
#   tc_ct_begin <repo>                  temp index = copy of the real index
#   tc_ct_add <cwd> <git add args…>     replay a preceding `git add`/`git stage`
#   tc_ct_rm  <cwd> <git rm args…>      replay a preceding `git rm` (dry-run check
#                                       with the user's args, then --cached on the temp)
#   tc_ct_commit <repo> <cwd> <plain|all|only|include> <pathspec…>  -> TC_CT_TREE
#       plain   = the index;  all (-a) = index + `add -u :/`;
#       include = (-i) index + `add -u -- <paths>` (paths must be known to git);
#       only    = (<paths> / -o) HEAD's tree + the working-tree state of every path
#                 matching <paths> in index ∪ HEAD (`ls-files --with-tree=HEAD`).
#   tc_ct_end
# rc: 0 ok; 3 git would refuse the command (unmatched pathspec, rm safety check) —
# TC_ERR says why; 1 internal error. Pathspecs are relative to <cwd>, as for git.
TC_CT_DIR=""
tc_ct_begin() {
  local real
  TC_CT_DIR=$(mktemp -d "${TMPDIR:-/tmp}/tc-ct.XXXXXX") || return 1
  real=$(tc__index_path "$1") || { tc_ct_end; return 1; }
  if [ -f "$real" ]; then cp "$real" "$TC_CT_DIR/index" || { tc_ct_end; return 1; }
  elif tc_has_head "$1"; then GIT_INDEX_FILE="$TC_CT_DIR/index" git -C "$1" read-tree HEAD 2>/dev/null || { tc_ct_end; return 1; }
  fi
  return 0
}
tc_ct_end() { [ -n "$TC_CT_DIR" ] && rm -rf "$TC_CT_DIR"; TC_CT_DIR=""; return 0; }
tc_ct_add() {
  local cwd="$1"; shift
  GIT_INDEX_FILE="$TC_CT_DIR/index" git -C "$cwd" add "$@" </dev/null >/dev/null 2>&1 && return 0
  TC_ERR="git add $* would fail"; return 3
}
tc_ct_rm() {
  local cwd="$1" a args=(); shift
  for a in "$@"; do case "$a" in --) break ;; -n|--dry-run|-[!-]*n*) return 0 ;; esac; done   # git rm -n removes nothing
  for a in "$@"; do case "$a" in -n|--dry-run|--cached) ;; *) args+=("$a") ;; esac; done
  # the dry run performs git's own safety checks for the user's exact form
  GIT_INDEX_FILE="$TC_CT_DIR/index" git -C "$cwd" rm -n "$@" </dev/null >/dev/null 2>&1 \
    || { TC_ERR="git rm $* would fail"; return 3; }
  GIT_INDEX_FILE="$TC_CT_DIR/index" git -C "$cwd" rm --cached -q ${args[@]+"${args[@]}"} </dev/null >/dev/null 2>&1 \
    || { TC_ERR="git rm $* would fail"; return 3; }
}
tc_ct_commit() {
  local repo="$1" cwd="$2" mode="$3" idx="$TC_CT_DIR/index" list wt=()
  shift 3
  TC_CT_TREE=""
  case "$mode" in
    plain) ;;
    all) GIT_INDEX_FILE="$idx" git -C "$repo" add -u -- ':/' </dev/null >/dev/null 2>&1 || { TC_ERR="git commit -a: cannot stage tracked changes"; return 3; } ;;
    include)
      [ $# -gt 0 ] || { TC_ERR="git commit -i without paths"; return 3; }
      GIT_INDEX_FILE="$idx" git -C "$cwd" ls-files --error-unmatch -- "$@" >/dev/null 2>&1 \
        || { TC_ERR="a pathspec of the commit matches no file known to git"; return 3; }
      GIT_INDEX_FILE="$idx" git -C "$cwd" add -u -- "$@" </dev/null >/dev/null 2>&1 || { TC_ERR="git commit -i: cannot stage the paths"; return 3; } ;;
    only)
      if [ $# -eq 0 ]; then   # --only without paths: HEAD's tree (message-only amend)
        TC_CT_TREE=$(git -C "$repo" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || TC_CT_TREE=$(tc_empty_tree "$repo")
        return 0
      fi
      tc_has_head "$repo" && wt=(--with-tree=HEAD)
      list="$TC_CT_DIR/list"
      GIT_INDEX_FILE="$idx" git -C "$cwd" ls-files -z --full-name --error-unmatch ${wt[@]+"${wt[@]}"} -- "$@" > "$list" 2>/dev/null \
        || { TC_ERR="a pathspec of the commit matches no file known to git"; return 3; }
      idx="$TC_CT_DIR/index.only"
      if tc_has_head "$repo"; then GIT_INDEX_FILE="$idx" git -C "$repo" read-tree HEAD 2>/dev/null || return 1
      else GIT_INDEX_FILE="$idx" git -C "$repo" read-tree --empty 2>/dev/null || return 1; fi
      GIT_INDEX_FILE="$idx" git -C "$repo" update-index --add --remove -z --stdin < "$list" >/dev/null 2>&1 \
        || { TC_ERR="git commit <paths>: cannot stage the paths"; return 3; } ;;
    *) TC_ERR="unknown commit mode $mode"; return 1 ;;
  esac
  TC_CT_TREE=$(GIT_INDEX_FILE="$idx" git -C "$repo" write-tree 2>/dev/null) || { TC_ERR="cannot write the commit tree (unresolved merge?)"; return 1; }
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

# tc_cache_root — ${XDG_CACHE_HOME} only when it is an ABSOLUTE path (the XDG spec:
# a relative value is invalid and ignored), else $HOME/.cache. Every receipt-store
# path (lib, hooks, session-start) goes through it.
tc_cache_root() {
  case "${XDG_CACHE_HOME:-}" in /*) printf '%s\n' "$XDG_CACHE_HOME" ;; *) printf '%s/.cache\n' "$HOME" ;; esac
}

tc_receipt_dir() { # <repo> -> receipt directory (not created)
  local id
  id=$(tc_repo_id "$1") || return 1
  [ -n "$id" ] || return 1
  printf '%s/claude-subteams/receipts/%s\n' "$(tc_cache_root)" "$id"
}

tc_receipt_purge() { # <receipt dir> — drop receipts (and stray temp files) older than 14 days
  find "$1" -maxdepth 1 -type f \( -name '*.json' -o -name '.tmp*' \) -mtime +"$TC_RECEIPT_TTL_DAYS" -exec rm -f {} + 2>/dev/null
  return 0
}

# Global recent index (B3): one line per receipt written in ANY store —
# "<ts>\t<store id>\t<repo root>\t<type>" — so subagent-rails can find evidence
# an agent left in other repositories (session in repo A, work in repo B).
# Append-only (one short line < PIPE_BUF per write: atomic with O_APPEND, no lock);
# lines older than 14 days are dropped by a rare rewrite (only when the FIRST line
# has expired). A line lost to a rewrite race only means an agent receipt is not
# copied to that store — the safe side (the gate then asks for the agent again).
tc_recent_log() { printf '%s/claude-subteams/receipts/_recent.log\n' "$(tc_cache_root)"; }
tc__recent_append() { # <ts> <store id> <root> <type>
  local log first cut tmp
  case "$3" in *$'\t'*|*$'\n'*|'') return 0 ;; esac
  log=$(tc_recent_log)
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" >> "$log" 2>/dev/null || return 0
  first=$(head -n 1 "$log" 2>/dev/null); first="${first%%$'\t'*}"
  cut=$(( $1 - TC_RECEIPT_TTL_DAYS * 86400 ))
  # a malformed first line also triggers the rewrite (it would otherwise block pruning forever)
  case "$first" in ''|*[!0-9]*) ;; *) [ "$first" -lt "$cut" ] || return 0 ;; esac
  tmp=$(mktemp "${log%/*}/.tmp.recent.XXXXXX") || return 0
  awk -F'\t' -v c="$cut" 'NF >= 4 && $1 ~ /^[0-9]+$/ && $1 + 0 >= c' "$log" > "$tmp" 2>/dev/null && mv -f -- "$tmp" "$log"
  rm -f -- "$tmp" 2>/dev/null
  return 0
}

# tc_recent_stores <from ts> <to ts> -> "<store id>\t<root>" of stores that got a
# suite or shot receipt in [from, to], newest first, one line per store (root =
# the newest such root). Unvalidated: callers check root / store id before use.
tc_recent_stores() {
  local log; log=$(tc_recent_log)
  [ -f "$log" ] || return 0
  awk -F'\t' -v s="$1" -v e="$2" 'NF >= 4 && $1 + 0 >= s && $1 + 0 <= e && ($4 == "suite" || $4 == "shot") && $2 ~ /^[0-9a-f]+$/ { print $1 "\t" $2 "\t" $3 }' "$log" 2>/dev/null \
    | sort -t "$(printf '\t')" -k1,1nr | awk -F'\t' '!seen[$2]++ { print $2 "\t" $3 }'
}

# tc_receipt_write <repo> <json object with .type> — THE way to write any receipt
# (suite, shot, ui, te, anchor): atomic (temp file + mv in the same dir), purge
# after 14 days, and one line in the global recent index (tc__recent_append).
# <repo> = any directory inside the repository/worktree the receipt is about.
# Sets TC_RECEIPT_PATH and PRINTS it on stdout (redirect it if unwanted); on
# failure rc 1 + TC_ERR (call it directly, not inside $(…), to keep TC_ERR).
# jq is used to validate .type when present; without jq a literal "type":"word"
# is accepted (bin/subteams-browser writes shot receipts with this function).
tc_receipt_write() {
  local repo="$1" json="$2" dir type ts name tmp root
  TC_RECEIPT_PATH=""
  dir=$(tc_receipt_dir "$repo") || { TC_ERR="not a git repository: $repo"; return 1; }
  if command -v jq >/dev/null 2>&1; then
    type=$(printf '%s' "$json" | jq -r 'if type == "object" and (.type | type) == "string" and (.type | test("^[a-z][a-z0-9_-]*$")) then .type else empty end' 2>/dev/null)
  else
    case "$json" in '{'*'}') type=$(printf '%s' "$json" | sed -n 's/^{"type":"\([a-z][a-z0-9_-]*\)".*$/\1/p' | head -n 1) ;; *) type="" ;; esac
  fi
  [ -n "$type" ] || { TC_ERR="receipt must be a JSON object with a simple .type"; return 1; }
  (umask 077; mkdir -p -- "$dir") 2>/dev/null || { TC_ERR="cannot create $dir"; return 1; }
  ts=$(date +%s)
  name=$(printf '%010d-%s-%s-%s.json' "$ts" "$type" "$$" "$RANDOM")
  tmp=$(mktemp "$dir/.tmp.XXXXXX") || { TC_ERR="cannot write in $dir"; return 1; }
  if printf '%s\n' "$json" > "$tmp" && mv -f -- "$tmp" "$dir/$name"; then
    tc_receipt_purge "$dir"
    TC_RECEIPT_PATH="$dir/$name"
    root=$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null) && tc__recent_append "$ts" "${dir##*/}" "$root" "$type"
    printf '%s\n' "$dir/$name"
    return 0
  fi
  rm -f -- "$tmp"; TC_ERR="cannot write receipt in $dir"; return 1
}

# tc_receipt_list <repo> -> receipt file paths, one per line: the NEWEST
# TC_RECEIPT_CAP (200) per type (from the file name "<ts>-<type>-…"; old shot
# names "shot-<ts>-…"), so a huge store can never push a hook past its timeout.
# How many were left out: the last line "#capped <n>" (tc_receipts_load turns it
# into TC_RECEIPTS_CAPPED).
TC_RECEIPT_CAP=200
tc_receipt_list() {
  local dir
  dir=$(tc_receipt_dir "$1") || return 1
  [ -d "$dir" ] || return 0
  # newest by the PARSED time stamp (legacy "shot-<ts>-…" and "<ts>-<type>-…" names mix)
  (cd "$dir" 2>/dev/null && ls -1 2>/dev/null) | awk '/\.json$/ && !/^\./ {
      n = split($0, f, "-"); if (f[1] ~ /^[0-9]+$/) { ts = f[1]; t = f[2] } else { t = f[1]; ts = (f[2] ~ /^[0-9]+$/) ? f[2] : 0 }
      print ts "\t" t "\t" $0 }' | LC_ALL=C sort -t "$(printf '\t')" -k1,1nr -k3,3r | awk -F'\t' -v d="$dir" -v cap="$TC_RECEIPT_CAP" '
    {
      if (++c[$2] <= cap) print d "/" $3; else dropped++
    }
    END { if (dropped) print "#capped " dropped }' | while IFS= read -r f; do
      case "$f" in '#capped '*) printf '%s\n' "$f" ;; *) [ -f "$f" ] && [ ! -L "$f" ] && printf '%s\n' "$f" ;; esac
    done
  return 0
}

tc_receipt_read() { # <file> -> its JSON (compact) or rc 1
  [ -f "$1" ] && [ ! -L "$1" ] && jq -ce 'select(type == "object")' "$1" 2>/dev/null
}

# tc_receipts_load <repo> -> JSON lines (one receipt per line, plus ._file).
# Receipt kind = .type; a shot receipt written without .type but with
# "kind":"shot" is normalized to type "shot".
TC_RECEIPTS_CAPPED=0
tc_receipts_load() {
  local files=() f out
  TC_RECEIPTS_CAPPED=0
  while IFS= read -r f; do
    case "$f" in '') ;; '#capped '*) TC_RECEIPTS_CAPPED="${f#\#capped }" ;; *) files+=("$f") ;; esac
  done < <(tc_receipt_list "$1")
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
# Among the 30 newest receipts of this suite, the newest one that ran the same
# command (cmd_sha) under the same contract (contract_sha), was not dirty and whose
# tree has the same content as <tree> for the suite's files decides: exit 0 ->
# valid. Content = paths present in <tree> or in the base tree only (tc_dcommit_set:
# files that were merely untracked at receipt time do not count). An OLDER failing
# receipt on that same content makes TC_SC_FLAKY=1 (the gate and `status` warn).
# A content mismatch on a file with unstaged changes (TC_UNSTAGED) says so: re-
# running alone cannot fix it. Sets TC_SC_OK (0/1), TC_SC_REASON, TC_SC_FILE,
# TC_SC_FLAKY. Requires tc_groups_load.
tc_suite_check() {
  local repo="$1" rfile="$2" tree="$3" i="$4" csha="$5" msha="$6"
  local name="${TC_S_NAME[$4]}" te ex dirty rc rm rt f n=0 why="" p found=0 res memb tmp rows map="" dc=/dev/null t ty
  TC_SC_OK=0; TC_SC_REASON="no receipt for suite $name"; TC_SC_FLAKY=0; TC_SC_FILE=""
  rows=$(jq -r --arg n "$name" 'select(.type == "suite" and .suite == $n)
      | [(.t_end // 0 | tostring), (.exit // "" | tostring), (if .dirty == true then "1" else "0" end),
         (.contract_sha // ""), (.cmd_sha // ""), (.tree // ""), ._file,
         ((.dirty_paths // []) | if type == "array" then .[:5] | map(tostring | gsub("[[:cntrl:]]"; " ")) | join(", ") else "" end)] | join("\u001f")' "$rfile" 2>/dev/null \
      | sort -t "$(printf '\037')" -k1,1nr | head -n 30)
  [ -n "$rows" ] || return 0
  # Content verdicts for all candidate trees at once (one cat-file, one diff-tree
  # --stdin, awk): map lines "<tree> same|missing|err|hit<TAB><path>".
  tmp=$(mktemp -d "${TC__WORK:-${TMPDIR:-/tmp}}/tc-sc.XXXXXX") || return 0
  memb=$(tc__memb_file "suite:$i") || { rm -rf "$tmp"; return 0; }
  printf '%s\n' "$rows" | awk -F'\037' -v c="$csha" -v m="$msha" '$4 == c && $5 == m && $3 == "0" && $6 ~ /^[0-9a-f]+$/ && !s[$6]++ { print $6 }' > "$tmp/trees"
  if [ -s "$tmp/trees" ]; then
    git -C "$repo" cat-file --batch-check='%(objectname) %(objecttype)' < "$tmp/trees" > "$tmp/types" 2>/dev/null || : > "$tmp/types"
    while read -r t ty; do
      if [ "$ty" = tree ]; then printf '%s %s\n' "$t" "$tree"; else map="$map$t missing"$'\n'; fi
    done < "$tmp/types" > "$tmp/pairs"
    if [ -s "$tmp/pairs" ]; then
      [ "$TC__DFILTER" = 1 ] && dc="$TC__WORK/dcommit"
      if git -c core.quotePath=false -C "$repo" diff-tree --stdin -r --no-renames --name-status -z < "$tmp/pairs" > "$tmp/z" 2>/dev/null \
         && tr '\0' '\n' < "$tmp/z" | awk -v filt="$TC__DFILTER" -v dcf="$dc" '
              FILENAME == dcf { d[$0] = 1; next }
              w == 0 && /^[0-9a-f]+ [0-9a-f]+$/ { split($0, h, " "); cur = h[1]; next }
              w == 0 { st = $0; w = 1; next }
              { w = 0; if (st == "D" && filt == 1 && !($0 in d)) next; print cur "\t" $0 }' "$dc" - > "$tmp/rp"; then
        cut -f2- "$tmp/rp" > "$tmp/paths"
        tc__memb_ensure "suite:$i" "$tmp/paths" "$memb"
        map="$map$(awk -F'\t' -v mf="$memb" -v rpf="$tmp/rp" '
              FILENAME == mf { mm[substr($0, 3)] = substr($0, 1, 1); next }
              FILENAME == rpf { p = substr($0, length($1) + 2); if (!($1 in hit) && mm[p] == "1") hit[$1] = p; next }
              { split($0, h, " "); c = h[1]; print c " " ((c in hit) ? "hit\t" hit[c] : "same") }' "$memb" "$tmp/rp" "$tmp/pairs")"$'\n'
      else
        while read -r t ty; do map="$map$t err"$'\n'; done < "$tmp/pairs"
      fi
    fi
  fi
  rm -rf "$tmp"; [ -n "$TC__WORK" ] || rm -f "$memb"
  while IFS=$'\037' read -r te ex dirty rc rm rt f dp; do
    [ -n "$f" ] || continue
    if [ "$rc" != "$csha" ]; then why="${why:-receipt is for another version of the test contract}"; continue; fi
    if [ "$rm" != "$msha" ]; then why="${why:-receipt ran a different command}"; continue; fi
    if [ "$dirty" = 1 ]; then why="${why:-files changed while the suite ran (dirty${dp:+: $dp}) — test artifacts? add them to .gitignore, then re-run}"; continue; fi
    res=$(printf '%s' "$map" | awk -v t="$rt" '$1 == t { print substr($0, length(t) + 2); exit }')
    [ -n "$res" ] || res=missing
    case "$res" in
      missing) why="${why:-receipt tree missing}"; continue ;;
      err) why="${why:-git diff failed}"; continue ;;
      hit*)
        p="${res#*$'\t'}"
        if [ -z "$why" ]; then
          case "${TC_UNSTAGED:-}" in
            *$'\n'"$p"$'\n'*) why="$p has changes that are not in this commit (staged or unstaged) — the suite ran on the working-tree version, the commit takes another; $(tc__unstaged_hint)" ;;
            *) why="content changed since the last run ($p)" ;;
          esac
        fi
        continue ;;
    esac
    if [ "$found" -eq 0 ]; then
      found=1; TC_SC_FILE="$f"
      if [ "$ex" = 0 ]; then TC_SC_OK=1; TC_SC_REASON="passed on this content"; continue; fi
      TC_SC_REASON="last run on this content failed (exit $ex)"; break
    fi
    [ "$ex" = 0 ] || { TC_SC_FLAKY=1; break; }   # an older failure on the same content
  done <<< "$rows"
  [ "$found" -eq 1 ] && return 0
  [ -n "$why" ] && TC_SC_REASON="$why"
  return 0
}

# tc_agent_check <repo> <receipts jsonl> <tree> <ui|code> <th_lines> <th_files> <e2e_req 0|1> <base tree>
# Uses TC__HEADC (the real HEAD: receipt / anchor ancestry), TC__BASEC (the base
# commit: HEAD, or HEAD^ for --amend — recorded in new anchors) and tc_dcommit_set. Requires tc_groups_load. Evidence is judged here, at check
# time, from the receipts written during the agent's [t_start, t_end] (a status
# alone is never believed):
#   ui pass      >= 2 shots AND, if <e2e_req> (a `run: auto` e2e suite whose paths
#                cover a UI file of this commit — computed by tc_requirements),
#                >= 1 e2e suite receipt with exit 0;
#   ui degraded  ONLY with a required e2e suite (<e2e_req> = 1) that has an e2e
#                receipt with exit 0 in the interval, AND the agent stated why the
#                live review was not performed (.reason_stated, recorded by
#                hooks/subagent-rails). No required e2e -> degraded never counts;
#   te pass      >= 1 suite receipt with exit 0;
#   issues-found a negative verdict (see shadowing below);
#   rejected     the agent ran but its final answer had no parsable first-line
#                Status (hooks/subagent-rails) — never counts, named in the reason.
# Candidates = up to 30 newest valid or issues-found receipts whose .head (the
# HEAD of the worktree the agent stopped in) is an ancestor of HEAD —
# receipts come from every worktree and branch, those about other branches are
# ignored — plus the newest drift ANCHOR whose commit is an ancestor of HEAD.
# The base is the valid candidate with the MINIMAL drift to <tree> (ties: the newer
# wins; receipts before the anchor). An issues-found receipt shadows it only if its
# own drift is smaller, or equal and it is newer — a verdict about the same or
# closer content. Neither a valid receipt nor an anchor -> the base is <base tree>
# and, if the change is small, TC_AC_ANCHOR is set (the gate writes it on allow,
# with TC__BASEC; `status` only reports it). Anchor: written when a group first
# passes as a small change without any agent receipt; later small commits do not
# move it, so a series of small commits accumulates drift (R9). Residual: anchors
# expire after 14 days like every receipt.
# Then: drift from the base within the threshold, no added/deleted/renamed/binary
# files. A drift computation that fails counts as NOT small (fail-closed).
# Sets TC_AC_OK, TC_AC_REASON, TC_AC_FILE, TC_AC_STATUS, TC_AC_BASE
# (receipt|anchor|head), TC_AC_ANCHOR (tree to anchor, or "") + TC_DRIFT_*.
# Reasons never name the threshold numbers.
tc_agent_check() {
  local repo="$1" rfile="$2" tree="$3" grp="$4" thl="$5" thf="$6" e2e_req="${7:-0}" htree="${8:-}" type who i auto=0
  local st rt f e2e suites shots rs ts te why n=0 skipped="" v at ats af ac k sc cache=$'\n' big=1000000
  local ck=() ctr=() cf=() cst=() cte=() csc=() cna=() hd anc=$'\n' a
  local bv=-1 bi=-1
  if [ "$grp" = ui ]; then type=ui; who="ui-tester"; else type=te; who="test-engineer"; fi
  for i in ${TC_S_NAME[@]+"${!TC_S_NAME[@]}"}; do [ "${TC_S_RUN[i]:-}" = auto ] && auto=1; done
  TC_AC_OK=0; TC_AC_REASON=""; TC_AC_FILE=""; TC_AC_STATUS=""; TC_AC_BASE=""; TC_AC_ANCHOR=""
  while IFS=$'\037' read -r st rt f e2e suites shots rs ts te why hd; do
    [ -n "$f" ] || continue
    # A receipt is bound to the history it was taken on (.head = the HEAD commit of
    # its worktree at stop): one from a commit that is not an ancestor of HEAD is
    # about other work and counts only if it saw EXACTLY this group content (drift
    # 0: a message-only amend or a pull --rebase must not void a valid check).
    # Receipts without .head count normally.
    a=1
    if [ -n "$hd" ] && [ -n "${TC__HEADC:-${TC__BASEC:-}}" ]; then
      case "$anc" in
        *$'\n'"$hd "[01]$'\n'*) a="${anc#*$'\n'"$hd "}"; a="${a:0:1}" ;;
        *) if git -C "$repo" merge-base --is-ancestor "$hd" "${TC__HEADC:-$TC__BASEC}" 2>/dev/null; then a=1; else a=0; fi
           anc="$anc$hd $a"$'\n' ;;
      esac
    fi
    if [ "$ts" -le 0 ] || [ "$te" -lt "$ts" ]; then skipped="${skipped:-a $who receipt without a valid time interval}"; continue; fi
    case "$type:$st" in
      ui:pass)
        if [ "$shots" -ge 2 ] && { [ "$e2e_req" -eq 0 ] || [ "$e2e" -ge 1 ]; }; then k=v
        else skipped="${skipped:-a $who pass without evidence (needs >= 2 screenshots$([ "$e2e_req" -eq 1 ] && echo ' and a run of the e2e suite covering these UI files with exit 0') during its run) does not count}"; continue; fi ;;
      ui:degraded)
        if [ "$e2e_req" -eq 1 ] && [ "$e2e" -ge 1 ] && [ "$rs" = 1 ]; then k=v
        elif [ "$e2e_req" -eq 0 ]; then skipped="${skipped:-a $who degraded result does not count when no required e2e suite covers these UI files (nothing was checked — screenshots are the only evidence, so it needs a pass)}"; continue
        else skipped="${skipped:-a $who degraded result without a run of the covering e2e suite with exit 0 or without a stated reason does not count}"; continue; fi ;;
      te:pass)
        if [ "$suites" -ge 1 ]; then k=v
        else skipped="${skipped:-a $who pass without a suite run with exit 0 during its run does not count}"; continue; fi ;;
      ui:issues-found|te:issues-found) k=i ;;
      *:rejected) skipped="${skipped:-$who ran but its final answer had no first-line 'Status: pass|degraded|issues-found|blocked'${why:+ ($why)} — re-run $who and have it end with that line}"; continue ;;
      *) skipped="${skipped:-a $who run without a verdict (status '$st') does not count}"; continue ;;
    esac
    n=${#ck[@]}; ck[n]=$k; ctr[n]="$rt"; cf[n]="$f"; cst[n]="$st"; cte[n]="$te"; csc[n]=-1; cna[n]=$((1 - a))
    [ "$n" -ge 29 ] && break
  done < <(jq -rs --arg t "$type" '
      [.[] | select(.type == "suite" and .exit == 0 and .dirty != true)] as $ok
      | [.[] | select(.type == "shot")] as $shots
      | [.[] | select(.type == $t)] | sort_by(.t_end // 0) | reverse | .[:100][]
      | ((.t_start // 0) | if type == "number" then floor else 0 end) as $s
      | ((.t_end // 0) | if type == "number" then floor else 0 end) as $e
      | def inside: ((.t_start // 0) >= $s and (.t_end // 0) <= $e);
        [(.status // "" | tostring), (.tree // "" | tostring), ._file,
         ([$ok[] | select(.kind == "e2e" and inside)] | length | tostring),
         ([$ok[] | select(inside)] | length | tostring),
         ([$shots[] | select((.ts // 0) >= $s and (.ts // 0) <= $e)] | length | tostring),
         (if .reason_stated == true then "1" else "0" end), ($s | tostring), ($e | tostring),
         (.reason // "" | tostring | gsub("[[:cntrl:]]"; " ") | .[:200]),
         (.head // "" | tostring | if test("^[0-9a-f]{7,64}$") then . else "" end)]
        | join("\u001f")' "$rfile" 2>/dev/null)
  # the newest anchor of this group whose commit is an ancestor of the base commit
  at=""; ats=0; af=""
  while IFS=$'\037' read -r v ats af ac; do
    [ -n "$v" ] && [ -n "$ac" ] && [ -n "${TC__HEADC:-${TC__BASEC:-}}" ] || continue
    git -C "$repo" merge-base --is-ancestor "$ac" "${TC__HEADC:-$TC__BASEC}" 2>/dev/null || continue
    at="$v"; break
  done < <(jq -rs --arg g "$grp" '[.[] | select(.type == "anchor" and .group == $g and (.tree | type) == "string")]
        | sort_by(.ts // 0) | reverse | .[:30][] | [.tree, ((.ts // 0) | floor | tostring), ._file, (.commit // "" | tostring)] | join("\u001f")' "$rfile" 2>/dev/null)
  [ -n "$at" ] || ats=0
  if [ -n "$at" ]; then n=${#ck[@]}; ck[n]=a; ctr[n]="$at"; cf[n]="$af"; cst[n]=""; cte[n]="$ats"; csc[n]=-1; cna[n]=0; fi
  # no valid receipt on this history and no anchor -> the base tree is the base
  v=0; for k in ${ck[@]+"${!ck[@]}"}; do [ "${ck[k]}" = i ] || [ "${cna[k]}" = 1 ] || v=1; done
  if [ "$v" -eq 0 ]; then n=${#ck[@]}; ck[n]=h; ctr[n]="${htree:-$(tc_empty_tree "$repo")}"; cf[n]=""; cst[n]=""; cte[n]=0; csc[n]=-1; cna[n]=0; fi
  # drift score per candidate (cached by tree): lines, +big when not small; -1 = unusable.
  # One batched pass (tc__drift_batch) settles every candidate that is not small by
  # its file set; only the few small-looking ones get an exact line count.
  if [ "${#ck[@]}" -gt 0 ]; then
    cache=$'\n'"$(printf '%s\n' "${ctr[@]}" | awk '!s[$0]++' | tc__drift_batch "$repo" "$tree" "$grp" "$thf" "$big")"$'\n'
  fi
  for k in ${ck[@]+"${!ck[@]}"}; do
    [ "${ck[k]}" != i ] && [ "$bv" -ge 0 ] && [ "${csc[bv]}" -eq 0 ] && continue   # an exact match cannot be beaten
    case "$cache" in
      *$'\n'"${ctr[k]} "[-0-9]*) sc="${cache#*$'\n'"${ctr[k]} "}"; sc="${sc%%$'\n'*}" ;;
      *)
        if tc_drift "$repo" "${ctr[k]}" "$tree" "$grp" "$thf"; then
          sc="$TC_DRIFT_LINES"
          if [ "$TC_DRIFT_ADDED$TC_DRIFT_DELETED$TC_DRIFT_RENAMED$TC_DRIFT_BINARY" != 0000 ] \
             || [ "$TC_DRIFT_LINES" -gt "$thl" ] || [ "$TC_DRIFT_FILES" -gt "$thf" ]; then sc=$((sc + big)); fi
        else sc=-1; fi
        cache="$cache${ctr[k]} $sc"$'\n' ;;
    esac
    [ "${cna[k]}" = 1 ] && [ "$sc" != 0 ] && sc=-1           # off-history: only an exact match counts
    csc[k]=$sc
    [ "$sc" -ge 0 ] || continue
    if [ "${ck[k]}" = i ]; then
      { [ "$bi" -lt 0 ] || [ "$sc" -lt "${csc[bi]}" ]; } && bi=$k
    else
      { [ "$bv" -lt 0 ] || [ "$sc" -lt "${csc[bv]}" ]; } && bv=$k
    fi
  done
  if [ "$bi" -ge 0 ] && { [ "$bv" -lt 0 ] || [ "${csc[bi]}" -lt "${csc[bv]}" ] \
       || { [ "${csc[bi]}" -eq "${csc[bv]}" ] && [ "${cte[bi]}" -ge "${cte[bv]}" ]; }; }; then
    TC_AC_STATUS=issues-found; TC_AC_FILE="${cf[bi]}"; TC_AC_BASE=receipt
    tc_drift "$repo" "${ctr[bi]}" "$tree" "$grp"
    TC_AC_REASON="the latest $who verdict on this work is issues-found — fix and re-run $who"
    return 0
  fi
  if [ "$bv" -lt 0 ]; then
    TC_AC_REASON="cannot compare with the last $who check / anchor (its tree is missing or git failed) — run $who${skipped:+ ($skipped)}"
    return 0
  fi
  case "${ck[bv]}" in
    v) TC_AC_BASE=receipt; TC_AC_STATUS="${cst[bv]}"; TC_AC_FILE="${cf[bv]}" ;;
    a) TC_AC_BASE=anchor; TC_AC_FILE="${cf[bv]}" ;;
    h) TC_AC_BASE=head ;;
  esac
  tc_drift "$repo" "${ctr[bv]}" "$tree" "$grp" || { TC_AC_REASON="cannot compare with the last $who check / anchor (git failed) — run $who"; return 0; }
  if [ "${csc[bv]}" -ge "$big" ]; then
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
    head) TC_AC_REASON="small change, no $who check needed (an anchor is created on commit)"; TC_AC_ANCHOR="${ctr[bv]}" ;;
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
# <base> = HEAD, HEAD^ for --amend, or the empty tree. Files = diff <base>..<tree>.
# Required:
#   - every `run: auto` suite with a touched file (its paths; no paths = any
#     non-docs file): a valid suite receipt for exactly this content (tc_suite_check);
#     opt-in / live suites are never required;
#   - ui-tester when the ui group is touched, test-engineer when the code group is
#     (tc_agent_check: evidence + accumulated drift).
# Sets TC_REQ_OK (1 = nothing missing), TC_REQ_MISSING (one item per line; no
# threshold numbers), TC_REQ_WARN (one warning per line: clamped threshold, flaky
# suites), TC_REQ_ANCHORS ("<group> <tree> <commit>" per line), TC_REQ_JSON ({tree,
# base, files, suites, agents, ok, missing, warnings}). rc 1 = could not evaluate
# (TC_ERR) — callers with a contract deny.
tc_requirements() {
  local repo="$1" tree="$2" base="$3" cfg="$4" csha="$5"
  local flist rfile i name req f v cwd cmd msha rows="" uit=0 cot=0 ag_ui ag_te files_json e2e_req=0 htree
  TC_REQ_OK=0; TC_REQ_MISSING=""; TC_REQ_JSON=""; TC_REQ_ANCHORS=""; TC_REQ_WARN=""
  tc_is_tree "$repo" "$tree" || { TC_ERR="not a tree: $tree"; return 1; }
  flist=$(tc_changed_files "$repo" "$base" "$tree") || { TC_ERR="git diff $base..$tree failed"; return 1; }
  tc_groups_load "$cfg" || { TC_ERR="cannot read the suites/globs of the test config"; return 1; }
  [ -n "$TC__WORK" ] && rm -rf "$TC__WORK"
  TC__WORK=$(mktemp -d "${TMPDIR:-/tmp}/tc-work.XXXXXX") || { TC_ERR="cannot create a temp dir"; return 1; }
  rfile="$TC__WORK/receipts.jsonl"
  tc_receipts_load "$repo" > "$rfile"
  tc_threshold "$cfg"
  htree=$(git -C "$repo" rev-parse "$base^{tree}" 2>/dev/null) || htree=$(tc_empty_tree "$repo")
  TC__BASEC=$(git -C "$repo" rev-parse -q --verify "$base^{commit}" 2>/dev/null) || TC__BASEC=""
  # receipts and anchors are bound to the REAL history: on --amend the base is
  # HEAD^, but a check taken now has .head = HEAD — ancestry is tested against HEAD
  TC__HEADC=$(git -C "$repo" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || TC__HEADC=""
  tc_dcommit_set "$repo" "$htree" "$tree" || TC__DFILTER=0      # no filter = the stricter old comparison
  TC_UNSTAGED=$'\n'"$(tc_unstaged "$repo" "$tree")"$'\n'
  # (i) unstaged files NOT in this commit that another live instance has claimed:
  # outside every group for this evaluation (tc__memb_file seeds them), with a warning
  printf '%s\n' "$flist" > "$TC__WORK/changed"
  if [ "$TC_UNSTAGED" != $'\n\n' ]; then
    printf '%s' "$TC_UNSTAGED" | awk -v cf="$TC__WORK/changed" 'FILENAME == cf { c[$0] = 1; next } $0 != "" && !($0 in c)' \
      "$TC__WORK/changed" - > "$TC__WORK/cand" 2>/dev/null
    if [ -s "$TC__WORK/cand" ]; then
      tc_coord_foreign "$repo" "${TC_SELF_ID:-}" "$TC__WORK/cand" > "$TC__WORK/foreign.tsv"
      cut -f1 "$TC__WORK/foreign.tsv" > "$TC__WORK/foreign"
      while IFS=$'\t' read -r f v; do
        [ -n "$f" ] && tc__req_warn "suite ran with $f modified by instance $v; not part of this commit"
      done < "$TC__WORK/foreign.tsv"
      [ -n "$TC_COORD_NOTE" ] && tc__req_warn "$TC_COORD_NOTE"
    fi
  fi
  tc__foreign_dirty "$repo" "$rfile"
  if [ "$(printf '%s' "$cfg" | jq -r '.small_change_clamped // false' 2>/dev/null)" = true ]; then
    tc__req_warn "small_change in the test contract is above the built-in ceiling — clamped to $TC_MAX_LINES lines / $TC_MAX_FILES files"
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
    [ "$TC_SC_FLAKY" -eq 1 ] && tc__req_warn "suite $name failed earlier on the same content (flaky?) — the newest run passed"
    rows="$rows$(jq -nc --arg n "$name" --argjson ok "$(tc_bool "$TC_SC_OK")" --arg why "$TC_SC_REASON" --arg f "$TC_SC_FILE" \
      --argjson fl "$(tc_bool "$TC_SC_FLAKY")" \
      '{name: $n, run: "auto", required: true, touched: true, ok: $ok, reason: $why, receipt: (if $f == "" then null else $f end)}
       + (if $fl then {flaky: true} else {} end)')"$'\n'
    if [ "$TC_SC_OK" -ne 1 ]; then
      TC_REQ_OK=0; TC_REQ_MISSING="$TC_REQ_MISSING${TC_REQ_MISSING:+$'\n'}suite $name: $TC_SC_REASON — run: subteams-tests run $name"
    fi
  done
  tc__req_agent "$repo" "$rfile" "$tree" ui "$uit" "$e2e_req" "$htree"; ag_ui="$TC__AG_JSON"
  [ "$TC_AC_OK" -eq 1 ] || { TC_REQ_OK=0; TC_REQ_MISSING="$TC_REQ_MISSING${TC_REQ_MISSING:+$'\n'}ui-tester: $TC_AC_REASON$(tc__unstaged_note ui ui-tester)"; }
  [ -n "${TC_AC_ANCHOR:-}" ] && TC_REQ_ANCHORS="${TC_REQ_ANCHORS}ui $TC_AC_ANCHOR ${TC__BASEC:--}"$'\n'
  tc__req_agent "$repo" "$rfile" "$tree" code "$cot" 0 "$htree"; ag_te="$TC__AG_JSON"
  [ "$TC_AC_OK" -eq 1 ] || { TC_REQ_OK=0; TC_REQ_MISSING="$TC_REQ_MISSING${TC_REQ_MISSING:+$'\n'}test-engineer: $TC_AC_REASON$(tc__unstaged_note code test-engineer)"; }
  [ -n "${TC_AC_ANCHOR:-}" ] && TC_REQ_ANCHORS="${TC_REQ_ANCHORS}code $TC_AC_ANCHOR ${TC__BASEC:--}"$'\n'
  rm -rf "$TC__WORK"; TC__WORK=""; TC__DFILTER=0
  files_json=$(printf '%s\n' "$flist" | jq -R . | jq -sc 'map(select(length > 0))')
  TC_REQ_JSON=$(printf '%s' "$rows" | jq -sc --arg tree "$tree" --arg base "$base" --argjson files "$files_json" \
    --argjson ui "$ag_ui" --argjson te "$ag_te" --argjson ok "$(tc_bool "$TC_REQ_OK")" --arg missing "$TC_REQ_MISSING" \
    --arg warn "$TC_REQ_WARN" \
    '{tree: $tree, base: $base, files: $files, suites: ., agents: {"ui-tester": $ui, "test-engineer": $te}, ok: $ok,
      missing: ($missing | split("\n") | map(select(length > 0))), warnings: ($warn | split("\n") | map(select(length > 0)))}') || { TC_ERR="cannot build the requirements JSON"; return 1; }
  return 0
}

# ------------------------------------------------- multi-instance claims (i)
# A shared working tree (scripts/coord.sh, CLAUDE_SUBTEAMS_MULTI_INSTANCE): another
# live instance may have an unfinished edit in a tracked file that is NOT part of
# this commit. The suite then ran with that edit present; the commit does not take
# it. Owner decision 14.11.2026: such a file, CLAIMED by ANOTHER LIVE instance, is a
# warning ("suite ran with <file> modified by instance <id>"), not a deny. Anything
# else — unclaimed, claimed by this instance, by a dead / unregistered instance, or
# coord state that cannot be read — stays a deny (fail-closed).
# Read-only mirror of coord.sh: store $CLAUDE_SUBTEAMS_COORD_HOME (default
# ~/.claude/subteams)/<repokey>/{claims,instances}.json, repokey = first 16 hex of
# md5 (cksum fallback) of the canonical git-common-dir; liveness = worktree exists
# AND (pid alive, or — only for an untrusted pid — heartbeat younger than
# CLAUDE_SUBTEAMS_HEARTBEAT_TTL, default 1800 s). Never writes, never reaps.
tc__coord_dir() { # <repo> -> coord dir of this repository (may not exist)
  local common key
  common=$(cd "$1" 2>/dev/null && git rev-parse --git-common-dir 2>/dev/null) || return 1
  common=$(cd "$1" 2>/dev/null && cd "$common" 2>/dev/null && pwd -P) || return 1
  key=$(printf '%s' "$common" | { md5sum 2>/dev/null || cksum; } | tr -cd '0-9a-f' | cut -c1-16)
  [ -n "$key" ] || return 1
  printf '%s/%s\n' "${CLAUDE_SUBTEAMS_COORD_HOME:-$HOME/.claude/subteams}" "$key"
}

# tc_coord_foreign <repo> <self id> <candidate paths file> -> "<path>\t<owner id>"
# for candidates claimed by another LIVE instance. Unreadable state -> nothing (and
# TC_COORD_NOTE says so): the caller then denies as usual.
tc_coord_foreign() {
  local dir top id pid tr wt hb now ttl live=$'\n' claims
  TC_COORD_NOTE=""
  dir=$(tc__coord_dir "$1") || return 0
  [ -e "$dir/claims.json" ] || return 0
  top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 0
  ttl="${CLAUDE_SUBTEAMS_HEARTBEAT_TTL:-1800}"; case "$ttl" in ''|*[!0-9]*) ttl=1800 ;; esac
  now=$(date +%s)
  if ! claims=$(jq -r 'if type == "object" then to_entries[] | select((.value.by | type) == "string") | "\(.key)\t\(.value.by)" else error("bad") end' "$dir/claims.json" 2>/dev/null) \
     || ! jq -e 'type == "object"' "$dir/instances.json" >/dev/null 2>&1; then
    TC_COORD_NOTE="coordination state ($dir) cannot be read — claims are not taken into account"; return 0
  fi
  while IFS=$'\t' read -r id pid tr wt hb; do
    [ -n "$id" ] || continue
    [ -z "$wt" ] || [ -d "$wt" ] || continue
    case "$pid" in ''|*[!0-9]*) pid=0 ;; esac
    if [ "$pid" -gt 0 ] && kill -0 "$pid" 2>/dev/null; then live="$live$id"$'\n'; continue; fi
    [ "$tr" = true ] && continue
    case "$hb" in ''|*[!0-9]*) hb=0 ;; esac
    [ $((now - hb)) -lt "$ttl" ] && live="$live$id"$'\n'
  done < <(jq -r 'to_entries[] | [.key, (.value.pid // 0 | tostring), (.value.pid_trusted // false | tostring), (.value.worktree // "" | tostring), (.value.heartbeat // 0 | tostring)] | @tsv' "$dir/instances.json" 2>/dev/null)
  printf '%s\n' "$claims" | awk -F'\t' -v top="$top/" -v self="${2:-}" -v live="$live" -v cf="$3" '
    BEGIN { n = split(live, L, "\n"); for (i = 1; i <= n; i++) if (L[i] != "") ok[L[i]] = 1 }
    FILENAME == cf { if ($0 in own) print $0 "\t" own[$0]; next }
    { k = $1; sub(/^\.\//, "", k); if (index(k, top) == 1) k = substr(k, length(top) + 1)
      if ($2 != self && ($2 in ok)) own[k] = $2 }' - "$3"
}

# tc__foreign_dirty <repo> <receipts jsonl> — (owner rule, as for unstaged files) a
# suite receipt marked dirty ONLY because tracked files changed during the run that
# are NOT part of this commit and are claimed by another LIVE instance is not dirty
# for this evaluation: rewritten with dirty=false + foreign_paths, and a warning.
# Decided at check time (the commit is known only here); the run records dirty_paths.
tc__foreign_dirty() {
  local rf="$2" f n paths id fo files="" tmp
  jq -r 'select(.type == "suite" and .dirty == true and ((.dirty_paths // []) | type) == "array" and ((.dirty_paths // []) | length) > 0)
         | .dirty_paths[] | tostring' "$rf" 2>/dev/null | LC_ALL=C sort -u \
    | awk -v cf="$TC__WORK/changed" 'FILENAME == cf { c[$0] = 1; next } $0 != "" && !($0 in c)' "$TC__WORK/changed" - > "$TC__WORK/dcand"
  [ -s "$TC__WORK/dcand" ] || return 0
  tc_coord_foreign "$1" "${TC_SELF_ID:-}" "$TC__WORK/dcand" > "$TC__WORK/dforeign.tsv"
  [ -s "$TC__WORK/dforeign.tsv" ] || return 0
  while IFS=$'\037' read -r f n paths; do
    [ -n "$f" ] || continue
    fo=1
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      awk -F'\t' -v p="$id" '$1 == p { found = 1 } END { exit !found }' "$TC__WORK/dforeign.tsv" || { fo=0; break; }
    done <<< "$(printf '%s' "$paths" | tr '\036' '\n')"
    [ "$fo" -eq 1 ] || continue
    files="$files$f"$'\n'
    tc__req_warn "suite $n ran while $(printf '%s' "$paths" | tr '\036' ' ') changed (claimed by another live instance); not part of this commit — the run counts"
  done < <(jq -r 'select(.type == "suite" and .dirty == true and ((.dirty_paths // []) | type) == "array" and ((.dirty_paths // []) | length) > 0)
                  | [._file, (.suite // ""), (.dirty_paths | map(tostring) | join("\u001e"))] | join("\u001f")' "$rf" 2>/dev/null)
  [ -n "$files" ] || return 0
  tmp="$rf.fd"
  jq -c --arg fl "$files" '($fl | split("\n")) as $L | if (._file as $x | $L | index($x)) then .dirty = false | .foreign_paths = .dirty_paths else . end' "$rf" > "$tmp" 2>/dev/null && mv -f "$tmp" "$rf"
}

tc__req_warn() { TC_REQ_WARN="$TC_REQ_WARN${TC_REQ_WARN:+$'\n'}$1"; }

# tc__unstaged_note <group> <agent> — after a failed agent check against a receipt:
# names the group's files with unstaged changes (the agent saw the working-tree
# version; a re-run alone sees it again). Prints "" when none / other bases.
tc__unstaged_note() {
  local p out=""
  [ "$TC_AC_BASE" = receipt ] && [ "$TC_AC_STATUS" != issues-found ] || return 0
  while IFS= read -r p; do
    [ -n "$p" ] && tc_in_group "$p" "$1" && out="$out${out:+, }$p"
  done <<< "${TC_UNSTAGED:-}"
  [ -n "$out" ] && printf '; note: %s has changes that are not in this commit (staged or unstaged) — the %s check saw the working-tree version; %s' "$out" "$2" "$(tc__unstaged_hint)"
  return 0
}

# tc__req_agent <repo> <rfile> <tree> <ui|code> <touched 0/1> -> TC__AG_JSON,
# TC_AC_OK / TC_AC_REASON (runs in the caller's shell: call it directly, not in $(…)).
tc__req_agent() { # … <e2e_req> <base tree>
  TC_AC_ANCHOR=""; TC_AC_BASE=""; TC_AC_STATUS=""
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

# tc_anchor_write <repo> <ui|code> <tree> <base commit|-> — the drift anchor (see
# tc_agent_check). Written ONLY by the commit gate when it allows a commit
# (TC_REQ_ANCHORS). The commit binds it to a branch: it is used only while that
# commit is an ancestor of the base commit.
tc_anchor_write() {
  local now c=""; now=$(date +%s)
  case "${4:-}" in ''|-) ;; *) printf '%s' "$4" | grep -qE '^[0-9a-f]{7,64}$' && c="$4" ;; esac
  tc_receipt_write "$1" "{\"type\":\"anchor\",\"group\":\"$2\",\"tree\":\"$3\",\"commit\":\"$c\",\"ts\":$now,\"t_end\":$now}" >/dev/null
}
