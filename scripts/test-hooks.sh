#!/usr/bin/env bash
# test-hooks.sh — регрессия хуков Claude Code плагина (hooks/*): гейт ревью перед коммитом,
# маркер ревью на SubagentStop, доставка причин блокировки/подсказок, таймауты hooks.json;
# с 1.50 — гейт тестов (контракт, квитанции, дрейф) и квитанции ui/te в subagent-rails.
# Каждый хук получает stdin-JSON как от CLI; временные git-репо и XDG_CACHE_HOME живут в
# $TMPDIR (по умолчанию /tmp) и удаляются на выходе. Боевой кэш пользователя не трогается.
# Отрицательный контроль: HOOKS_DIR=<каталог со старыми хуками> bash scripts/test-hooks.sh
#   (старые версии: git show <rev>:hooks/<имя> > каталог/<имя>; на них ключевые проверки должны быть FAIL).
# Использование: bash scripts/test-hooks.sh   (exit 0 = все PASS, иначе 1)
set -u

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="${HOOKS_DIR:-$DIR/hooks}"
TMP=$(mktemp -d "${TMPDIR:-/tmp}/test-hooks-XXXXXX")
trap 'rm -rf "$TMP"' EXIT

command -v jq >/dev/null || { echo "jq required"; exit 2; }

export XDG_CACHE_HOME="$TMP/cache"
export CLAUDE_PLUGIN_ROOT="$DIR"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset CLAUDE_SUBTEAMS_SKIP_REVIEW_GATE CLAUDE_SUBTEAMS_SKIP_TEST_GATE CLAUDE_SUBTEAMS_AUTONOMY CLAUDE_SUBTEAMS_MULTI_INSTANCE GIT_INDEX_FILE GIT_DIR GIT_WORK_TREE

FAILS=0
check() { # <name> <expected> <actual>
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected [$2] got [$3]"; FAILS=$((FAILS+1)); fi
}

RC=0; OUT=""; ERR=""
# run_hook <cwd> <hook-with-args> <stdin-json>  -> RC / OUT / ERR
run_hook() {
  local cwd="$1" hook="$2" json="$3"
  # shellcheck disable=SC2086
  (cd "$cwd" && printf '%s' "$json" | bash "$HOOKS/${hook%% *}" ${hook#"${hook%% *}"}) >"$TMP/out" 2>"$TMP/err"
  RC=$?; OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
bash_json() { jq -nc --arg sid "$1" --arg c "$2" '{session_id:$sid,tool_name:"Bash",tool_input:{command:$c}}'; }
bash_json_file() { jq -nc --arg sid "$1" --rawfile c "$2" '{session_id:$sid,tool_name:"Bash",tool_input:{command:$c}}'; }  # for >128 KiB commands (no argv)
# gate <repo> <sid> <command> -> RC
gate() { run_hook "$1" pre-commit-gate "$(bash_json "$2" "$3")"; }
# Sections: TH_ONLY=<regex> runs only the sections whose name matches (e.g.
# TH_ONLY='^fix' for the review-fix sections; used by mutation runs). Default: all.
sec() { [ -z "${TH_ONLY:-}" ] || [[ $1 =~ $TH_ONLY ]]; }
HD_MSG=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: handle "foo bar" case\nEOF\n)"')

mkrepo() { # <name> -> path; base commit with a.ts + doc.md
  local r="$TMP/$1"
  mkdir -p "$r" && git -C "$r" init -q -b main
  printf 'export const a = 1;\n' > "$r/a.ts"; printf '# doc\n' > "$r/doc.md"
  git -C "$r" add -A && git -C "$r" commit -q -m base
  echo "$r"
}

if sec legacy; then
# R_DIRTY: tracked a.ts modified, NOTHING staged (+ untracked new.ts)
R_DIRTY=$(mkrepo dirty); echo 'x' >> "$R_DIRTY/a.ts"; echo 'y' > "$R_DIRTY/new.ts"
# R_STAGED: a.ts staged
R_STAGED=$(mkrepo staged); echo 'x' >> "$R_STAGED/a.ts"; git -C "$R_STAGED" add a.ts
# R_MD: doc.md staged, a.ts dirty and unstaged (neighbour instance's work)
R_MD=$(mkrepo md); echo 'x' >> "$R_MD/doc.md"; git -C "$R_MD" add doc.md; echo 'z' >> "$R_MD/a.ts"

SID=sNOMARK

echo "--- gate: forms that the OLD gate let through (code not yet staged)"
for c in 'git add -A && git commit -m x' 'git add a.ts; git commit -m x' 'git add . && git commit -m x' \
         'git commit -am x' 'git commit -a -m x' 'git commit --all -m x' 'git commit a.ts -m x' \
         'git add -u && git commit -m x' 'git add new.ts && git commit new.ts -m x'; do
  gate "$R_DIRTY" "$SID" "$c"; check "block: $c" 2 "$RC"
done

echo "--- gate: syntax variants (code staged)"
for c in 'git commit -m x' 'git -c user.name=x commit -m x' 'git -C . commit -m x' 'git --no-pager commit -m x' \
         'env git commit -m x' 'command git commit -m x' '/usr/bin/git commit -m x' 'bash -c "git commit -m x"' \
         '(git commit -m x)' 'if true; then git commit -m x; fi' 'cd . && git -c a=b -C . commit -m x'; do
  gate "$R_STAGED" "$SID" "$c"; check "block: $c" 2 "$RC"
done

echo "--- gate: must NOT fire"
for c in 'git commit-tree HEAD^{tree} -m x' 'git commit --dry-run' 'echo "a; git commit -m y"' 'git status' 'git log --oneline'; do
  gate "$R_STAGED" "$SID" "$c"; check "pass: $c" 0 "$RC"
done

echo "--- gate: precision on a dirty tree (only .md in the commit)"
for c in 'git commit -m docs' 'git add doc.md && git commit -m docs' 'git commit doc.md -m docs' 'git add -u doc.md && git commit -m docs'; do
  gate "$R_MD" "$SID" "$c"; check "pass (md only): $c" 0 "$RC"
done
gate "$R_MD" "$SID" 'git add -A && git commit -m all'; check "block: add -A drags the dirty .ts in" 2 "$RC"
gate "$R_MD" "$SID" 'git commit -am all';             check "block: -am drags the dirty .ts in" 2 "$RC"

echo "--- gate: hardening (review round 1) — parse mistakes must err toward BLOCK, never toward open"
gate "$R_STAGED" "$SID" "$HD_MSG";  check "block: C1 heredoc message with \"a b\" inside" 2 "$RC"
HD_APOS=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nDon'"'"'t break it; really\nEOF\n)"')
gate "$R_STAGED" "$SID" "$HD_APOS"; check "block: C1 heredoc message with apostrophe and ;" 2 "$RC"
gate "$R_STAGED" "$SID" 'git commit --mess x'; check "block: unknown long option does not shrink the set" 2 "$RC"
HD_OUT=$(printf 'cat >> notes.md <<'"'"'EOF'"'"'\nDon'"'"'t forget\nEOF\ngit commit -m x')
gate "$R_STAGED" "$SID" "$HD_OUT";  check "block: C2 apostrophe in heredoc body outside quotes" 2 "$RC"
gate "$R_STAGED" "$SID" "echo \$'it\\'s' && git commit -m x"; check "block: C2 \$'it\\'s' ANSI-C quote" 2 "$RC"
gate "$R_STAGED" "$SID" 'echo "unterminated; git commit -m x'; check "block: unterminated quote -> legacy detection" 2 "$RC"
gate "$R_DIRTY" "$SID" 'git commit --dry-run -a && git commit -am x';   check "block: C3 dry-run then real commit -am" 2 "$RC"
gate "$R_STAGED" "$SID" 'git commit -h; git commit -m x';                 check "block: C3 commit -h then real commit" 2 "$RC"
gate "$R_DIRTY" "$SID" 'git add doc.md && git commit -m docs && git add -A && git commit -m code'; check "block: C3 docs commit then add -A commit" 2 "$RC"
gate "$R_STAGED" "$SID" 'git commit --dry-run -m x && git commit-tree HEAD^{tree} -m y'; check "pass: only dry-run and commit-tree... (staged code, but no real commit)" 0 "$RC"
BIG="$TMP/big.cmd"; { printf 'echo '; head -c 140000 /dev/zero | tr '\0' a; printf '; git commit -m x'; } > "$BIG"
run_hook "$R_STAGED" pre-commit-gate "$(bash_json_file "$SID" "$BIG")"; check "block: I1 command over 130 KB" 2 "$RC"
for c in 'timeout 60 git commit -m x' 'timeout -s KILL 60 git commit -m x' 'flock /tmp/lk git commit -m x' 'stdbuf -oL git commit -m x' \
         'ionice -c 2 -n 7 git commit -m x' 'bash -o pipefail -c "git commit -m x"' 'sudo -u nobody git commit -m x'; do
  gate "$R_STAGED" "$SID" "$c"; check "block: I3 $c" 2 "$RC"
done
for c in 'git stage a.ts && git commit -m x' 'find . -name "*.ts" | xargs git add && git commit -m x' 'git add "$f" && git commit -m x' \
         'git add $(git ls-files -m) && git commit -m x'; do
  gate "$R_DIRTY" "$SID" "$c"; check "block: I3 $c" 2 "$RC"
done
gate "$R_MD" "$SID" 'find . | xargs git add && git commit -m x'; check "block: I3 xargs add drags the dirty .ts in" 2 "$RC"
R_CYR_MD=$(mkrepo cyrmd); echo 'x' > "$R_CYR_MD/Заметка.md"; git -C "$R_CYR_MD" add Заметка.md
R_CYR_TS=$(mkrepo cyrts); echo 'x' > "$R_CYR_TS/Код.ts"; git -C "$R_CYR_TS" add Код.ts
gate "$R_CYR_MD" "$SID" 'git commit -m x'; check "pass: I4 Cyrillic .md is docs" 0 "$RC"
gate "$R_CYR_TS" "$SID" 'git commit -m x'; check "block: I4 Cyrillic .ts is code" 2 "$RC"

echo "--- gate: hardening (review round 2) — arithmetic <<, fallback target, coord.sh lock wrapper"
gate "$R_STAGED" "$SID" "$(printf 'echo $((1 << 3))\ngit commit -m x')";  check "block: N1 \$((1 << 3)) is a shift, not a heredoc" 2 "$RC"
gate "$R_DIRTY" "$SID" "$(printf 'n=$((1<<2))\ngit add -A && git commit -m x')"; check "block: N1 n=\$((1<<2)) then add -A && commit" 2 "$RC"
gate "$R_STAGED" "$SID" "$(printf 'cat <<ZZ\nbody\ngit commit -m x')";   check "block: N1 heredoc terminator never found -> legacy fallback" 2 "$RC"
R_CLEAN=$(mkrepo clean)
gate "$R_CLEAN" "$SID" "$(printf 'cd %s && git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: 5" screen\nEOF\n)"' "$R_STAGED")"
check "block: N2 fallback keeps the cd target (cwd repo is clean)" 2 "$RC"
gate "$R_CLEAN" "$SID" "git -C $R_STAGED commit -m \"oops unterminated"
check "block: N2 fallback keeps git -C target" 2 "$RC"
gate "$R_DIRTY" "$SID" 'git add -A && git commit -m "unterminated'; check "block: N2 fallback widens on add seen in the parsed prefix" 2 "$RC"
gate "$R_DIRTY" "$SID" 'git commit -am "unterminated';             check "block: N2 fallback widens on -am in the raw text" 2 "$RC"
gate "$R_CLEAN" "$SID" 'git commit -m "unterminated';              check "pass: N2 fallback, nothing to commit in the clean repo" 0 "$RC"
for c in 'coord.sh commit-lock -- git commit -m x' '"$CLAUDE_PLUGIN_ROOT/scripts/coord.sh" commit-lock -- git commit -m x' \
         'scripts/coord.sh gate-lock --timeout 60 -- git commit -m x' 'bash scripts/coord.sh commit-lock -- git commit -m x'; do
  gate "$R_STAGED" "$SID" "$c"; check "block: N3 $c" 2 "$RC"
done
gate "$R_DIRTY" "$SID" 'coord.sh commit-lock -- git commit -am x'; check "block: N3 lock wrapper + commit -am" 2 "$RC"
gate "$R_STAGED" "$SID" 'coord.sh commit-lock -- git status';      check "pass: N3 lock wrapper around a non-commit" 0 "$RC"

echo "--- gate: review check runs BEFORE the compile check"
mkdir -p "$TMP/fakebin"; printf '#!/bin/sh\necho "error TS1: fake"\nexit 1\n' > "$TMP/fakebin/npx"; chmod +x "$TMP/fakebin/npx"
R_TSC=$(mkrepo tsc); echo '{}' > "$R_TSC/tsconfig.json"; echo 'x' >> "$R_TSC/a.ts"; git -C "$R_TSC" add a.ts
PATH="$TMP/fakebin:$PATH" gate "$R_TSC" sTSC 'git commit -m x'
check "no marker: block reason is the review, not tsc" 1 "$(printf '%s' "$ERR" | grep -q 'code-reviewer' && ! printf '%s' "$ERR" | grep -q 'TS1' && echo 1 || echo 0)"
mkdir -p "$XDG_CACHE_HOME/claude-subteams/review-marks"; : > "$XDG_CACHE_HOME/claude-subteams/review-marks/sTSC"
PATH="$TMP/fakebin:$PATH" gate "$R_TSC" sTSC 'git commit -m x'
check "marker present: tsc failure blocks with its output" 1 "$([ "$RC" = 2 ] && printf '%s' "$ERR" | grep -q 'TS1' && echo 1 || echo 0)"

echo "--- gate: block reason reaches the model (stderr), nothing meaningful on stdout"
gate "$R_STAGED" "$SID" 'git commit -m x'
check "reason in stderr" 1 "$([ -n "$ERR" ] && printf '%s' "$ERR" | grep -q 'code-reviewer' && echo 1 || echo 0)"
check "reason tells to ask the user for the env override" 1 "$(printf '%s' "$ERR" | grep -q 'ask the user' && echo 1 || echo 0)"
check "stdout empty on block" "" "$OUT"

echo "--- review marker: SubagentStop writes it, SubagentStart does not"
MS=sMARK; MARK="$XDG_CACHE_HOME/claude-subteams/review-marks/$MS"
start=$(jq -nc --arg s "$MS" '{session_id:$s,hook_event_name:"SubagentStart",agent_id:"a1",agent_type:"claude-subteams:code-reviewer"}')
run_hook "$R_STAGED" "subagent-rails SubagentStart" "$start"
check "SubagentStart emits rails JSON" "SubagentStart" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
check "no marker after SubagentStart" "absent" "$([ -e "$MARK" ] && echo present || echo absent)"
stop() { jq -nc --arg s "$MS" --arg t "$1" --arg m "$2" '{session_id:$s,hook_event_name:"SubagentStop",agent_id:"a1",agent_type:$t,last_assistant_message:$m,stop_hook_active:false}'; }
run_hook "$R_STAGED" "subagent-rails SubagentStop" "$(stop 'claude-subteams:code-reviewer' '')"
check "no marker: reviewer returned nothing" "absent" "$([ -e "$MARK" ] && echo present || echo absent)"
run_hook "$R_STAGED" "subagent-rails SubagentStop" "$(stop 'claude-subteams:code-reviewer' '   ')"
check "no marker: reviewer returned blank" "absent" "$([ -e "$MARK" ] && echo present || echo absent)"
run_hook "$R_STAGED" "subagent-rails SubagentStop" "$(stop 'developer' 'done')"
check "no marker: not a reviewer" "absent" "$([ -e "$MARK" ] && echo present || echo absent)"
gate "$R_STAGED" "$MS" 'git commit -m x'; check "still blocked before reviewer finished" 2 "$RC"
run_hook "$R_STAGED" "subagent-rails SubagentStop" "$(stop 'claude-subteams:code-reviewer' 'Verdict: approve')"
check "marker after SubagentStop (reviewer)" "present" "$([ -e "$MARK" ] && echo present || echo absent)"
check "SubagentStop prints nothing" "" "$OUT"
gate "$R_STAGED" "$MS" 'git commit -m x';                 check "commit passes after marker" 0 "$RC"
gate "$R_DIRTY" "$MS" 'git add -A && git commit -m x';    check "add -A && commit passes after marker" 0 "$RC"
rm -f "$MARK"
# Live CLI 2.1.312 shape (probe 29.10.2026): no last_assistant_message at all.
live=$(jq -nc --arg s "$MS" '{session_id:$s,hook_event_name:"SubagentStop",agent_id:"a1",agent_type:"claude-subteams:code-reviewer",agent_transcript_path:"/x.jsonl",stop_hook_active:false}')
run_hook "$R_STAGED" "subagent-rails SubagentStop" "$live"
check "marker on live CLI payload (no last_assistant_message)" "present" "$([ -e "$MARK" ] && echo present || echo absent)"
rm -f "$MARK"
run_hook "$R_STAGED" "subagent-rails SubagentStop" "$(stop 'my-code-reviewer-lite' 'ok')"
check "marker for custom teammate name containing code-reviewer" "present" "$([ -e "$MARK" ] && echo present || echo absent)"

echo "--- fail-open on bad stdin"
run_hook "$R_STAGED" pre-commit-gate 'not json at all'; check "garbage stdin -> rc 0" 0 "$RC"
run_hook "$R_STAGED" pre-commit-gate "$(jq -nc '{tool_input:{command:"git commit -m x"}}')"; check "no session_id -> rc 0" 0 "$RC"

echo "--- user-prompt-check"
run_hook "$R_STAGED" user-prompt-check '{"prompt":"please fix the bug and refactor"}'
check "reacts to .prompt (valid JSON additionalContext)" "UserPromptSubmit" "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
check "additionalContext non-empty" 1 "$(printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext|length>0' >/dev/null 2>&1 && echo 1 || echo 0)"
run_hook "$R_STAGED" user-prompt-check '{"user_prompt":"please fix the bug and refactor"}'
check "legacy .user_prompt still works" 1 "$(printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext|length>0' >/dev/null 2>&1 && echo 1 || echo 0)"
run_hook "$R_STAGED" user-prompt-check '{"prompt":"hello there"}'
check "no match -> silent" "" "$OUT"
check "user-prompt-check is sync in hooks.json" "false" "$(jq -r '[.hooks.UserPromptSubmit[].hooks[]|select(.command|test("user-prompt-check"))][0].async' "$HOOKS/hooks.json")"

echo "--- pre-push-check"
run_hook "$R_STAGED" pre-push-check "$(bash_json s1 'git push origin main')"
check "push main: valid JSON" PreToolUse "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)"
check "push main: strong warning" 1 "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'main/master' && echo 1 || echo 0)"
for c in 'git push origin +main' 'timeout 30 git push origin main' 'git push origin +HEAD:refs/heads/master'; do
  run_hook "$R_STAGED" pre-push-check "$(bash_json s1 "$c")"
  check "push strong warning: $c" 1 "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'main/master' && echo 1 || echo 0)"
done
run_hook "$R_STAGED" pre-push-check "$(bash_json s1 'git push origin fix-main-bug')"
check "push fix-main-bug: no main warning" 0 "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null | grep -c 'main/master')"
check "push fix-main-bug: still a plain warning" 1 "$(printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext|length>0' >/dev/null 2>&1 && echo 1 || echo 0)"
run_hook "$R_STAGED" pre-push-check "$(bash_json s1 'echo "do not git push main"')"
check "echo text with git push: silent" "" "$OUT"

echo "--- post-edit-check (async: JSON additionalContext + edit registry)"
EDIT_SID=sEDIT
run_hook "$R_STAGED" post-edit-check "$(jq -nc --arg s "$EDIT_SID" --arg f "$R_STAGED/SKILL.md" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f}}')"
printf '# s\n' > "$R_STAGED/SKILL.md"
run_hook "$R_STAGED" post-edit-check "$(jq -nc --arg s "$EDIT_SID" --arg f "$R_STAGED/SKILL.md" '{session_id:$s,tool_name:"Write",tool_input:{file_path:$f}}')"
check "SKILL.md warning as additionalContext" 1 "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null | grep -q 'SKILL.md' && echo 1 || echo 0)"
check "edit registry still written" 1 "$(grep -qxF 'SKILL.md' "$XDG_CACHE_HOME/claude-subteams/session-edits/$EDIT_SID" 2>/dev/null && echo 1 || echo 0)"

echo "--- convention-preflight (autonomy): reason on stderr"
BIG=$(awk 'BEGIN{for(i=0;i<450;i++) print "x"}')
CLAUDE_SUBTEAMS_AUTONOMY=1 run_hook "$R_STAGED" convention-preflight "$(jq -nc --arg f "$R_STAGED/big.ts" --arg c "$BIG" '{session_id:"s",tool_name:"Write",tool_input:{file_path:$f,content:$c}}')"
check "preflight deny rc" 2 "$RC"
check "preflight reason in stderr" 1 "$([ -n "$ERR" ] && echo 1 || echo 0)"

fi   # sec legacy

# ============================================================== 1.50 test gate
LIB="$DIR/scripts/lib-testclass.sh"
STS="$DIR/bin/subteams-tests"
TSID=sTESTGATE   # review marker present: the review gate is not what these cases test
mkdir -p "$XDG_CACHE_HOME/claude-subteams/review-marks"; : > "$XDG_CACHE_HOME/claude-subteams/review-marks/$TSID"
tg() { gate "$1" "$TSID" "$2"; }                         # gate <repo> <command> with the review marker
has() { printf '%s' "$2" | grep -qF -- "$1" && echo 1 || echo 0; }
sts() { (cd "$1" && shift && "$STS" "$@") >"$TMP/sout" 2>"$TMP/serr"; }   # subteams-tests in a repo
ctr() { printf '# P\n\n<!-- subteams:test-suites v1 -->\n```json\n%s\n```\n<!-- /subteams:test-suites -->\n' "$2" > "$1"; }
CJSON='{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]},{"name":"e2e","cmd":"true","kind":"e2e","paths":["src/ui/**"]},{"name":"live","cmd":"exit 9","run":"live"}],
 "ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**","**/*.spec.*"]}'
# e2e that does NOT cover src/ui/a.html (only src/ui/forms/**): ui pass by screenshots alone
CNARROW='{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]},{"name":"e2e","cmd":"true","kind":"e2e","paths":["src/ui/forms/**"]}],"ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**","**/*.spec.*"]}'
mkc() { # <name> [contract json] -> repo with the contract committed + src/lib (code), src/ui (ui), tests
  local r="$TMP/$1"
  mkdir -p "$r/src/lib" "$r/src/ui" "$r/tests" && git -C "$r" init -q -b main
  awk 'BEGIN{for(i=1;i<=30;i++) print "line " i}' > "$r/src/lib/x.ts"; cp "$r/src/lib/x.ts" "$r/src/lib/y.ts"
  awk 'BEGIN{for(i=1;i<=30;i++) print "<p>" i "</p>"}' > "$r/src/ui/a.html"; echo 'test' > "$r/tests/t.test.ts"; echo 'spec' > "$r/src/ui/form.spec.ts"
  printf 'bin\000ary\n' > "$r/src/lib/b.bin"
  ctr "$r/CLAUDE.md" "${2:-$CJSON}"
  git -C "$r" add -A && git -C "$r" commit -q -m base
  echo "$r"
}
addl() { # <file> <n> <tag> — append n lines
  awk -v n="$2" -v t="$3" 'BEGIN{for(i=1;i<=n;i++) print t " " i}' >> "$1"
}
ag_start() { run_hook "$1" "subagent-rails SubagentStart" "$(jq -nc --arg t "$2" --arg a "$3" --arg c "$1" '{session_id:"sx",hook_event_name:"SubagentStart",agent_id:$a,agent_type:$t,cwd:$c}')"; }
ag_stop() {  run_hook "$1" "subagent-rails SubagentStop"  "$(jq -nc --arg t "$2" --arg a "$3" --arg m "$4" --arg c "$1" '{session_id:"sx",hook_event_name:"SubagentStop",agent_id:$a,agent_type:$t,cwd:$c,last_assistant_message:$m}')"; }
shot() { (. "$LIB"; tc_receipt_write "$1" "{\"type\":\"shot\",\"kind\":\"shot\",\"path\":\"/s.png\",\"size\":3,\"session\":\"t\",\"ts\":$(date +%s)}" >/dev/null); }
nrec() { (. "$LIB"; tc_receipts_load "$1") | jq -s --arg t "$2" '[.[] | select(.type == $t)] | length'; }
lastrec() { (. "$LIB"; tc_receipts_load "$1") | jq -sc --arg t "$2" '[.[] | select(.type == $t)] | sort_by(.t_end) | last'; }
AGN=0
ui_check() { # <repo> <final message> [shots] [e2e: 1|0] — a ui-tester run through the real rails hook
  AGN=$((AGN+1)); ag_start "$1" claude-subteams:ui-tester "ui$AGN"
  [ "${4:-1}" = 1 ] && sts "$1" run e2e
  local k=0; while [ "$k" -lt "${3:-2}" ]; do shot "$1"; k=$((k+1)); done
  ag_stop "$1" claude-subteams:ui-tester "ui$AGN" "$2"
}
te_check() { # <repo> [final message] — a test-engineer run (runs unit) through the rails hook
  AGN=$((AGN+1)); ag_start "$1" claude-subteams:test-engineer "te$AGN"
  sts "$1" run unit
  ag_stop "$1" claude-subteams:test-engineer "te$AGN" "${2:-Status: pass
new tests: 2}"
}
full() { sts "$1" run unit; sts "$1" run e2e; }        # final suite runs on the current content
stage() { git -C "$1" add -A; }

if sec gate150; then
echo "--- test gate: no contract -> allow + ONE JSON with systemMessage + additionalContext"
R=$(mkrepo tg-nocontract); echo '<b>x</b>' > "$R/page.html"; echo 'y' >> "$R/a.ts"; git -C "$R" add -A
tg "$R" 'git commit -m x'
check "no contract: rc 0" 0 "$RC"
check "no contract: stdout is exactly one JSON object" 1 "$(printf '%s' "$OUT" | jq -s 'length' 2>/dev/null)"
check "no contract: systemMessage + additionalContext both carry the warning" "1:1" \
  "$(printf '%s' "$OUT" | jq -r '.systemMessage' | grep -c 'ui-tester'):$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext' | grep -c 'Relay it to the user in ONE short line')"
check "no contract: stderr empty" "" "$ERR"
R=$(mkrepo tg-nocontract-docs); echo 'more' >> "$R/doc.md"; git -C "$R" add -A
tg "$R" 'git commit -m docs'; check "no contract, docs only: rc 0, no output" "0:" "$RC:$OUT"

echo "--- test gate: contract in HEAD, the basic deny/allow"
RC1=$(mkc tg-basic); addl "$RC1/src/lib/x.ts" 20 c; addl "$RC1/src/ui/a.html" 20 u; stage "$RC1"
tg "$RC1" 'git commit -m x'
check "contract, nothing checked: deny (rc 2)" 2 "$RC"
check "deny lists ALL missing at once (unit, e2e, ui-tester, test-engineer)" "1:1:1:1" \
  "$(has 'suite unit' "$ERR"):$(has 'suite e2e' "$ERR"):$(has 'ui-tester:' "$ERR"):$(has 'test-engineer:' "$ERR")"
check "deny names the bypass and §6.7, no threshold numbers, stdout empty" "1:1:0:" \
  "$(has 'CLAUDE_SUBTEAMS_SKIP_TEST_GATE=1' "$ERR"):$(has '6.7' "$ERR"):$(printf '%s' "$ERR" | grep -cE '\b(10|2) (lines|files)\b'):$OUT"
check "opt-in/live suite never required" 0 "$(has 'suite live' "$ERR")"
ui_check "$RC1" "Status: pass
Regression: e2e green"
te_check "$RC1"; full "$RC1"
tg "$RC1" 'git commit -m x'; check "all checks on this content: allow (rc 0)" 0 "$RC"
sts "$RC1" status; check "status agrees with the gate (rc 0, ok)" "0:true" "$?:$(jq -r .ok "$TMP/sout")"

echo "--- test gate: forms that decide content at commit time (contract) — B13/B14: computed, not refused"
tg "$RC1" 'git commit -am x'; check "commit -am with NO unstaged changes (same content as the index): allow" 0 "$RC"
tg "$RC1" "$HD_MSG"; check "heredoc message with quotes (two readings, same tree): allow" 0 "$RC"
tg "$RC1" "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: "x" -a and -i src/lib/x.ts\n\nCo-Authored-By: X <x@y>\nEOF\n)"')"
check "heredoc message mentioning -a / -i and a real path: allow" 0 "$RC"
tg "$RC1" 'git commit -m "unterminated -a'; check "B13 unreliable parse under a contract: deny, names the heredoc form" "2:1" "$RC:$(has 'cannot be parsed reliably' "$ERR")"
echo 'unchecked' >> "$RC1/src/lib/x.ts"           # an UNSTAGED change inside the suites' paths
for c in 'git commit -am x' 'git commit -a -m x' 'git add -A && git commit -m x' 'git add src && git commit -m x' \
         'git commit src/lib/x.ts -m x' 'git commit -o src/lib/x.ts -m x' 'git commit -i src/lib/x.ts -m x' \
         'git commit -F - -- src/lib/x.ts <<EOF
msg
EOF'; do
  tg "$RC1" "$c"; check "B14 computed tree has the unchecked change -> deny names the suite: $c" "2:1" "$RC:$(has 'suite unit' "$ERR")"
done
tg "$RC1" 'git commit -m x'; check "B14 plain commit (the index = the checked content), unstaged change elsewhere: allow" 0 "$RC"
for c in 'git stash && git commit -m x' 'npm run lint:fix && git commit -a -m x' 'seq 1 200 > src/lib/a.js && git commit -am x' \
         'echo x>src/lib/a.js; git commit -m x' 'git checkout -- src && git commit -m x' 'touch src/lib/n.ts && git add -A && git commit -m x'; do
  tg "$RC1" "$c"; check "B13 state-changing command before the commit -> deny 'separately': $c" "2:1" "$RC:$(has 'separately first' "$ERR")"
done
tg "$RC1" 'git log --oneline > src/lib/log.txt && git commit -m x'; check "B13 read-only git redirected INTO the repo -> deny" "2:1" "$RC:$(has 'inside the repository' "$ERR")"
tg "$RC1" "git log --oneline > $TMP/log.txt && git commit -m x"; check "B13 redirect outside the repo -> allow" 0 "$RC"
tg "$RC1" 'git commit -m x > src/lib/x.ts'; check "B13 the commit's own output redirected into a repo file -> deny" "2:1" "$RC:$(has 'truncated' "$ERR")"
for c in 'git commit -p -m x' 'git commit --patch -m x' 'git commit --interactive' 'git commit --patc -m x' 'git add -p && git commit -m x'; do
  tg "$RC1" "$c"; check "B13 interactive staging -> deny: $c" 2 "$RC"
done
tg "$RC1" 'git status && git diff --cached --stat && git commit -m x'; check "read-only git before commit: allow" 0 "$RC"
tg "$RC1" "$(printf 'R=x; cd . && echo "msg" && printf "%%s" y && coord.sh commit-lock -- git commit -m x')"; check "B13 allowed prefix: assignment, cd, echo, printf, coord lock" 0 "$RC"
tg "$RC1" "$(printf 'cat <<'"'"'EOF'"'"' | git commit -F -\nfix: "quoted" and; semicolons\nEOF')"; check "r3 shape: a pipe INTO the commit (cat <<EOF | git commit -F -) -> deny, use -F - <<EOF" "2:1" "$RC:$(has 'git commit [-a] [-m' "$ERR")"
tg "$RC1" "$(printf 'git commit -F - <<'"'"'EOF'"'"'\nfix: "quoted" and; semicolons\nEOF')"; check "r3 shape: git commit -F - <<EOF -> allow" 0 "$RC"
tg "$RC1" 'git commit -m "msg with -a and -i in it"'; check "-a/-i inside the message: allow" 0 "$RC"
git -C "$RC1" checkout -q -- src/lib/x.ts
echo 'unstaged' >> "$RC1/tests/t.test.ts"         # a change no suite / group covers
tg "$RC1" 'git commit -am x'; check "B14 -a picks up only a change outside every suite/group: allow" 0 "$RC"
tg "$RC1" 'git rm -q --cached tests/t.test.ts; git commit -m x'; check "B14 git rm --cached replayed on a temp index (test file): allow" 0 "$RC"
check "B14 replay never touches the real index or the file" "1:1" "$(git -C "$RC1" ls-files --error-unmatch tests/t.test.ts >/dev/null 2>&1 && echo 1):$([ -f "$RC1/tests/t.test.ts" ] && echo 1)"
tg "$RC1" 'git rm -q tests/t.test.ts && git commit -m x'; check "B14 git rm (no --cached) replayed: worktree file still there" "1" "$([ -f "$RC1/tests/t.test.ts" ] && echo 1)"
tg "$RC1" 'git commit -m x -- nosuchpath'; check "B14 pathspec that matches nothing: deny (git would refuse)" "2:1" "$RC:$(has 'git would refuse' "$ERR")"
tg "$RC1" "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: "x -a -m" y\nEOF\n)"')"
check "r3 a message heredoc with quotes inside is no longer split (pre-pass): its '-a' text is message, plain commit -> allow" 0 "$RC"
git -C "$RC1" checkout -q -- tests/t.test.ts
R=$(mkrepo tg-nc-forms); echo 'y' >> "$R/a.ts"
tg "$R" 'git commit -am x'; check "twin: commit -am without contract -> allow" 0 "$RC"

echo "--- test gate: inline bypass ignored, env bypass works, git -C target"
addl "$RC1/src/lib/x.ts" 20 d; stage "$RC1"
tg "$RC1" 'CLAUDE_SUBTEAMS_SKIP_TEST_GATE=1 git commit -m x'; check "inline VAR=1 in the command: still denied" 2 "$RC"
tg "$RC1" 'export CLAUDE_SUBTEAMS_SKIP_TEST_GATE=1; git commit -m x'; check "export in the command: still denied" 2 "$RC"
CLAUDE_SUBTEAMS_SKIP_TEST_GATE=1 tg "$RC1" 'git commit -m x'
check "env of the hook: allow + visible warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c bypassed)"
R=$(mkrepo tg-clean)
tg "$R" "git -C $RC1 commit -m x"; check "git -C <contract repo> from a clean repo: denied (right repo)" 2 "$RC"
tg "$RC1" "git -C $R commit -m x"; check "git -C <clean repo> from the contract repo: allowed" 0 "$RC"
tg "$R" "cd $RC1 && git commit -m x"; check "cd <contract repo> && commit: denied" 2 "$RC"

echo "--- test gate: content binding (R10)"
R=$(mkc tg-content); addl "$R/src/lib/x.ts" 3 a; stage "$R"; te_check "$R"; full "$R"
tg "$R" 'git commit -m x'; check "baseline: checked content -> allow" 0 "$RC"
addl "$R/src/lib/x.ts" 1 b; stage "$R"
tg "$R" 'git commit -m x'
check "KEY content mismatch: staged content != suite receipt tree -> deny (unit)" "2:1" "$RC:$(has 'suite unit: content changed' "$ERR")"
R=$(mkc tg-partial); addl "$R/src/lib/x.ts" 3 a; stage "$R"; addl "$R/src/lib/x.ts" 1 unstaged
te_check "$R"; full "$R"
tg "$R" 'git commit -m x'
check "KEY partial staging: checked the working tree, staged another version -> deny" "2:1" "$RC:$(has 'suite unit' "$ERR")"
git -C "$R" add -A; tg "$R" 'git commit -m x'; check "partial staging twin: stage what was checked -> allow" 0 "$RC"
R=$(mkc tg-del); addl "$R/src/lib/x.ts" 2 a; stage "$R"; te_check "$R"; full "$R"
git -C "$R" rm -q src/lib/y.ts; tg "$R" 'git commit -m x'
check "deleted file in suite paths after the receipt -> deny" "2:1" "$RC:$(has 'suite unit' "$ERR")"
R=$(mkc tg-dirty '{"suites":[{"name":"unit","cmd":"echo z >> src/lib/x.ts","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" run unit; git -C "$R" checkout -q -- src/lib/x.ts
tg "$R" 'git commit -m x'; check "dirty suite receipt -> deny" "2:1" "$RC:$(has 'dirty' "$ERR")"
R=$(mkc tg-exit1 '{"suites":[{"name":"unit","cmd":"exit 1","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" run unit
tg "$R" 'git commit -m x'; check "suite exit 1 on this content -> deny" "2:1" "$RC:$(has 'failed (exit 1)' "$ERR")"
R=$(mkc tg-csha '{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" run unit
git -C "$R" stash -q; ctr "$R/CLAUDE.md" '{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]},{"name":"other","cmd":"true","paths":["nothing/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}'
git -C "$R" commit -q -am contract2; git -C "$R" stash pop -q; stage "$R"
tg "$R" 'git commit -m x'; check "receipt under another contract version -> deny" "2:1" "$RC:$(has 'another version of the test contract' "$ERR")"

echo "--- test gate: worktree shares receipts, another repo does not"
R=$(mkc tg-wt); git -C "$R" worktree add -q -b wt "$TMP/tg-wt2" 2>/dev/null
addl "$TMP/tg-wt2/src/lib/x.ts" 2 a; stage "$TMP/tg-wt2"; te_check "$TMP/tg-wt2"; full "$TMP/tg-wt2"
addl "$R/src/lib/x.ts" 2 a; stage "$R"
tg "$R" 'git commit -m x'; check "receipts from another worktree, same content -> allow" 0 "$RC"
R2=$(mkc tg-other); addl "$R2/src/lib/x.ts" 2 a; stage "$R2"
tg "$R2" 'git commit -m x'; check "another repository with identical content: receipts not visible -> deny" 2 "$RC"

echo "--- subagent-rails: ui/te receipts"
R=$(mkc tg-rails); addl "$R/src/ui/a.html" 20 u; stage "$R"
N0=$(nrec "$R" ui)
ui_check "$R" "" ; check "B6 ui-tester with an empty result: a rejected receipt with the reason" "$((N0+1)):rejected:1" "$(nrec "$R" ui):$(lastrec "$R" ui | jq -r .status):$(lastrec "$R" ui | jq -r .reason | grep -c 'empty')"
full "$R"; tg "$R" 'git commit -m x'
check "B6 deny says ui-tester ran without a Status line (not a bare 'run ui-tester')" "2:1" "$RC:$(has 'ui-tester ran but its final answer had no first-line' "$ERR")"
sts "$R" status; check "B6 status says the same" 1 "$(jq -r '.missing[]' "$TMP/sout" | grep -c 'final answer had no first-line')"
N0=$(nrec "$R" ui)
AGN=$((AGN+1)); ag_start "$R" claude-subteams:ui-tester "ui$AGN"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "ui$AGN" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:ui-tester"}')"
check "ui-tester aborted (no message, no transcript): rejected receipt" "$((N0+1)):rejected" "$(nrec "$R" ui):$(lastrec "$R" ui | jq -r .status)"
ui_check "$R" "Some preamble
Status: pass"; check "Status not on the first non-empty line: rejected, reason quotes the first line" "rejected:1" "$(lastrec "$R" ui | jq -r .status):$(lastrec "$R" ui | jq -r .reason | grep -c 'Some preamble')"
ui_check "$R" "Status: pass | degraded | issues-found | blocked"; check "B6 the copied template line is not a verdict: rejected" rejected "$(lastrec "$R" ui | jq -r .status)"
N0=$(nrec "$R" ui)
AGN=$((AGN+1)); ag_start "$R" not-ui-tester "x$AGN"; ag_stop "$R" not-ui-tester "x$AGN" "Status: pass"
ag_start "$R" ui-tester-lite "y$AGN"; ag_stop "$R" ui-tester-lite "y$AGN" "Status: pass"
check "not-ui-tester / ui-tester-lite: no receipt (canonical match only)" "$N0" "$(nrec "$R" ui)"
check "no start marker for non-canonical names" 0 "$(find "$XDG_CACHE_HOME/claude-subteams/agent-starts" -name "x$AGN" -o -name "y$AGN" 2>/dev/null | wc -l | tr -d ' ')"
ag_stop "$R" claude-subteams:ui-tester never-started "Status: pass"; check "no SubagentStart (no t_start): no receipt" "$N0" "$(nrec "$R" ui)"
ui_check "$R" "Status: pass" 0
check "ui pass without screenshots: receipt written (pass)" "$((N0+1)):pass" "$(nrec "$R" ui):$(lastrec "$R" ui | jq -r .status)"
full "$R"; tg "$R" 'git commit -m x'
check "KEY ui pass without screenshots: not counted -> deny names ui-tester" "2:1" "$RC:$(has 'ui-tester:' "$ERR")"
ui_check "$R" "Status: pass" 2 0; full "$R"; tg "$R" 'git commit -m x'
check "ui pass with shots but no e2e run (an auto e2e suite exists): not counted" "2:1" "$RC:$(has 'ui-tester:' "$ERR")"
ui_check "$R" "Status: degraded
live review not performed: Chrome not found" 0 1; full "$R"
tg "$R" 'git commit -m x'; check "ui degraded with e2e + stated reason: allow" 0 "$RC"
check "degraded receipt: reason_stated recorded, evidence summary present" "true:1" "$(lastrec "$R" ui | jq -r '.reason_stated'):$(lastrec "$R" ui | jq -r '.evidence.e2e_ok')"
R=$(mkc tg-degr); addl "$R/src/ui/a.html" 20 u; stage "$R"
ui_check "$R" "Status: degraded" 0 1; full "$R"; tg "$R" 'git commit -m x'
check "ui degraded without a stated reason: not counted" 2 "$RC"
R=$(mkc tg-monkey); addl "$R/src/ui/a.html" 20 u; stage "$R"
ui_check "$R" "Status: pass"; full "$R"; tg "$R" 'git commit -m x'; check "valid scenario review: allow" 0 "$RC"
sleep 1; ui_check "$R" "Status: pass
monkey: 200 actions, no console errors" 0 0
tg "$R" 'git commit -m x'; check "newer monkey-mode pass (no evidence) does not shadow the valid review" 0 "$RC"
sleep 1; ui_check "$R" "Status: issues-found
button overlaps" 2 1; full "$R"
tg "$R" 'git commit -m x'; check "newer issues-found verdict does shadow it -> deny" "2:1" "$RC:$(has 'issues-found' "$ERR")"
R=$(mkc tg-handback); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit
TP="$TMP/transcript-$AGN.jsonl"; printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}' > "$TP"
HB=$(jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:"Status: pass\nnew tests: 1"}}]}}')
( sleep 0.6; printf '%s\n' "$HB" >> "$TP" ) &
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p}')"
wait
check "result via SubagentHandback written after the hook fired: te receipt (poll)" "pass" "$(lastrec "$R" te | jq -r .status)"
full "$R"; tg "$R" 'git commit -m x'; check "handback te receipt counts at the gate" 0 "$RC"
R=$(mkc tg-te-noev); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" test-engineer "te$AGN"; ag_stop "$R" test-engineer "te$AGN" "Status: pass"
sleep 1; full "$R"   # 1 s gap: receipts are second-resolution, a run in the same second as Stop would count
tg "$R" 'git commit -m x'; check "te pass without a suite run during it: not counted" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
check "SubagentStop prints nothing for ui/te" "" "$OUT"

echo "--- subagent-rails: E8 shape (session cwd = main checkout, agent works in a worktree)"
R=$(mkc tg-e8); git -C "$R" worktree add -q -b e8 "$TMP/tg-e8wt" 2>/dev/null; W="$TMP/tg-e8wt"
addl "$W/src/lib/x.ts" 20 w; stage "$W"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$W" run unit; ag_stop "$R" claude-subteams:test-engineer "te$AGN" "Status: pass"
check "te receipt bound to the worktree it ran in (tree = worktree snapshot)" "$(. "$LIB"; tc_snapshot_tree "$W")" "$(lastrec "$R" te | jq -r .tree)"
full "$W"; tg "$W" 'git commit -m x'; check "E8: commit in the worktree passes" 0 "$RC"
R=$(mkc tg-e8ui "$CNARROW"); git -C "$R" worktree add -q -b e8ui "$TMP/tg-e8uiwt" 2>/dev/null; W="$TMP/tg-e8uiwt"
addl "$W/src/ui/a.html" 20 w; stage "$W"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:ui-tester "ui$AGN"
wshot() { (. "$LIB"; tc_receipt_write "$1" "{\"type\":\"shot\",\"kind\":\"shot\",\"path\":\"/s.png\",\"size\":3,\"session\":\"t\",\"ts\":$(date +%s),\"root\":\"$1\"}" >/dev/null); }
wshot "$W"; wshot "$W"; ag_stop "$R" claude-subteams:ui-tester "ui$AGN" "Status: pass"
check "ui-tester in a worktree, session in main, pass by screenshots only: tree = worktree snapshot" "$(. "$LIB"; tc_snapshot_tree "$W")" "$(lastrec "$R" ui | jq -r .tree)"
full "$W"; tg "$W" 'git commit -m x'; check "that ui receipt counts in the worktree commit" 0 "$RC"
R=$(mkc tg-lasttext); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit
TP="$TMP/transcript-$AGN.jsonl"; jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Status: pass\nnew tests: 3"}]}}' > "$TP"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p}')"
check "no last_assistant_message, no handback: status from the last assistant text" pass "$(lastrec "$R" te | jq -r .status)"

echo "--- test gate: small-change threshold (R9) — drift since the last agent check"
R=$(mkc tg-drift); addl "$R/src/lib/x.ts" 20 c; stage "$R"; te_check "$R"; full "$R"
tg "$R" 'git commit -m base2'; git -C "$R" commit -q -m base2
addl "$R/src/lib/x.ts" 5 d; addl "$R/src/lib/y.ts" 5 d; stage "$R"; full "$R"
tg "$R" 'git commit -m x'; check "drift 10 lines / 2 files after te: agents not needed" 0 "$RC"
addl "$R/src/lib/y.ts" 1 e; stage "$R"; full "$R"
tg "$R" 'git commit -m x'; check "drift 11 lines: test-engineer needed, suites fine" "2:1:0" "$RC:$(has 'test-engineer:' "$ERR"):$(has 'suite unit' "$ERR")"
R=$(mkc tg-series); addl "$R/src/lib/x.ts" 20 c; stage "$R"; te_check "$R"; full "$R"; git -C "$R" commit -q -m checked
addl "$R/src/lib/x.ts" 6 s1; stage "$R"; full "$R"; tg "$R" 'git commit -m s1'
check "series: first 6-line commit passes" 0 "$RC"; git -C "$R" commit -q -m s1
addl "$R/src/lib/x.ts" 6 s2; stage "$R"; full "$R"; tg "$R" 'git commit -m s2'
check "KEY series: second 6-line commit needs test-engineer (accumulated drift)" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
R=$(mkc tg-newfile); addl "$R/src/lib/x.ts" 20 c; stage "$R"; te_check "$R"; full "$R"; git -C "$R" commit -q -m checked
addl "$R/src/lib/n.ts" 3 n; stage "$R"; full "$R"; tg "$R" 'git commit -m x'
check "new 3-line file in the code group: test-engineer needed" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
R=$(mkc tg-bin); addl "$R/src/lib/x.ts" 20 c; stage "$R"; te_check "$R"; full "$R"; git -C "$R" commit -q -m checked
printf 'bin\000ary2\n' > "$R/src/lib/b.bin"; stage "$R"; full "$R"; tg "$R" 'git commit -m x'
check "binary change in the code group: test-engineer needed" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
R=$(mkc tg-testfile); addl "$R/src/ui/a.html" 20 u; stage "$R"; ui_check "$R" "Status: pass"; full "$R"; git -C "$R" commit -q -m checked
addl "$R/src/ui/form.spec.ts" 30 t; addl "$R/src/ui/a.html" 1 v; stage "$R"; full "$R"
tg "$R" 'git commit -m x'; check "test file (inside ui_globs) edited by 30 lines: ui receipt still valid" 0 "$RC"

echo "--- test gate: e2e evidence only from a suite covering the commit's UI files; degraded"
R=$(mkc tg-e2enarrow "$CNARROW"); addl "$R/src/ui/a.html" 20 u; stage "$R"
ui_check "$R" "Status: pass" 2 0; full "$R"; tg "$R" 'git commit -m x'
check "e2e suite does not cover these UI files: pass with 2 screenshots counts" 0 "$RC"
R=$(mkc tg-e2ecover "$CNARROW"); mkdir -p "$R/src/ui/forms"; addl "$R/src/ui/forms/f.html" 20 u; git -C "$R" add -A; git -C "$R" commit -q -m f
addl "$R/src/ui/forms/f.html" 20 v; stage "$R"
ui_check "$R" "Status: pass" 2 0; full "$R"; tg "$R" 'git commit -m x'
check "covering e2e suite exists: pass without its run not counted" "2:1" "$RC:$(has 'ui-tester:' "$ERR")"
R=$(mkc tg-degr-noe2e "$CNARROW"); addl "$R/src/ui/a.html" 20 u; stage "$R"
ui_check "$R" "Status: degraded
live review not performed: Chrome not found" 0 1; full "$R"; tg "$R" 'git commit -m x'
check "degraded without a REQUIRED e2e suite: not counted (nothing was checked)" "2:1" "$RC:$(has 'degraded result does not count' "$ERR")"

echo "--- test gate: no auto suite -> test-engineer cannot give evidence (said explicitly)"
R=$(mkc tg-noauto '{"suites":[{"name":"slow","cmd":"true","run":"opt-in"}],"ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 20 c; stage "$R"; tg "$R" 'git commit -m x'
check "no run:auto suite: deny says test-engineer cannot produce evidence" "2:1" "$RC:$(has 'no run:auto suite' "$ERR")"
sts "$R" status; check "status says the same" 1 "$(jq -r '.missing[]' "$TMP/sout" | grep -c 'no run:auto suite')"

echo "--- test gate: drift anchor (no agent receipt yet)"
R=$(mkc tg-anchor); addl "$R/src/lib/x.ts" 5 a; stage "$R"; full "$R"
sts "$R" status; check "status: small change ok, anchor announced, NOT written" "0:1:0" "$?:$(grep -c 'drift anchor' "$TMP/serr"):$(nrec "$R" anchor)"
tg "$R" 'git commit -m small1'; check "E10: first small logic change without agents: allow" 0 "$RC"
check "gate wrote one code anchor at HEAD's tree" "1:code:$(git -C "$R" rev-parse 'HEAD^{tree}')" "$(nrec "$R" anchor):$(lastrec "$R" anchor | jq -r '.group + ":" + .tree')"
git -C "$R" commit -q -m small1
addl "$R/src/lib/x.ts" 6 b; stage "$R"; full "$R"; tg "$R" 'git commit -m small2'
check "KEY anchor: second small commit (5+6 lines) needs test-engineer" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
check "anchor not moved by the small commit" 1 "$(nrec "$R" anchor)"
te_check "$R"; full "$R"; tg "$R" 'git commit -m small2'; check "after test-engineer: allow (receipt newer than anchor)" 0 "$RC"

echo "--- test gate: small_change above the ceiling -> visible warning"
R=$(mkc tg-clamp '{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**"],"small_change":{"max_lines":50,"max_files":9}}')
addl "$R/src/lib/x.ts" 3 a; stage "$R"; full "$R"; tg "$R" 'git commit -m x'
check "clamped small_change: allow + warning naming the ceiling" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'clamped to 10 lines / 2 files')"
sts "$R" status; check "status warns too" 1 "$(grep -c 'clamped' "$TMP/serr")"
addl "$R/src/lib/x.ts" 20 b; stage "$R"; full "$R"; tg "$R" 'git commit -m x'
check "clamped: 23 lines still needs test-engineer (ceiling applies)" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"

echo "--- test gate: contract changes (R11)"
R=$(mkc tg-cc); ctr "$R/CLAUDE.md" '{"suites":[],"ui_globs":[],"code_globs":[]}'; addl "$R/src/lib/x.ts" 2 a; stage "$R"
tg "$R" 'git commit -m weaken'; check "contract change + another file: deny" "2:1" "$RC:$(has 'ALONE' "$ERR")"
git -C "$R" reset -q -- src/lib/x.ts
tg "$R" 'git commit -m contract'; check "contract-only commit: allow + visible warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'test contract changed')"
R=$(mkc tg-crm); printf '# no contract any more\n' > "$R/CLAUDE.md"; addl "$R/src/lib/x.ts" 2 a; stage "$R"
tg "$R" 'git commit -m x'; check "removing the contract together with code: deny" 2 "$RC"
git -C "$R" reset -q -- src/lib/x.ts; tg "$R" 'git commit -m x'; check "removing the contract alone: allow + warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'removed')"
R=$(mkc tg-cbroken); printf '# P\n\n<!-- subteams:test-suites v1 -->\n```json\n{"suites":[\n```\n' > "$R/CLAUDE.md"; stage "$R"
tg "$R" 'git commit -m x'; check "committing an invalid contract: deny" "2:1" "$RC:$(has 'invalid' "$ERR")"
R=$(mkrepo tg-newc); echo '<p>' > "$R/page.html"; ctr "$R/CLAUDE.md" "$CJSON"; git -C "$R" add -A
tg "$R" 'git commit -m x'; check "contract only in the index (new contract mode): allow + warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'new test contract staged')"
R=$(mkrepo tg-newc0); rm -rf "$R/.git"; git -C "$R" init -q -b main; ctr "$R/CLAUDE.md" "$CJSON"; git -C "$R" add -A
tg "$R" 'git commit -m first'; check "first commit of a new repo with a contract: allow" 0 "$RC"

R=$(mkc tg-headbroken); printf '# P\n\n<!-- subteams:test-suites v1 -->\n```json\n{"suites":[\n```\n' > "$R/CLAUDE.md"; git -C "$R" commit -q -am broken
addl "$R/src/lib/x.ts" 2 a; stage "$R"; tg "$R" 'git commit -m x'
check "contract in HEAD broken: code commit denied with the reason" "2:1" "$RC:$(has 'is broken' "$ERR")"
git -C "$R" reset -q -- src/lib/x.ts; ctr "$R/CLAUDE.md" "$CJSON"; git -C "$R" add CLAUDE.md; tg "$R" 'git commit -m fix'
check "contract in HEAD broken: contract-only fix allowed + warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'test contract changed')"

echo "--- test gate: no jq / no library with a contract -> deny; without -> allow"
mkdir -p "$TMP/nojq"
for c in bash env cat dirname basename git awk sed grep sort head tail mktemp rm cp mv tr wc date find paste cut sha1sum shasum readlink realpath mkdir ls printf sleep; do
  p=$(command -v "$c" 2>/dev/null) && case "$p" in /*) ln -sf "$p" "$TMP/nojq/$c" ;; esac
done
R=$(mkc tg-nojq); addl "$R/src/lib/x.ts" 2 a; stage "$R"; te_check "$R"; full "$R"
nojq_gate() { # <repo> <command> — payload built WITH jq, hook run on a PATH without it
  local j; j=$(bash_json "$TSID" "$2")
  (cd "$1" && printf '%s' "$j" | PATH="$TMP/nojq" bash "$HOOKS/pre-commit-gate") >"$TMP/out" 2>"$TMP/err"
  RC=$?; OUT=$(cat "$TMP/out"); ERR=$(cat "$TMP/err")
}
nojq_gate "$R" 'git commit -m x'
check "KEY contract in HEAD + no jq: deny 'install jq'" "2:1" "$RC:$(has 'jq is not installed' "$ERR")"
R=$(mkrepo tg-nojq-twin); echo 'y' >> "$R/a.ts"; git -C "$R" add -A
nojq_gate "$R" 'git commit -m x'; check "twin: no contract + no jq: allow (old fail-open)" "0:" "$RC:$ERR"
R=$(mkc tg-nojq2); addl "$R/src/lib/x.ts" 2 a; stage "$R"
nojq_gate "$R" 'echo "no commit here"'; check "no jq, contract, command without a commit: allow" 0 "$RC"
mkdir -p "$TMP/nolib/hooks"; cp "$HOOKS"/pre-commit-gate "$HOOKS"/lib-gitcmd.sh "$TMP/nolib/hooks/"
(cd "$R" && printf '%s' "$(bash_json "$TSID" 'git commit -m x')" | bash "$TMP/nolib/hooks/pre-commit-gate") >/dev/null 2>"$TMP/err"; RC=$?
check "contract + library missing: deny with the reason" "2:1" "$RC:$(has 'lib-testclass.sh did not load' "$(cat "$TMP/err")")"
R=$(mkrepo tg-nolib-twin); echo 'y' >> "$R/a.ts"; git -C "$R" add -A
(cd "$R" && printf '%s' "$(bash_json "$TSID" 'git commit -m x')" | bash "$TMP/nolib/hooks/pre-commit-gate") >/dev/null 2>&1
check "twin: library missing, no contract: allow" 0 "$?"

echo "--- test gate: merged output with NOTES (size signal) = one JSON object"
R=$(mkrepo tg-notes); awk 'BEGIN{for(i=0;i<450;i++) print "x"}' > "$R/big.ts"; git -C "$R" add -A
tg "$R" 'git commit -m x'
check "NOTES + test warning: one object, both in additionalContext" "1:1:1" \
  "$(printf '%s' "$OUT" | jq -s length):$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext | grep -c 'Size signal'):$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c test-gate)"

echo "--- test gate: performance (300 staged files)"
R=$(mkc tg-perf); for d in src/lib src/ui tests; do for i in $(seq 1 100); do echo "f $i" > "$R/$d/p$i.ts"; done; done; git -C "$R" add -A; git -C "$R" commit -q -m p
for d in src/lib src/ui tests; do for i in $(seq 1 100); do echo "g" >> "$R/$d/p$i.ts"; done; done; stage "$R"
TIMEFORMAT=%R; { time tg "$R" 'git commit -m x'; } 2>"$TMP/time"; T=$(tail -n 1 "$TMP/time")
check "gate on 300 staged files < 5 s (took ${T}s), denies" "1:2" "$(awk -v t="$T" 'BEGIN{print (t<5)?1:0}'):$RC"

echo "--- session-start: jq warning, one-time contract suggestion"
R=$(mkrepo ss-ui); echo '<p>' > "$R/page.html"; git -C "$R" add -A; git -C "$R" commit -q -m ui
run_hook "$R" session-start '{}'
check "suggestion shown once (repo with UI files, no contract)" 1 "$(has 'subteams-tests --init-contract' "$OUT")"
run_hook "$R" session-start '{}'; check "not shown the second time" 0 "$(has 'init-contract' "$OUT")"
R=$(mkc ss-c); run_hook "$R" session-start '{}'; check "repo with a contract: no suggestion" 0 "$(has 'init-contract' "$OUT")"
R=$(mkrepo ss-none); printf '<!-- subteams:test-suites none -->\n' > "$R/CLAUDE.md"; echo '<p>' > "$R/page.html"; git -C "$R" add -A; git -C "$R" commit -q -m n
run_hook "$R" session-start '{}'; check "'none' marker: no suggestion" 0 "$(has 'init-contract' "$OUT")"
R=$(mkrepo ss-plain); run_hook "$R" session-start '{}'; check "no UI files, no e2e: no suggestion" 0 "$(has 'init-contract' "$OUT")"
(cd "$R" && printf '{}' | PATH="$TMP/nojq" bash "$HOOKS/session-start") > "$TMP/out" 2>/dev/null; OUT=$(cat "$TMP/out")
check "no jq: one JSON object with a visible systemMessage" "1:1" "$(printf '%s' "$OUT" | jq -s length):$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'jq is not installed')"
TIMEFORMAT=%R; R=$(mkrepo ss-fast); { time run_hook "$R" session-start '{}'; } 2>"$TMP/time"; T=$(tail -n 1 "$TMP/time")
check "session-start < 1 s (took ${T}s)" 1 "$(awk -v t="$T" 'BEGIN{print (t<1)?1:0}')"

fi   # sec gate150

# ====================================================== review fixes (1.50, B1-B19)
# Each section is a regression test for one finding of the full review; the
# mutation table in the fix report names the change that turns each one red.

if sec fix01-untracked; then
echo "--- fix B1: untracked files at test time do not invalidate receipts; unstaged files are named"
R=$(mkc fx1); addl "$R/src/lib/x.ts" 20 c; stage "$R"
echo 'scratch' > "$R/src/lib/scratch.ts"; echo 'tmp' > "$R/notes.swp"          # untracked, not committed
te_check "$R"; full "$R"
tg "$R" 'git commit -m x'; check "KEY B1 untracked scratch file in the suite paths during the run: allow" 0 "$RC"
sts "$R" status; check "B1 status agrees" true "$(jq -r .ok "$TMP/sout")"
R=$(mkc fx1b); addl "$R/src/lib/x.ts" 3 a; stage "$R"; addl "$R/src/lib/x.ts" 1 unstaged
te_check "$R"; full "$R"; tg "$R" 'git commit -m x'
check "KEY B1 unstaged hunk: deny names the file and says add/revert, no stash / --include-untracked" "2:1:1:0" \
  "$RC:$(has 'src/lib/x.ts has changes that are not in this commit' "$ERR"):$(has 'add it to this commit, or revert/finish that edit, then re-run' "$ERR"):$(printf '%s' "$ERR" | grep -c 'stash\|include-untracked')"
sts "$R" status; check "B1 status names it too" 1 "$(jq -r '.missing[]' "$TMP/sout" | grep -c 'src/lib/x.ts has changes that are not in this commit')"
fi

if sec fix02-mindrift; then
echo "--- fix B2: agent receipts by minimal drift across worktrees; anchors bound to the branch"
R=$(mkc fx2); git -C "$R" worktree add -q -b other "$TMP/fx2-w" 2>/dev/null; W="$TMP/fx2-w"
addl "$R/src/lib/x.ts" 20 mine; stage "$R"; te_check "$R"
sleep 1; addl "$W/src/lib/x.ts" 30 theirs; stage "$W"; te_check "$W"        # newer receipt, other content
full "$R"; tg "$R" 'git commit -m x'
check "KEY B2 the newest te receipt is from another worktree: the one with minimal drift is used -> allow" 0 "$RC"
sleep 1; te_check "$W" "Status: issues-found
broken in their branch"; full "$R"; tg "$R" 'git commit -m x'
check "B2 a newer issues-found on FARTHER content does not shadow the closer pass" 0 "$RC"
sleep 1; te_check "$R" "Status: issues-found
found a bug here"; full "$R"; tg "$R" 'git commit -m x'
check "B2 issues-found on the same content does shadow it -> deny" "2:1" "$RC:$(has 'issues-found' "$ERR")"
# anchors: an anchor written on branch b1 is ignored on b2 (its commit is not an ancestor)
R=$(mkc fx2a); git -C "$R" checkout -q -b b1
addl "$R/src/lib/x.ts" 20 c; git -C "$R" commit -q -am b1work                 # raw commit: no agent receipt anywhere
addl "$R/src/lib/x.ts" 5 s1; stage "$R"; full "$R"; tg "$R" 'git commit -m s1'
check "B2 small commit on b1 writes an anchor bound to its base commit" "0:$(git -C "$R" rev-parse HEAD)" "$RC:$(lastrec "$R" anchor | jq -r .commit)"
git -C "$R" commit -q -m s1; git -C "$R" checkout -q main
addl "$R/src/lib/y.ts" 6 m; stage "$R"; full "$R"; tg "$R" 'git commit -m m1'
check "KEY B2 on main the b1 anchor (not an ancestor) is ignored: base = HEAD, small change allowed" 0 "$RC"
R=$(mkc fx2c); git -C "$R" checkout -q -b feat; git -C "$R" commit -q --allow-empty -m feat
addl "$R/src/lib/x.ts" 40 big; stage "$R"; te_check "$R"; git -C "$R" commit -q -m featwork; git -C "$R" checkout -q main
addl "$R/src/lib/y.ts" 3 small; stage "$R"; full "$R"; tg "$R" 'git commit -m small'
check "KEY B2 a valid te receipt from an unrelated branch (big drift) does not block a small change on main" 0 "$RC"
check "B2 receipts carry the HEAD they were taken on" "$(git -C "$R" rev-parse feat~1)" "$(lastrec "$R" te | jq -r .head)"
fi

if sec fix03-crossrepo; then
echo "--- fix B3: session in repo A, agent works in repo B — the receipt lands in B's store"
A=$(mkrepo fx3-a); B=$(mkc fx3-b); addl "$B/src/lib/x.ts" 20 c; stage "$B"
C=$(mkc fx3-c); addl "$C/src/lib/x.ts" 20 c; stage "$C"
TP3="$TMP/transcript-fx3.jsonl"
jq -nc --arg c "cd $B && subteams-tests run unit" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}' > "$TP3"
ag_stop3() { run_hook "$A" "subagent-rails SubagentStop" "$(jq -nc --arg a "$1" --arg c "$A" --arg p "$TP3" --arg m "$2" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",cwd:$c,agent_transcript_path:$p,last_assistant_message:$m}')"; }
AGN=$((AGN+1)); ag_start "$A" claude-subteams:test-engineer "te$AGN"; sts "$B" run unit
sts "$C" run unit                                   # another session's run in an unrelated repo, same interval
ag_stop3 "te$AGN" "Status: pass"
check "KEY B3 te receipt written into B's store (with B's snapshot)" "1:$(. "$LIB"; tc_snapshot_tree "$B")" "$(nrec "$B" te):$(lastrec "$B" te | jq -r .tree)"
check "B3 nothing written into A's store (no evidence there)" 0 "$(nrec "$A" te)"
check "KEY B3 nothing written into C's store (its run is not in the agent's transcript)" 0 "$(nrec "$C" te)"
full "$B"; tg "$A" "git -C $B commit -m x"; check "B3 commit in B (from A's cwd) passes" 0 "$RC"
check "B3 recent index has suite lines for B" 1 "$(awk -F'\t' -v r="$B" '$3 == r && $4 == "suite"' "$XDG_CACHE_HOME/claude-subteams/receipts/_recent.log" | grep -c . | awk '{print ($1 > 0)}')"
LOG="$XDG_CACHE_HOME/claude-subteams/receipts/_recent.log"; cp "$LOG" "$TMP/log.bak"
{ printf '%s\tdeadbeef\t/nonexistent\tsuite\n' 1000; cat "$TMP/log.bak"; } > "$LOG"
shot "$B"; check "B3 an expired first line triggers the rewrite (lines older than 14 days dropped)" 0 "$(grep -c '^1000	' "$LOG")"
check "B3 the rewrite keeps current lines" 1 "$(awk -F'\t' -v r="$B" '$3 == r' "$LOG" | grep -c . | awk '{print ($1 > 0)}')"
printf '%s\t%s\t%s\tsuite\n' "$(date +%s)" "$(. "$LIB"; tc_repo_id "$B")" "/nonexistent/evil" >> "$LOG"
AGN=$((AGN+1)); ag_start "$A" claude-subteams:test-engineer "te$AGN"; ag_stop3 "te$AGN" "Status: pass"
check "B3 a forged index line with a missing root is ignored (receipt falls back to the cwd store)" 1 "$(nrec "$A" te)"
fi

if sec fix04-merge; then
echo "--- fix B4: merge / cherry-pick / revert / rebase in progress -> warning only"
R=$(mkc fx4); git -C "$R" checkout -q -b side; git -C "$R" commit -q --allow-empty -m side; SIDE=$(git -C "$R" rev-parse HEAD); git -C "$R" checkout -q main
addl "$R/src/lib/x.ts" 20 c; stage "$R"
echo "$SIDE" > "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD"
tg "$R" 'git commit -m merge'
check "KEY B4 merge in progress, nothing checked: allow + visible warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'merge in progress')"
ctr "$R/CLAUDE.md" '{"suites":[],"ui_globs":[],"code_globs":[]}'; stage "$R"
tg "$R" 'git commit -m merge'; check "B4 merge: the 'contract change alone' rule is not applied" 0 "$RC"
git -C "$R" rev-parse HEAD > "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD"
tg "$R" 'git commit -m x'; check "KEY r3 a MERGE_HEAD naming a commit already in HEAD (hand-made) does not switch to warnings -> deny" 2 "$RC"
rm -f "$(git -C "$R" rev-parse --absolute-git-dir)/MERGE_HEAD"
tg "$R" 'git commit -m x'; check "B4 twin: no merge -> the same commit is denied" 2 "$RC"
R=$(mkc fx4r); addl "$R/src/lib/x.ts" 20 c; stage "$R"; RB="$(git -C "$R" rev-parse --absolute-git-dir)/rebase-merge"; mkdir -p "$RB"
tg "$R" 'git commit -m x'; check "r3 an empty rebase-merge dir (no 'onto') is not a rebase -> deny" 2 "$RC"
git -C "$R" rev-parse HEAD > "$RB/onto"
tg "$R" 'git commit -m x'; check "r4 a rebase dir with 'onto' but HEAD attached and no head-name is forged -> deny (a real rebase: see r4)" 2 "$RC"
fi

if sec fix05-none; then
echo "--- fix B5: 'none' marker -> the test gate is completely silent"
R=$(mkrepo fx5); printf '<!-- subteams:test-suites none -->\n' > "$R/CLAUDE.md"; git -C "$R" add -A; git -C "$R" commit -q -m none
echo '<p>x</p>' > "$R/page.html"; echo 'y' >> "$R/a.ts"; git -C "$R" add -A
tg "$R" 'git commit -m x'; check "KEY B5 none marker: rc 0, no output at all" "0::" "$RC:$OUT:$ERR"
R=$(mkrepo fx5n); printf '<!-- subteams:test-suites none -->\n' > "$R/CLAUDE.md"; git -C "$R" add -A; git -C "$R" commit -q -m none
ctr "$R/CLAUDE.md" "$CJSON"; git -C "$R" add -A; tg "$R" 'git commit -m contract'
check "B5 'none' in HEAD + a staged v1 contract: the new-contract notice is still shown" 1 "$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'test contract')"
R=$(mkrepo fx5t); echo '<p>x</p>' > "$R/page.html"; echo 'y' >> "$R/a.ts"; git -C "$R" add -A
tg "$R" 'git commit -m x'; check "B5 twin without the marker: a warning" 1 "$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'no test contract')"
fi

if sec fix06-status; then
echo "--- fix B6: tolerant Status line"
R=$(mkc fx6); addl "$R/src/lib/x.ts" 20 c; stage "$R"
for m in '**Status:** pass' '## Status: pass' '> Status: PASS — all green' '- **Status**: pass' 'Статус: pass' '`Status`: pass.'; do
  te_check "$R" "$m
details"; check "KEY B6 parses: $m" pass "$(lastrec "$R" te | jq -r .status)"
done
for m in 'Status: pass | issues-found | blocked' 'Status: passed' 'Statuses: pass' 'Result: pass'; do
  te_check "$R" "$m"; check "B6 rejected: $m" rejected "$(lastrec "$R" te | jq -r .status)"
done
check "B6 a rejected receipt carries no snapshot (status parsed before snapshotting)" null "$(lastrec "$R" te | jq -r .tree)"
fi

if sec fix07-budget; then
echo "--- fix B7: non-target agents are a fast no-op; large untracked files are named"
R=$(mkc fx7); TIMEFORMAT=%R
{ time run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc '{session_id:"sx",agent_id:"zz",agent_type:"developer",last_assistant_message:"done"}')"; } 2>"$TMP/time"
check "B7 SubagentStop for a non-target agent < 0.5 s (took $(tail -n 1 "$TMP/time")s), silent" "1:" "$(awk -v t="$(tail -n 1 "$TMP/time")" 'BEGIN{print (t<0.5)?1:0}'):$OUT"
dd if=/dev/zero of="$R/huge.bin" bs=1048576 count=11 2>/dev/null
addl "$R/src/lib/x.ts" 20 c; stage "$R"; git -C "$R" reset -q -- huge.bin
tg "$R" 'git commit -m x'; check "KEY B7 deny names the >10 MB untracked file" "2:1" "$RC:$(has 'huge.bin (11 MB)' "$ERR")"
sts "$R" status; check "B7 status names it (JSON + stderr)" "huge.bin (11 MB):1" "$(jq -r '.large_untracked[0]' "$TMP/sout"):$(grep -c 'huge.bin' "$TMP/serr")"
fi

if sec fix08-resume; then
echo "--- fix B8: a resumed agent (no new SubagentStart) still gets a receipt"
R=$(mkc fx8); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit
ag_stop "$R" claude-subteams:test-engineer "te$AGN" "Status: issues-found
bug"; N1=$(nrec "$R" te)
sleep 1; sts "$R" run unit; ag_stop "$R" claude-subteams:test-engineer "te$AGN" "Status: pass"
check "KEY B8 second Stop of the same agent_id (resume) writes a receipt" "$((N1+1)):pass" "$(nrec "$R" te):$(lastrec "$R" te | jq -r .status)"
check "B8 the start file is kept" 1 "$([ -f "$XDG_CACHE_HOME/claude-subteams/agent-starts/te$AGN" ] && echo 1)"
fi

if sec fix09-heuristic; then
echo "--- fix B9: without a contract only the default test command is auto; build is never auto"
R=$(mkrepo fx9); printf '{"scripts":{"test":"true","test:e2e":"npm run build && touch E2E_RAN","test:int":"touch INT_RAN","build":"touch BUILT"}}' > "$R/package.json"
git -C "$R" add -A; git -C "$R" commit -q -m p
sts "$R"; check "KEY B9 recommend: run = [test], suggest = [test:e2e, test:int]" '["test"]:["test:e2e","test:int"]' "$(jq -c '.recommend.run' "$TMP/sout"):$(jq -c '[.recommend.suggest[].name] | sort' "$TMP/sout")"
sts "$R" config; check "B9 effective config: test:e2e opt-in" opt-in "$(jq -r '.config.suites[] | select(.name=="test:e2e") | .run' "$TMP/sout")"
sts "$R" run --all-auto; check "B9 run --all-auto runs neither test:e2e (no build) nor test:int" "0:0:0" "$([ -e "$R/E2E_RAN" ] && echo 1 || echo 0):$([ -e "$R/BUILT" ] && echo 1 || echo 0):$([ -e "$R/INT_RAN" ] && echo 1 || echo 0)"
echo 'y' >> "$R/a.ts"; git -C "$R" add -A; tg "$R" 'git commit -m x'
check "B9 the no-contract warning names only the default suite" "1:0" "$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'suite test[,.]'):$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext | grep -c 'test:e2e')"
R=$(mkrepo fx9b); printf '{"scripts":{"test":"npm run build && vitest"}}' > "$R/package.json"
sts "$R"; check "B9 a default test script that runs a build is not auto either" "opt-in:[]" "$(jq -r '.suites[0].run' "$TMP/sout"):$(jq -c '.recommend.run' "$TMP/sout")"
fi

if sec fix10-uiscript; then
echo "--- fix B10: logic inside ui_globs needs test-engineer when there are no code_globs"
R=$(mkc fx10 '{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]}],"ui_globs":["src/ui/**"],"test_globs":["tests/**"]}')
awk 'BEGIN{for(i=1;i<=30;i++) print "x" i}' > "$R/src/ui/C.tsx"; git -C "$R" add -A; git -C "$R" commit -q -m c
addl "$R/src/ui/C.tsx" 20 u; stage "$R"; ui_check "$R" "Status: pass" 2 0; sts "$R" run unit
tg "$R" 'git commit -m x'; check "KEY B10 .tsx in ui_globs: test-engineer required as well" "2:1:0" "$RC:$(has 'test-engineer:' "$ERR"):$(has 'ui-tester:' "$ERR")"
git -C "$R" reset -q --hard; addl "$R/src/ui/a.html" 20 u; stage "$R"; ui_check "$R" "Status: pass" 2 0; sts "$R" run unit
tg "$R" 'git commit -m x'; check "B10 twin: markup only -> ui-tester is enough" 0 "$RC"
fi

if sec fix11-items; then
echo "--- fix B11: suite names with ':' are not truncated in the warning summary"
R=$(mkrepo fx11); ctr "$R/CLAUDE.md" '{"suites":[{"name":"test","cmd":"true"},{"name":"test:e2e","cmd":"true","kind":"e2e"}],"ui_globs":[],"code_globs":[]}'
echo 'y' >> "$R/a.ts"; git -C "$R" add -A; tg "$R" 'git commit -m x'
check "KEY B11 summary lists 'suite test, suite test:e2e'" 1 "$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'suite test, suite test:e2e')"
fi

if sec fix12-flaky; then
echo "--- fix B12: a failure on the same content before the latest pass -> flaky warning"
R=$(mkc fx12 '{"suites":[{"name":"unit","cmd":"if [ -e '"$TMP"'/flaky-flag ]; then true; else touch '"$TMP"'/flaky-flag; exit 1; fi","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
rm -f "$TMP/flaky-flag"; addl "$R/src/lib/x.ts" 2 a; stage "$R"
sts "$R" run unit; sleep 1; sts "$R" run unit
tg "$R" 'git commit -m x'; check "KEY B12 allow + 'failed earlier on the same content (flaky?)'" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'unit failed earlier on the same content (flaky?)')"
sts "$R" status; check "B12 status warns too" "1:true" "$(grep -c 'flaky' "$TMP/serr"):$(jq -r '.suites[] | select(.name=="unit") | .flaky' "$TMP/sout")"
fi

if sec fix13-prior; then
echo "--- fix B13: the commit is the only state-changing command (fully checked baseline: the deny is the rule's own)"
R=$(mkc fx13); addl "$R/src/lib/x.ts" 20 c; stage "$R"; te_check "$R"; full "$R"
tg "$R" 'git commit -m x'; check "B13 baseline: plain commit of the checked content -> allow" 0 "$RC"
tg "$R" 'git commit -am x'; check "B13 baseline: -am with nothing unstaged -> allow" 0 "$RC"
for c in 'npm run lint:fix && git commit -m x' 'git stash && git commit -m x' 'touch src/lib/z.ts; git commit -m x' \
         'seq 1 2 > src/lib/a.js && git commit -m x' 'git -c diff.external=/bin/true diff && git commit -m x' \
         'M="$(npm run lint:fix)"; git commit -am x' 'echo "$(sed -i s/a/b/ src/lib/x.ts)" && git commit -am x' \
         'git commit -am "$(sed -i s/a/b/ src/lib/x.ts; echo msg)"' 'git commit -m "`touch src/lib/q.ts`"' \
         "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nmsg\nEOF\n)$(touch src/lib/w.ts)"')"; do
  tg "$R" "$c"; check "KEY B13 deny on a checked baseline: $(printf '%s' "$c" | head -1)" 2 "$RC"
done
for d in "'EOF'" EOF; do
  for c in "$(printf 'git commit -am "$(cat <<%s | sh\nsed -i s/1/X/ src/lib/x.ts\nEOF\n)"' "$d")" \
           "$(printf 'git commit -am "$(cat <<%s >src/lib/x.ts\nx\nEOF\n)"' "$d")" \
           "$(printf 'git commit -am "$(cat <<%s\nmsg\nEOF\nsed -i s/1/X/ src/lib/x.ts\n)"' "$d")"; do
    tg "$R" "$c"; check "KEY B13 heredoc message extended on its operator line / after the terminator -> deny: $(printf '%s' "$c" | head -1)" 2 "$RC"
  done
done
check "B13 none of those ran (hook only parses): x.ts untouched" 0 "$(git -C "$R" diff --name-only | grep -c x.ts)"
tg "$R" "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\ndocs: $(literal) and `ticks` in a quoted heredoc\nEOF\n)"')"
check "B13 a quoted-delimiter message heredoc with \$( / backticks in its literal body: allow" 0 "$RC"
for c in "GIT_INDEX_FILE=/tmp/i git commit -m x" "env GIT_DIR=.git git commit -m x" "export GIT_WORK_TREE=/tmp; git commit -m x" \
         "git --git-dir=.git commit -m x" "git --work-tree /tmp commit -m x" "git -c core.worktree=/tmp commit -m x"; do
  tg "$R" "$c"; check "KEY B15 GIT_* override on a checked baseline -> deny: $c" "2:1" "$RC:$( [ "$(has 'GIT_INDEX_FILE / GIT_DIR' "$ERR")$(has 'injects git configuration' "$ERR")" != 00 ] && echo 1 || echo 0)"
done
tg "$R" 'git commit -m x src/lib/*.ts'; check "B13 commit pathspec with a glob -> deny (shell vs git expansion)" "2:1" "$RC:$(has 'glob characters' "$ERR")"
fi

if sec fix14-difftree; then
echo "--- fix B14: computed commit tree == the tree git really records (differential)"
. "$DIR/hooks/lib-gitcmd.sh"; . "$DIR/hooks/lib-commitscan.sh"; . "$LIB"
ctfix() { # <dir> — fresh fixture: base commit, then staged/unstaged/untracked/deleted state
  local r="$1"; rm -rf "$r"; mkdir -p "$r/sub" && git -C "$r" init -q -b main
  printf 'a\n' > "$r/a.ts"; printf 'b\n' > "$r/b.ts"; printf 'c\n' > "$r/sub/c.ts"; printf 'd\n' > "$r/doc.md"; printf 'e\n' > "$r/e.ts"
  git -C "$r" add -A; git -C "$r" commit -q -m base; printf 'a2\n' >> "$r/a.ts"; git -C "$r" commit -q -am second
  printf 'staged\n' >> "$r/a.ts"; git -C "$r" add a.ts; printf 'unstaged\n' >> "$r/a.ts"     # a.ts: staged + unstaged
  printf 'unstaged\n' >> "$r/b.ts"                                                         # b.ts: unstaged only
  printf 'new\n' > "$r/sub/new.ts"                                                         # untracked
  printf 'n2\n' > "$r/staged-new.ts"; git -C "$r" add staged-new.ts                         # staged new file
  rm "$r/e.ts"                                                                             # unstaged deletion
  printf 'c2\n' >> "$r/sub/c.ts"
}
ctcmp() { # <label> <command> — computed (gate logic) vs real git on a copy; plus "the real index is untouched"
  local r="$TMP/ctd" c="$TMP/ctd-real" k ck=-1 rc idx0 idx1 comp real
  ctfix "$r"; [ -n "${CT_SETUP:-}" ] && (cd "$r" && eval "$CT_SETUP" >/dev/null 2>&1)
  rm -rf "$c"; cp -R "$r" "$c"
  idx0=$(cksum < "$r/.git/index")
  ( cd "$r" && CS_REPO=$(git rev-parse --show-toplevel); cs_scan "$2"
    for k in "${!CS_KIND[@]}"; do [ "${CS_KIND[k]}" = git ] && [ "${CS_SUB[k]}" = commit ] && ck=$k; done
    cs_prior_ok "$ck" && cs_commit_tree "$ck"; rc=$?
    if [ "$rc" -eq 0 ]; then echo "$CS_TREE"; else echo "refused:$rc"; fi ) > "$TMP/ct-comp" 2>/dev/null
  comp=$(cat "$TMP/ct-comp"); idx1=$(cksum < "$r/.git/index")
  if (cd "$c" && bash -c "$2") >/dev/null 2>&1; then real=$(git -C "$c" rev-parse 'HEAD^{tree}')
  else real="refused"; fi
  case "$comp" in refused:*) comp=refused ;; esac
  check "KEY B14 $1: computed == real" "$real" "$comp"
  check "B14 $1: real index untouched" "$idx0" "$idx1"
}
ctcmp "plain (index)" 'git commit -q -m x'
ctcmp "-a" 'git commit -q -am x'
ctcmp "<path> (staged + unstaged hunks)" 'git commit -q -m x a.ts'
ctcmp "-o <path>" 'git commit -q -o -m x -- a.ts'
ctcmp "-i <path>" 'git commit -q -i -m x b.ts'
ctcmp "<dir> pathspec" 'git commit -q -m x -- sub'
ctcmp "<path> of an unstaged deletion" 'git commit -q -m x e.ts'
ctcmp "<path> from a subdirectory" 'cd sub && git commit -q -m x c.ts'
ctcmp "git add <dir> && commit" 'git add sub && git commit -q -m x'
ctcmp "git add -A && commit" 'git add -A && git commit -q -m x'
ctcmp "git rm --cached && commit" 'git rm -q --cached doc.md && git commit -q -m x'
ctcmp "git rm && commit" 'git rm -q doc.md && git commit -q -m x'
ctcmp "-F - -- <paths> (heredoc)" "$(printf 'git commit -q -F - -- a.ts b.ts <<'"'"'EOF'"'"'\nmsg "q"; x\nEOF')"
printf 'b.ts\nsub/c.ts\n' > "$TMP/pf.txt"
ctcmp "--pathspec-from-file" "git commit -q -m x --pathspec-from-file=$TMP/pf.txt"
ctcmp "--amend (index)" 'git commit -q --amend -m y'
ctcmp "--amend -a" 'git commit -q --amend --no-edit -a'
ctcmp "--amend <path>" 'git commit -q --amend -m y a.ts'
CT_SETUP='git rm -q --cached doc.md; printf "d2\n" >> doc.md' ctcmp "<path> removed from the index, still in HEAD (--with-tree)" 'git commit -q -m x doc.md'
ctcmp "-i <untracked path>: both refuse" 'git commit -q -i -m x sub/new.ts'
ctcmp "<nomatch>: both refuse" 'git commit -q -m x nomatch'
ctcmp "abbreviated --inc (= --include)" 'git commit -q --inc -m x b.ts'
ctcmp "ambiguous --al: both refuse" 'git commit -q --al -m x'
fi

if sec fix15-target; then
echo "--- fix B15: target repo from VAR=literal; unresolvable -> literal path; different targets; GIT_* env"
R=$(mkc fx15); addl "$R/src/lib/x.ts" 20 c; stage "$R"; C=$(mkrepo fx15-clean)
tg "$C" "R=$R; git -C \"\$R\" commit -m x"; check "KEY B15 git -C \"\$R\" with R=literal earlier: the contract repo is checked -> deny" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
tg "$C" "D=$R; cd \"\${D}\" && git commit -m x"; check "B15 cd \"\${D}\": resolved -> deny" 2 "$RC"
tg "$C" "git -C $C commit -m a; git -C $R commit -m b"; check "KEY R6d one of two target repos has a contract -> deny 'split'" "2:1" "$RC:$(has 'different repositories' "$ERR")"
for c in "GIT_INDEX_FILE=/tmp/i git commit -m x" "env GIT_DIR=.git git commit -m x" "export GIT_WORK_TREE=/tmp; git commit -m x" \
         "git --git-dir=.git commit -m x" "git --work-tree /tmp commit -m x" "git -c core.worktree=/tmp commit -m x"; do
  tg "$R" "$c"; check "B15 GIT_* override under a contract -> deny: $c" "2:1" "$RC:$( [ "$(has 'GIT_INDEX_FILE / GIT_DIR' "$ERR")$(has 'injects git configuration' "$ERR")" != 00 ] && echo 1 || echo 0)"
done
tg "$R" "git commit -m a && git commit -m b"; check "B15 two commits in one line under a contract -> deny" "2:1" "$RC:$(has 'several commits' "$ERR")"
fi

if sec fix15r6-target; then
echo "--- R6 (coordinator decision): unresolvable / cross-repo targets deny only where a contract is active"
R=$(mkc fx15r6); addl "$R/src/lib/x.ts" 20 c; stage "$R"; te_check "$R"; full "$R"   # fully checked baseline
C=$(mkrepo fx15r6-c); echo 'y' >> "$C/a.ts"; git -C "$C" add -A
D=$(mkrepo fx15r6-d); echo 'y' >> "$D/a.ts"; git -C "$D" add -A
tg "$R" 'git commit -m x'; check "R6 baseline: checked content in the contract repo -> allow" 0 "$RC"
tg "$R" 'cd "$(git rev-parse --show-toplevel)" && git commit -m x'
check "KEY R6a cd \"\$(git rev-parse --show-toplevel)\" resolves to the repo (contract repo, checked) -> allow" 0 "$RC"
tg "$R" 'git -C "`git rev-parse --show-toplevel`" commit -m x'; check "R6a backtick form resolves too -> allow" 0 "$RC"
tg "$C" 'cd "$(git rev-parse --show-toplevel)" && git commit -m x'
check "R6a in a repo without a contract: resolved, no 'unresolved' warning" 0 "$(printf '%s' "$OUT" | jq -r '.systemMessage // ""' | grep -c 'could not be resolved')"
tg "$C" 'git -C "$NOPE_UNSET" commit -m x'
check "KEY R6b unresolvable target, cwd repo WITHOUT a contract -> allow + warning naming the cwd repo" "0:1:1" \
  "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c "target repo could not be resolved ('\$NOPE_UNSET'); test gate evaluated against $C"):$(printf '%s' "$OUT" | jq -r .hookSpecificOutput.additionalContext | grep -c 'could not be resolved')"
tg "$C" 'cd - && git commit -m x'; check "R6b 'cd -' in a repo without a contract -> allow + warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'could not be resolved')"
tg "$R" 'git -C "$NOPE_UNSET" commit -m x'
check "KEY R6c unresolvable target, cwd repo WITH a contract (checked content) -> deny 'Use a literal path'" "2:1" "$RC:$(has 'Use a literal path' "$ERR")"
tg "$R" 'cd "$(pwd)" && git commit -m x'; check "R6c other \$(…) in a contract cwd -> deny (now by the shape rule)" "2:1" "$RC:$(has 'not a shape the gate can verify' "$ERR")"
tg "$C" "git -C $C commit -m a; git -C $D commit -m b"
check "KEY R6d two target repos, none with a contract -> allow + warning 'different repositories'" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'different repositories')"
tg "$C" "git -C $C commit -m a; git -C $R commit -m b"; check "KEY R6d one target repo with a contract -> deny" "2:1" "$RC:$(has 'at least one has a test contract' "$ERR")"
SID19=sNOMARKR6; tg2() { gate "$1" "$SID19" "$2"; }
tg2 "$C" 'git -C "$NOPE_UNSET" commit -m x'
check "R6 review gate unchanged vs 1.49: unresolvable target falls back to cwd, code without review -> review deny" "2:1" "$RC:$(has 'code-reviewer' "$ERR")"
fi

if sec fix16-amend; then
echo "--- fix B16: --amend is checked against HEAD^ (contract source and drift base)"
R=$(mkc fx16); printf '# no contract\n' > "$R/CLAUDE.md"; git -C "$R" add CLAUDE.md
tg "$R" 'git commit -m drop'; check "B16 dropping the contract alone: allow (warning)" 0 "$RC"; git -C "$R" commit -q -m drop
addl "$R/src/lib/x.ts" 20 c; stage "$R"
tg "$R" 'git commit --amend --no-edit'; check "KEY B16 amend code into the contract-removal commit -> deny (contract change + code)" "2:1" "$RC:$(has 'ALONE' "$ERR")"
git -C "$R" reset -q -- src/lib/x.ts
tg "$R" 'git commit --amend -m "new message"'; check "B16 amend with nothing staged (message only): allow, unchanged" 0 "$RC"
R=$(mkc fx16b); addl "$R/src/lib/x.ts" 5 a; stage "$R"; full "$R"; tg "$R" 'git commit -m s'; git -C "$R" commit -q -m s
addl "$R/src/lib/x.ts" 6 b; stage "$R"; full "$R"
tg "$R" 'git commit --amend --no-edit'; check "KEY B16 amend adding 6 lines: drift from HEAD^ = 11 -> test-engineer needed" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
te_check "$R"; full "$R"; tg "$R" 'git commit --amend --no-edit'
check "KEY B16 after test-engineer the same amend passes (receipt ancestry is checked against HEAD, not HEAD^)" 0 "$RC"
fi

if sec fix17-envrun; then
echo "--- fix B17: suite runs with a changed environment are denied; overrides scrubbed"
R=$(mkc fx17 '{"suites":[{"name":"unit","cmd":"test -z \"$NODE_OPTIONS$PYTEST_ADDOPTS$npm_config_foo$NPM_CONFIG_BAR\"","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
for c in 'CI=1 subteams-tests run unit' 'env FOO=1 subteams-tests run unit' 'export X=1; subteams-tests run unit' \
         'set -a; subteams-tests run unit' 'bash -c "Y=2 subteams-tests run unit"' 'Z=1 bash /x/scripts/discover-tests.sh run unit'; do
  tg "$R" "$c"; check "KEY B17 deny: $c" "2:1" "$RC:$(has 'changed environment' "$ERR")"
done
for c in "cd $R && subteams-tests run unit" 'subteams-tests run --all-auto' 'CI=1 subteams-tests status' 'echo subteams-tests'; do
  tg "$R" "$c"; check "B17 allow: $c" 0 "$RC"
done
CLAUDE_SUBTEAMS_SKIP_TEST_GATE=1 tg "$R" 'CI=1 subteams-tests run unit'; check "B17 the user's SKIP_TEST_GATE in the hook env bypasses it" 0 "$RC"
NODE_OPTIONS=--x PYTEST_ADDOPTS=-q npm_config_foo=1 NPM_CONFIG_BAR=2 sts "$R" run unit
check "KEY B17 run_one scrubs NODE_OPTIONS / PYTEST_ADDOPTS / npm_config_* (any case)" 0 "$(jq -r .exit "$(ls -t "$XDG_CACHE_HOME"/claude-subteams/receipts/*/*-suite-*.json | head -1)")"
fi

if sec fix18-driftfail; then
echo "--- fix B18: a failing git diff inside tc_drift is an error, never 'no drift'"
R=$(mkc fx18); addl "$R/src/lib/x.ts" 20 c; git -C "$R" add -A
T1=$(git -C "$R" rev-parse 'HEAD^{tree}'); T2=$(git -C "$R" write-tree)
check "KEY B18 tc_drift with git diff --name-status failing: rc 1" 1 "$( (. "$LIB"; tc_groups_load "$CJSON"; git() { case "$*" in *--name-status*) return 128 ;; esac; command git "$@"; }; tc_drift "$R" "$T1" "$T2" code; echo $?) )"
check "KEY B18 tc_drift with git diff --numstat failing: rc 1" 1 "$( (. "$LIB"; tc_groups_load "$CJSON"; git() { case "$*" in *--numstat*) return 128 ;; esac; command git "$@"; }; tc_drift "$R" "$T1" "$T2" code; echo $?) )"
check "KEY B18 the gate's agent check treats a failing drift as not small (deny)" "0" "$( (. "$LIB"; tc_groups_load "$CJSON"; git() { case "$*" in *diff*) return 128 ;; esac; command git "$@"; }
   rf=$(mktemp); tc_agent_check "$R" "$rf" "$T2" code 10 2 0 "$T1"; rm -f "$rf"; echo "$TC_AC_OK") )"
check "B18 twin: without the failure the drift is seen" "0:20" "$( (. "$LIB"; tc_groups_load "$CJSON"; tc_drift "$R" "$T1" "$T2" code; echo "$?:$TC_DRIFT_LINES") )"
fi

if sec fix19-reviewlib; then
echo "--- fix B19: the review gate works without scripts/lib-testclass.sh"
mkdir -p "$TMP/nolib19/hooks"; cp "$HOOKS"/pre-commit-gate "$HOOKS"/lib-gitcmd.sh "$HOOKS"/lib-commitscan.sh "$TMP/nolib19/hooks/"
R=$(mkrepo fx19); echo 'y' >> "$R/a.ts"; git -C "$R" add -A
(cd "$R" && bash_json sNOMARK19 'git commit -m x' | bash "$TMP/nolib19/hooks/pre-commit-gate") >/dev/null 2>"$TMP/err"; RC=$?
check "KEY B19 library missing: code commit without review still denied by the review gate" "2:1" "$RC:$(has 'code-reviewer' "$(cat "$TMP/err")")"
R=$(mkrepo fx19d); echo 'more' >> "$R/doc.md"; git -C "$R" add -A
(cd "$R" && bash_json sNOMARK19 'git commit -m x' | bash "$TMP/nolib19/hooks/pre-commit-gate") >/dev/null 2>&1
check "B19 library missing: docs-only commit allowed (fallback docs-class)" 0 "$?"
eval "$(sed -n '/^  tc_is_docs_class() {$/,/^  }$/p' "$HOOKS/pre-commit-gate" | sed 's/^  //; s/^tc_is_docs_class()/fb_docs()/')"
n=0; for f in README.md a/b.txt req/requirements-dev.txt Constraints.TXT x.csv .gitignore sub/.DS_Store sub/.gitignore package-lock.json a/package-lock.json x.ts x.html x.json x.yaml doc.rst d.adoc Заметка.md; do
  a=0; b=0; fb_docs "$f" && a=1; (. "$LIB"; tc_is_docs_class "$f") && b=1; [ "$a" = "$b" ] || n=$((n+1))
done
check "B19 fallback docs-class == tc_is_docs_class on the matrix" 0 "$n"
n=0; for v in TC_NEUTRAL_RE TC_DOCS_EXT_RE TC_REQ_TXT_RE; do
  lit=$(. "$LIB"; eval "printf '%s' \"\$$v\"")
  grep -qF -- "$lit" "$HOOKS/pre-commit-gate" || { n=$((n+1)); echo "     missing verbatim in the gate fallback: $v"; }
done
check "KEY r3k the three docs-class regex literals of lib-testclass appear verbatim in the gate's fallback" 0 "$n"
fi

if sec fix-perf; then
echo "--- fix perf: gate on 300 files with 30 suite + 30 agent receipts of distinct trees"
R=$(mkc fxp); for d in src/lib src/ui tests; do for i in $(seq 1 100); do echo "f $i" > "$R/$d/p$i.ts"; done; done; git -C "$R" add -A; git -C "$R" commit -q -m p
for i in $(seq 1 30); do echo "v $i" >> "$R/src/lib/p1.ts"; sts "$R" run unit; done
for i in $(seq 1 30); do
  echo "w $i" >> "$R/src/lib/p2.ts"
  (. "$LIB"; t=$(tc_snapshot_tree "$R"); n=$(date +%s); tc_receipt_write "$R" "{\"type\":\"te\",\"status\":\"pass\",\"tree\":\"$t\",\"t_start\":$((n-5)),\"t_end\":$n}" >/dev/null)
done
for d in src/lib src/ui tests; do for i in $(seq 1 100); do echo "g" >> "$R/$d/p$i.ts"; done; done; stage "$R"
TIMEFORMAT=%R; { time tg "$R" 'git commit -m x'; } 2>"$TMP/time"; T=$(tail -n 1 "$TMP/time")
check "KEY perf: gate < 10 s with 60 receipts on 300 staged files (took ${T}s), denies" "1:2" "$(awk -v t="$T" 'BEGIN{print (t<10)?1:0}'):$RC"
fi

if sec r3-receipts; then
echo "--- r3 b: an off-history agent receipt counts when it saw exactly this content (message-only amend)"
R=$(mkc r3b); addl "$R/src/lib/x.ts" 5 c1; git -C "$R" commit -q -am c1
addl "$R/src/lib/x.ts" 20 c2; te_check "$R"                       # receipt .head = c1, content c2 (unstaged)
git -C "$R" commit -q --amend -m "c1 reworded"                       # c1 is no longer an ancestor of HEAD
stage "$R"; full "$R"; tg "$R" 'git commit -m c2'
check "KEY r3b receipt from the amended-away commit, drift 0 -> counts (allow)" 0 "$RC"
addl "$R/src/lib/x.ts" 1 more; stage "$R"; full "$R"; tg "$R" 'git commit -m c2'
check "r3b twin: off-history receipt with drift > 0 does not count -> deny" "2:1" "$RC:$(has 'test-engineer:' "$ERR")"
fi

if sec r3-amendnew; then
echo "--- r3 c: amend onto the contract-introducing commit"
R=$(mkrepo r3c); ctr "$R/CLAUDE.md" "$CJSON"; git -C "$R" add CLAUDE.md; git -C "$R" commit -q -m contract
echo 'y' >> "$R/a.ts"; git -C "$R" add a.ts
tg "$R" 'git commit --amend --no-edit'; check "KEY r3c amending code into the contract-introducing commit -> deny" "2:1" "$RC:$(has 'introduced the test contract' "$ERR")"
git -C "$R" reset -q -- a.ts
tg "$R" 'git commit --amend -m "contract v1"'; check "r3c message-only amend of it -> allow" 0 "$RC"
tg "$R" 'git commit --amend --no-edit && git status | cat'; check "r3c shape is enforced there too (pipe after commit into cat is fine)" 0 "$RC"
tg "$R" 'git commit --amend -m x || true'; check "r3c ... and || is not (structural checks apply when HEAD has the contract)" 2 "$RC"
fi

if sec r3-review-pff; then
echo "--- r3 d: the review gate sees --pathspec-from-file (both forms)"
R=$(mkrepo r3d); echo 'more' >> "$R/doc.md"; git -C "$R" add doc.md; echo 'z' >> "$R/a.ts"; printf 'a.ts\n' > "$TMP/r3d-pf"; printf 'doc.md\n' > "$TMP/r3d-pfdoc"
for c in "git commit --pathspec-from-file=$TMP/r3d-pf -m x" "git commit --pathspec-from-file $TMP/r3d-pf -m x" 'git commit --pathspec-from-file=- -m x'; do
  gate "$R" sNOMARKD "$c"; check "KEY r3d review gate: code listed via $c -> review deny" "2:1" "$RC:$(has 'code-reviewer' "$ERR")"
done
gate "$R" sNOMARKD "git commit --pathspec-from-file=$TMP/r3d-pfdoc -m x"; check "r3d twin: the file lists only a doc -> allow" 0 "$RC"
fi

if sec r3-store; then
echo "--- r3 e/f: receipt cap, temp-dir cleanup on a kill, cache root, _recent.log pruning"
R=$(mkc r3e); D=$( . "$LIB"; tc_receipt_dir "$R"); mkdir -p "$D"
for i in $(seq 1 205); do printf '{"type":"shot","kind":"shot","path":"/s","size":1,"session":"t","ts":%s}\n' "$i" > "$D/$(printf '%010d' "$i")-shot-1-$i.json"; done
check "KEY r3e tc_receipts_load keeps the newest 200 per type and says how many were left out" "200:5" \
  "$( (. "$LIB"; tc_receipts_load "$R" > "$TMP/r3e.jl"; printf '%s' "$TC_RECEIPTS_CAPPED") | { read -r c; printf '%s:%s' "$(grep -c . "$TMP/r3e.jl")" "$c"; } )"
check "r3e the dropped ones are the OLDEST" 6 "$(jq -s 'map(.ts) | min' "$TMP/r3e.jl")"
addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" status; check "r3e status says so" 1 "$(grep -c 'only the newest 200 receipts per type' "$TMP/serr")"
mkdir -p "$TMP/slowgit" "$TMP/r3tmp"; GITBIN=$(command -v git)
printf '#!/bin/bash\ncase "${GIT_INDEX_FILE:-}" in *tc-ct*) case "$*" in *write-tree*) sleep 2 ;; esac ;; esac\nexec %s "$@"\n' "$GITBIN" > "$TMP/slowgit/git"; chmod +x "$TMP/slowgit/git"
R=$(mkc r3e2); addl "$R/src/lib/x.ts" 2 a; stage "$R"
( cd "$R" && bash_json "$TSID" 'git commit -m x' | PATH="$TMP/slowgit:$PATH" TMPDIR="$TMP/r3tmp" bash "$HOOKS/pre-commit-gate" >/dev/null 2>&1 ) & GP=$!
sleep 1; check "r3e the gate is inside the commit-tree computation" 1 "$(ls -d "$TMP"/r3tmp/tc-ct.* 2>/dev/null | wc -l | tr -d ' ')"
kill -TERM "$(pgrep -P "$GP" bash | head -1)" 2>/dev/null; wait "$GP" 2>/dev/null; sleep 0.3
check "KEY r3e killed with TERM: no tc-* temp dir left behind" 0 "$(ls -d "$TMP"/r3tmp/tc-* 2>/dev/null | wc -l | tr -d ' ')"
check "KEY r3f a relative XDG_CACHE_HOME is ignored (\$HOME/.cache)" "$TMP/h/.cache" "$(HOME="$TMP/h" XDG_CACHE_HOME=rel/cache bash -c ". '$LIB'; tc_cache_root")"
check "r3f an absolute XDG_CACHE_HOME is used" "$TMP/xc" "$(XDG_CACHE_HOME="$TMP/xc" bash -c ". '$LIB'; tc_cache_root")"
LOG="$XDG_CACHE_HOME/claude-subteams/receipts/_recent.log"; cp "$LOG" "$TMP/log.r3"
{ printf 'garbage-first-line\n%s\tdeadbeef\t/x\tsuite\n' 1000; cat "$TMP/log.r3"; } > "$LOG"; shot "$R"
check "KEY r3f a malformed first line no longer blocks pruning (both old lines gone)" "0:0" "$(grep -c '^garbage' "$LOG"):$(grep -c '^1000	' "$LOG")"
fi

if sec r3-env; then
echo "--- r3 g: run_one drops ENV / SHELLOPTS / BASHOPTS, keeps BASH_ENV"
R=$(mkc r3g '{"suites":[{"name":"unit","cmd":"test -z \"$(env | grep -E \"^(ENV|SHELLOPTS|BASHOPTS)=\")\" && test \"$BASH_ENV\" = /dev/null","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
(cd "$R" && env ENV=/nonexistent SHELLOPTS=braceexpand:hashall:interactive-comments BASHOPTS=checkwinsize BASH_ENV=/dev/null "$STS" run unit) >/dev/null 2>&1
check "KEY r3g the suite sees no ENV/SHELLOPTS/BASHOPTS, and BASH_ENV as set" 0 "$?"
fi

if sec r3-rails; then
echo "--- r3 h: an explicit final answer without a Status is rejected (no fallback to an older transcript status)"
R=$(mkc r3h); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit
TP="$TMP/r3h-transcript.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:"Status: pass\nold verdict"}}]}}' > "$TP"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p,last_assistant_message:"I ran out of time"}')"
check "KEY r3h explicit unparsable answer + an older Status in the transcript -> rejected" rejected "$(lastrec "$R" te | jq -r .status)"
sleep 1   # receipts have second resolution: keep the twin's t_end strictly later (L1)
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p}')"
check "r3h twin: no last_assistant_message at all (handback mode) -> the transcript is used" pass "$(lastrec "$R" te | jq -r .status)"
fi

if sec r3-claims; then
echo "--- r3 i: unstaged file NOT in the commit, claimed by another live instance -> warning; otherwise deny"
export CLAUDE_SUBTEAMS_COORD_HOME="$TMP/coord"
R=$(mkc r3i); addl "$R/src/lib/x.ts" 3 mine; stage "$R"
addl "$R/src/lib/y.ts" 4 peer                                       # another instance's unfinished edit (unstaged)
te_check "$R"; full "$R"
CD=$( . "$LIB"; tc__coord_dir "$R"); mkdir -p "$CD"
check "r3i coord dir = the one coord.sh uses" "$CD" "$(cd "$R" && CLAUDE_SUBTEAMS_MULTI_INSTANCE=1 bash "$DIR/scripts/coord.sh" repokey 2>/dev/null | sed 's/^[^(]*(\(.*\))$/\1/')"
coord_set() { # <owner> <pid> <trusted>
  jq -nc --arg w "$R" --argjson p "$2" --argjson t "$3" --argjson now "$(date +%s)" '{peer1:{pid:$p,pid_trusted:$t,worktree:$w,heartbeat:$now}, sTESTGAT:{pid:$p,pid_trusted:$t,worktree:$w,heartbeat:$now}}' > "$CD/instances.json"
  jq -nc --arg o "$1" '{"src/lib/y.ts":{by:$o,at:1}}' > "$CD/claims.json"
}
rm -f "$CD/claims.json"; tg "$R" 'git commit -m x'
check "KEY r3i unclaimed: deny names the file, says add/revert, no stash advice" "2:1:1:0" \
  "$RC:$(has 'src/lib/y.ts has changes that are not in this commit' "$ERR"):$(has 'add it to this commit, or revert/finish that edit, then re-run' "$ERR"):$(has 'stash' "$ERR")"
CLAUDE_SUBTEAMS_MULTI_INSTANCE=1 tg "$R" 'git commit -m x'; check "r3i with multi-instance on, the deny adds the claim hint" 1 "$(has 'have it claim the file' "$ERR")"
coord_set peer1 $$ true; tg "$R" 'git commit -m x'
check "KEY r3i claimed by another LIVE instance -> allow + warning naming file and instance" "0:1" \
  "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'suite ran with src/lib/y.ts modified by instance peer1; not part of this commit')"
sts "$R" status; check "KEY r3i status gives the same verdict (ok)" true "$(jq -r .ok "$TMP/sout")"
coord_set sTESTGAT $$ true; tg "$R" 'git commit -m x'; check "r3i claimed by THIS instance -> deny" 2 "$RC"
coord_set peer1 999999 true; tg "$R" 'git commit -m x'; check "KEY r3i claimed by a DEAD instance -> deny" 2 "$RC"
sts "$R" status; check "r3i status agrees (missing)" false "$(jq -r .ok "$TMP/sout")"
coord_set peer1 $$ true; printf 'not json' > "$CD/claims.json"; tg "$R" 'git commit -m x'
check "KEY r3i unreadable coord state -> deny (fail-closed)" 2 "$RC"
coord_set peer1 $$ true; jq -nc '{"src/lib/x.ts":{by:"peer1",at:1}}' > "$CD/claims.json"; tg "$R" 'git commit -m x'
check "r3i a claim on a file that IS in the commit does not help -> deny" 2 "$RC"
unset CLAUDE_SUBTEAMS_COORD_HOME
echo "--- r3 i: dirty receipts name the paths; untracked files a suite writes do not make it dirty"
R=$(mkc r3dirty '{"suites":[{"name":"unit","cmd":"echo log > run.log; echo z >> src/lib/y.ts","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" run unit; git -C "$R" checkout -q -- src/lib/y.ts
tg "$R" 'git commit -m x'; check "KEY r3i dirty deny names src/lib/y.ts + .gitignore hint" "2:1:1" "$RC:$(has 'src/lib/y.ts' "$ERR"):$(has '.gitignore' "$ERR")"
R=$(mkc r3clean '{"suites":[{"name":"unit","cmd":"echo log > run.log","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":[],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" run unit
check "KEY r3i a suite that only writes an untracked log: receipt not dirty" false "$(lastrec "$R" suite | jq -r .dirty)"
tg "$R" 'git commit -m x'; check "r3i ... and it counts" 0 "$RC"
fi

if sec r3-discover; then
echo "--- r3 j: discovery cache; build detection is a case-insensitive word"
R=$(mkrepo r3j); printf '{"scripts":{"test":"vitest","test:e2e":"BUILD=1 vite BUILD && pw","test:int":"esbuild-runner x"}}' > "$R/package.json"; git -C "$R" add -A; git -C "$R" commit -q -m p
sts "$R"; check "KEY r3j 'BUILD' (any case, a word) is a build; 'esbuild-runner' is not" "command runs a build:not the default" \
  "$(jq -r '.recommend.suggest[] | select(.name=="test:e2e") | .reason' "$TMP/sout"):$(jq -r '.recommend.suggest[] | select(.name=="test:int") | .reason' "$TMP/sout" | cut -c1-15)"
check "r3j a cache entry was written for this HEAD" 1 "$(find "$XDG_CACHE_HOME/claude-subteams/discovery" -name '*.json' -newer "$R/package.json" | wc -l | tr -d ' ' | awk '{print ($1 >= 1)}')"
sts "$R"; A1=$(jq -c .suites "$TMP/sout")
printf '{"scripts":{"test":"vitest","test:new":"x"}}' > "$R/package.json"; sts "$R"
check "KEY r3j a modified package.json bypasses the cache (no stale suites)" '["test","test:new"]' "$(jq -c '[.suites[].name]' "$TMP/sout")"
git -C "$R" checkout -q -- package.json; sts "$R"; check "r3j back to HEAD: the cached result is the same as discovery" "$A1" "$(jq -c .suites "$TMP/sout")"
fi

if sec r4; then
echo "--- r4 5: forged in-progress markers do not switch the gate to warnings; a real rebase still does"
R=$(mkc r4m); addl "$R/src/lib/x.ts" 20 c; stage "$R"; GD=$(git -C "$R" rev-parse --absolute-git-dir)
git -C "$R" rev-parse HEAD > "$GD/REVERT_HEAD"; tg "$R" 'git commit -m x'
check "KEY r4 forged REVERT_HEAD (= HEAD, reachable) -> deny" 2 "$RC"; rm -f "$GD/REVERT_HEAD"
mkdir -p "$GD/rebase-merge"; git -C "$R" rev-parse HEAD > "$GD/rebase-merge/onto"; tg "$R" 'git commit -m x'
check "KEY r4 forged rebase-merge/onto with HEAD attached -> deny" 2 "$RC"; rm -rf "$GD/rebase-merge"
mkdir -p "$GD/rebase-apply"; git -C "$R" rev-parse HEAD > "$GD/rebase-apply/onto"; tg "$R" 'git commit -m x'
check "r4 forged rebase-apply/onto -> deny" 2 "$RC"; rm -rf "$GD/rebase-apply"
R=$(mkc r4rb); git -C "$R" checkout -q -b topic; echo 'topic' > "$R/src/lib/x.ts"; git -C "$R" commit -q -am topic
git -C "$R" checkout -q main; echo 'main' > "$R/src/lib/x.ts"; git -C "$R" commit -q -am main
git -C "$R" checkout -q topic; git -C "$R" rebase -q main >/dev/null 2>&1
echo 'resolved' > "$R/src/lib/x.ts"; git -C "$R" add src/lib/x.ts
tg "$R" 'git commit -m x'; check "r4 a REAL rebase stopped on a conflict -> warning only (not over-tightened)" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'rebase in progress')"
git -C "$R" rebase --abort >/dev/null 2>&1

echo "--- r4 10 / M1: dirty receipts and claims; a dirty run is no test-engineer evidence"
export CLAUDE_SUBTEAMS_COORD_HOME="$TMP/coord4"
R=$(mkc r4d '{"suites":[{"name":"unit","cmd":"echo z >> docs/SYSTEM.md","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**"]}')
mkdir -p "$R/docs"; echo s > "$R/docs/SYSTEM.md"; git -C "$R" add -A; git -C "$R" commit -q -m sys
addl "$R/src/lib/x.ts" 3 a; stage "$R"; sts "$R" run unit; git -C "$R" checkout -q -- docs/SYSTEM.md
check "r4 the run that changed a tracked file is dirty, path recorded" "true:docs/SYSTEM.md" "$(lastrec "$R" suite | jq -r '"\(.dirty):\(.dirty_paths[0])"')"
tg "$R" 'git commit -m x'; check "KEY r4 unclaimed: dirty -> deny naming the path" "2:1" "$RC:$(has 'docs/SYSTEM.md' "$ERR")"
CD=$( . "$LIB"; tc__coord_dir "$R"); mkdir -p "$CD"
jq -nc --arg w "$R" --argjson p $$ --argjson now "$(date +%s)" '{peer1:{pid:$p,pid_trusted:true,worktree:$w,heartbeat:$now}}' > "$CD/instances.json"
jq -nc '{"docs/SYSTEM.md":{by:"peer1",at:1}}' > "$CD/claims.json"
tg "$R" 'git commit -m x'
check "KEY r4 10 claimed by another live instance, not in the commit -> not dirty, allow + warning" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'ran while docs/SYSTEM.md changed')"
sts "$R" status; check "r4 10 status agrees" true "$(jq -r .ok "$TMP/sout")"
jq -nc --arg w "$R" --argjson now "$(date +%s)" '{peer1:{pid:999999,pid_trusted:true,worktree:$w,heartbeat:$now}}' > "$CD/instances.json"
tg "$R" 'git commit -m x'; check "r4 10 claimed by a DEAD instance -> deny" 2 "$RC"
unset CLAUDE_SUBTEAMS_COORD_HOME
R=$(mkc r4m1 '{"suites":[{"name":"unit","cmd":"echo z >> src/lib/y.ts","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**"]}')
addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit; git -C "$R" checkout -q -- src/lib/y.ts
ag_stop "$R" claude-subteams:test-engineer "te$AGN" "Status: pass"
sts "$R" status; check "KEY r4 M1 a dirty suite run is not test-engineer evidence" 1 "$(jq -r '.missing[]' "$TMP/sout" | grep -c 'test-engineer pass without a suite run')"

echo "--- r4 11: subteams-tests run <suite> --root DIR"
R=$(mkc r4r); addl "$R/src/lib/x.ts" 2 a; stage "$R"
(cd "$TMP" && "$STS" run unit --root "$R") >/dev/null 2>&1; check "KEY r4 run unit --root DIR (after the suite) works" 0 "$?"
(cd "$TMP" && "$STS" run --root="$R" unit) >/dev/null 2>&1; check "r4 run --root=DIR unit works" 0 "$?"
(cd "$R" && "$STS" run unit --diff HEAD) >/dev/null 2>&1; check "r4 other extra arguments are still refused (64)" 64 "$?"

echo "--- r4 H8: review gate reads --pathspec-from-file with --pathspec-file-nul"
R=$(mkrepo r4h8); echo 'more' >> "$R/doc.md"; git -C "$R" add doc.md; echo 'z' >> "$R/a.ts"
printf 'doc.md\0a.ts\0' > "$TMP/r4-pf0"; printf 'doc.md\0' > "$TMP/r4-pf0doc"
gate "$R" sNOMARK8 "git commit --pathspec-from-file=$TMP/r4-pf0 --pathspec-file-nul -m x"
check "KEY r4 H8 NUL list naming code -> review deny" "2:1" "$RC:$(has 'code-reviewer' "$ERR")"
gate "$R" sNOMARK8 "git commit --pathspec-file-nul --pathspec-from-file $TMP/r4-pf0doc -m x"; check "r4 H8 NUL list naming only a doc -> allow" 0 "$RC"

echo "--- r4 M3: handback mode — only the FINAL assistant output carries the status"
R=$(mkc r4m3); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit
TP="$TMP/r4m3.jsonl"
{ jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Status: pass\nall good"}]}}'
  jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:"done"}}]}}'; } > "$TP"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p}')"
check "KEY r4 M3 earlier 'Status: pass' text, final handback 'done' -> rejected" rejected "$(lastrec "$R" te | jq -r .status)"

echo "--- r4 L2 / L3 / L4"
R=$(mkc r4l2); D=$( . "$LIB"; tc_receipt_dir "$R"); mkdir -p "$D"
for i in $(seq 1 205); do printf '{"type":"shot","kind":"shot","path":"/s","size":1,"session":"t","ts":%s}\n' "$i" > "$D/shot-$(printf '%010d' "$i")-1-$i.json"; done
printf '{"type":"shot","kind":"shot","path":"/s","size":1,"session":"t","ts":%s}\n' 9000000000 > "$D/9000000000-shot-1-1.json"
check "KEY r4 L2 the newest receipt by parsed time survives the cap (legacy names mixed in)" 1 "$( (. "$LIB"; tc_receipts_load "$R") | jq -s 'map(.ts) | index(9000000000) != null' | grep -c true)"
mkdir -p "$TMP/slowgit2" "$TMP/r4tmp"
printf '#!/bin/bash\ncase "$*" in *diff-tree*--stdin*) : > %s/r4-in-dt; sleep 2 ;; esac\nexec %s "$@"\n' "$TMP" "$(command -v git)" > "$TMP/slowgit2/git"; chmod +x "$TMP/slowgit2/git"; rm -f "$TMP/r4-in-dt"
R=$(mkc r4l3); addl "$R/src/lib/x.ts" 2 a; stage "$R"; sts "$R" run unit; addl "$R/src/lib/x.ts" 1 b; stage "$R"
( cd "$R" && bash_json "$TSID" 'git commit -m x' | PATH="$TMP/slowgit2:$PATH" TMPDIR="$TMP/r4tmp" bash "$HOOKS/pre-commit-gate" >/dev/null 2>&1 ) & GP=$!
for _w in $(seq 1 100); do [ -e "$TMP/r4-in-dt" ] && break; sleep 0.1; done
check "r4 L3 the gate is inside the batched diff-tree (suite check)" 1 "$([ -e "$TMP/r4-in-dt" ] && echo 1)"
kill -TERM "$(pgrep -P "$GP" bash | head -1)" 2>/dev/null; wait "$GP" 2>/dev/null; sleep 0.3
check "KEY r4 L3 killed inside the suite check: no tc-* temp dir left (tc-sc lives in the trapped work dir)" 0 "$(find "$TMP/r4tmp" -mindepth 1 -maxdepth 2 -name 'tc-*' 2>/dev/null | wc -l | tr -d ' ')"
R=$(mkrepo r4l4); printf '{"scripts":{"test":"vitest","pretest":"npm run build"}}' > "$R/package.json"; git -C "$R" add -A; git -C "$R" commit -q -m p
sts "$R"; check "KEY r4 L4 a pretest that builds makes the default test script non-auto" "opt-in:[]" "$(jq -r '.suites[0].run' "$TMP/sout"):$(jq -c '.recommend.run' "$TMP/sout")"
fi

if sec r5; then
echo "--- r5 3 / G4: real revert and real rebase-from-detached-HEAD conflicts are in-progress operations"
R=$(mkc r5rv); printf 'v1\n' > "$R/src/lib/x.ts"; git -C "$R" commit -q -am v1; V1=$(git -C "$R" rev-parse HEAD)
printf 'v2\n' > "$R/src/lib/x.ts"; git -C "$R" commit -q -am v2
git -C "$R" revert --no-edit "$V1" >/dev/null 2>&1
check "r5 the revert really stopped on a conflict (REVERT_HEAD = v1)" "$V1" "$(cat "$(git -C "$R" rev-parse --absolute-git-dir)/REVERT_HEAD" 2>/dev/null)"
printf 'resolved\n' > "$R/src/lib/x.ts"; git -C "$R" add src/lib/x.ts
tg "$R" 'git commit -m revert'
check "KEY r5 3 a REAL conflicted revert (REVERT_HEAD = an ancestor, != HEAD) -> warning only" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'revert in progress')"
git -C "$R" revert --abort >/dev/null 2>&1
R=$(mkc r5rb); git -C "$R" checkout -q -b topic; echo 'topic' > "$R/src/lib/x.ts"; git -C "$R" commit -q -am topic
git -C "$R" checkout -q main; echo 'main' > "$R/src/lib/x.ts"; git -C "$R" commit -q -am main
git -C "$R" checkout -q --detach topic; git -C "$R" rebase -q main >/dev/null 2>&1
check "r5 the rebase from a detached HEAD wrote head-name 'detached HEAD'" "detached HEAD" "$(cat "$(git -C "$R" rev-parse --absolute-git-dir)/rebase-merge/head-name" 2>/dev/null)"
echo 'resolved' > "$R/src/lib/x.ts"; git -C "$R" add src/lib/x.ts
tg "$R" 'git commit -m x'; check "KEY r5 G4 a REAL rebase started on a detached HEAD -> warning only" "0:1" "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'rebase in progress')"
git -C "$R" rebase --abort >/dev/null 2>&1

echo "--- r5 9: the REVIEW gate sees a commit behind a coord.sh / wrapper read from a variable (silent in 1.49.0)"
R=$(mkrepo r5rv9); echo 'export const b = 2;' >> "$R/a.ts"; git -C "$R" add a.ts
for c in "C=$DIR/scripts/coord.sh; bash \$C commit-lock -- git commit -m x" "C=$DIR/scripts/coord.sh; \$C commit-lock -- git commit -m x" "W=flock; \$W $TMP/r5l9 git commit -m x"; do
  gate "$R" sNOREV9 "$c"
  check "KEY r5 9 no contract, code staged, no review: '$c' -> review deny" "2:1" "$RC:$(has 'no code-reviewer subagent has finished' "$ERR")"
done
gate "$R" sNOREV9 'echo "Next: git add -A && git commit -m done"'; check "r5 9 twin: quoted prose in the same repo -> 0" 0 "$RC"
P=$(mkrepo r5rv9p); echo 'export const b = 2;' >> "$P/a.ts"; echo more >> "$P/doc.md"     # both UNSTAGED
gate "$P" sNOREV9 "C=$DIR/scripts/coord.sh; bash \$C commit-lock -- git commit -m x -- a.ts"
check "KEY r5 9 the wrapped commit's own pathspec (unstaged code) -> review deny" "2:1" "$RC:$(has 'no code-reviewer subagent has finished' "$ERR")"
gate "$P" sNOREV9 "C=$DIR/scripts/coord.sh; bash \$C commit-lock -- git commit -m x -- doc.md"; check "r5 9 twin: its pathspec names only the doc -> 0" 0 "$RC"
D=$(mkrepo r5rv9d); echo more >> "$D/doc.md"; git -C "$D" add doc.md
gate "$D" sNOREV9 "C=$DIR/scripts/coord.sh; bash \$C commit-lock -- git commit -m x"; check "r5 9 twin: docs-only staged -> 0" 0 "$RC"

echo "--- r5 8 (E12): no contract + a commit line the gate cannot model -> still a warning (working tree)"
R=$(mkrepo r5e12); printf '{"scripts":{"test":"true"}}' > "$R/package.json"; git -C "$R" add -A; git -C "$R" commit -q -m p
echo 'body{color:red}' > "$R/style.css"; git -C "$R" add style.css; git -C "$R" commit -q -m css; echo 'a{}' >> "$R/style.css"
tg "$R" 'npm test 2>&1 | grep -E "^# (pass|fail)" && git add style.css && git commit -q -m x && git log --oneline -1'
check "KEY r5 8 unmodelled line, nothing staged: rc 0 + warning with 'Commit line not modelled — checked the working tree'" "0:1" \
  "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage 2>/dev/null | grep -c 'Commit line not modelled — checked the working tree instead')"
tg "$R" 'git add style.css && git commit -m x'
check "r5 8 twin: the modellable form warns WITHOUT the 'not modelled' note" "0:1:0" \
  "$RC:$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'no test contract'):$(printf '%s' "$OUT" | jq -r .systemMessage | grep -c 'not modelled')"

echo "--- r5 7: the partial-commit deny names a STAGED file accurately"
R=$(mkc r5w); addl "$R/src/lib/x.ts" 2 a; addl "$R/src/lib/y.ts" 2 b; stage "$R"; sts "$R" run unit
tg "$R" 'git commit -m x -- src/lib/x.ts'
check "KEY r5 7 a staged file left out of a partial commit: 'changes that are not in this commit (staged or unstaged)'" "2:1:0" \
  "$RC:$(has 'src/lib/y.ts has changes that are not in this commit (staged or unstaged)' "$ERR"):$(has 'has unstaged changes' "$ERR")"

echo "--- r5 G2: the final turn's own text counts when its handback has no status; never 'first line: H'"
R=$(mkc r5g2); addl "$R/src/lib/x.ts" 20 c; stage "$R"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:test-engineer "te$AGN"; sts "$R" run unit
TP="$TMP/r5g2.jsonl"
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:"Status: pass\nall good"},{type:"tool_use",name:"SubagentHandback",input:{message:"done"}}]}}' > "$TP"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p}')"
check "KEY r5 G2 one final turn: text 'Status: pass' + handback 'done' -> pass" pass "$(lastrec "$R" te | jq -r .status)"
sleep 1
jq -nc '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",name:"SubagentHandback",input:{message:""}}]}}' > "$TP"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "te$AGN" --arg p "$TP" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:test-engineer",agent_transcript_path:$p}')"
check "KEY r5 G2 an empty final handback -> rejected 'empty or missing final answer', not 'first line: H'" "rejected:1:0" \
  "$(lastrec "$R" te | jq -r .status):$(lastrec "$R" te | jq -r .reason | grep -c 'empty or missing'):$(lastrec "$R" te | jq -r .reason | grep -c 'first line: H')"
fi

if sec corpus; then
echo "--- corpus: commit-line shapes under a contract (all-receipts-green baseline)"
# Baseline CB: contract repo, every change staged and checked (te + unit). must-ALLOW
# forms run against it and must pass. must-DENY forms sneak an UNVERIFIED change into
# the commit: the gate must deny, and the form is EXECUTED for real in a copy of CB
# to prove the committed tree differs from the checked one ("sneaks"), or does not
# ("same", the form is denied for its shape), or races ("race": background / <( )).
# Templates: @R@ = the repo (CB for the gate, the copy for the real run), @N@ = a repo
# without a contract.
CB=$(mkc corpus '{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":["src/lib/**"],"test_globs":["tests/**"]}')
mkdir -p "$CB/docs"; printf 'n\n' > "$CB/docs/release notes.md"; printf 'n\n' > "$CB/docs/notes[1].md"
awk 'BEGIN{for(i=1;i<=20;i++) print "s " i}' > "$CB/src/lib/a b.ts"
mkdir -p "$CB/src/app/[id]"; printf 'export default 1\n' > "$CB/src/app/[id]/page.tsx"
git -C "$CB" add -A; git -C "$CB" commit -q -m second
printf 'export const p = 2\n' >> "$CB/src/app/[id]/page.tsx"
addl "$CB/src/lib/x.ts" 3 base; addl "$CB/src/lib/a b.ts" 2 base
echo more >> "$CB/docs/release notes.md"; echo more >> "$CB/docs/notes[1].md"
stage "$CB"; te_check "$CB"; sts "$CB" run unit
CB_TREE=$(git -C "$CB" write-tree); CB_HEAD=$(git -C "$CB" rev-parse HEAD)
NC=$(mkrepo corpus-nc)
# CA: the same kind of repo with a clean index (message-only amend cases)
CA=$(mkc corpus-a); addl "$CA/src/lib/x.ts" 3 a; stage "$CA"; te_check "$CA"; sts "$CA" run unit; git -C "$CA" commit -q -m checked
cx() { local c="${1//@R@/$2}"; printf '%s' "${c//@N@/$NC}"; }   # template -> command
corpus_allow() { # <repo> <label> <command template>
  tg "$1" "$(cx "$3" "$1")"
  check "corpus ALLOW $2" 0 "$RC"
  [ "$RC" = 0 ] || printf '     deny text: %s\n' "$(printf '%s' "$ERR" | head -2 | tr '\n' ' ' | cut -c1-220)"
}
corpus_deny() { # <label> <setup: none|unstaged|unstaged-app|staged-evil> <proof: sneaks|same|race> <command template>
  local cp="$TMP/corpus-run" got
  case "$2" in
    unstaged) echo 'evil-unstaged' >> "$CB/src/lib/x.ts" ;;
    unstaged-app) echo 'evil-unstaged' >> "$CB/src/app/[id]/page.tsx" ;;
    staged-evil) echo 'evil' > "$CB/src/lib/evil.ts"; git -C "$CB" add src/lib/evil.ts ;;
  esac
  tg "$CB" "$(cx "$4" "$CB")"
  check "corpus DENY $1" 2 "$RC"
  rm -rf "$cp"; cp -R "$CB" "$cp"
  (cd "$cp" && timeout 20 bash -c "$(cx "$4" "$cp")" >/dev/null 2>&1 </dev/null); sleep 0.5
  if [ "$(git -C "$cp" rev-parse HEAD)" = "$CB_HEAD" ]; then got=no-commit
  elif [ "$(git -C "$cp" rev-parse 'HEAD^{tree}')" = "$CB_TREE" ]; then got=same
  else got=sneaks; fi
  if [ "$3" = race ]; then echo "INFO corpus DENY $1: real run -> $got (race)"
  else check "corpus DENY $1: real run proves '$3'" "$3" "$got"; fi
  case "$2" in
    unstaged) git -C "$CB" checkout -q -- src/lib/x.ts ;;
    unstaged-app) git -C "$CB" checkout -q -- 'src/app/[id]/page.tsx' ;;
    staged-evil) git -C "$CB" rm -q --cached -f src/lib/evil.ts ;;
  esac
  git -C "$CB" clean -qfd -- src >/dev/null 2>&1
  rm -rf "$cp"
}
HDQ() { printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\n%s\nEOF\n)"' "$1"; }
corpus_allow "$CB" 'plain -m'                         'git commit -m "plain message"'
corpus_allow "$CB" 'heredoc, even double quotes'      "$(HDQ 'fix: "quoted" thing')"
corpus_allow "$CB" 'heredoc, ODD double quote'        "$(HDQ 'fix: 5" screen')"
corpus_allow "$CB" "heredoc, apostrophes"             "$(HDQ "fix: don't break it")"
corpus_allow "$CB" 'heredoc, backticks'               "$(HDQ 'docs: use `foo` here')"
corpus_allow "$CB" 'heredoc, <email>'                 "$(HDQ 'fix: x

Co-Authored-By: X Y <x@y.z>')"
corpus_allow "$CB" 'heredoc, $(…) text in the body'   "$(HDQ 'docs: explain $(literal) usage')"
corpus_allow "$CB" '$(cat<<EOF without a space'       "$(printf 'git commit -m "$(cat<<'"'"'EOF'"'"'\nmsg\nEOF\n)"')"
corpus_allow "$CB" '-F - <<EOF (quoted delimiter)'    "$(printf 'git commit -F - <<'"'"'EOF'"'"'\nmsg "x" `y` $(z)\nEOF')"
corpus_allow "$CB" "single-quoted -m with backticks"  "git commit -m 'use \`foo\` here'"
corpus_allow "$CB" 'single-quoted -m with $( )'       "git commit -m 'cost \$(5)'"
corpus_allow "$CB" 'git add <paths> && commit'        'git add src/lib/x.ts "src/lib/a b.ts" && git commit -m x'
corpus_allow "$CB" 'git add -A && commit'             'git add -A && git commit -m x'
corpus_allow "$CB" '-am'                              'git commit -am x'
corpus_allow "$CB" 'path with a space (commit --)'    'git commit -m x -- "docs/release notes.md"'
corpus_allow "$CB" 'git add "a b.ts" && commit'       'git add "src/lib/a b.ts" && git commit -m x'
corpus_allow "$CB" 'cd /abs &&'                       'cd @R@ && git commit -m x'
corpus_allow "$CB" 'cd -P /abs &&'                    'cd -P @R@ && git commit -m x'
corpus_allow "$CB" 'git -C /abs'                      'git -C @R@ commit -m x'
corpus_allow "$CB" 'git -C/abs (attached)'            'git -C@R@ commit -m x'
corpus_allow "$CB" 'cd "$(git rev-parse --show-toplevel)"' 'cd "$(git rev-parse --show-toplevel)" && git commit -m x'
corpus_allow "$CB" 'cd $(git rev-parse --show-toplevel) unquoted' 'cd $(git rev-parse --show-toplevel) && git commit -m x'
corpus_allow "$CB" 'coord.sh commit-lock --'          'coord.sh commit-lock -- git commit -m x'
corpus_allow "$CB" '"$CLAUDE_PLUGIN_ROOT/scripts/coord.sh" commit-lock --' '"$CLAUDE_PLUGIN_ROOT/scripts/coord.sh" commit-lock -- git commit -m x'
corpus_allow "$CB" 'bash scripts/coord.sh commit-lock --' 'bash scripts/coord.sh commit-lock -- git commit -m x'
corpus_allow "$CB" 'subteams-tests status && commit'  'subteams-tests status && git commit -m x'
corpus_allow "$CB" 'git stash list; commit'           'git stash list; git commit -m x'
corpus_allow "$CB" 'git stash show && commit'         'git stash show && git commit -m x'
corpus_allow "$CB" 'git branch && commit'             'git branch && git commit -m x'
corpus_allow "$CB" 'git branch --show-current && commit' 'git branch --show-current && git commit -m x'
corpus_allow "$CB" 'git remote -v && commit'          'git remote -v && git commit -m x'
corpus_allow "$CB" 'git config --get && commit'       'git config --get user.name && git commit -m x'
corpus_allow "$CB" 'commit 2>&1 | tail -5'            'git commit -m x 2>&1 | tail -5'
corpus_allow "$CB" 'commit && git push'               'git commit -m x && git push'
corpus_allow "$CB" 'commit && git log -1'             'git commit -m x && git log -1'
corpus_allow "$CB" 'git -c user.name=… commit'        'git -c user.name=Bot -c commit.gpgsign=false commit -m x'
corpus_allow "$CB" 'git -cuser.email=… (attached)'    'git -cuser.email=b@x commit -m x'
corpus_allow "$CB" ':(literal) path with glob chars'  "git commit -m x -- ':(literal)docs/notes[1].md'"
corpus_allow "$CB" '--literal-pathspecs + glob chars' 'git --literal-pathspecs commit -m x -- "docs/notes[1].md"'
corpus_allow "$CA" '--amend --no-edit (nothing staged)' 'git commit --amend --no-edit'
corpus_allow "$CA" '--amend -m reworded (message only)' 'git commit --amend -m reworded'

F=src/lib/x.ts
corpus_deny 'unquoted $( ) in commit args'         none sneaks "git commit -am \$(echo evil >> $F; echo m)"
corpus_deny 'unquoted backticks in commit args'    none sneaks "git commit -am \`echo evil >> $F; echo m\`"
corpus_deny '-F <( … )'                            none sneaks "git commit -a -F <(echo evil >> $F; echo m)"
corpus_deny 'unquoted heredoc, $( ) in the body'   none sneaks "$(printf 'git commit -a -F - <<EOF\n$(echo evil >> %s)msg\nEOF' "$F")"
corpus_deny 'unquoted heredoc, backticks in body'  none sneaks "$(printf 'git commit -a -F - <<EOF\n`echo evil >> %s`msg\nEOF' "$F")"
corpus_deny 'echo >& file && commit'               none sneaks "echo evil >& $F && git commit -am x"
corpus_deny 'echo >&file && commit'                none sneaks "echo evil >&$F && git commit -am x"
corpus_deny 'commit & echo (background)'           none race   "git commit -am x & echo evil >> $F"
corpus_deny ': <> f; commit'                       none same   ": <> $F; git commit -am x"
corpus_deny 'git -c core.fsmonitor=…'              none sneaks "git -c core.fsmonitor='echo evil >> $F; true' commit -am x"
corpus_deny 'GIT_CONFIG_COUNT/KEY/VALUE fsmonitor' none sneaks "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0='echo evil >> $F; true' git commit -am x"
corpus_deny "git com''mit (split quote)"            unstaged sneaks "git com''mit -am x"
corpus_deny 'git co\mmit (backslash)'              unstaged sneaks 'git co\mmit -am x'
corpus_deny "git \$'\\x63ommit' (ANSI-C)"           unstaged sneaks "git \$'\\x63ommit' -am x"
corpus_deny '(cd /no-contract) && commit'          unstaged sneaks '(cd @N@) && git commit -am x'
corpus_deny 'true || cd /no-contract; commit'      unstaged sneaks 'true || cd @N@; git commit -am x'
corpus_deny 'commit && commit --amend'             none same   'git commit -m a && git commit --amend -m b'
corpus_deny 'xargs git commit (path from stdin)'   unstaged sneaks "printf '%s\\n' $F | xargs git commit -m x"
corpus_deny 'commit < <( … )'                      none race   "git commit -a -m x < <(echo evil >> $F)"
printf '%s\n' "$F" > "$TMP/corpus-list"
corpus_deny 'xargs git commit < file (no pipe)'    unstaged sneaks "xargs git commit -m x < $TMP/corpus-list"
corpus_deny 'a pipe INTO the commit'               none same   'printf m | git commit -a -F -'

echo "--- corpus round 4"
# 1 (N1): commits the 1.49 tokenizer does not see are evaluated / denied
corpus_deny "git \$'\\x63ommit' -am 'fix commit hook'"  unstaged sneaks "git \$'\\x63ommit' -am 'fix commit hook'"
corpus_deny 'git -C $(git rev-parse --show-toplevel) commit -am (unquoted, routed)' unstaged sneaks 'git -C $(git rev-parse --show-toplevel) commit -am x'
corpus_deny 'git -C `git rev-parse --show-toplevel` commit -am (routed)' unstaged sneaks 'git -C `git rev-parse --show-toplevel` commit -am x'
corpus_deny 'git ${X:-commit} -am x'                 unstaged sneaks 'git ${X:-commit} -am x'
corpus_deny 'C=commit; git $C -am x'                 unstaged sneaks 'C=commit; git $C -am x'
corpus_allow "$CB" 'git -C $(git rev-parse --show-toplevel) commit -m x (unquoted, routed and evaluated)' 'git -C $(git rev-parse --show-toplevel) commit -m x'
# 2: conditional cd / shell control flow
corpus_deny 'false && cd /nc; git commit -am x'      unstaged sneaks 'false && cd @N@; git commit -am x'
corpus_deny '[ -d /nope ] && cd /nc; git commit'     unstaged sneaks '[ -d /nope ] && cd @N@; git commit -am x'
corpus_deny 'test -d /nope && cd /nc; git commit'    unstaged sneaks 'test -d /nope && cd @N@; git commit -am x'
corpus_deny 'false && pushd /nc; git commit'         unstaged sneaks 'false && pushd @N@; git commit -am x'
corpus_deny 'if false; then cd /nc; fi; git commit'  unstaged sneaks 'if false; then cd @N@; fi; git commit -am x'
corpus_allow "$CB" 'cd /abs && git add <path> && git commit (unconditional)' 'cd @R@ && git add src/lib/x.ts && git commit -m x'
# H1: a conditional add/rm must be chained to the commit with &&
corpus_deny 'git diff --cached --quiet && git rm --cached evil; git commit' staged-evil sneaks 'git diff --cached --quiet && git rm --cached -q src/lib/evil.ts; git commit -m x'
corpus_allow "$CB" 'git status && git add -A && git commit (conditional add chained to the commit)' 'git status && git add -A && git commit -m x'
# 3 / H2 / 4: env options and config-moving variables
corpus_deny "env -S 'GIT_INDEX_FILE=…' git commit"   none sneaks "env -S 'GIT_INDEX_FILE=.git/evil-index' git commit -m x"
corpus_deny 'env --chdir=/abs git commit -am x'      unstaged sneaks 'env --chdir=@R@ git commit -am x'
echo 'evil-unstaged' >> "$CB/src/lib/x.ts"
for c in "env --chdir=$CB git commit -am x" "env -C $CB git commit -am x" "env --chdir $CB git commit -am x"; do
  tg "$NC" "$c"; check "KEY r4 H2 from a cwd WITHOUT a contract, $c resolves to the contract repo -> deny" 2 "$RC"
done
git -C "$CB" checkout -q -- src/lib/x.ts
corpus_allow "$CB" 'env -u NAME / env NAME=value git commit' 'env -u FOO GIT_AUTHOR_NAME=bot git commit -m x'
corpus_deny 'HOME=… git commit (global config swap)' none same 'HOME=/tmp/elsewhere git commit -m x'
corpus_deny 'XDG_CONFIG_HOME=… git commit'           none same 'XDG_CONFIG_HOME=/tmp/elsewhere git commit -m x'
# H3 / H4 / H6 / H7
corpus_deny 'echo "$(…; git commit -am x)" (commit inside a quoted substitution)' none sneaks 'echo "$(echo evil >> src/lib/x.ts; git commit -am x)"'
corpus_deny '>file git commit -am x (prefix redirect)' none sneaks '>src/lib/x.ts git commit -am x'
corpus_deny '2>file git commit -am x'                none sneaks '2>src/lib/x.ts git commit -am x'
corpus_deny '$(printf git) commit -am x'             unstaged sneaks '$(printf git) commit -am x'
corpus_deny "\$'\\x67it' commit -am x"            unstaged sneaks "\$'\\x67it' commit -am x"
corpus_deny '"g"it commit -am x'                     unstaged sneaks '"g"it commit -am x'
corpus_deny 'g\it commit -am x'                     unstaged sneaks 'g\it commit -am x'
corpus_deny 'git commit | cat > file (consumer writes into the repo)' none race 'git commit -am x | cat > src/lib/x.ts'
corpus_deny 'git -C $(echo /abs) commit'             unstaged sneaks 'git -C $(echo @R@) commit -am x'
corpus_deny 'git -C ../$(basename /abs) commit'      unstaged sneaks 'git -C ../$(basename @R@) commit -am x'
# M2: pathspec-semantics variables
corpus_deny 'GIT_ICASE_PATHSPECS=1 git add … && commit' unstaged sneaks 'GIT_ICASE_PATHSPECS=1 git add SRC/LIB/X.TS && git commit -m x'
check "corpus M2 the deny names the environment override (not 'git would refuse')" 1 "$(tg "$CB" 'GIT_ICASE_PATHSPECS=1 git add SRC/LIB/X.TS && git commit -m x'; has 'GIT_INDEX_FILE / GIT_DIR' "$ERR")"
# M5: git rm -n removes nothing
corpus_allow "$CB" 'git rm -n <path> && git commit (dry run)' 'git rm -n -q src/lib/x.ts && git commit -m x'
# 7: quoted ">" is text, not a redirection
corpus_allow "$CB" "echo 'a -> b' && commit"          "echo 'a -> b' && git commit -m x"
corpus_allow "$CB" 'echo "staged: a -> b" && commit'  'echo "staged: a -> b" && git commit -m x'
corpus_allow "$CB" "printf 'x>y\\n' && commit"         "printf 'x>y\\n' && git commit -m x"
# 9: quoted glob characters in paths (code path, so the twins can go red)
corpus_allow "$CB" 'git add "src/app/[id]/page.tsx" && commit' 'git add "src/app/[id]/page.tsx" && git commit -m x'
corpus_allow "$CB" "git add ':(literal)src/app/[id]/page.tsx' && commit" "git add ':(literal)src/app/[id]/page.tsx' && git commit -m x"
corpus_allow "$CB" 'git --literal-pathspecs add "src/app/[id]/page.tsx" && commit' 'git --literal-pathspecs add "src/app/[id]/page.tsx" && git commit -m x'
corpus_deny 'git add "src/app/[id]/…" with an unchecked change' unstaged-app sneaks 'git add "src/app/[id]/page.tsx" && git commit -m x'
corpus_deny "git add ':(literal)src/app/[id]/…' unchecked" unstaged-app sneaks "git add ':(literal)src/app/[id]/page.tsx' && git commit -m x"
corpus_deny 'git --literal-pathspecs add "src/app/[id]/…" unchecked' unstaged-app sneaks 'git --literal-pathspecs add "src/app/[id]/page.tsx" && git commit -m x'
# commit -- <path>: a fixture where ONLY that code file changed (and was checked)
CP=$(mkc corpus-p '{"suites":[{"name":"unit","cmd":"true","paths":["src/**"]}],"ui_globs":["src/ui/**"],"code_globs":["src/**"],"test_globs":["tests/**"]}')
mkdir -p "$CP/src/app/[id]"; printf 'a\n' > "$CP/src/app/[id]/page.tsx"; git -C "$CP" add -A; git -C "$CP" commit -q -m p
printf 'b\n' >> "$CP/src/app/[id]/page.tsx"; stage "$CP"; te_check "$CP"; sts "$CP" run unit
for c in "git commit -m x -- ':(literal)src/app/[id]/page.tsx'" 'git --literal-pathspecs commit -m x -- "src/app/[id]/page.tsx"' 'git commit -m x -- "src/app/[id]/page.tsx"'; do
  tg "$CP" "$c"; check "corpus ALLOW commit -- code path with glob chars (checked): $c" 0 "$RC"
  echo 'evil-unstaged' >> "$CP/src/app/[id]/page.tsx"
  tg "$CP" "$c"; check "corpus DENY the same with an unchecked change (red twin): $c" 2 "$RC"
  rm -rf "$TMP/cp-run"; cp -R "$CP" "$TMP/cp-run"; (cd "$TMP/cp-run" && bash -c "$c" >/dev/null 2>&1)
  check "corpus DENY red twin: real run proves 'sneaks': $c" 1 "$([ "$(git -C "$TMP/cp-run" show 'HEAD:src/app/[id]/page.tsx' 2>/dev/null | grep -c evil-unstaged)" = 1 ] && echo 1)"
  git -C "$CP" checkout -q -- 'src/app/[id]/page.tsx'
done
# a sibling the glob [id] also matches (src/app/i/): literal forms must NOT pick it up
mkdir -p "$CP/src/app/i"; printf 'i\n' > "$CP/src/app/i/page.tsx"; git -C "$CP" add -A; git -C "$CP" commit -q -m i
printf 'c\n' >> "$CP/src/app/[id]/page.tsx"; git -C "$CP" add 'src/app/[id]/page.tsx'; te_check "$CP"; sts "$CP" run unit
echo 'unchecked' >> "$CP/src/app/i/page.tsx"
tg "$CP" 'git --literal-pathspecs commit -m x -- "src/app/[id]/page.tsx"'
check "KEY r4 --literal-pathspecs is replayed (the glob sibling with an unchecked change is NOT taken) -> allow" 0 "$RC"
tg "$CP" "git commit -m x -- ':(literal)src/app/[id]/page.tsx'"; check "r4 :(literal) the same -> allow" 0 "$RC"
tg "$CP" 'git commit -m x -- "src/app/[id]/page.tsx"'; check "r4 the plain quoted glob DOES take the sibling (git semantics) -> deny" 2 "$RC"
git -C "$CP" checkout -q -- src/app/i/page.tsx
corpus_deny 'git add src/app/*/page.tsx (unquoted glob)' unstaged-app sneaks 'git add src/app/*/page.tsx && git commit -m x'
# 8: a symlink OUTSIDE the repo pointing at a tracked file
ln -sfn "$CB/src/lib/x.ts" "$TMP/corpus-lnk"
tg "$CB" "echo evil >> $TMP/corpus-lnk && git commit -am x"; check "corpus DENY redirect into a symlink outside the repo that points at a tracked file" "2:1" "$RC:$(has 'inside the repository' "$ERR")"
CPL="$TMP/corpus-run-lnk"; rm -rf "$CPL"; cp -R "$CB" "$CPL"; ln -sfn "$CPL/src/lib/x.ts" "$TMP/corpus-lnk2"
(cd "$CPL" && bash -c "echo evil >> $TMP/corpus-lnk2 && git commit -qam x") >/dev/null 2>&1
check "corpus DENY symlink redirect: real run proves 'sneaks'" 1 "$([ "$(git -C "$CPL" rev-parse 'HEAD^{tree}')" != "$CB_TREE" ] && echo 1)"
rm -rf "$CPL"
# 6 / 12: suite runs with a changed environment, also through escapes; the deny text
tg "$CB" "PATH=/tmp/shim:\$PATH subteams-test\$'\\x73' run unit"
check "KEY r4 B17 on the normalized text: PATH=… subteams-test\$'\\x73' run -> deny, text says 'the user's call'" "2:1" "$RC:$(has "the user's call; report it, do not edit the contract" "$ERR")"

echo "--- corpus round 5"
# 1: quoted prose with a separator + git commit is not a command (normalized hit needs visible obfuscation)
corpus_allow "$CB" 'r5 echo "Next: git add -A && git commit -m done"' 'echo "Next: git add -A && git commit -m done"'
corpus_allow "$CB" 'r5 echo "then; git commit"'                      'echo "then; git commit"'
corpus_allow "$CB" "r5 printf 'Then: git add . && git commit' >> notes" "printf '%s\\n' 'Then: git add . && git commit' >> $TMP/notes.md"
corpus_allow "$CB" "r5 gh pr create --body 'run: git add -A && git commit'" "gh pr create --title t --body 'run: git add -A && git commit'"
corpus_allow "$CB" "r5 gh issue comment --body 'Repro: cd /repo; git commit -m x'" "gh issue comment 5 --body 'Repro: cd /repo; git commit -m x'"
corpus_allow "$CB" "r5 git log --oneline --grep='; git commit'"      "git log --oneline --grep='; git commit'"
corpus_allow "$CB" "r5 tmux send-keys -t w 'git add -A && git commit -m y' Enter" "tmux send-keys -t w 'git add -A && git commit -m y' Enter"
corpus_allow "$CB" "r5 ssh host 'cd /x && git commit -m y'"          "ssh host 'cd /x && git commit -m y'"
corpus_allow "$CB" "r5 docker exec c sh -c 'cd /app && git commit -m y'" "docker exec c sh -c 'cd /app && git commit -m y'"
corpus_allow "$CB" 'r5 B17 echo "tip: cd x && FOO=1 subteams-tests run unit"' 'echo "tip: cd x && FOO=1 subteams-tests run unit"'
# 2: --dry-run / -h / --help commit nothing
for c in 'git commit --dry-run' 'git commit -h' 'git commit --help' 'git status; git commit --dry-run' 'git commit --dry-run --short -a'; do
  corpus_allow "$CB" "r5 dry run: $c" "$c"
done
# 4: env -S / --split-string can hide the commit itself
corpus_deny "r5 env -S 'git commit -am x'"              unstaged sneaks "env -S 'git commit -am x'"
corpus_deny 'r5 env -S"git commit -am x"'               unstaged sneaks 'env -S"git commit -am x"'
corpus_deny "r5 env --split-string='git commit -am x'"  unstaged sneaks "env --split-string='git commit -am x'"
# 5: a conditional cd chained to the commit with && is safe (if it fails, the commit does not run)
corpus_allow "$CB" 'r5 git status && cd /abs && git commit'              'git status && cd @R@ && git commit -m x'
corpus_allow "$CB" 'r5 subteams-tests status && cd /abs && git commit'   'subteams-tests status && cd @R@ && git commit -m x'
corpus_allow "$CB" 'r5 git -C /abs status --short && cd /abs && git commit' 'git -C @R@ status --short && cd @R@ && git commit -m x'
# 6: a new branch at HEAD before the commit (checkout -b / switch -c|--create, nothing else)
corpus_allow "$CB" 'r5 git checkout -b docs/readme-typo && git add … && git commit' 'git checkout -b docs/readme-typo && git add src/lib/x.ts && git commit -m x'
corpus_allow "$CB" 'r5 git switch -c t1 && git commit'          'git switch -c t1 && git commit -m x'
corpus_allow "$CB" 'r5 git switch --create t2 && git commit'    'git switch --create t2 && git commit -m x'
for c in 'git checkout -b x HEAD~1 && git commit -m x' 'git checkout -B x && git commit -m x' 'git checkout --orphan x && git commit -m x' \
         'git checkout -b x -t && git commit -m x' 'git switch -c x HEAD~1 && git commit -m x' 'git checkout main && git commit -m x'; do
  tg "$CB" "$c"; check "corpus DENY r5 new-branch twin (start point / reset / orphan / track / switching): $c" 2 "$RC"
done
# G5: a `2>|` prefix redirect hid the whole commit from both scanners (91de048: rc 0 even unchecked)
corpus_deny 'r5 2>| file git commit -am x (prefix clobber redirect)' unstaged sneaks "2>| $TMP/r5f git commit -am x"
corpus_allow "$CB" 'r5 2>| file git commit (checked: evaluated, allowed)' "2>| $TMP/r5f git commit -m x"
corpus_allow "$CB" 'r5 git commit -m x 2>| file (suffix clobber: not a pipe)' "git commit -m x 2>| $TMP/r5f"
# G6: a redirect into a DANGLING symlink outside the repo is outside the repo
ln -sfn "$TMP/no/such/dir/file" "$TMP/r5-dangle"
corpus_allow "$CB" 'r5 echo > dangling symlink outside the repo && git commit' "echo x > $TMP/r5-dangle && git commit -m x"
ln -sfn "$CB/no/such/file" "$TMP/r5-dangle-in"
tg "$CB" "echo x > $TMP/r5-dangle-in && git commit -m x"; check "corpus DENY r5 twin: a dangling symlink pointing INTO the repo" 2 "$RC"
# G3: a commit inside a substitution (reported as passing; it never did — guarded now)
corpus_deny 'r5 G3 x=$(git commit -am y)'          unstaged sneaks 'x=$(git commit -qam y)'
corpus_deny 'r5 G3 echo $(git commit -am y)'       unstaged sneaks 'echo $(git commit -qam y)'
corpus_deny 'r5 G3 `git commit -am y`'             unstaged sneaks '`git commit -qam y`'
corpus_deny 'r5 G3 : "$(git commit -am y)"'        unstaged sneaks ': "$(git commit -qam y)"'
# 9: a git commit in the ARGUMENTS of a statement the gate does not model as a commit.
# One rule, both sides: an UNQUOTED `git … commit` -> routed when the wrapper resolves
# (a literal coord.sh / flock / timeout / nice / command, or a VAR=literal earlier in
# the line), else denied; a QUOTED one is an argument string (item 1 above) -> ignored.
R9CO="$DIR/scripts/coord.sh"
corpus_allow "$CB" 'r5 9 C=/abs/coord.sh; bash $C commit-lock -- git commit'   "C=$R9CO; bash \$C commit-lock -- git commit -m x"
corpus_allow "$CB" 'r5 9 C=/abs/coord.sh; bash "$C" commit-lock -- git commit' "C=$R9CO; bash \"\$C\" commit-lock -- git commit -m x"
corpus_allow "$CB" 'r5 9 C=/abs/coord.sh; $C commit-lock -- git commit'        "C=$R9CO; \$C commit-lock -- git commit -m x"
corpus_allow "$CB" 'r5 9 C=/abs/coord.sh; "$C" commit-lock -- git commit'      "C=$R9CO; \"\$C\" commit-lock -- git commit -m x"
corpus_allow "$CB" 'r5 9 W=flock; $W f git commit'                            "W=flock; \$W $TMP/r5lock git commit -m x"
for c in "flock $TMP/r5lock git commit -m x" 'timeout 60 git commit -m x' 'time git commit -m x' 'nice git commit -m x' 'command git commit -m x' 'exec git commit -m x'; do
  corpus_allow "$CB" "r5 9 known pass-through wrapper: $c" "$c"
done
corpus_allow "$CB" 'r5 9 unquoted words after echo are text: echo git commit -m x'   'echo git commit -m x'
corpus_allow "$CB" "r5 9 quoted: grep -rn 'git commit' docs"                          "grep -rn 'git commit' docs"
echo 'evil-unstaged' >> "$CB/src/lib/x.ts"     # (coord.sh needs a live coord dir to really run: rc only)
tg "$CB" "C=$R9CO; bash \$C commit-lock -- git commit -qam x"
check "corpus DENY r5 9 C=/abs/coord.sh; bash \$C commit-lock -- git commit -am (routed, unchecked change)" 2 "$RC"
git -C "$CB" checkout -q -- src/lib/x.ts
corpus_deny 'r5 9 W=flock; $W f git commit -am (routed, unchecked)'  unstaged sneaks "W=flock; \$W $TMP/r5lock git commit -qam x"
corpus_deny 'r5 9 find -exec git commit -am'                         unstaged sneaks 'find @R@ -maxdepth 0 -exec git -C @R@ commit -qam x \;'
printf '#!/bin/sh\nexec "$@"\n' > "$TMP/r5wrap.sh"; chmod +x "$TMP/r5wrap.sh"
corpus_deny 'r5 9 /abs/wrap.sh git commit -am'                       unstaged sneaks "$TMP/r5wrap.sh git commit -qam x"
corpus_deny 'r5 9 /abs/wrap.sh "git" "commit" -am (separately quoted words still run)' unstaged sneaks "$TMP/r5wrap.sh \"git\" 'commit' -qam x"
for c in 'watch git commit -m x' 'parallel git commit ::: a' './wrap.sh git -C . commit -m x'; do
  tg "$CB" "$c"; check "corpus DENY r5 9 unknown wrapper: $c" "2:1" "$RC:$(has 'as an argument of a command the gate cannot model' "$ERR")"
done
# a command word held in a variable that is git itself plus more words, or unknown
corpus_deny 'r5 9 G="git -C /abs"; $G commit -am'   unstaged sneaks 'G="git -C @R@"; $G commit -qam x'
corpus_deny 'r5 9 G="git commit"; $G -am'           unstaged sneaks 'G="git commit"; $G -qam x'
tg "$CB" '$G commit -am x'; check "corpus DENY r5 9 unknown \$G commit -am x" 2 "$RC"
corpus_allow "$CB" 'r5 9 twin: G=git; $G commit (one word, resolved and evaluated)' 'G=git; $G commit -m x'
corpus_allow "$CB" 'r5 9 twin: G="git -C /abs"; $G status (no commit)'           'G="git -C @R@"; $G status'
# G5's bypass half (91de048: `2>| f git commit` unseen, rc 0 even unchecked) is closed by
# the word rule; the false deny on a CHECKED tree is G5 proper (second hand-back)
corpus_deny 'r5 9 covers the G5 bypass: 2>| f git commit -am' unstaged sneaks "2>| $TMP/r5f9 git commit -qam x"
tg "$CB" "$TMP/r5wrap.sh git commit -m y; git commit -m x"
check "corpus DENY r5 9 a wrapped commit NEXT TO a plain one (enforced path names it)" "2:1" "$RC:$(has 'runs a git commit as an argument of a command the gate cannot model' "$ERR")"
tg "$CB" '$C commit-lock -- git commit -m x'
check "corpus DENY r5 9 unresolvable \$C commit-lock -> 'write coord.sh with a literal path'" "2:1" "$RC:$(has 'write coord.sh with a literal path' "$ERR")"
tg "$CB" "C=$R9CO; F=src/lib/x.ts; bash \$C commit-lock -- git commit -m x -- \$F"
check "corpus DENY r5 9 the exact E8 form (-- \$F): named, not silently mis-evaluated" "2:1" "$RC:$(has "commit pathspec '\$F' has dynamic characters" "$ERR")"

# target resolution from ANOTHER cwd (in CB the old parser passed these by accident)
echo 'evil-unstaged' >> "$CB/src/lib/x.ts"
tg "$NC" "cd -P $CB && git commit -am x"; check "corpus DENY cd -P /contract-repo from another cwd (resolved, unchecked -a content)" 2 "$RC"
tg "$NC" "git -C$CB commit -am x"; check "corpus DENY git -C/contract-repo (attached) from another cwd" 2 "$RC"
tg "$NC" "git -cuser.name=x -C$CB commit -am x"; check "corpus DENY git -cuser.name=x -C/abs (attached, both)" 2 "$RC"
git -C "$CB" checkout -q -- src/lib/x.ts
fi

if sec corpus-nc; then
echo "--- corpus: no-contract parity — the review gate answers like 1.49 (080fb12) on 20 forms"
mkdir -p "$TMP/old149/hooks"
git -C "$DIR" show 080fb12:hooks/pre-commit-gate > "$TMP/old149/hooks/pre-commit-gate"
git -C "$DIR" show 080fb12:hooks/lib-gitcmd.sh > "$TMP/old149/hooks/lib-gitcmd.sh"
PS=$(mkrepo par-staged); echo 'x' >> "$PS/a.ts"; git -C "$PS" add a.ts
PM=$(mkrepo par-md); echo 'x' >> "$PM/doc.md"; git -C "$PM" add doc.md; echo 'z' >> "$PM/a.ts"
par() { # <repo> <command> -> "old:new" rc of the two gates (no review marker)
  local j o n; j=$(bash_json sPARITY "$2")
  o=$( (cd "$1" && printf '%s' "$j" | bash "$TMP/old149/hooks/pre-commit-gate") >/dev/null 2>&1; echo $?)
  n=$( (cd "$1" && printf '%s' "$j" | bash "$HOOKS/pre-commit-gate") >/dev/null 2>&1; echo $?)
  printf '%s:%s' "$o" "$n"
}
for c in 'git commit -m x' 'git commit -am x' 'git add -A && git commit -m x' 'git commit a.ts -m x' 'cd . && git commit -m x' \
         'git -C . commit -m x' 'timeout 60 git commit -m x' 'bash -c "git commit -m x"' "$HD_MSG" 'git commit --dry-run' \
         'echo "a; git commit -m y"' 'git commit-tree HEAD^{tree} -m x' 'coord.sh commit-lock -- git commit -m x' \
         "$(printf 'git commit -F - <<EOF\nm\nEOF')" 'git commit -m "unterminated' "git com''mit -m x" 'git -c a=b commit -m x' \
         'env git commit -m x' 'if true; then git commit -m x; fi' 'git commit -m x 2>&1 | tail -3'; do
  v=$(par "$PS" "$c"); check "parity (code staged): ${c%%$'\n'*}" "${v%%:*}:${v%%:*}" "$v"
done
for c in 'git commit -m docs' 'git add doc.md && git commit -m docs' 'git commit doc.md -m docs' 'git add -A && git commit -m all' 'git commit -am all'; do
  v=$(par "$PM" "$c"); check "parity (doc staged, code dirty): $c" "${v%%:*}:${v%%:*}" "$v"
done
fi

if sec hooksjson; then
echo "--- hooks.json"
check "valid JSON" 1 "$(jq -e . "$HOOKS/hooks.json" >/dev/null 2>&1 && echo 1 || echo 0)"
check "all timeouts are seconds (<= 120)" 0 "$(jq '[.. | objects | select(has("timeout")) | .timeout | select(. > 120)] | length' "$HOOKS/hooks.json")"
check "SubagentStop registered for subagent-rails" 1 "$(jq '[.hooks.SubagentStop[]?.hooks[]? | select(.command|test("subagent-rails SubagentStop"))] | length' "$HOOKS/hooks.json")"
check "B7 subagent-rails Start/Stop timeouts are 20 s" "20:20" "$(jq -r '[.hooks.SubagentStart[].hooks[] | select(.command|test("subagent-rails"))][0].timeout' "$HOOKS/hooks.json"):$(jq -r '[.hooks.SubagentStop[].hooks[] | select(.command|test("subagent-rails"))][0].timeout' "$HOOKS/hooks.json")"
fi   # sec hooksjson

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILED"; fi
[ "$FAILS" -eq 0 ]
