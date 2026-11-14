#!/usr/bin/env bash
# discover-tests.sh — project test suites: discovery, classification, receipts.
# Entry point: bin/subteams-tests (IMPL-PLAN 1.50.0, Task 1). Rules shared with the
# commit gate live in scripts/lib-testclass.sh.
#
#   subteams-tests [--root DIR] [--diff BASE | --files -]
#       JSON: root, contract (v1|none|declined), suites[], groups, recommend.
#       Contract from the WORKING TREE; without one — heuristics (source: heuristic).
#   subteams-tests [--root DIR] run <suite> | run --all-auto
#       Runs the suite's cmd from the contract in HEAD (no contract in HEAD: the
#       staged one; none at all: discovery) in its cwd, stdin </dev/null, output
#       streamed as is; writes a `suite` receipt (content snapshot before/after,
#       `dirty` if the tree changed during the run) and exits with the suite's code.
#       Extra arguments are refused: a partial run must not yield a full receipt.
#   subteams-tests [--root DIR] --init-contract
#       Prints a contract v1 JSON draft (stdout: bare JSON; markers hint on stderr).
#   subteams-tests [--root DIR] status
#       What the commit gate will check for the current INDEX (the same function:
#       tc_requirements in lib-testclass.sh): suite receipts valid for this
#       content, ui/te receipts and drift. Nothing staged -> the WORKING TREE
#       snapshot is evaluated instead ("target": "worktree", said on stderr).
#       JSON on stdout, summary on stderr; exit 0 = nothing missing for that
#       target, 1 = something missing.
#   subteams-tests [--root DIR] config
#       The effective config run/status/the gate use (HEAD contract -> staged
#       contract -> discovery): {state, contract_sha, file, config} as JSON.
#
# Exit codes: 0 ok · 1 error / status incomplete · 2 broken JSON (contract,
# package.json) · 3 jq missing · 64 bad usage · run: the suite's own exit code.
# Safety: JSON parsed only by jq; nothing from the project is executed except the
# suite cmd in `run`; project files over 1 MB or resolving outside the root
# (symlinks) are not read; the environment is never printed.
set -u

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/lib-testclass.sh
. "$SCRIPT_DIR/lib-testclass.sh" || { echo "[subteams-tests] cannot load lib-testclass.sh" >&2; exit 1; }

say() { printf '[subteams-tests] %s\n' "$*" >&2; }
die() { local rc="$1"; shift; say "$*"; exit "$rc"; }
usage() {
  cat >&2 <<'EOF'
usage: subteams-tests [--root DIR] [--diff BASE | --files -]   list suites + classify changed files (JSON)
       subteams-tests [--root DIR] run <suite> | run --all-auto  run with a receipt (no extra args)
       subteams-tests [--root DIR] --init-contract              print a contract v1 JSON draft
       subteams-tests [--root DIR] status                       receipts valid for the current index
       subteams-tests [--root DIR] config                       effective config (contract or discovery)
EOF
}

command -v jq >/dev/null 2>&1 || die 3 "jq is required (install jq: apt install jq / brew install jq)"

MODE=list; ROOT_ARG=""; DIFF_BASE=""; FILES_STDIN=0; SUITE=""; ALL_AUTO=0
# --root DIR / --root=DIR is accepted anywhere (also after `run <suite>`); it is
# the only option taken out of order
_a=(); while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || die 64 "--root needs a directory"; ROOT_ARG="$2"; shift 2 ;;
    --root=*) ROOT_ARG="${1#--root=}"; shift ;;
    *) _a+=("$1"); shift ;;
  esac
done
set -- ${_a[@]+"${_a[@]}"}
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || die 64 "--root needs a directory"; ROOT_ARG="$2"; shift 2 ;;
    --root=*) ROOT_ARG="${1#--root=}"; shift ;;
    --diff) [ $# -ge 2 ] || die 64 "--diff needs a base revision"; DIFF_BASE="$2"; shift 2 ;;
    --files) [ "${2:-}" = - ] || die 64 "--files takes '-' (one path per line on stdin)"; FILES_STDIN=1; shift 2 ;;
    --init-contract) MODE=init; shift ;;
    -h|--help) usage; exit 0 ;;
    run)
      MODE=run; shift
      [ $# -ge 1 ] || die 64 "run: name a suite or --all-auto"
      if [ "$1" = --all-auto ]; then ALL_AUTO=1; else SUITE="$1"; fi
      shift
      [ $# -eq 0 ] && break
      die 64 "run: extra arguments are refused — the command comes from the contract as is, and a partial run must not produce a receipt for the whole suite" ;;
    status)
      MODE=status; shift
      [ $# -eq 0 ] || die 64 "status takes no arguments" ;;
    config)
      MODE=config; shift
      [ $# -eq 0 ] || die 64 "config takes no arguments" ;;
    *) die 64 "unknown argument: $1 (see --help)" ;;
  esac
done
[ -n "$DIFF_BASE" ] && [ "$FILES_STDIN" -eq 1 ] && die 64 "--diff and --files are mutually exclusive"

R="${ROOT_ARG:-$PWD}"
[ -d "$R" ] || die 64 "not a directory: $R"
if TOP=$(git -C "$R" rev-parse --show-toplevel 2>/dev/null) && [ -n "$TOP" ]; then
  ROOT="$TOP"; IS_GIT=1
else
  ROOT=$(cd "$R" && pwd -P); IS_GIT=0
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/subteams-tests.XXXXXX") || die 1 "cannot create a temp dir"
trap 'rm -rf "$WORK"; tc_tmp_cleanup' EXIT; trap 'exit 143' TERM; trap 'exit 130' INT

# ------------------------------------------------------------------ discovery

PRUNE=(-name node_modules -o -name .git -o -name dist -o -name build -o -name out -o -name coverage
       -o -name vendor -o -name target -o -name venv -o -name __pycache__ -o -name '.?*')

find_files() { # <maxdepth> <name pattern>... -> paths relative to ROOT
  local depth="$1" expr=() n; shift
  for n in "$@"; do expr+=(${expr[@]+-o} -name "$n"); done
  find "$ROOT" -mindepth 1 -maxdepth "$depth" \( -type d \( "${PRUNE[@]}" \) -prune \) \
    -o \( \( -type f -o -type l \) \( "${expr[@]}" \) -print \) 2>/dev/null \
    | while IFS= read -r p; do printf '%s\n' "${p#"$ROOT"/}"; done | LC_ALL=C sort
}

pm_for() { # <rel dir> -> npm|pnpm|yarn|bun (lockfile in the package dir, then at the root)
  local d
  for d in "$ROOT/$1" "$ROOT"; do
    if [ -f "$d/pnpm-lock.yaml" ]; then echo pnpm; return; fi
    if [ -f "$d/yarn.lock" ]; then echo yarn; return; fi
    if [ -f "$d/bun.lockb" ] || [ -f "$d/bun.lock" ]; then echo bun; return; fi
    if [ -f "$d/package-lock.json" ] || [ -f "$d/npm-shrinkwrap.json" ]; then echo npm; return; fi
  done
  echo npm
}

pmx_for() { case "$1" in pnpm) echo "pnpm exec" ;; yarn) echo yarn ;; bun) echo bunx ;; *) echo npx ;; esac; }

# shellcheck disable=SC2016  # jq program
PKG_JQ='
if type != "object" then error("not a JSON object") else . end
| (.scripts // {}) | (if type == "object" then . else {} end) | . as $all | to_entries[]
| select((.key | test("^(test|test:.+|e2e.*)$")) and (.value | type == "string"))
| .key as $k | .value as $v
| if ($k | test("^[A-Za-z0-9_][A-Za-z0-9_:.@/+-]*$") | not) then empty else
  ($v | test("RUN_[A-Za-z0-9_]*=")) as $runenv
  | ((($all["pre" + $k] // "") | tostring) as $pre | (($v + " " + $pre) | test("\\bbuild\\b"; "i"))) as $build
  | ($k | test("live|canary"; "i")) as $live
  | (($k | test("watch|(^|:)ui($|:)|debug|headed|update"; "i"))
     or ($v | test("--watch|--ui( |$)|--headed|--debug|--update|(^| )-u( |$)"))) as $inter
  | {name: (if $dir == "." then $k else "\($dir):\($k)" end),
     cmd: (if $pm == "bun" then "bun run \($k)" elif $k == "test" then "\($pm) test" else "\($pm) run \($k)" end),
     cwd: $dir,
     kind: (if (($k + " " + $v) | test("e2e|playwright|cypress"; "i")) then "e2e"
            elif ($k | test("integration|(^|:)int($|:)"; "i")) then "integration" else "unit" end),
     run: (if $runenv or $live or $inter or $build then "opt-in" else "auto" end),
     paths: (if $dir == "." then null else ["\($dir)/**"] end),
     source: "heuristic",
     why: (if $runenv then "command sets RUN_*" elif $live then "name says live/canary"
           elif $inter then "watch/interactive/update mode" elif $build then "command runs a build" else null end),
     _default: ($k == "test"),
     _pw: ($v | test("playwright")), _cy: ($v | test("cypress"))}
  end'

SUITES_JL="$WORK/suites.jsonl"

add_suite() { # name cmd cwd kind run why [cfg] [default 0/1]
  jq -nc --arg name "$1" --arg cmd "$2" --arg cwd "$3" --arg kind "$4" --arg run "$5" --arg why "$6" --arg cfg "${7:-}" \
    --argjson def "$([ "${8:-0}" = 1 ] && echo true || echo false)" \
    '{name: $name, cmd: $cmd, cwd: $cwd, kind: $kind, run: $run, paths: null, source: "heuristic",
      why: (if $why == "" then null else $why end), _default: $def} + (if $cfg == "" then {} else {_cfg: $cfg} end)' >> "$SUITES_JL"
}

workspace_globs() { # root package.json workspaces + pnpm-workspace.yaml packages
  if [ -f "$ROOT/package.json" ] && tc_safe_file "$ROOT" "$ROOT/package.json" 2>/dev/null; then
    jq -r '(.workspaces // []) | (if type == "object" then (.packages // []) else . end)
           | if type == "array" then .[] | strings else empty end' "$ROOT/package.json" 2>/dev/null
  fi
  if [ -f "$ROOT/pnpm-workspace.yaml" ] && tc_safe_file "$ROOT" "$ROOT/pnpm-workspace.yaml"; then
    awk '/^packages:/ { on = 1; next } on && /^[^ \t#-]/ { on = 0 }
         on && /^[ \t]*-[ \t]*/ { s = $0; sub(/^[ \t]*-[ \t]*/, "", s); sub(/[ \t]*#.*$/, "", s)
                                  gsub(/["\047]/, "", s); if (s != "") print s }' "$ROOT/pnpm-workspace.yaml"
  fi
}

discover_package() { # <rel dir> — appends suites from <dir>/package.json; rc 2 on broken JSON
  local dir="$1" f out pm
  f="$ROOT/package.json"; [ "$dir" = . ] || f="$ROOT/$dir/package.json"
  if ! tc_safe_file "$ROOT" "$f"; then say "skipped: $TC_ERR"; return 0; fi
  pm=$(pm_for "$dir")
  if ! out=$(jq -c --arg dir "$dir" --arg pm "$pm" "$PKG_JQ" "$f" 2>&1); then
    say "broken JSON in ${f#"$ROOT"/}: $(printf '%s\n' "$out" | head -1)"; return 2
  fi
  [ -n "$out" ] && printf '%s\n' "$out" >> "$SUITES_JL"
  return 0
}

# discover_heuristic -> HEUR_SUITES (JSON array, internal `why` kept), PW_CONFIGS; rc 2 broken JSON
discover_heuristic() {
  local inc=() exc=() g re_inc re_exc f d dirs=() t mk pmx kind run why pyc
  : > "$SUITES_JL"
  if [ -f "$ROOT/package.json" ] || [ -L "$ROOT/package.json" ]; then discover_package . || return 2; fi
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    g="${g#./}"; g="${g%/}"
    case "$g" in '!'*) exc+=("${g#!}") ;; *) inc+=("$g") ;; esac
  done < <(workspace_globs)
  inc+=("packages/**" "apps/**")
  tc_globs_re "${inc[@]}"; re_inc="$TC_RE"
  tc_globs_re ${exc[@]+"${exc[@]}"}; re_exc="$TC_RE"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    d="${f%/package.json}"
    tc_re_match "$d" "$re_inc" || continue
    tc_re_match "$d" "$re_exc" && continue
    case "$d" in *[!A-Za-z0-9_.@/+-]*) say "skipped package dir with unusual characters: $d"; continue ;; esac
    dirs+=("$d")
  done < <(find_files 4 package.json | grep -v '^package.json$')
  for d in ${dirs[@]+"${dirs[@]}"}; do discover_package "$d" || return 2; done

  PW_CONFIGS=$(find_files 4 'playwright.config.*' 'cypress.config.*')
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    tc_safe_file "$ROOT" "$ROOT/$f" || { say "skipped: $TC_ERR"; continue; }
    d=$(dirname "$f")
    case "$d" in *[!A-Za-z0-9_.@/+-]*) continue ;; esac
    pmx=$(pmx_for "$(pm_for "$d")")
    case "$(basename "$f")" in
      playwright.*) add_suite "playwright$([ "$d" = . ] || echo ":$d")" "$pmx playwright test" "$d" e2e auto "" pw ;;
      cypress.*)    add_suite "cypress$([ "$d" = . ] || echo ":$d")" "$pmx cypress run" "$d" e2e auto "" cy ;;
    esac
  done <<< "$PW_CONFIGS"

  pyc=0
  [ -f "$ROOT/pytest.ini" ] && pyc=1
  if [ "$pyc" -eq 0 ] && [ -f "$ROOT/pyproject.toml" ] && tc_safe_file "$ROOT" "$ROOT/pyproject.toml" \
     && grep -q '^\[tool\.pytest' "$ROOT/pyproject.toml"; then pyc=1; fi
  if [ "$pyc" -eq 0 ] && { [ -f "$ROOT/pyproject.toml" ] || [ -f "$ROOT/setup.py" ] || [ -f "$ROOT/setup.cfg" ]; } \
     && { [ -d "$ROOT/tests" ] || [ -f "$ROOT/conftest.py" ]; }; then pyc=1; fi
  if [ "$pyc" -eq 1 ]; then
    if [ -f "$ROOT/uv.lock" ]; then add_suite pytest "uv run pytest" . unit auto "" "" 1
    elif [ -f "$ROOT/poetry.lock" ]; then add_suite pytest "poetry run pytest" . unit auto "" "" 1
    else add_suite pytest "python3 -m pytest" . unit auto "" "" 1; fi
  fi
  [ -f "$ROOT/go.mod" ] && add_suite go-test "go test ./..." . unit auto "" "" 1
  [ -f "$ROOT/Cargo.toml" ] && add_suite cargo-test "cargo test" . unit auto "" "" 1
  for mk in GNUmakefile makefile Makefile; do
    [ -f "$ROOT/$mk" ] || continue
    tc_safe_file "$ROOT" "$ROOT/$mk" || { say "skipped: $TC_ERR"; break; }
    while IFS= read -r t; do
      [ -n "$t" ] || continue
      kind=unit; run=auto; why=""
      case "$t" in *e2e*) kind=e2e ;; *integration*) kind=integration ;; esac
      case "$t" in *live*|*canary*|*watch*) run=opt-in; why="name says live/canary/watch" ;; esac
      add_suite "make:$t" "make $t" . "$kind" "$run" "$why"
    done < <(awk '/^(test|e2e)[A-Za-z0-9_.-]*[ \t]*:/ {
                    n = $0; sub(/[ \t]*:.*/, "", n); r = $0; sub(/^[^:]*:/, "", r)
                    c = substr(r, 1, 1); if (c != "=" && c != ":") print n }' "$ROOT/$mk" | LC_ALL=C sort -u)
    break
  done

  # Dedupe: a config already driven by a package script that mentions the runner
  # (same package or an ancestor) is dropped; identical (cwd, cmd) kept once;
  # colliding names get ~N.
  HEUR_SUITES=$(jq -cs '
    . as $all
    | [ $all[] | select(._cfg == null) ] as $scripts
    | def covered($s): any($scripts[]; (if $s._cfg == "pw" then ._pw else ._cy end) == true
                         and (.cwd == "." or .cwd == $s.cwd or ($s.cwd | startswith(.cwd + "/"))));
      [ $all[] | select(._cfg == null or (covered(.) | not)) ]
    | reduce .[] as $s ({seen: {}, names: {}, out: []};
        ($s.cwd + "\u0000" + $s.cmd) as $key
        | if .seen[$key] then . else
            .seen[$key] = true
            | (.names[$s.name] // 0) as $c
            | .names[$s.name] = ($c + 1)
            | .out += [$s | del(._pw, ._cy, ._cfg) | (if $c > 0 then .name = "\(.name)~\($c + 1)" else . end)]
          end)
    | .out' "$SUITES_JL") || return 1
  return 0
}

# Without a contract only the DEFAULT test command of each ecosystem (package.json
# `test`, pytest, go test, cargo test) runs automatically — in `run --all-auto`,
# `recommend.run` and the gate's no-contract warnings. Every other discovered suite
# (e2e, test:*, Playwright/Cypress configs, Makefile targets) becomes opt-in with
# suggest: true (listed under recommend.suggest, never auto): an unknown suite can
# have side effects (a `test:e2e` that runs a build overwrites a live dist/). A
# command that runs a build is never auto, default or not. --init-contract keeps
# the fuller draft (a contract is reviewed and committed by the user).
heuristic_config() { # -> CONFIG from HEUR_SUITES + default globs
  CONFIG=$(jq -nc --argjson s "$HEUR_SUITES" --argjson ui "$TC_DEFAULT_UI_GLOBS" --argjson te "$TC_DEFAULT_TEST_GLOBS" \
    '{suites: [$s[] | if (._default != true) and .run == "auto"
                       then .run = "opt-in" | .suggest = true
                            | .why = "not the default test command of its ecosystem — suggested, not run automatically without a contract"
                       elif .why == "command runs a build" then .suggest = true
                       else . end],
      ui_globs: $ui, ui_exclude: [], test_globs: $te, code_globs: null, small_change: null}')
}

# Discovery cache (pure performance): the heuristic result depends only on the
# discovery inputs, so it is cached per HEAD tree + contract sha + this script's
# own version — and only while every discovery input is clean against HEAD (a
# modified or untracked package.json / config / lockfile bypasses the cache).
# Residual: a gitignored discovery input that changes is not noticed until HEAD moves.
DISC_INPUTS=(':(glob)**/package.json' ':(glob)**/pnpm-workspace.yaml' ':(glob)**/playwright.config.*' ':(glob)**/cypress.config.*'
  ':(glob)**/pnpm-lock.yaml' ':(glob)**/yarn.lock' ':(glob)**/bun.lock*' ':(glob)**/package-lock.json' ':(glob)**/npm-shrinkwrap.json'
  pyproject.toml pytest.ini setup.py setup.cfg conftest.py tests uv.lock poetry.lock go.mod Cargo.toml Makefile makefile GNUmakefile)
disc_cache_file() { # -> path of the cache entry for this state, rc 1 = do not cache
  local ht sv dir id
  [ "$IS_GIT" -eq 1 ] || return 1
  ht=$(git -C "$ROOT" rev-parse -q --verify 'HEAD^{tree}' 2>/dev/null) || return 1
  [ -z "$(git -C "$ROOT" status --porcelain=v1 -- "${DISC_INPUTS[@]}" 2>/dev/null | head -n 1)" ] || return 1
  sv=$(cat "$SCRIPT_DIR/discover-tests.sh" "$SCRIPT_DIR/lib-testclass.sh" 2>/dev/null | tc_sha1) || return 1
  id=$(tc_repo_id "$ROOT") || return 1
  dir="$(tc_cache_root)/claude-subteams/discovery/$id"
  printf '%s/%s.json\n' "$dir" "$(printf '%s %s %s' "$ht" "${CSHA:-none}" "$sv" | tc_sha1)"
}

run_discovery() { # sets CONFIG from heuristics or dies
  local cf="" v rc
  if cf=$(disc_cache_file) && [ -f "$cf" ] && v=$(jq -c 'select(type == "object" and (.heur | type) == "array")' "$cf" 2>/dev/null) && [ -n "$v" ]; then
    HEUR_SUITES=$(printf '%s' "$v" | jq -c '.heur'); PW_CONFIGS=$(printf '%s' "$v" | jq -r '.pw // ""')
    heuristic_config; return 0
  fi
  discover_heuristic; rc=$?
  [ "$rc" -eq 2 ] && die 2 "cannot list suites: broken JSON (see above)"
  [ "$rc" -eq 0 ] || die 1 "discovery failed"
  if [ -n "$cf" ] && (umask 077; mkdir -p "${cf%/*}") 2>/dev/null; then
    jq -nc --argjson h "$HEUR_SUITES" --arg pw "${PW_CONFIGS:-}" '{heur: $h, pw: $pw}' > "$cf.tmp.$$" 2>/dev/null && mv -f "$cf.tmp.$$" "$cf"
    rm -f "$cf.tmp.$$" 2>/dev/null
    find "${cf%/*}" -maxdepth 1 -type f -name '*.json' -mtime +"$TC_RECEIPT_TTL_DAYS" -exec rm -f {} + 2>/dev/null
  fi
  heuristic_config
}

load_contract_or_die() { # <head|index|worktree> -> rc of tc_contract_load (0/1/4), dies on 2/3
  TC_WARN=""; tc_contract_load "$ROOT" "$1"; local rc=$?
  [ -n "$TC_WARN" ] && say "note: $TC_WARN"
  case "$rc" in
    2) die 2 "${TC_ERR:-broken test contract}" ;;
    3) die 3 "$TC_ERR" ;;
  esac
  return "$rc"
}

# ------------------------------------------------------------------- modes

mode_list() {
  local cstate=none cfile="" flist="" hasfiles=false f i FS=$'\037'
  load_contract_or_die worktree
  case $? in
    0) cstate=v1; cfile="$TC_CONTRACT_FILE"; CONFIG="$TC_CONTRACT_JSON" ;;
    4) cstate=declined; cfile="$TC_CONTRACT_FILE"; run_discovery ;;
    *) run_discovery ;;
  esac
  if [ -n "$DIFF_BASE" ]; then
    [ "$IS_GIT" -eq 1 ] || die 64 "--diff needs a git repository"
    git -C "$ROOT" rev-parse --verify -q "$DIFF_BASE^{commit}" >/dev/null || die 64 "unknown base revision: $DIFF_BASE"
    flist=$( { git -c core.quotePath=false -C "$ROOT" diff --name-only --no-renames -z "$DIFF_BASE" -- 2>/dev/null
               git -c core.quotePath=false -C "$ROOT" ls-files -o --exclude-standard -z 2>/dev/null; } \
             | tr '\0' '\n' | LC_ALL=C sort -u)
    hasfiles=true
  elif [ "$FILES_STDIN" -eq 1 ]; then
    flist=$(tr -d '\r' | sed -e 's#^\./##' | grep -v '^$' | LC_ALL=C sort -u)
    hasfiles=true
  fi
  tc_groups_load "$CONFIG" || die 1 "cannot load groups"
  : > "$WORK/rows"
  if [ "$hasfiles" = true ]; then
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      tc_classify "$f"
      [ "$TC_C_UI" -eq 1 ] && printf 'ui%s%s\n' "$FS" "$f"
      [ "$TC_C_CODE" -eq 1 ] && printf 'code%s%s\n' "$FS" "$f"
      [ "$TC_C_TEST" -eq 1 ] && printf 'test%s%s\n' "$FS" "$f"
      [ "$TC_C_DOCS" -eq 1 ] && printf 'docs%s%s\n' "$FS" "$f"
      for i in ${TC_S_NAME[@]+"${!TC_S_NAME[@]}"}; do
        tc_in_suite "$f" "$i" && printf 's:%s%s%s\n' "$i" "$FS" "$f"
      done
    done <<< "$flist" > "$WORK/rows"
  fi
  jq -nR --arg root "$ROOT" --argjson git "$([ "$IS_GIT" -eq 1 ] && echo true || echo false)" \
    --arg contract "$cstate" --arg cfile "$cfile" --argjson cfg "$CONFIG" --argjson hasfiles "$hasfiles" '
    [inputs | select(length > 0) | split("\u001f")] as $rows
    | $cfg.suites as $s
    | def files($g): [$rows[] | select(.[0] == $g) | .[1]];
    (if $hasfiles then {ui: files("ui"), code: files("code"), test: files("test"), docs: files("docs"),
        suites: (reduce range(0; $s | length) as $i ({}; .[$s[$i].name] = files("s:\($i)")))} else null end) as $groups
    | [range(0; $s | length) as $i | $s[$i] as $x
        | (if $hasfiles then ($groups.suites[$x.name] | length) > 0 else true end) as $hit
        | if $x.run == "live" then {skip: {name: $x.name, reason: "live: never run automatically"}}
          elif $x.suggest == true then (if $hit then {suggest: {name: $x.name, cmd: $x.cmd, reason: $x.why}}
                                     else {skip: {name: $x.name, reason: "suggested suite, not affected by these changes"}} end)
          elif $x.run == "opt-in" then {skip: {name: $x.name, reason: ("opt-in: run only on explicit request" + (if $x.why then " (\($x.why))" else "" end))}}
          elif $hit then {run: $x.name}
          else {skip: {name: $x.name, reason: (if $x.paths == null then "no non-docs file changed" else "no changed file in its paths" end)}} end] as $rec
    | {root: $root, git: $git, contract: $contract, contract_file: (if $cfile == "" then null else $cfile end),
       suites: [$s[] | {name, cmd, cwd, kind, run, paths, source}],
       groups: $groups,
       recommend: {run: [$rec[] | .run // empty], suggest: [$rec[] | .suggest // empty], skip: [$rec[] | .skip // empty]}}' < "$WORK/rows"
}

mode_init() {
  local app="null" f txt url
  tc_contract_load "$ROOT" worktree; case $? in
    0) say "note: $TC_CONTRACT_FILE already has a contract; this draft comes from discovery only" ;;
    2) say "note: the existing contract is broken (${TC_ERR}); this draft comes from discovery only" ;;
  esac
  run_discovery
  while IFS= read -r f; do
    case "$(basename "$f")" in playwright.config.*) ;; *) continue ;; esac
    tc_safe_file "$ROOT" "$ROOT/$f" || continue
    txt=$(cat "$ROOT/$f")
    printf '%s' "$txt" | grep -q 'webServer' || continue
    url=$(printf '%s\n' "$txt" | sed -nE "s/.*baseURL:[[:space:]]*['\"](https?:\/\/[^'\"\`\$]+)['\"].*/\1/p" | head -1)
    [ -n "$url" ] || continue
    app=$(jq -nc --arg u "$url" '{url: $u, start: "playwright-webServer"}'); break
  done <<< "${PW_CONFIGS:-}"
  [ "$app" = null ] && [ -n "${PW_CONFIGS:-}" ] && say "note: no literal baseURL + webServer found in the Playwright config — \"app\" left out; add {\"url\": ..., \"start\": \"playwright-webServer\"|\"none\"} if the UI check should open the app"
  jq -n --argjson s "$HEUR_SUITES" --argjson ui "$TC_DEFAULT_UI_GLOBS" --argjson te "$TC_DEFAULT_TEST_GLOBS" \
    --argjson code "$TC_DEFAULT_CODE_GLOBS" --argjson app "$app" --argjson ml "$TC_MAX_LINES" --argjson mf "$TC_MAX_FILES" '
    {suites: [$s[] | {name, cmd, kind, run} + (if .cwd != "." then {cwd} else {} end) + (if .paths != null then {paths} else {} end)],
     ui_globs: $ui, ui_exclude: [], code_globs: $code, test_globs: $te}
    + (if $app != null then {app: $app} else {} end)
    + {small_change: {max_lines: $ml, max_files: $mf}}'
  say "draft printed. Put it into CLAUDE.md between '<!-- subteams:test-suites v1 -->' + a \`\`\`json fence and '<!-- /subteams:test-suites -->'; review suites (opt-in/live) and globs before committing — the contract is committed alone."
}

CSHA=none; CSTATE=none
resolve_config() { # CONFIG CSHA CSTATE CSRC: HEAD contract -> staged contract -> discovery (lib: tc_config_resolve)
  TC_WARN=""; tc_config_resolve "$ROOT"; local rc=$?
  [ -n "$TC_WARN" ] && say "note: $TC_WARN"
  case "$rc" in
    0) CONFIG="$TC_CFG_JSON"; CSHA="$TC_CFG_SHA"; CSTATE="$TC_CFG_STATE"
       if [ "$CSTATE" = new ]; then CSRC=contract-staged; else CSRC=contract; fi ;;
    2) die 2 "${TC_ERR:-broken test contract}" ;;
    3) die 3 "$TC_ERR" ;;
    *) CSTATE="$TC_CFG_STATE"; run_discovery; CSHA=none; CSRC=heuristic ;;
  esac
}

run_config() { # resolve_config + the notes `run` prints (never the working-tree contract)
  resolve_config
  if [ "$CSRC" = contract-staged ]; then
    say "no contract in HEAD yet — using the STAGED contract ($TC_CFG_FILE)"
  elif [ "$CSTATE" = none ] && tc_contract_marker "$ROOT" worktree >/dev/null; then
    say "note: the contract in the working tree is not committed or staged — ignored; using discovered suites"
  fi
}

run_one() { # <suite index> -> the suite's exit code
  local i="$1" v name cmd cwd kind dir msha tree0 tree1 t0 t1 rc dirty receipt rpath
  v=$(printf '%s' "$CONFIG" | jq -r --argjson i "$i" '.suites[$i] | [.name, .cmd, .cwd, .kind] | join("\u001f")')
  IFS=$'\037' read -r name cmd cwd kind <<< "$v"
  dir="$ROOT"; [ "$cwd" = . ] || dir="$ROOT/$cwd"
  [ -d "$dir" ] || { say "$name: cwd '$cwd' does not exist"; return 1; }
  tc_inside_root "$ROOT" "$dir" || { say "$name: cwd '$cwd' resolves outside the project root"; return 1; }
  msha=$(tc_cmd_sha "$cwd" "$cmd")
  tree0=$(tc_snapshot_tree "$ROOT") || { say "$name: cannot snapshot the working tree"; return 1; }
  t0=$(date +%s)
  say "run $name: $cmd   (cwd: $cwd)"
  # B17: environment overrides that silently change what a suite runs are removed
  # (npm_config_* in any case — npm reads them case-insensitively — NODE_OPTIONS,
  # PYTEST_ADDOPTS); the suite gets the project's own command, as the receipt says.
  ( cd "$dir" || exit 1
    while IFS= read -r v; do
      case "$v" in [Nn][Pp][Mm]_[Cc][Oo][Nn][Ff][Ii][Gg]_*) unset "$v" ;; esac
    done < <(compgen -e)
    unset NODE_OPTIONS PYTEST_ADDOPTS
    # ENV (sh startup file), SHELLOPTS / BASHOPTS (exported shell options) would change
    # how the suite's shell behaves; they are readonly inside bash, so they are dropped
    # from the environment of the child. BASH_ENV is kept on purpose (residual, ADR):
    # the Claude Code shell snapshot sets it and suites may rely on it.
    exec env -u ENV -u SHELLOPTS -u BASHOPTS bash -c "$cmd" ) </dev/null
  rc=$?
  t1=$(date +%s)
  tree1=$(tc_snapshot_tree "$ROOT") || tree1=""
  # dirty = a TRACKED file (in HEAD or the index) changed while the suite ran;
  # untracked files the suite wrote (not in the commit, not in the base) are ignored,
  # exactly as the receipt comparison ignores them
  dirty=false; dpaths="[]"; changed=""; untr=0
  if [ "$tree0" != "$tree1" ]; then
    if [ -z "$tree1" ]; then dirty=true
    else
      changed=$(tc_changed_files "$ROOT" "$tree0" "$tree1")
      tracked=$(printf '%s\n' "$changed" | sed '/^$/d; s/^/:(literal)/' | tr '\n' '\0' \
        | { if tc_has_head "$ROOT"; then xargs -0 git -C "$ROOT" ls-files --with-tree=HEAD --; else xargs -0 git -C "$ROOT" ls-files --; fi; } 2>/dev/null | LC_ALL=C sort -u)
      if [ -n "$tracked" ]; then dirty=true; dpaths=$(printf '%s\n' "$tracked" | jq -R . | jq -sc 'map(select(length > 0))')
      else untr=1; fi
    fi
  fi
  receipt=$(jq -nc --arg suite "$name" --arg kind "$kind" --arg cwd "$cwd" --arg cmd_sha "$msha" --arg contract_sha "$CSHA" \
    --argjson exit "$rc" --argjson dirty "$dirty" --argjson dpaths "$dpaths" --arg tree "$tree0" --arg tree_after "$tree1" \
    --argjson t_start "$t0" --argjson t_end "$t1" --arg source "$CSRC" --arg root "$ROOT" \
    '{type: "suite", suite: $suite, kind: $kind, cwd: $cwd, cmd_sha: $cmd_sha, contract_sha: $contract_sha,
      exit: $exit, dirty: $dirty, dirty_paths: $dpaths, tree: $tree, tree_after: $tree_after, t_start: $t_start, t_end: $t_end, source: $source,
      root: $root}')
  rpath=""
  if tc_receipt_write "$ROOT" "$receipt" >/dev/null; then rpath="$TC_RECEIPT_PATH"; else say "$name: WARNING receipt not written: $TC_ERR"; fi
  if [ "$dirty" = true ]; then
    say "$name: tracked files changed while the suite ran — receipt marked dirty (does not count). Changed: $(printf '%s' "$dpaths" | jq -r '.[:5] | join(" ")' 2>/dev/null)"
    say "  (test artifacts? add them to .gitignore)"
  elif [ "$untr" -eq 1 ]; then
    say "$name: the suite created/changed untracked files only ($(printf '%s\n' "$changed" | head -3 | tr '\n' ' ')) — not part of any commit, the receipt counts; consider .gitignore"
  fi
  say "$name: exit $rc${rpath:+ — receipt ${rpath##*/}}"
  return "$rc"
}

mode_run() {
  local i idx="" first=0 rc n=0
  [ "$IS_GIT" -eq 1 ] || die 1 "run needs a git repository (receipts are content snapshots)"
  run_config
  if [ "$ALL_AUTO" -eq 1 ]; then
    while IFS= read -r i; do
      [ -n "$i" ] || continue
      n=$((n+1)); run_one "$i"; rc=$?
      [ "$rc" -ne 0 ] && [ "$first" -eq 0 ] && first=$rc
    done < <(printf '%s' "$CONFIG" | jq -r '.suites | to_entries[] | select(.value.run == "auto") | .key')
    [ "$n" -gt 0 ] || say "no auto suites to run"
    printf '%s' "$CONFIG" | jq -r '.suites[] | select(.run != "auto") | "skipped (\(.run)): \(.name)"' | while IFS= read -r i; do say "$i"; done
    exit "$first"
  fi
  idx=$(printf '%s' "$CONFIG" | jq -r --arg n "$SUITE" '[.suites[].name] | index($n) // empty')
  [ -n "$idx" ] || die 64 "unknown suite '$SUITE'. Known: $(printf '%s' "$CONFIG" | jq -r '[.suites[].name] | join(", ")')"
  run_one "$idx"; exit $?
}

mode_status() {
  local tree base btree target=index big
  [ "$IS_GIT" -eq 1 ] || die 1 "status needs a git repository"
  resolve_config
  tree=$(tc_index_tree "$ROOT") || die 1 "cannot read the index (unresolved merge?)"
  if tc_has_head "$ROOT"; then base=HEAD; btree=$(git -C "$ROOT" rev-parse 'HEAD^{tree}' 2>/dev/null)
  else base=$(tc_empty_tree "$ROOT"); btree="$base"; fi
  if [ "$tree" = "$btree" ]; then
    # Nothing staged: evaluate what `git add -A && git commit` would record, so the
    # orchestrator sees what is missing before staging. Labelled; exit code is for
    # that snapshot (the gate itself always checks the staged tree).
    tree=$(tc_snapshot_tree "$ROOT") || die 1 "cannot snapshot the working tree"
    target=worktree; TC_NO_UNSTAGED=1
    say "nothing staged — evaluating the WORKING TREE (what 'git add -A' would commit) instead of the index"
  fi
  TC_SELF_ID="${CLAUDE_SUBTEAMS_INSTANCE_ID:-}"   # the gate uses ${session_id:0:8}; status has no session
  tc_requirements "$ROOT" "$tree" "$base" "$CONFIG" "$CSHA" || die 1 "cannot evaluate: $TC_ERR"
  [ "${TC_RECEIPTS_CAPPED:-0}" -gt 0 ] && say "note: only the newest $TC_RECEIPT_CAP receipts per type were considered ($TC_RECEIPTS_CAPPED older ignored)"
  big=$(tc_large_untracked "$ROOT")
  printf '%s' "$TC_REQ_JSON" | jq --arg root "$ROOT" --arg contract "$CSTATE" --arg target "$target" --arg big "$big" \
    '{root: $root, contract: $contract, enforced: ($contract == "v1"), target: $target} + .
     + {large_untracked: ($big | split("\n") | map(select(length > 0)))}'
  printf '%s\n' "$TC_REQ_WARN" | while IFS= read -r f; do [ -n "$f" ] && say "WARNING: $f"; done
  big=$(printf '%s\n' "$big" | paste -sd, - | sed 's/,/, /g')
  [ -n "$big" ] && say "WARNING: large untracked files make every content snapshot slow: $big — add them to .gitignore or move them out"
  [ -n "$TC_REQ_ANCHORS" ] && say "note: small change without an agent check — the commit gate will create a drift anchor ($(printf '%s' "$TC_REQ_ANCHORS" | awk '{print $1}' | paste -sd, -)) on commit; further small commits accumulate from it"
  if [ "$TC_REQ_OK" -eq 1 ]; then say "status ($target): everything the gate checks is in place (contract: $CSTATE)"
  else
    say "status ($target): missing (contract: $CSTATE$([ "$CSTATE" = v1 ] || echo ', gate only warns')):"
    printf '%s\n' "$TC_REQ_MISSING" | while IFS= read -r f; do say "  - $f"; done
  fi
  [ "$TC_REQ_OK" -eq 1 ]
}

mode_config() {
  [ "$IS_GIT" -eq 1 ] || die 1 "config needs a git repository (the contract is read from HEAD / the index)"
  resolve_config
  jq -n --arg state "$CSTATE" --arg sha "$CSHA" --arg file "${TC_CFG_FILE:-}" --argjson cfg "$CONFIG" \
    '{state: $state, contract_sha: $sha, file: (if $file == "" then null else $file end), config: $cfg}'
}

case "$MODE" in
  list) mode_list ;;
  init) mode_init ;;
  run) mode_run ;;
  status) mode_status ;;
  config) mode_config ;;
esac
