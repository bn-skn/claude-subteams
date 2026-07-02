# ADR-008: session-end-reminder is a non-blocking systemMessage reminder; the Bash record-guard is blanket-deny

**Status:** accepted
**Date:** 2026-07-02

## Context

A full health audit of v1.27.0 (9 agents + a Codex GPT-5.5 cross-model pass) surfaced two things that were not shell *bugs* but design faults in the hook layer:

1. **`session-end-reminder` coerced the model every turn.** The hook is wired to the `Stop` event. `Stop` fires at the end of **every assistant turn**, not at end-of-session — the filename is a misnomer. In its Case D (code changed, no `.md`) and Case-C-breaking branches it did `exit 2`, which *blocks* the turn and feeds stderr back to the model, forcing it to document-or-explain after the first code edit of a feature — before the feature even exists. A `/tmp` counter (2 strikes per HEAD) was a band-aid for exactly that misfire. For a conversational SDK deployment (the operator's bot) this meant the doc gate could fire mid-dialogue. The operator asked for it to be fixed.

2. **The v1.27.0 autonomy-gate Bash record-guard was a leaky read/write classifier.** It tried to *allow* read-only inspection of the run record while denying writes, by matching the leading command token against a viewer allowlist. Cross-model review found this trivially bypassable — `cat /dev/null; mv payload <record>` latches read-only on the leading `cat` then writes via the second command; `sort -o <record>` and `uniq in <record>` write with no `>` redirection — and therefore **strictly worse** than the blanket deny it replaced (which denied any command naming the record).

## Decision

**(1) Downgrade the reminder, keep it model-visible.** `session-end-reminder` no longer blocks. Every reminder path funnels through a `_remind()` helper that emits a single `{"decision":"approve","systemMessage":"<text>"}` JSON object on stdout and `exit 0`. This was verified against the Claude Code hook docs: for a `Stop` hook a bare `printf`+exit 0 is **transcript-only** (reaches neither the model nor the operator), `exit 2`+stderr reaches the model **but blocks**, and `Stop` does **not** support `hookSpecificOutput.additionalContext` (that is a PreToolUse/PostToolUse field). `systemMessage` + `decision:"approve"` is the documented non-blocking, surfaced channel. All doc-classification logic (Case A–D, breaking-signal detection, doc-map-freshness accumulation, neutral-file handling, escape hatch) is preserved unchanged; the dead `/tmp` counter/HEAD machinery is removed. The operator's bot additionally sets `CLAUDE_SUBTEAMS_SKIP_DOC_CHECK=1` so the reminder is silent in conversational turns; the hook remains useful in interactive CLI development.

*Honest caveat:* the hook docs consulted were a local copy; whether `systemMessage` renders into the model's context or the operator-facing surface is not 100% pinned. Either way it is the documented non-blocking channel and strictly better than the transcript-only bare-stdout path it replaces; the old bare-stdout reminder was invisible.

**(2) Revert the Bash record-guard to blanket-deny.** Any Bash command whose text references the active run record (its basename or the literal `autonomy-run`) is denied outright — no read/write classification. A robust read-vs-write decision on arbitrary shell text is not achievable (command-chaining, substitution, write-via-flag all defeat a token classifier), so we do not attempt it. To read the record mid-run, use the Read tool. This is consistent with ADR-007's honest framing: the guard is **partial mitigation against casual/named record edits, not a sandbox** — a write that never names the record (variable/base64/heredoc indirection) still escapes, and that residual stays a documented, deferred operator decision.

## Consequences

- **Positive:** the doc gate can no longer coerce the model per-turn (the operator's complaint), yet the reminder still reaches the model non-blockingly in CLI use. The record-guard is now obviously-correct (blanket deny) instead of cleverly-wrong, closing the `cat; mv` / `sort -o` / `uniq` bypasses that the classifier reopened. 55-case adversarial suite green, including every one of those bypasses asserted as DENY.
- **Negative:** reading the run record via Bash is denied during a run (use the Read tool) — a minor usability cost, and the reason the v1.27.0 classifier existed; we accept it as the price of a guard that can't be chained past. The doc-discipline enforcement the plugin's Full-pipeline Step 10 / Critical Rule 17 leaned on is now advisory, not enforced — documentation discipline rests on orchestrator behavior and the project's own conventions, not hook coercion (which was impossible to do correctly on a per-turn Stop event anyway).
- **Deferred (named, not solved):** (a) AC3's fail-closed can halt an autonomous run on a transient `.git/index.lock` held by a concurrent commit — accepted, because the asymmetry favors a false halt (one re-invocation) over a false pass (a run off its caps); a retry was judged disproportionate for a per-tool-call hook. (b) hooks.json's unquoted `${CLAUDE_PLUGIN_ROOT}` command path is accepted-residual — safe for standard install paths under `~/.claude/plugins/` (no spaces), fixable only after confirming the harness shell-executes the `command` field. Both are recorded in BACKLOG.

## Related
Branch `fix/shell-hardening-1.28.0`; CHANGELOG [1.28.0]. Extends ADR-007 (autonomy enforcement is drift-containment, not a sandbox) — this revert keeps the Bash guard within that honest boundary rather than overclaiming a read/write firewall. Files: `hooks/session-end-reminder`, `hooks/autonomy-gate`. Adversarial suite: 55/55.
