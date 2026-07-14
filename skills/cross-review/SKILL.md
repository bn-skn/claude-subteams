---
name: cross-review
description: "Orchestrates parallel GPT + Claude critics to break model-monoculture blind spots in code and architecture review."
---

# Cross-Review

## 1. When to Use This Skill

1. User explicitly requests `/cross-review` on a diff or set of files.
2. User triggers `/rescue` — Claude is stuck on a bug and needs Codex to take over.
3. Security-critical change (auth, crypto, key handling, injection surface).
4. Breaking change (Class 4 per `doc-quality-gate` skill) — optional but recommended.
5. New service bootstrap — first review of a net-new system.
6. Cross-review is for meaningful reviews (the triggers above), not an automatic hook on every trivial commit — invoke it when you are actually reviewing, not on every save. This is about relevance, not rationing: when cross-review runs, run the full critic set.

## 2. Model and Effort Policy — Read This First

**How the model is selected:**

- **Default:** whatever model the Codex CLI is configured to use (`~/.codex/config.toml`). Both agent files do NOT pass `-m` unless `CROSS_REVIEW_MODEL` is set, so Codex uses its own configured default natively.
- **Optional pin:** set `CROSS_REVIEW_MODEL=<model>` in the environment to lock a specific model for both agents at once, without any agent file edits.
- **Effort:** same idiom as the model above — the agents pass `-c model_reasoning_effort` only when `CROSS_REVIEW_EFFORT` is set; otherwise they pass nothing and Codex applies whatever its own config resolves (`model_reasoning_effort`, profile-scoped keys included). No TOML parsing in the plugin, no forced fallback. To control depth, set `model_reasoning_effort` in your Codex config (recommended `high` or above) or set `CROSS_REVIEW_EFFORT=<level>` to override per run.

```
# Optional overrides — only set these if you want to deviate from Codex CLI defaults
CROSS_REVIEW_MODEL=<specific-model>   # pin a model; omit to use Codex CLI default
CROSS_REVIEW_EFFORT=high              # override effort; unset → Codex uses its own config
```

**Why this matters:** Codex's bare default can be low or no reasoning effort, producing shallow reviews equivalent to a quick scan. High effort enables multi-step reasoning over the diff, which is the whole point of cross-review. The plugin no longer forces this — set `model_reasoning_effort = "high"` (or higher) in your Codex config so every Codex call including cross-review runs deep, or set `CROSS_REVIEW_EFFORT` for a per-run override.

**Severity normalization (apply when merging findings across model families):**

| Claude critic scale | GPT critic scale | Unified scale |
|---------------------|-----------------|---------------|
| Critical | critical | **critical** |
| Important | high | **high** |
| Suggestions | medium | **medium** |
| — | low | **low** |
| — | blocking (devils-advocate) | **critical** |
| — | significant | **high** |
| — | worth-considering | **medium** |

**Maintenance note:** To upgrade the model or change reasoning effort, edit your Codex CLI config (`~/.codex/config.toml`) — the critics inherit both automatically, exactly as Codex resolves them (profiles included); no plugin edit needed. Use `CROSS_REVIEW_MODEL` / `CROSS_REVIEW_EFFORT` only to pin model/effort temporarily. Verify the configured model and effort with:
```bash
codex exec -c model_reasoning_effort=high -s read-only --skip-git-repo-check "Return your model name and reasoning effort level as JSON."
```

**Agents implementing this policy:** `agents/gpt-code-reviewer.md` · `agents/gpt-devils-advocate.md`

## 3. Trigger: `/cross-review`

### 3.1 Dispatch (parallel)

Dispatch the FULL critic set in parallel — both model families together — for complete cross-model coverage:
1. Claude critics: `code-reviewer` + `devils-advocate`.
2. GPT critics: `gpt-code-reviewer` + `gpt-devils-advocate`.
3. All four receive the same diff/file context. Write sets are empty — all read-only.

Run all four by default. Do NOT drop GPT critics to conserve quota — full coverage is the point of cross-review; the user has opted into it.

**Reviewer-name rule (harness quirk):** in harnesses where a custom spawn name overrides `agent_type` in the hook payload (observed in teammate mode), the review-gate matches a reviewer by the substring `code-reviewer` — so spawn review agents with no custom name, or a name containing `code-reviewer`. An unrelated custom name hides the review from the gate.

### 3.2 Merge Results

1. Collect all findings. Normalize severity to the unified scale from Section 2 before comparing.
2. **Escalation rule (load-bearing — deterministic):** any finding at `critical` or `blocking` severity from EITHER model family triggers immediate human review. Do NOT auto-resolve. This rule takes precedence over all others.
3. **Intersection heuristic:** where both families independently raise the SAME `file:line` or the SAME named risk, label it high-confidence and surface it prominently. Do NOT force matches across different granularity levels — different severity words on different aspects of the same file are not a match.
4. **Union rule:** findings from only one model family are still valid — list them with their source. Neither family is a superset of the other.
5. **Non-critical disagreements:** note both perspectives in the merged report; the developer decides.

### 3.3 Merged Report Format

```
## Cross-Review Report
### Escalated — human decision required before merge
- [file:line] critical/blocking finding. Sources: <agent(s)>.
### High-Confidence (both model families, same file:line or named risk)
- [file:line] Issue. Sources: <agent> + <agent>.
### Claude-Only Findings
- [file:line] Issue. Source: code-reviewer | devils-advocate.
### GPT-Only Findings
- [file:line] Issue. Source: gpt-code-reviewer | gpt-devils-advocate.
### Cross-Review Skipped (if applicable)
- Reason: Codex unavailable. Claude critics ran; results are single-model.
```

## 4. Trigger: `/rescue`

Use when Claude has been debugging a problem across multiple turns without resolution.

1. Run availability check first: `command -v codex` and `codex login status`. If either fails, skip to step 5.
2. Gather all relevant files and the symptom description.
3. Invoke Codex. Do not auto-retry the same call on a non-zero exit (that just burns a failed call) — but you may run `/rescue` again with refined context if the first diagnosis missed:

```bash
MODEL_FLAG=()
[ -n "${CROSS_REVIEW_MODEL:-}" ] && MODEL_FLAG=(-m "$CROSS_REVIEW_MODEL")
# Reasoning effort: pass CROSS_REVIEW_EFFORT when set, else nothing so Codex reads its own config.
EFFORT_FLAG=()
[ -n "${CROSS_REVIEW_EFFORT:-}" ] && EFFORT_FLAG=(-c model_reasoning_effort="$CROSS_REVIEW_EFFORT")

codex exec "${MODEL_FLAG[@]}" "${EFFORT_FLAG[@]}" \
  -s read-only \
  "<symptom description> — files: <list>. Diagnose the root cause and propose a concrete fix. You may read files in read-only sandbox."
```

4. Present Codex's diagnosis to the human. Implement the proposed fix yourself after human confirmation — do not let Codex write to the repo directly.
5. If Codex is unavailable or the one attempt fails: acknowledge, explain, ask the human for additional context to try a different approach. Do not retry.

## 5. Running Any Agent Through GPT (Optional Escape Hatch)

The two named GPT critics (`gpt-code-reviewer`, `gpt-devils-advocate`) are the standing pairs. For any other specialist role — security-auditor, test-engineer, architecture-guard, design-critic, prompt-evaluator — you can cross-check on GPT using the same invocation pattern. This is opt-in: the user asks for it explicitly (e.g., "cross-check the security audit on GPT"), not a default step.

**Generic pattern:**

```bash
# Run availability check first (same as standing critics)
command -v codex || { echo "codex not on PATH"; exit 0; }
codex login status | grep -q "Logged in" || { echo "codex not authenticated"; exit 0; }

SCHEMA_FILE=$(mktemp /tmp/gpt-generic-schema-XXXXXX.json)
OUTPUT_FILE=$(mktemp /tmp/gpt-generic-out-XXXXXX.json)

# Define a schema appropriate for the specialist role
cat > "$SCHEMA_FILE" << 'SCHEMA'
{"type":"object","properties":{"findings":{"type":"array","items":{"type":"object","properties":{"severity":{"type":"string","enum":["critical","high","medium","low"]},"target":{"type":"string"},"issue":{"type":"string"},"why_claude_might_miss":{"type":"string"}},"required":["severity","target","issue","why_claude_might_miss"]}},"summary":{"type":"string"}},"required":["findings","summary"]}
SCHEMA

MODEL_FLAG=()
[ -n "${CROSS_REVIEW_MODEL:-}" ] && MODEL_FLAG=(-m "$CROSS_REVIEW_MODEL")
# Reasoning effort: pass CROSS_REVIEW_EFFORT when set, else nothing so Codex reads its own config.
EFFORT_FLAG=()
[ -n "${CROSS_REVIEW_EFFORT:-}" ] && EFFORT_FLAG=(-c model_reasoning_effort="$CROSS_REVIEW_EFFORT")

codex exec "${MODEL_FLAG[@]}" "${EFFORT_FLAG[@]}" \
  -s read-only \
  --output-schema "$SCHEMA_FILE" \
  -o "$OUTPUT_FILE" \
  "<Role mandate for this specialist — e.g., 'You are a security auditor...' — plus the files/diff to examine. Ask for findings the Claude specialist is statistically likely to miss from a different training distribution. Return JSON matching the schema.>"
RC=$?

if [ "$RC" -ne 0 ]; then
  echo "Status: cross-review-unavailable"
  echo "Reason: codex exit $RC. Claude specialist findings stand alone."
  rm -f "$SCHEMA_FILE" "$OUTPUT_FILE"
  exit 0
fi

cat "$OUTPUT_FILE"
rm -f "$SCHEMA_FILE" "$OUTPUT_FILE"
```

**Rules for generic invocations:**
- Do NOT create a new agent file for each specialist role — use this pattern directly.
- Apply the same availability check, read-only sandbox, one-call-per-review, and no-auto-retry rules as the standing critics.
- Merge findings using the same escalation and union/intersection rules from Section 3.2.
- The Claude specialist's output still stands — GPT findings are additive, not a replacement.

## 6. Fallback and Reliability

1. If `codex` is not on PATH, not authenticated, or exits non-zero: skip GPT critics, log the reason, run Claude critics only. NEVER block the main pipeline — Claude critics are always sufficient to proceed.
2. Do NOT auto-retry a failed Codex call — a non-zero exit means skip and report, not loop on the same call.
3. For awareness, not as a limit: ChatGPT Plus uses a 5-hour shared bucket across CLI and web. Run the full critic set whenever cross-review fires — do not ration GPT calls. If the human reports ChatGPT being throttled, pause Codex calls and notify; that is a reaction to a real signal, never a pre-emptive cap.

## 7. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Running cross-review automatically on every trivial commit | Adds latency and noise to changes that don't need a second model | Invoke when actually reviewing — explicit triggers and high-risk changes |
| Dropping a GPT critic to "save quota" | Defeats cross-model coverage — the user opted into the full set | Run all four critics whenever cross-review fires |
| Hardcoding a model name in agent files | Creates drift; model name baked into agent files silently persists after a CLI config change | Change the default in `~/.codex/config.toml`; agents inherit it. Use `CROSS_REVIEW_MODEL` to pin temporarily |
| Auto-resolving a critical disagreement between model families | Two models disagreeing on critical/security = genuine ambiguity | Escalate to human; do not merge until addressed |
| Auto-retrying Codex after a non-zero exit | Looping on a failed call wastes it and can cascade errors | Log unavailable, proceed with Claude critics, notify human |
| Treating GPT findings as a superset of Claude findings | Different models miss different things; neither is complete | Use intersection for confidence, union for coverage |
| Skipping availability check before Codex call | Network or auth failure will produce a cryptic error mid-review | Always run `command -v codex && codex login status` first |
| Letting Codex write to the repo during /rescue | Codex operates in read-only sandbox; changes must be reviewed | Always use `-s read-only`; implement fixes yourself after human confirmation |

## 8. Critical Rules

1. MUST invoke Codex with `-s read-only`. Pass `-c model_reasoning_effort="$CROSS_REVIEW_EFFORT"` only when `CROSS_REVIEW_EFFORT` is set, and `-m "$CROSS_REVIEW_MODEL"` only when `CROSS_REVIEW_MODEL` is set — otherwise pass neither and let Codex resolve model and effort from its own config. Never hardcode a model name or effort level in agent files.
2. SHOULD run cross-review at `high` reasoning effort or above — Codex's bare default can be a shallow scan. The plugin does not force this; configure `model_reasoning_effort` in `~/.codex/config.toml` (or `CROSS_REVIEW_EFFORT`) so reviews run deep.
3. ALWAYS run availability check before invoking Codex.
4. NEVER block the main pipeline when Codex is unavailable.
5. NEVER auto-resolve critical/blocking cross-model disagreements — escalate to human.
6. NEVER run cross-review as a default commit gate.
7. MUST keep model and effort sourced from the Codex config (`~/.codex/config.toml`) or the `CROSS_REVIEW_MODEL` / `CROSS_REVIEW_EFFORT` env vars — those are the single source of truth for both (the no-hardcode mandate is in Rule 1).
8. NEVER allow Codex to write to the repository — read-only sandbox always.
9. MUST cap review rounds at 1-2 — no Claude↔GPT debate loops.

## 9. Agent Reference

| Agent | Role | Pairs with Claude critic |
|-------|------|--------------------------|
| `gpt-code-reviewer` | Concurrency, numeric, platform, spec-drift, resource lifecycle bugs | `code-reviewer` |
| `gpt-devils-advocate` | Abstraction boundaries, implicit contracts, failure model, composability | `devils-advocate` |
