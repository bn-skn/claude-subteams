#!/usr/bin/env bash
# test-hooks.sh — регрессия хуков Claude Code плагина (hooks/*): гейт ревью перед коммитом,
# маркер ревью на SubagentStop, доставка причин блокировки/подсказок, таймауты hooks.json.
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
unset CLAUDE_SUBTEAMS_SKIP_REVIEW_GATE CLAUDE_SUBTEAMS_AUTONOMY CLAUDE_SUBTEAMS_MULTI_INSTANCE

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

echo "--- hooks.json"
check "valid JSON" 1 "$(jq -e . "$HOOKS/hooks.json" >/dev/null 2>&1 && echo 1 || echo 0)"
check "all timeouts are seconds (<= 120)" 0 "$(jq '[.. | objects | select(has("timeout")) | .timeout | select(. > 120)] | length' "$HOOKS/hooks.json")"
check "SubagentStop registered for subagent-rails" 1 "$(jq '[.hooks.SubagentStop[]?.hooks[]? | select(.command|test("subagent-rails SubagentStop"))] | length' "$HOOKS/hooks.json")"

echo
if [ "$FAILS" -eq 0 ]; then echo "ALL PASS"; else echo "$FAILS FAILED"; fi
[ "$FAILS" -eq 0 ]
