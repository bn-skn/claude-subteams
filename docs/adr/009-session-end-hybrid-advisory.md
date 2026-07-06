# ADR-009: session-end-reminder becomes hybrid advisory (additionalContext to the model + systemMessage to the operator), fire-once per session

**Status:** accepted — fire-once granularity revised by the 2026-07-06 amendment below (once per *changeset*, not once per session; v1.30.0)
**Date:** 2026-07-05

## Context

Two independent problems converged on this hook.

**1. The 1.28.0 delivery premise was wrong.** ADR-008 downgraded the hook from blocking (`exit 2`) to `{"decision":"approve","systemMessage":"…"}`, on the belief that `systemMessage` "actually reaches the model". The BACKLOG carried an honest caveat: "the model-vs-user surface wasn't pinned". Checked against the official hooks documentation (code.claude.com/docs/en/hooks.md, 2026-07-05): `systemMessage` is a **warning shown to the user only** — the model never sees it. Additionally, `decision:"approve"` does not exist on Stop (only `"block"` does), so the emitted field was schema-noise. The 1.28.0 hook therefore silently became operator-only, while the operator's actual goal was the opposite: a gentle, model-visible nudge.

**2. Live behavior of the pre-1.28.0 blocking variant confirmed the coercion failure mode.** With 1.27.0 installed, the blocking hook fired per turn on a dirty tree (Stop is per-turn, not end-of-session), fed the model an imperative numbered checklist as a block reason, and the model responded by launching unsolicited documentation work mid-task ("самодеятельность"). Observed repeatedly in a live session on 2026-07-05, including the attempt counter resetting on every user message — costing two extra hook round-trips per message.

The operator's target behavior: the model should learn, **once per session**, that undocumented edits exist, treat it as a recommendation to surface to the user — never as a work order — and the operator should get a short notice too.

## Decision

Rewrite `hooks/session-end-reminder` (v1.29.0) as follows:

- **Hybrid delivery, no decision field at all.** On fire, emit one JSON object: `{"systemMessage":"<one fixed operator line>","hookSpecificOutput":{"hookEventName":"Stop","additionalContext":"<advisory>"}}`, exit 0. `additionalContext` on Stop is documented as model-visible ("non-error feedback that continues the conversation"). Nothing blocks, ever; the attempt counter and HEAD-hash machinery stay deleted.
- **Fire-once per session.** `session_id` is extracted from Stop stdin (jq, sed fallback), sanitized by allowlist (`^[A-Za-z0-9._-]+$`, `.`/`..` rejected), and used as a marker filename under `${XDG_CACHE_HOME:-$HOME/.cache}/claude-subteams/session-end-marks/`. Marker present → silent exit before any git work. The marker is written **only when a reminder actually fires**, so silent passes never consume the slot. Markers older than 7 days are pruned opportunistically. If `session_id` is missing or unsafe, the hook falls back to firing every turn with no marker — availability wins over strict once-ness. `once: true` was not an option: it is honored only in skill frontmatter, not in plugin hooks.json.
- **Advisory texts, not checklists.** All model-facing texts open with an explicit frame — "Advisory (not a task — surface to the user, don't act now)" — state facts declaratively, and end on a passivity anchor ("Nothing to do now" / "raise it with the user"). Numbered imperative checklists and "Run the doc-agent" are gone; the authoritative checklists are referenced by skill name (`doc-quality-gate`, `decision-context`) instead of inlined. The classification logic (Cases A–D, breaking signals, doc-map NOTES rider, neutral filtering, escape hatch) is unchanged.
- **The fire-once marker doubles as loop protection**: `additionalContext` provokes one extra model turn, which produces one extra Stop — which the marker silences.

Validation: code-reviewer approved (no critical/important findings); prompt-evaluator simulated all seven model-facing texts (six terminal + NOTES rider) against happy/edge/adversarial/minimal cases — two RISK phrasings (a self-directed invitation, a missing passivity anchor) were patched before merge, including the adversarial case of a filename crafted to read as an instruction, which is defused by the don't-act frame sitting upstream of any interpolated file list.

## Consequences

- **Positive:** The model actually receives the nudge (it did not in 1.28.0); it receives it once, not every turn; the texts are engineered against the launch-unsolicited-work failure mode; the operator keeps a short notice line; schema-invalid `decision:"approve"` is gone.
- **Negative:** One extra short model turn per session when the advisory fires (inherent to `additionalContext` on Stop). If `session_id` is ever absent from the Stop payload, the hook reverts to per-turn firing (documented fallback, considered acceptable). Cross-session dirty trees re-fire once per new session by design.
- **Neutral:** The filename `session-end-reminder` remains a misnomer (Stop is per-turn); kept for hooks.json wiring stability. ADR-008's Bash record-guard half is untouched; only its delivery-channel half is superseded.

## Related

- Supersedes the delivery half of [ADR-008](008-session-end-reminder-nonblocking.md).
- BACKLOG "session-end-reminder systemMessage rendering" spot-check → resolved by documentation verification (user-only surface), closed by this redesign.

## Amendment — 2026-07-06 (v1.30.0): once per changeset + standing doc-hygiene recommendation

Operator feedback after one day live: once-per-session can go blind in long sessions (the operator's bot sessions run up to ~24h) — an advisory consumed in the morning silences genuinely new undocumented work in the evening. Per-turn firing stays rejected (each fire costs an extra model turn; habituation kills the signal). Revised to **once per changeset**:

- The marker now stores the bare list of non-doc changed files at the last fire (empty for NOTES-only / not-a-git fires) instead of being an empty flag. Written atomically (tmp + `mv -f`).
- The marker-exists early-exit is gone; classification always runs. Before firing, `_remind()` gates: marker fresh (younger than the cooldown — default 45 min, `CLAUDE_SUBTEAMS_DOC_REMIND_COOLDOWN_MIN`, validated positive integer) → silent; no file in the current set that the stored set lacks → silent; otherwise fire and overwrite the marker with the current set. A shrinking set (files got documented/committed) never re-fires; a missing `find` degrades to "cooldown elapsed" — the fail-toward-reminding direction.
- Known accepted consequences: NOTES-only / not-a-git advisories don't repeat on their own (empty current set can never contain a new file); a NOTES-only fire can delay the first real code advisory by up to one cooldown window — still strictly better than the 1.29.0 baseline, where any first fire silenced the whole session. No upper bound on the cooldown by choice: a huge value just degrades to once-per-session.
- **Standing recommendation restored** (the useful spirit of the pre-1.28 blocking hook, minus the coercion): every terminal advisory now ends with "Standing recommendation: when the current piece of work wraps up, offer the user a doc update (decisions journal, CHANGELOG, descriptive sections) rather than starting one unprompted." Leads with the offer-framing, not an imperative, on prompt-evaluator advice; the evaluator passed all six variants post-append, including repeated-delivery accumulation.

Validation: developer smoke suite (8 scenarios: first fire, same-state silence, fresh-marker suppression, aged re-fire, shrinking set, cooldown override, no-session_id fallback) + orchestrator re-run after review fixes; code-reviewer approve (no critical/important; atomic write and explicit empty-list arg adopted from its suggestions); prompt-evaluator PASS on the appended sentence and the updated operator line.
