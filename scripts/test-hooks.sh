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

mkrepo() { # <name> -> path; base commit with a.ts + doc.md
  local r="$TMP/$1"
  mkdir -p "$r" && git -C "$r" init -q -b main
  printf 'export const a = 1;\n' > "$r/a.ts"; printf '# doc\n' > "$r/doc.md"
  git -C "$r" add -A && git -C "$r" commit -q -m base
  echo "$r"
}

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
HD_MSG=$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: handle "foo bar" case\nEOF\n)"')
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

echo "--- test gate: forms that decide content at commit time (contract) -> deny"
tg "$RC1" 'git commit -am x'; check "commit -am with NO unstaged changes (same content as the index): allow" 0 "$RC"
tg "$RC1" "$HD_MSG"; check "heredoc message with quotes (garbage pathspecs in the parse): allow" 0 "$RC"
tg "$RC1" "$(printf 'git commit -m "$(cat <<'"'"'EOF'"'"'\nfix: "x" -a and -i src/lib/x.ts\n\nCo-Authored-By: X <x@y>\nEOF\n)"')"
check "heredoc message mentioning -a / -i and a real path: allow" 0 "$RC"
tg "$RC1" 'git commit -m "unterminated -a'; check "unreliable parse, raw '-a', clean worktree: allow" 0 "$RC"
echo 'unstaged' >> "$RC1/tests/t.test.ts"
for c in 'git commit -am x' 'git commit -a -m x' 'git add -A && git commit -m x' 'git add src && git commit -m x' \
         'git commit src/lib/x.ts -m x' 'git commit -i src/lib/x.ts -m x' 'git rm -q --cached tests/t.test.ts; git commit -m x' \
         'git stash && git commit -m x' 'git commit -m "unterminated -a' 'git add -A && git commit -m "unterminated'; do
  tg "$RC1" "$c"; check "deny: $c" "2:1" "$RC:$(has 'Stage separately' "$ERR")"
done
tg "$RC1" 'git status && git diff --cached --stat && git commit -m x'; check "read-only git before commit: allow" 0 "$RC"
tg "$RC1" 'git commit -m "msg with -a and -i in it"'; check "-a/-i inside the message: allow" 0 "$RC"
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
ui_check "$R" "" ; check "ui-tester with an empty result: no receipt" "$N0" "$(nrec "$R" ui)"
AGN=$((AGN+1)); ag_start "$R" claude-subteams:ui-tester "ui$AGN"
run_hook "$R" "subagent-rails SubagentStop" "$(jq -nc --arg a "ui$AGN" '{session_id:"sx",agent_id:$a,agent_type:"claude-subteams:ui-tester"}')"
check "ui-tester aborted (no message, no transcript): no receipt" "$N0" "$(nrec "$R" ui)"
ui_check "$R" "Some preamble
Status: pass"; check "Status not on the first non-empty line: no receipt" "$N0" "$(nrec "$R" ui)"
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

echo "--- hooks.json"
check "valid JSON" 1 "$(jq -e . "$HOOKS/hooks.json" >/dev/null 2>&1 && echo 1 || echo 0)"
check "all timeouts are seconds (<= 120)" 0 "$(jq '[.. | objects | select(has("timeout")) | .timeout | select(. > 120)] | length' "$HOOKS/hooks.json")"
check "SubagentStop registered for subagent-rails" 1 "$(jq '[.hooks.SubagentStop[]?.hooks[]? | select(.command|test("subagent-rails SubagentStop"))] | length' "$HOOKS/hooks.json")"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILED"; fi
[ "$FAILS" -eq 0 ]
