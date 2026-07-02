# IMPL-PLAN: Shell-layer hardening (v1.28.0)

**Status:** active
**Date:** 2026-07-02
**Branch:** `fix/shell-hardening-1.28.0`
**Origin:** health-audit of v1.27.0 (9 agents + Codex GPT-5.5). Codex returned 1 CRITICAL + 7 HIGH + 2 MEDIUM in the shell layer; the devil + analysts flagged two pre-existing hooks.

## Scope / contract

**In scope:** `scripts/coord.sh`, `scripts/autonomy-check.sh`, `scripts/check-plan.sh`, `hooks/autonomy-gate`, `hooks/pre-commit-gate`, `hooks/session-end-reminder`. Shell-only. No skill/agent prompt changes. No behavioral change to the *happy path* of any command — only failure-mode correctness (fail-closed where a safety gate currently fails open) and one hook enforcement-downgrade.

**Non-goals:** cutting skills; the interview/stack/spec feature; env-fingerprint autonomy (Tier 3); renaming files (breaks hooks.json wiring). The marketplace-publish cut-list is a separate operator decision, out of scope here.

**Acceptance criteria** (write-once):
- [x] AC1 — DONE — coord.sh: every `( flock 9 ... ) 9>"$LOCK"` subshell aborts with a non-zero, diagnosed failure if `flock` itself fails (no unlocked body).
- [x] AC2 — DONE — autonomy-check.sh single-writer check fails **closed** (exit 4) when it cannot determine peer state in multi-instance mode (coord.sh/jq missing, roster errors), instead of silently no-op'ing.
- [x] AC3 — DONE — autonomy-check.sh: git query failures in `$(...)` are detected and fail closed, never interpreted as "0 files / 0 lines".
- [x] AC4 — DONE — coord.sh `cmd_deregister` validates `--id` via `_valid_id` before touching the inbox path (path-traversal closed).
- [x] AC5 — DONE — coord.sh `_reap_locked` iterates jq keys without word-splitting/glob expansion (whitespace/glob-char keys handled).
- [x] AC6 — DONE — coord.sh `cmd_roster` reads `instances.json` under the lock in a single locked critical section (no post-release re-read window).
- [x] AC7 — DONE — coord.sh notify-due and send/recv synchronize on the **same** physical lock file for a given inbox (mutual exclusion actually holds).
- [x] AC8 — DONE — check-plan.sh: an oversized (>1MB) plan file is a FAILURE (non-zero exit), not a silent green — contract says "Exit 0 = every IMPL-PLAN valid".
- [x] AC9 — DONE — autonomy-gate Bash record-guard: REVISED after review — a read/write classifier was tried but cross-model review (Codex) showed it trivially bypassable (`cat; mv <record>`) and worse than deny-all, so it was reverted to **blanket-deny any Bash reference to the record** (reads go via the Read tool). See ADR-008.
- [x] AC10 — DONE — autonomy-gate pre-scan of `IMPL-PLAN-*.md` carries the same `MAX_RECORD_BYTES` DoS guard as the delegated script.
- [x] AC11 — DONE — pre-commit-gate: nvm is sourced ONLY inside the `git commit` branch; non-commit Bash calls early-exit before any nvm/tsc work (removes the ~190-220ms per-call tax).
- [x] AC12 — DONE — session-end-reminder: Case D and Case-C-breaking emit a reminder and `exit 0` (non-blocking); the `exit 2` coercion and the now-dead /tmp counter/HEAD machinery are removed. Escape hatch and soft reminders preserved. Header comment corrected to state Stop-per-turn semantics.
- [x] AC13 — DONE — adversarial tests cover the fail-closed paths (AC2, AC3, AC8) and the guard-read allowance (AC9); existing 142-test suite still green.
- [x] AC14 — DONE — hooks.json:35 unquoted `${CLAUDE_PLUGIN_ROOT}` command path: assessed. If the host-harness parsing makes safe quoting impossible, recorded as accepted-residual with rationale (paths under `~/.claude/plugins/` have no spaces); otherwise fixed.

## Rollup
| AC | Status |
|----|--------|
| AC1–AC14 | DONE — 55/55 adversarial suite green; reviewed by code-reviewer + devils-advocate + Codex cross-model; AC9 reverted to blanket-deny (ADR-008), AC14 accepted-residual |

## Risks & nuances
- **flock semantics (AC1):** must not deadlock or change happy-path behavior — flock on a fd that succeeds behaves exactly as before; only the failure branch is new. Watch for `flock -w` vs blocking: keep current blocking behavior, just check the return.
- **fail-closed (AC2/AC3):** risk of *over*-blocking — if git/coord legitimately returns empty (e.g. genuinely zero changes), must distinguish "command failed" from "command succeeded with empty output". Use explicit exit-code capture, not string-emptiness.
- **session-end downgrade (AC12):** removing enforcement is a deliberate posture change — the plugin's own Step 10 doc-discipline now rests on orchestrator behavior + the operator's CLAUDE.md, not hook coercion. Documented in CHANGELOG + a short ADR.
- **Rollback:** `git reset --hard backup/pre-shell-hardening-*` tag.

## Decision context (why these fixes, not others)
- **Decision:** fix failure-mode correctness in the shell safety layer; downgrade the one per-turn blocking hook to a reminder.
- **Why:** the audited safety scripts fail *open* in exactly the checks whose purpose is to fail *closed* (single-writer, scope/cap arithmetic), and one Stop-hook coerces the model per-turn.
- **Alternatives:** (a) blanket-disable hooks via env — rejected, hides the bug instead of fixing it; (b) rewrite coord.sh locking wholesale — rejected, disproportionate, happy path is correct.
- **Linked:** ADR-007 (autonomy enforcement), ADR-008 (this — session-end downgrade), CHANGELOG 1.28.0.
