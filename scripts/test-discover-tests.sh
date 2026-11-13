#!/usr/bin/env bash
# test-discover-tests.sh — тесты scripts/lib-testclass.sh, scripts/discover-tests.sh и
# bin/subteams-tests (IMPL-PLAN 1.50.0, Задача 1.2): обнаружение наборов, контракт v1,
# классификация, снимок дерева, дрейф, квитанции, run/status/--init-contract.
# Временные каталоги и XDG_CACHE_HOME живут в $TMPDIR (по умолчанию /tmp) и удаляются
# на выходе. Боевой кэш пользователя и глобальный git-конфиг не трогаются.
# Использование: bash scripts/test-discover-tests.sh   (exit 0 = все PASS, иначе 1)
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ST="$DIR/bin/subteams-tests"
LIB="$DIR/scripts/lib-testclass.sh"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-discover-XXXXXX")
TMP=$(cd -P "$TMP" && pwd)
trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null || { echo "jq required"; exit 2; }

export XDG_CACHE_HOME="$TMP/cache"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE

mkdir -p "$TMP/nojq"   # PATH without jq (for the no-jq cases)
for c in bash env readlink realpath dirname basename cat mktemp rm git sed grep awk tr sort find wc cut head sha1sum shasum; do
  p=$(command -v "$c") && ln -sf "$p" "$TMP/nojq/$c"
done

FAILS=0; PASSES=0
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS $1"; PASSES=$((PASSES+1)); else echo "FAIL $1: expected [$2] got [$3]"; [ -n "${ERR:-}" ] && printf "     last stderr: %s\n" "$(printf "%s" "$ERR" | tail -2)"; FAILS=$((FAILS+1)); fi
}

RC=0; OUT=""; ERR=""
st() { # <cwd> <args...> -> RC OUT ERR (stdin passes through)
  local cwd="$1"; shift
  (cd "$cwd" && "$ST" "$@") >"$TMP/out" 2>"$TMP/err"
  RC=$?; OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
q() { printf '%s' "$OUT" | jq -c "$1" 2>/dev/null; }      # compact jq over OUT
qr() { printf '%s' "$OUT" | jq -r "$1" 2>/dev/null; }

mkd() { mkdir -p "$TMP/$1" && echo "$TMP/$1"; }
mkgit() { # <name> -> path; empty commit so HEAD exists
  local r; r=$(mkd "$1"); git -C "$r" init -q -b main; git -C "$r" commit -q --allow-empty -m init; echo "$r"
}
commit_all() { git -C "$1" add -A && git -C "$1" commit -q -m "${2:-c}"; }
contract() { # <file> <json> — writes a contract block into a markdown file
  printf '# Project\n\ntext\n\n<!-- subteams:test-suites v1 -->\n```json\n%s\n```\n<!-- /subteams:test-suites -->\n' "$2" > "$1"
}
receipts() { find "$XDG_CACHE_HOME/claude-subteams/receipts" -name '*.json' 2>/dev/null | wc -l | tr -d ' '; }
newest_receipt() { # <repo> -> JSON of the newest suite receipt
  (. "$LIB"; d=$(tc_receipt_dir "$1"); ls -t "$d"/*-suite-*.json 2>/dev/null | head -1 | xargs cat)
}

echo "--- discovery: package managers"
P=$(mkd npm); printf '{"scripts":{"test":"vitest run","test:e2e":"playwright test","build":"tsc","lint":"eslint ."}}' > "$P/package.json"; : > "$P/package-lock.json"
st "$P"
check "npm: rc 0" 0 "$RC"
check "npm: names" '["test","test:e2e"]' "$(q '[.suites[].name]')"
check "npm: cmds" '["npm test","npm run test:e2e"]' "$(q '[.suites[].cmd]')"
check "npm: kinds" '["unit","e2e"]' "$(q '[.suites[].kind]')"
check "npm: source heuristic, contract none" '["heuristic","none"]' "$(q '[.suites[0].source, .contract]')"
P=$(mkd pnpm); printf '{"scripts":{"test":"vitest run","test:int":"vitest run -c int"}}' > "$P/package.json"; : > "$P/pnpm-lock.yaml"
st "$P"; check "pnpm: cmds" '["pnpm test","pnpm run test:int"]' "$(q '[.suites[].cmd]')"
check "pnpm: test:int is integration" '"integration"' "$(q '.suites[1].kind')"
P=$(mkd yarn); printf '{"scripts":{"test":"jest","e2e":"cypress run"}}' > "$P/package.json"; : > "$P/yarn.lock"
st "$P"; check "yarn: cmds" '["yarn test","yarn run e2e"]' "$(q '[.suites[].cmd]')"
P=$(mkd bun); printf '{"scripts":{"test":"bun test"}}' > "$P/package.json"; : > "$P/bun.lockb"
st "$P"; check "bun: bun run test (not bun's own runner)" '["bun run test"]' "$(q '[.suites[].cmd]')"

echo "--- discovery: monorepo"
P=$(mkd mono); printf '{"workspaces":["packages/*","libs/*","!libs/skip"],"scripts":{"build":"x"}}' > "$P/package.json"; : > "$P/package-lock.json"
mkdir -p "$P/packages/a" "$P/apps/web" "$P/libs/x" "$P/libs/skip" "$P/other/y" "$P/packages/g/h" "$P/packages/d/a/b" "$P/node_modules/z"
printf '{"scripts":{"test":"jest"}}' > "$P/packages/a/package.json"
printf '{"scripts":{"test":"vitest run","e2e":"playwright test"}}' > "$P/apps/web/package.json"
printf '{"scripts":{"test":"x"}}' > "$P/libs/x/package.json"
printf '{"scripts":{"test":"x"}}' > "$P/libs/skip/package.json"
printf '{"scripts":{"test":"x"}}' > "$P/other/y/package.json"
printf '{"scripts":{"test":"x"}}' > "$P/packages/g/h/package.json"
printf '{"scripts":{"test":"x"}}' > "$P/packages/d/a/b/package.json"
printf '{"scripts":{"test":"x"}}' > "$P/node_modules/z/package.json"
: > "$P/apps/web/pnpm-lock.yaml"
st "$P"
check "mono: names (depth<=3, workspaces, negation, apps/*, no node_modules)" \
  '["apps/web:e2e","apps/web:test","libs/x:test","packages/a:test","packages/g/h:test"]' "$(q '[.suites[].name] | sort')"
check "mono: cwd + paths of a package" '{"cwd":"packages/a","paths":["packages/a/**"]}' "$(q '.suites[] | select(.name=="packages/a:test") | {cwd,paths}')"
check "mono: per-package lockfile wins (pnpm in apps/web)" '"pnpm test"' "$(q '.suites[] | select(.name=="apps/web:test") | .cmd')"
P=$(mkd pnpmws); printf '{"scripts":{}}' > "$P/package.json"; : > "$P/pnpm-lock.yaml"
printf "packages:\n  - 'tools/*'   # comment\nonlyBuiltDependencies:\n  - esbuild\n" > "$P/pnpm-workspace.yaml"
mkdir -p "$P/tools/t" "$P/esbuild"; printf '{"scripts":{"test":"x"}}' > "$P/tools/t/package.json"; printf '{"scripts":{"test":"x"}}' > "$P/esbuild/package.json"
st "$P"; check "pnpm-workspace.yaml packages only" '["tools/t:test"]' "$(q '[.suites[].name]')"

echo "--- discovery: Playwright config in a subdirectory"
P=$(mkd pw); printf '{"scripts":{"test":"vitest run"}}' > "$P/package.json"; mkdir -p "$P/e2e"
printf "export default { use: { baseURL: 'http://localhost:4000' }, webServer: { command: 'node s.js', url: 'http://localhost:4000' } }\n" > "$P/e2e/playwright.config.ts"
st "$P"
check "pw: config suite added (B9: not the default test command -> opt-in, suggested)" '{"name":"playwright:e2e","cmd":"npx playwright test","cwd":"e2e","kind":"e2e","run":"opt-in"}' \
  "$(q '.suites[] | select(.name=="playwright:e2e") | {name,cmd,cwd,kind,run}')"
check "B9: recommend.run = only the default test command; e2e under recommend.suggest" '{"run":["test"],"suggest":["playwright:e2e"]}' \
  "$(q '{run: .recommend.run, suggest: [.recommend.suggest[].name]}')"
st "$P" --init-contract
check "B9: --init-contract keeps the e2e suite auto (the user reviews the draft)" '"auto"' "$(q '.suites[] | select(.name=="playwright:e2e") | .run')"
P2=$(mkd pw2); cp -R "$P/e2e" "$P2/"; printf '{"scripts":{"test":"vitest run","test:e2e":"playwright test -c e2e/playwright.config.ts"}}' > "$P2/package.json"
st "$P2"; check "pw: deduped with the script that runs Playwright" '["test","test:e2e"]' "$(q '[.suites[].name]')"
mkdir -p "$P/a/b/c/d"; printf 'x' > "$P/a/b/c/d/cypress.config.js"; mkdir -p "$P/a/b/c"; printf 'x' > "$P/a/b/c/cypress.config.js"
st "$P"; check "cypress depth: a/b/c found, a/b/c/d not" '["cypress:a/b/c"]' "$(q '[.suites[].name | select(startswith("cypress"))]')"

echo "--- discovery: Python, Go, Cargo, Makefile"
P=$(mkd py); printf '[project]\nname="x"\n[tool.pytest.ini_options]\naddopts="-q"\n' > "$P/pyproject.toml"
st "$P"; check "python: pytest" '[{"name":"pytest","cmd":"python3 -m pytest"}]' "$(q '[.suites[] | {name,cmd}]')"
: > "$P/uv.lock"; st "$P"; check "python + uv.lock" '"uv run pytest"' "$(q '.suites[0].cmd')"
P=$(mkd pyini); : > "$P/pytest.ini"; st "$P"; check "pytest.ini" '["pytest"]' "$(q '[.suites[].name]')"
P=$(mkd go); printf 'module x\n' > "$P/go.mod"; st "$P"; check "go" '[{"name":"go-test","cmd":"go test ./..."}]' "$(q '[.suites[] | {name,cmd}]')"
P=$(mkd rs); printf '[package]\n' > "$P/Cargo.toml"; st "$P"; check "cargo" '["cargo test"]' "$(q '[.suites[].cmd]')"
P=$(mkd mk); printf 'test:\n\techo t\ntest-integration: build\n\techo i\ne2e:\n\techo e\ntest_live:\n\techo l\ntestvar := 1\nTESTX: \nbuild:\n\techo b\n' > "$P/Makefile"
st "$P"
check "make: targets" '["make:e2e","make:test","make:test-integration","make:test_live"]' "$(q '[.suites[].name] | sort')"
check "make: kinds/run" '{"e2e":"e2e","int":"integration","live":"opt-in"}' \
  "$(q '{e2e: (.suites[]|select(.name=="make:e2e")|.kind), int: (.suites[]|select(.name=="make:test-integration")|.kind), live: (.suites[]|select(.name=="make:test_live")|.run)}')"

echo "--- discovery: empty / non-git / broken / opt-in"
P=$(mkd empty); st "$P"
check "empty non-git: rc 0, no suites, git false" '[0,[],false,"none"]' "[$RC,$(q '.suites'),$(q '.git'),$(q '.contract')]"
P=$(mkgit emptygit); st "$P"; check "empty git repo: rc 0, no suites" '[0,[]]' "[$RC,$(q '.suites')]"
P=$(mkd nohead); git -C "$P" init -q -b main; printf '{"scripts":{"test":"x"}}' > "$P/package.json"
st "$P"; check "git repo without commits: lists" '["test"]' "$(q '[.suites[].name]')"
P=$(mkd broken); printf '{"scripts":{"test":' > "$P/package.json"; st "$P"
check "broken package.json -> rc 2" 2 "$RC"
check "broken package.json -> reason on stderr, stdout empty" '1:' "$(printf '%s' "$ERR" | grep -q 'broken JSON' && echo 1):$OUT"
P=$(mkd optin); printf '{"scripts":{"test":"vitest run","test:slow":"RUN_X=1 vitest run","test:canary":"vitest run c","test:live-sdk":"vitest run l","test:watch":"vitest"}}' > "$P/package.json"
st "$P"
check "RUN_X=1 / canary / live / watch -> opt-in" '{"test":"auto","test:canary":"opt-in","test:live-sdk":"opt-in","test:slow":"opt-in","test:watch":"opt-in"}' "$(printf '%s' "$OUT" | jq -cS '[.suites[] | {(.name): .run}] | add')"
check "opt-in skipped in recommend with reason" 1 "$(q '.recommend.skip[] | select(.name=="test:slow") | .reason' | grep -q 'RUN_' && echo 1 || echo 0)"
check "recommend.run = auto suites without a file list" '["test"]' "$(q '.recommend.run')"

echo "--- contract v1"
P=$(mkd c1); printf '{"scripts":{"test":"vitest run"}}' > "$P/package.json"
contract "$P/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"npm test","kind":"unit","run":"auto","paths":["src/**"]},{"name":"live","cmd":"x","run":"live"}]}'
st "$P"
check "contract wins over heuristics" '{"c":"v1","f":"CLAUDE.md","n":["unit","live"],"s":["contract","contract"]}' "$(q '{c:.contract,f:.contract_file,n:[.suites[].name],s:[.suites[].source]}')"
check "contract defaults filled (cwd, kind)" '{"cwd":".","kind":"unit"}' "$(q '.suites[1] | {cwd,kind}')"
check "live suite skipped" '"live: never run automatically"' "$(q '.recommend.skip[0].reason')"
P=$(mkd c2); contract "$P/AGENTS.md" '{"suites":[{"name":"from-agents","cmd":"x"}]}'
st "$P"; check "contract in AGENTS.md only" '["AGENTS.md",["from-agents"]]' "$(q '[.contract_file,[.suites[].name]]')"
contract "$P/CLAUDE.md" '{"suites":[{"name":"from-claude","cmd":"x"}]}'
st "$P"; check "CLAUDE.md wins over AGENTS.md" '["CLAUDE.md",["from-claude"]]' "$(q '[.contract_file,[.suites[].name]]')"
printf '# x\n<!-- subteams:test-suites none -->\n' > "$P/CLAUDE.md"
st "$P"; check "none in CLAUDE.md does not fall through to AGENTS.md" '"declined"' "$(q '.contract')"
P=$(mkd c3); printf '{"scripts":{"test":"jest"}}' > "$P/package.json"
printf '# Doc\n```markdown\n<!-- subteams:test-suites v1 -->\n```\n' > "$P/CLAUDE.md"
st "$P"; check 'marker inside a 3-backtick block ignored' '["none",["test"]]' "$(q '[.contract,[.suites[].name]]')"
printf '# Doc\n````markdown\n<!-- subteams:test-suites v1 -->\n```json\n{"suites":[]}\n```\n<!-- /subteams:test-suites -->\n````\n' > "$P/CLAUDE.md"
st "$P"; check 'marker inside a 4-backtick block (with an inner 3-backtick fence) ignored' '"none"' "$(q '.contract')"
printf '~~~\n<!-- subteams:test-suites v1 -->\n~~~\n' > "$P/CLAUDE.md"; st "$P"; check "marker inside ~~~ ignored" '"none"' "$(q '.contract')"
printf ' <!-- subteams:test-suites v1 -->\n```json\n{"suites":[]}\n```\n' > "$P/CLAUDE.md"; st "$P"; check "marker not at line start ignored" '"none"' "$(q '.contract')"
printf '```\nexample\n```\n\n<!-- subteams:test-suites v1 -->\n\n```json\n{"suites":[{"name":"u","cmd":"x"}]}\n```\n' > "$P/CLAUDE.md"
st "$P"; check "real marker after a closed fence + blank line" '["v1",["u"]]' "$(q '[.contract,[.suites[].name]]')"
printf '<!-- subteams:test-suites v1 -->\r\n```json\r\n{"suites":[{"name":"crlf","cmd":"x"}]}\r\n```\r\n' > "$P/CLAUDE.md"
st "$P"; check "CRLF contract" '["crlf"]' "$(q '[.suites[].name]')"
P=$(mkd c4); printf '{"scripts":{"test":"jest"}}' > "$P/package.json"; printf '# x\n<!-- subteams:test-suites none -->\n' > "$P/CLAUDE.md"
st "$P"; check "none marker -> declined, heuristic suites still listed" '["declined",["test"]]' "$(q '[.contract,[.suites[].name]]')"
P=$(mkd c5)
for bad in '{"suites":[{"name":"u","cmd":"x"}' '{"suites":[{"name":"u","cmd":"x","run":"sometimes"}]}' \
           '{"suites":[{"name":"u","cmd":"x"},{"name":"u","cmd":"y"}]}' '{"suites":[{"name":"u","cmd":"x","cwd":"../up"}]}' \
           '{"suites":[{"name":"a b","cmd":"x"}]}' '{"suites":[{"name":"u","cmd":""}]}' '[1]' '{"ui_globs":"src/**"}' \
           '{"app":{"start":"npm start"}}' '{"small_change":{"max_lines":-1}}' '{} {}' \
           '{"suites":[{"name":"u","cmd":"exit 0\nexit 1"}]}' '{"suites":[{"name":"u","cmd":"x","cwd":"a\tb"}]}'; do
  contract "$P/CLAUDE.md" "$bad"; st "$P"; check "broken contract -> rc 2: $bad" 2 "$RC"
done
printf '<!-- subteams:test-suites v1 -->\nno fence here\n' > "$P/CLAUDE.md"; st "$P"; check "marker without a fence -> rc 2" 2 "$RC"
printf '<!-- subteams:test-suites v1 -->\n```json\n{"suites":[]}\n' > "$P/CLAUDE.md"; st "$P"; check "unclosed fence -> rc 2" 2 "$RC"
contract "$P/CLAUDE.md" '{"suites":[],"small_change":{"max_lines":50,"max_files":1}}'
check "small_change can only be lowered (50/1 -> 10/1)" "10 1" "$(. "$LIB"; tc_contract_load "$P" worktree; tc_threshold "$TC_CONTRACT_JSON"; echo "$TC_TH_LINES $TC_TH_FILES")"
check "marker check works without jq (awk only)" "v1" "$(. "$LIB"; PATH="$TMP/nojq"; command -v jq >/dev/null && echo has-jq; tc_contract_marker "$P" worktree)"

echo "--- classification matrix"
P=$(mkd cls)
contract "$P/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"x","paths":["src/**"]},{"name":"e2e","cmd":"y","kind":"e2e"}],"ui_globs":["src/ui/**","public/**"],"ui_exclude":["public/emails/**"],"test_globs":["**/*.test.*","tests/**"]}'
st "$P" --files - < <(printf 'templates/plan.md\napp/main.py\npublic/emails/welcome.html\ntests/a.test.ts\nsrc/ui/Button.tsx\nsrc/ui/Button.test.tsx\n./src/lib/x.ts\n')
check "rc 0" 0 "$RC"
check "ui = ui_globs - ui_exclude - test" '["src/ui/Button.tsx"]' "$(q '.groups.ui')"
check "code (no code_globs) = non-docs outside ui/test + B10 scripts inside ui_globs" '["app/main.py","src/lib/x.ts","src/ui/Button.tsx"]' "$(q '.groups.code')"
check "test files" '["src/ui/Button.test.tsx","tests/a.test.ts"]' "$(q '.groups.test')"
check "docs" '["templates/plan.md"]' "$(q '.groups.docs')"
check "suite with paths" '["src/lib/x.ts","src/ui/Button.test.tsx","src/ui/Button.tsx"]' "$(q '.groups.suites.unit')"
check "suite without paths = every non-docs file (tests included)" 6 "$(q '.groups.suites.e2e | length')"
st "$P" --files - < <(printf 'src/ui/page.html\nsrc/ui/a.css\nsrc/ui/C.vue\nsrc/ui/s.mjs\n')
check "B10: markup/styles in ui only; .vue/.mjs in ui AND code" '{"code":["src/ui/C.vue","src/ui/s.mjs"],"ui":["src/ui/C.vue","src/ui/a.css","src/ui/page.html","src/ui/s.mjs"]}' "$(q '{code:.groups.code, ui:.groups.ui}')"
contract "$P/CLAUDE.md" '{"suites":[],"ui_globs":["src/ui/**"],"code_globs":["src/**"],"test_globs":["**/*.test.*"]}'
st "$P" --files - < <(printf 'src/ui/Button.tsx\napp/main.py\nsrc/a.test.ts\n')
check "explicit code_globs: ui file is also code, outside file is not, test is not" '{"code":["src/ui/Button.tsx"],"ui":["src/ui/Button.tsx"]}' "$(q '{code:.groups.code, ui:.groups.ui}')"
contract "$P/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"x","paths":["src/**"]},{"name":"e2e","cmd":"y"}]}'
st "$P" --files - < <(printf 'templates/plan.md\n')
check "docs-only change: nothing to run, reasons given" '{"run":[],"why":["no changed file in its paths","no non-docs file changed"]}' "$(q '{run:.recommend.run, why:[.recommend.skip[].reason]}')"
check "brace globs" '[1,0]' "$(. "$LIB"; tc_globs_re 'src/*.{ts,tsx}'; a=0; b=0; tc_re_match src/a.tsx "$TC_RE" && a=1; tc_re_match src/d/a.ts "$TC_RE" && b=1; echo "[$a,$b]")"
check "**/ matches zero dirs; trailing /** everything inside" '[1,1,1,0]' "$(. "$LIB"; r=""; for f in a.test.ts d/e/a.test.ts; do tc_globs_re '**/*.test.*'; tc_re_match "$f" "$TC_RE" && r="$r,1" || r="$r,0"; done; tc_globs_re 'src/**'; tc_re_match src/x/y "$TC_RE" && r="$r,1" || r="$r,0"; tc_re_match srcx/y "$TC_RE" && r="$r,1" || r="$r,0"; echo "[${r#,}]")"

echo "--- docs-class: identical to the pre-1.50 inline logic of pre-commit-gate"
old_docs() { # verbatim logic from hooks/pre-commit-gate before the move (rc 0 = skip)
  local f="$1" NEUTRAL_RE='^(\.gitignore|\.editorconfig|\.gitattributes|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Cargo\.lock|go\.sum|poetry\.lock|uv\.lock|composer\.lock)$|(^|/)\.DS_Store$'
  printf '%s\n' "$f" | grep -qE "$NEUTRAL_RE" && return 0
  if printf '%s\n' "$f" | grep -qE '\.(md|txt|csv|rst|adoc)$' \
     && ! printf '%s\n' "$f" | grep -qiE '(^|/)[^/]*(requirements|constraints)[^/]*\.txt$'; then return 0; fi
  return 1
}
diffs=""
for f in README.md a.txt a.TXT notes.csv x.rst y.adoc docs/requirements-dev.txt Constraints.txt REQUIREMENTS.TXT requirements.txt \
         sub/package-lock.json package-lock.json sub/.DS_Store .DS_Store .gitignore sub/.gitignore yarn.lock go.sum uv.lock \
         a.ts index.html c.yaml d.json Makefile 'dir with space/a.md' 'ünï/код.md' 'a.md.bak' '.md' 'mdx.mdx' 'x/Cargo.lock'; do
  o=0; n=0; old_docs "$f" && o=1; (. "$LIB"; tc_is_docs_class "$f") && n=1
  [ "$o" = "$n" ] || diffs="$diffs $f($o/$n)"
done
check "tc_is_docs_class == old inline logic on 30 paths" "" "$diffs"
check "tc_is_docs_class leaves nocasematch as it was" "off" "$(. "$LIB"; tc_is_docs_class requirements.txt; shopt -q nocasematch && echo on || echo off)"

echo "--- snapshot tree (temp index; real index untouched)"
R=$(mkgit snap); printf 'a\n' > "$R/a.txt"; printf 'b\n' > "$R/b.txt"; printf 'ign\n' > "$R/.gitignore"; commit_all "$R"
echo staged > "$R/s.txt"; git -C "$R" add s.txt
IDX0=$(git -C "$R" ls-files -s | cksum); IDXF0=$(cksum < "$R/.git/index")
T0=$(. "$LIB"; tc_snapshot_tree "$R")
echo new > "$R/c.txt"; T1=$(. "$LIB"; tc_snapshot_tree "$R")
rm "$R/b.txt"; T2=$(. "$LIB"; tc_snapshot_tree "$R")
git -C "$R" mv a.txt d.txt 2>/dev/null || mv "$R/a.txt" "$R/d.txt"; T3=$(. "$LIB"; tc_snapshot_tree "$R")
echo x > "$R/ign"; T4=$(. "$LIB"; tc_snapshot_tree "$R")
check "snapshot: new file changes the tree and is in it" "1:c.txt" "$([ "$T0" != "$T1" ] && echo 1):$(git -C "$R" ls-tree --name-only "$T1" | grep -x c.txt)"
check "snapshot: deleted file is gone" "" "$(git -C "$R" ls-tree --name-only "$T2" | grep -x b.txt)"
check "snapshot: renamed file" "d.txt|" "$(git -C "$R" ls-tree --name-only "$T3" | grep -x d.txt)|$(git -C "$R" ls-tree --name-only "$T3" | grep -x a.txt)"
check "snapshot: .gitignore respected" "$T3" "$T4"
check "snapshot: staged file included" "s.txt" "$(git -C "$R" ls-tree --name-only "$T0" | grep -x s.txt)"
git -C "$R" reset -q -- d.txt a.txt 2>/dev/null
R2=$(mkgit snap2); echo s > "$R2/s.txt"; git -C "$R2" add s.txt; echo u > "$R2/u.txt"
IDXB=$(cksum < "$R2/.git/index"); (. "$LIB"; tc_snapshot_tree "$R2" >/dev/null); IDXA=$(cksum < "$R2/.git/index")
check "snapshot: real index file byte-identical" "$IDXB" "$IDXA"
check "snapshot: untracked file not staged in the real index" "s.txt" "$(git -C "$R2" diff --cached --name-only)"
check "index tree == git write-tree of the staged state" "$(git -C "$R2" write-tree)" "$(. "$LIB"; tc_index_tree "$R2")"
R4=$(mkgit snap4); echo a > "$R4/a.txt"; echo s > "$R4/s.txt"; commit_all "$R4"
git -C "$R4" update-index --assume-unchanged a.txt; echo CHANGED >> "$R4/a.txt"
git -C "$R4" update-index --skip-worktree s.txt; rm "$R4/s.txt"
T=$(. "$LIB"; tc_snapshot_tree "$R4")
check "snapshot: edit of an assume-unchanged file is seen" "a CHANGED" "$(git -C "$R4" cat-file -p "$T:a.txt" | tr '\n' ' ' | sed 's/ $//')"
check "snapshot: skip-worktree (sparse) file absent on disk is not a deletion" "s.txt" "$(git -C "$R4" ls-tree --name-only "$T" | grep -x s.txt)"
check "snapshot: assume-unchanged bit kept in the real index" "h a.txt" "$(git -C "$R4" ls-files -v a.txt)"
R5=$(mkgit snap5); printf 'dist/\n' > "$R5/.gitignore"; mkdir -p "$R5/dist"; echo b > "$R5/dist/b.js"; git -C "$R5" add .gitignore; git -C "$R5" add -f dist/b.js
check "snapshot: force-added ignored file kept (= commit tree)" "$(git -C "$R5" write-tree)" "$(. "$LIB"; tc_snapshot_tree "$R5")"
R3=$(mkd snap3); git -C "$R3" init -q -b main; echo n > "$R3/n.txt"
check "snapshot without HEAD (fresh repo)" "n.txt" "$(T=$(. "$LIB"; tc_snapshot_tree "$R3") && git -C "$R3" ls-tree --name-only "$T")"
check "snapshot without HEAD leaves no index behind" "no" "$([ -e "$R3/.git/index" ] && echo yes || echo no)"

echo "--- drift"
R=$(mkgit drift)
mkdir -p "$R/src/ui" "$R/tests"; printf '1\n2\n3\n4\n5\n' > "$R/src/ui/a.html"; printf 'x\n' > "$R/src/ui/b.css"; printf 't\n' > "$R/tests/u.test.ts"; commit_all "$R"
CFG='{"suites":[],"ui_globs":["src/ui/**"],"test_globs":["tests/**"],"ui_exclude":[]}'
A=$(git -C "$R" rev-parse 'HEAD^{tree}')
printf '1\nX\nY\n4\n5\nZ\n' > "$R/src/ui/a.html"; printf 'changed\n' > "$R/tests/u.test.ts"
B=$(. "$LIB"; tc_snapshot_tree "$R")
check "drift: lines/files, test file not counted" '{"lines":5,"files":1,"added":false,"deleted":false,"renamed":false,"binary":false}' \
  "$(. "$LIB"; tc_groups_load "$CFG"; tc_drift "$R" "$A" "$B" ui; tc_drift_json | jq -c .)"
echo n > "$R/src/ui/new.js"; printf '\000\001' > "$R/src/ui/img.png"; B=$(. "$LIB"; tc_snapshot_tree "$R")
check "drift: added + binary flagged" '[true,true]' "$(. "$LIB"; tc_groups_load "$CFG"; tc_drift "$R" "$A" "$B" ui; tc_drift_json | jq -c '[.added,.binary]')"
git -C "$R" checkout -q -- . ; rm -f "$R/src/ui/new.js" "$R/src/ui/img.png"; mv "$R/src/ui/b.css" "$R/src/ui/c.css"; B=$(. "$LIB"; tc_snapshot_tree "$R")
check "drift: rename flagged" 'true' "$(. "$LIB"; tc_groups_load "$CFG"; tc_drift "$R" "$A" "$B" ui; tc_drift_json | jq -c '.renamed')"
check "drift: missing tree -> rc 1" 1 "$(. "$LIB"; tc_groups_load "$CFG"; tc_drift "$R" "$A" 0123456789012345678901234567890123456789 ui; echo $?)"

echo "--- receipt store"
R=$(mkgit store)
EXP="$XDG_CACHE_HOME/claude-subteams/receipts/$(printf '%s' "$(cd -P "$R/.git" && pwd)" | (sha1sum 2>/dev/null || shasum -a 1) | cut -d' ' -f1)"
check "receipt dir = sha1 of canonical git-common-dir" "$EXP" "$(. "$LIB"; tc_receipt_dir "$R")"
check "receipt dir from a subdirectory is the same" "$EXP" "$(mkdir -p "$R/sub"; . "$LIB"; tc_receipt_dir "$R/sub")"
mkdir -p "$EXP"; printf '{}' > "$EXP/0000000001-suite-old.json"; touch -t 202001010000 "$EXP/0000000001-suite-old.json"
printf '{}' > "$EXP/fresh.json"
WP=$(. "$LIB"; tc_receipt_write "$R" '{"type":"te","status":"pass","t_start":1,"t_end":2,"tree":"x"}')
check "write: atomic file in place, no temp left" "1:0" "$([ -f "$WP" ] && echo 1):$(find "$EXP" -name '.tmp*' | wc -l | tr -d ' ')"
check "write: purge > 14 days, fresh kept" "gone:kept" "$([ -e "$EXP/0000000001-suite-old.json" ] && echo kept || echo gone):$([ -e "$EXP/fresh.json" ] && echo kept || echo gone)"
check "write: rejects receipt without .type" 1 "$(. "$LIB"; tc_receipt_write "$R" '{"x":1}' >/dev/null 2>&1; echo $?)"
check "read/list" '"te"' "$(. "$LIB"; tc_receipt_read "$WP" | jq -c .type)"
printf '{"kind":"shot","path":"/p.png","size":3,"session":"s","ts":5}\n' > "$EXP/shot-5-1-1.json"; printf 'garbage{' > "$EXP/zz-broken.json"
check "load: shot receipt of subteams-browser normalized, broken file skipped" '["shot","te"]' "$(. "$LIB"; tc_receipts_load "$R" | jq -sc 'map(.type) | map(select(. != null)) | sort')"

echo "--- run"
R=$(mkgit run); mkdir -p "$R/src" "$R/sub"; echo 1 > "$R/src/a.ts"; echo t > "$R/tracked.txt"
contract "$R/CLAUDE.md" '{"suites":[
 {"name":"pass","cmd":"exit 0","paths":["src/**"]},
 {"name":"fail","cmd":"echo out-line; echo err-line >&2; exit 3"},
 {"name":"flip","cmd":"exit 1","run":"opt-in"},
 {"name":"dirty","cmd":"echo more >> tracked.txt","run":"opt-in"},
 {"name":"stdin","cmd":"test -z \"$(cat)\"","run":"opt-in"},
 {"name":"cwd","cmd":"test \"$(basename \"$PWD\")\" = sub","cwd":"sub","run":"opt-in"},
 {"name":"optin","cmd":"touch ran-optin","run":"opt-in"}]}'
commit_all "$R"
st "$R" run fail
check "run: real exit code" 3 "$RC"
check "run: suite output streamed (stdout/stderr)" "out-line|1" "$OUT|$(printf '%s\n' "$ERR" | grep -cx err-line)"
REC=$(newest_receipt "$R")
CSHA=$(. "$LIB"; tc_contract_load "$R" head; echo "$TC_CONTRACT_SHA")
check "run: receipt fields" "{\"type\":\"suite\",\"suite\":\"fail\",\"exit\":3,\"dirty\":false,\"contract_sha\":\"$CSHA\",\"tree\":\"$(. "$LIB"; tc_snapshot_tree "$R")\"}" \
  "$(printf '%s' "$REC" | jq -c '{type,suite,exit,dirty,contract_sha,tree}')"
check "run: cmd_sha binds cmd + cwd" "$(. "$LIB"; tc_cmd_sha . 'echo out-line; echo err-line >&2; exit 3')" "$(printf '%s' "$REC" | jq -r .cmd_sha)"
check "run: t_start <= t_end" true "$(printf '%s' "$REC" | jq '.t_start <= .t_end')"
sed 's/"cmd":"exit 1"/"cmd":"exit 0"/' "$R/CLAUDE.md" > "$R/CLAUDE.md.new" && mv "$R/CLAUDE.md.new" "$R/CLAUDE.md"
st "$R" run flip; check "run: cmd from HEAD, not the edited working tree" 1 "$RC"
git -C "$R" add CLAUDE.md; st "$R" run flip; check "run: cmd from HEAD, not the staged contract" 1 "$RC"
git -C "$R" checkout -q HEAD -- CLAUDE.md
st "$R" run dirty; check "run: dirty suite still returns its code" 0 "$RC"
check "run: file changed during the run -> dirty" true "$(newest_receipt "$R" | jq .dirty)"
git -C "$R" checkout -q -- tracked.txt
N0=$(receipts); st "$R" run pass --grep x
check "run: extra args refused (rc 64, no receipt)" "64:$N0" "$RC:$(receipts)"
st "$R" run pass -- x; check "run: '-- x' refused too" 64 "$RC"
st "$R" run nosuch; check "run: unknown suite -> 64" 64 "$RC"
st "$R" run stdin < <(printf 'data'); check "run: suite stdin is /dev/null" 0 "$RC"
st "$R" run cwd; check "run: cwd honoured" 0 "$RC"
st "$R" run --all-auto
check "run --all-auto: first failing code, opt-in not run" "3:no" "$RC:$([ -e "$R/ran-optin" ] && echo yes || echo no)"
check "run --all-auto: both auto suites got receipts" '["fail","pass"]' "$(. "$LIB"; tc_receipts_load "$R" | jq -sc '[.[] | select(.type=="suite" and (.suite=="pass" or .suite=="fail")) | .suite] | unique')"
: > "$TMP/notadir"; XDG_CACHE_HOME="$TMP/notadir" st "$R" run pass
check "run: receipt write failure is reported with its reason, suite code kept" "0:1" "$RC:$(printf '%s' "$ERR" | grep -c 'receipt not written: cannot create')"
P=$(mkd runnogit); printf '{"scripts":{"test":"true"}}' > "$P/package.json"; st "$P" run test; check "run outside git -> rc 1" 1 "$RC"
R=$(mkgit runheur); printf '{"scripts":{"test":"exit 0"}}' > "$R/package.json"; commit_all "$R"
st "$R" run test; check "run without contract: discovered suite, contract_sha none" "0:none:heuristic" "$RC:$(newest_receipt "$R" | jq -r '.contract_sha + ":" + .source')"

echo "--- status (what the gate checks for the index)"
R=$(mkgit stat); mkdir -p "$R/src/lib" "$R/src/ui" "$R/tests"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "l$i" ; done > "$R/src/lib/x.ts"; echo '<p>' > "$R/src/ui/a.html"
contract "$R/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"exit 0","paths":["src/**"]},{"name":"e2e","cmd":"exit 0","kind":"e2e","paths":["src/ui/**"]},{"name":"bad","cmd":"exit 1","paths":["nothing/**"]}],
 "ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**"]}'
commit_all "$R"
st "$R" status; check "status: clean index -> ok, rc 0" "0:true" "$RC:$(q .ok)"
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "w$i"; done >> "$R/src/lib/x.ts"; st "$R" status
check "status: nothing staged, dirty worktree -> target worktree, labelled, rc 1, files from the worktree" '1:"worktree":1:["src/lib/x.ts"]' \
  "$RC:$(q .target):$(printf '%s' "$ERR" | grep -c 'nothing staged'):$(q .files)"
git -C "$R" checkout -q -- src/lib/x.ts
echo 'l13' >> "$R/src/lib/x.ts"; git -C "$R" add -A
st "$R" status
check "status: staged 1-line logic change -> rc 1, unit missing, te not needed (small, anchor on commit)" "1:false:false:true:head" \
  "$RC:$(q '.suites[]|select(.name=="unit")|.ok'):$(q '.missing|any(startswith("test-engineer"))'):$(q '.agents["test-engineer"].anchor_on_commit != null'):$(qr '.agents["test-engineer"].drift_base')"
check "status: says the anchor is created on commit, writes none" "1:0" "$(printf '%s' "$ERR" | grep -c 'drift anchor (code) on commit'):$(find "$XDG_CACHE_HOME/claude-subteams/receipts" -name '*-anchor-*' | wc -l | tr -d ' ')"
check "status: untouched suite not required" false "$(q '.suites[]|select(.name=="e2e")|.required')"
check "status: enforced with HEAD contract" '"v1":true' "$(q .contract):$(q .enforced)"
st "$R" run unit; st "$R" status
check "status: suite receipt valid for this content" true "$(q '.suites[]|select(.name=="unit")|.ok')"
TR=$(. "$LIB"; tc_snapshot_tree "$R"); NOW=$(date +%s)
(. "$LIB"; tc_receipt_write "$R" "{\"type\":\"te\",\"status\":\"pass\",\"tree\":\"$TR\",\"t_start\":$((NOW-100)),\"t_end\":$((NOW+100))}" >/dev/null)
st "$R" status; check "status: te pass with a suite run in its interval -> all ok" "0:true" "$RC:$(q .ok)"
for i in 1 2 3 4 5 6 7 8 9 10 11; do echo "m$i"; done >> "$R/src/lib/x.ts"; git -C "$R" add -A
st "$R" status
check "status: 11 more lines -> te drift beyond threshold, suite content changed" "false:false:11" \
  "$(q '.agents["test-engineer"].ok'):$(q '.suites[]|select(.name=="unit")|.ok'):$(q '.agents["test-engineer"].drift.lines')"
git -C "$R" reset -q --hard HEAD
for i in 1 2 3; do echo "s$i"; done >> "$R/src/lib/x.ts"; git -C "$R" add -A
st "$R" run unit; TR=$(. "$LIB"; tc_snapshot_tree "$R"); NOW=$(date +%s)
(. "$LIB"; tc_receipt_write "$R" "{\"type\":\"te\",\"status\":\"pass\",\"tree\":\"$TR\",\"t_start\":$((NOW-100)),\"t_end\":$((NOW+100))}" >/dev/null)
echo 's4' >> "$R/src/lib/x.ts"; git -C "$R" add -A; st "$R" run unit; st "$R" status
check "status: 1-line drift after te -> te still ok (small change)" "true:1" "$(q '.agents["test-engineer"].ok'):$(q '.agents["test-engineer"].drift.lines')"
git -C "$R" commit -q -m step
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do echo "<p>$i</p>"; done >> "$R/src/ui/a.html"; git -C "$R" add -A; st "$R" run unit; st "$R" run e2e
TR=$(. "$LIB"; tc_snapshot_tree "$R"); NOW=$(date +%s)
(. "$LIB"; tc_receipt_write "$R" "{\"type\":\"ui\",\"status\":\"pass\",\"tree\":\"$TR\",\"t_start\":$((NOW-100)),\"t_end\":$((NOW+100))}" >/dev/null)
st "$R" status; check "status: ui pass without screenshots -> not counted" "false" "$(q '.agents["ui-tester"].ok')"
D=$(. "$LIB"; tc_receipt_dir "$R")
printf '{"kind":"shot","path":"/a.png","size":3,"session":"s","ts":%s}\n' "$NOW" > "$D/shot-$NOW-1-1.json"
printf '{"kind":"shot","path":"/b.png","size":3,"session":"s","ts":%s}\n' "$NOW" > "$D/shot-$NOW-1-2.json"
st "$R" status; check "status: ui pass + e2e + 2 shots -> ok" "true:0" "$(q '.agents["ui-tester"].ok'):$RC"
(. "$LIB"; tc_receipt_write "$R" "{\"type\":\"ui\",\"status\":\"issues-found\",\"tree\":\"$TR\",\"t_start\":$((NOW+1)),\"t_end\":$((NOW+101))}" >/dev/null)
st "$R" status; check "status: newest ui receipt issues-found -> not ok" "false" "$(q '.agents["ui-tester"].ok')"
check "status: test file change does not touch ui/code groups" '{"ui":false,"code":false}' \
  "$(. "$LIB"; tc_groups_load "$(tc_contract_load "$R" head; echo "$TC_CONTRACT_JSON")"; tc_classify tests/z.ts; echo "{\"ui\":$([ $TC_C_UI = 1 ] && echo true || echo false),\"code\":$([ $TC_C_CODE = 1 ] && echo true || echo false)}")"
R=$(mkgit stat2); mkdir -p "$R/src"; echo a > "$R/src/a.ts"
contract "$R/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"exit 1"},{"name":"d","cmd":"echo x >> src/a.ts","run":"auto","paths":["nothing/**"]}],"ui_globs":[],"code_globs":[]}'
commit_all "$R"; echo b >> "$R/src/a.ts"; git -C "$R" add -A
st "$R" run unit; st "$R" status
check "status: exit 1 receipt -> invalid with reason" "false:1" "$(q '.suites[]|select(.name=="unit")|.ok'):$(q '.suites[]|select(.name=="unit")|.reason' | grep -c 'failed')"
R=$(mkgit stat3); mkdir -p "$R/src"; echo a > "$R/src/a.ts"
contract "$R/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"echo x >> src/a.ts"}],"ui_globs":[],"code_globs":[]}'
commit_all "$R"; echo b >> "$R/src/a.ts"; git -C "$R" add -A; st "$R" run unit; git -C "$R" checkout -q -- src/a.ts; st "$R" status
check "status: dirty receipt does not count" "false:1" "$(q '.suites[0].ok'):$(q '.suites[0].reason' | grep -c dirty)"
R=$(mkgit stat4); printf '{"scripts":{"test":"exit 0"}}' > "$R/package.json"; commit_all "$R"
contract "$R/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"exit 0"}],"ui_globs":[],"code_globs":[]}'; git -C "$R" add CLAUDE.md
st "$R" status; check "status: contract only staged -> mode new, not enforced" '"new":false' "$(q .contract):$(q .enforced)"
st "$R" run unit; check "run: staged contract used when HEAD has none" 0 "$RC"

echo "--- worktree: same store, same content -> receipt counts"
R=$(mkgit wtmain); mkdir -p "$R/src"; echo a > "$R/src/a.ts"
contract "$R/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"exit 0"}],"ui_globs":[],"code_globs":[]}'; commit_all "$R"
git -C "$R" worktree add -q -b wt "$TMP/wt" 2>/dev/null
check "worktree: same receipt dir" "$(. "$LIB"; tc_receipt_dir "$R")" "$(. "$LIB"; tc_receipt_dir "$TMP/wt")"
echo b >> "$TMP/wt/src/a.ts"; git -C "$TMP/wt" add -A; st "$TMP/wt" run unit
check "worktree: run ok" 0 "$RC"
echo b >> "$R/src/a.ts"; git -C "$R" add -A; st "$R" status
check "worktree: receipt from the other worktree on the same content counts in main" true "$(q '.suites[0].ok')"
R2=$(mkgit otherrepo); check "another repo: different receipt dir" 1 "$([ "$(. "$LIB"; tc_receipt_dir "$R")" != "$(. "$LIB"; tc_receipt_dir "$R2")" ] && echo 1 || echo 0)"

echo "--- --init-contract"
P=$(mkd init-empty); st "$P" --init-contract
check "init (empty project): rc 0, valid JSON object" "0:object" "$RC:$(qr type)"
check "init: required keys present, code_globs explicit" '["code_globs","small_change","suites","test_globs","ui_exclude","ui_globs"]' "$(q 'keys')"
check "init: no placeholders" 0 "$(printf '%s' "$OUT" | grep -ciE '<[a-z]|todo|\.\.\.|placeholder|example\.com|changeme')"
contract "$P/CLAUDE.md" "$OUT"; st "$P"
check "init: round trip through the contract reader" "0:v1:[]" "$RC:$(qr .contract):$(q .suites)"
P=$(mkd init-npm); cp "$TMP/pw/package.json" "$P/"; cp -R "$TMP/pw/e2e" "$P/"; : > "$P/package-lock.json"
printf '{"scripts":{"test":"vitest run","test:canary":"RUN_C=1 vitest run"}}' > "$P/package.json"
st "$P" --init-contract
check "init (npm + Playwright): suites, opt-in kept, app from webServer/baseURL" \
  '{"names":["test","test:canary","playwright:e2e"],"runs":["auto","opt-in","auto"],"app":{"url":"http://localhost:4000","start":"playwright-webServer"}}' \
  "$(q '{names:[.suites[].name], runs:[.suites[].run], app}')"
contract "$P/CLAUDE.md" "$OUT"; st "$P"; check "init (npm): round trip" "0:v1" "$RC:$(qr .contract)"

echo "--- safety"
P=$(mkd nojqp); (cd "$P" && PATH="$TMP/nojq" "$ST") >/dev/null 2>"$TMP/err"; check "no jq -> rc 3" 3 "$?"
P=$(mkd symesc); mkdir -p "$TMP/outside"; printf '{"scripts":{"test":"evil"}}' > "$TMP/outside/package.json"; ln -s "$TMP/outside/package.json" "$P/package.json"
contract "$TMP/outside/CLAUDE.md" '{"suites":[{"name":"evil","cmd":"x"}]}'; ln -s "$TMP/outside/CLAUDE.md" "$P/CLAUDE.md"
st "$P"; check "symlinks outside the root are not read" "0:[]:none" "$RC:$(q .suites):$(qr .contract)"
P=$(mkd symc); ln -s "$TMP/outside/CLAUDE.md" "$P/CLAUDE.md"; st "$P"
check "CLAUDE.md symlink outside the root: not read, note on stderr" "0:none:1" "$RC:$(qr .contract):$(printf '%s' "$ERR" | grep -c 'CLAUDE.md resolves outside the project root')"
P=$(mkd symin); printf '{"scripts":{"test":"ok"}}' > "$P/real.json"; ln -s real.json "$P/package.json"
contract "$P/AGENTS.md" '{"suites":[{"name":"inside","cmd":"x"}]}'; ln -s AGENTS.md "$P/CLAUDE.md"
st "$P"; check "symlinks inside the root are read" '["inside"]' "$(q '[.suites[].name]')"
P=$(mkd big); { printf '{"scripts":{"test":"x"},"pad":"'; head -c 1100000 /dev/zero | tr '\0' 'a'; printf '"}'; } > "$P/package.json"
st "$P"; check "package.json over 1 MB not read" "0:[]" "$RC:$(q .suites)"
P=$(mkd bigc); { printf '<!-- subteams:test-suites v1 -->\n```json\n{"suites":[]}\n```\n'; head -c 1100000 /dev/zero | tr '\0' 'a'; } > "$P/CLAUDE.md"
st "$P"; check "CLAUDE.md over 1 MB -> rc 2 with the reason (fail closed)" "2:1" "$RC:$(printf '%s' "$ERR" | grep -c 'larger than 1 MB')"
R=$(mkgit envleak); contract "$R/CLAUDE.md" '{"suites":[{"name":"u","cmd":"true"}]}'; commit_all "$R"
export SUBTEAMS_TEST_SECRET=sekret-marker-42
st "$R"; A1="$OUT$ERR"; st "$R" run u; A2="$OUT$ERR"; st "$R" status; A3="$OUT$ERR"
unset SUBTEAMS_TEST_SECRET
check "environment never printed (list/run/status)" 0 "$(printf '%s' "$A1$A2$A3" | grep -c sekret-marker)"
st "$TMP" --bogus; check "unknown argument -> 64" 64 "$RC"
st "$TMP" --help; check "--help -> 0" 0 "$RC"

echo "--- bin wrapper"
mkdir -p "$TMP/linkbin"; ln -s "$ST" "$TMP/linkbin/subteams-tests"
(cd "$TMP/npm" && "$TMP/linkbin/subteams-tests") > "$TMP/out" 2>/dev/null; RC=$?; OUT=$(cat "$TMP/out")
check "bin via symlink resolves the plugin root" "0:test" "$RC:$(qr '.suites[0].name')"
(cd "$TMP/npm" && env -u CLAUDE_PLUGIN_ROOT -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_DATA=/nonexistent "$ST") > /dev/null 2>&1
check "bin ignores CLAUDE_PLUGIN_DATA" 0 "$?"

echo "--- performance"
P=$(mkd perf); contract "$P/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"x","paths":["src/**"]},{"name":"e2e","cmd":"y"}],"ui_globs":["src/ui/**","public/**"],"ui_exclude":["public/emails/**"],"test_globs":["**/*.test.*","tests/**"]}'
awk 'BEGIN{for(i=0;i<300;i++){d=(i%3==0)?"src/ui":(i%3==1)?"src/lib":"tests"; print d "/f" i ".ts"}}' > "$TMP/300.txt"
TIMEFORMAT=%R; T=$( { time (cd "$P" && "$ST" --files - < "$TMP/300.txt" > "$TMP/out" 2>/dev/null); } 2>&1 ); OUT=$(cat "$TMP/out")
check "300 files classified < 2 s (took ${T}s; src/ui/*.ts count as ui AND code: 400)" "1:400" "$(awk -v t="$T" 'BEGIN{print (t<2)?1:0}'):$(q '[.groups.ui,.groups.code,.groups.test] | map(length) | add')"
R=$(mkgit perfgit); cp "$P/CLAUDE.md" "$R/"; while IFS= read -r f; do mkdir -p "$R/$(dirname "$f")"; echo "$f" > "$R/$f"; done < "$TMP/300.txt"; commit_all "$R"
while IFS= read -r f; do echo x >> "$R/$f"; done < "$TMP/300.txt"; git -C "$R" add -A
T=$( { time (cd "$R" && "$ST" status > /dev/null 2>&1); } 2>&1 )
check "status on 300 staged files < 5 s (took ${T}s)" 1 "$(awk -v t="$T" 'BEGIN{print (t<5)?1:0}')"
T=$( { time (. "$LIB"; tc_snapshot_tree "$R" > /dev/null); } 2>&1 )
check "snapshot of a 300-file working tree < 2 s (took ${T}s)" 1 "$(awk -v t="$T" 'BEGIN{print (t<2)?1:0}')"
T=$( { time (cd "$R" && "$ST" run e2e > /dev/null 2>&1); } 2>&1 )
check "run (2 snapshots + receipt) on 300 files < 3 s (took ${T}s)" 1 "$(awk -v t="$T" 'BEGIN{print (t<3)?1:0}')"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS ($PASSES)"; else echo "$FAILS FAILED ($PASSES passed)"; fi
[ "$FAILS" -eq 0 ]
