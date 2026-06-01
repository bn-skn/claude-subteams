---
name: cross-review
description: "Orchestrates parallel GPT-5.5 + Claude critics to break model-monoculture blind spots in code and architecture review."
---

# Cross-Review

## 1. When to Use This Skill

1. User explicitly requests `/cross-review` on a diff or set of files.
2. User triggers `/rescue` — Claude is stuck on a bug and needs Codex to take over.
3. Security-critical change (auth, crypto, key handling, injection surface).
4. Breaking change (Class 4 per `doc-quality-gate` skill) — optional but recommended.
5. New service bootstrap — first review of a net-new system.
6. NEVER run cross-review as a default gate on every commit — it is slower and consumes ChatGPT Plus quota.

**Validate before expanding:** Before widening the trigger list, measure the genuine-miss rate on 3-5 past reviews (GPT-only findings that were real bugs Claude missed). Keep triggers narrow until validated — this is a specialist tool, not a default capability.

## 2. Model and Effort Policy — Read This First

**Current defaults (env-var override — one place to change):**

```
CROSS_REVIEW_MODEL=gpt-5.5
CROSS_REVIEW_EFFORT=high
```

Both agent files read these env vars with fallback: `MODEL="${CROSS_REVIEW_MODEL:-gpt-5.5}"` / `EFFORT="${CROSS_REVIEW_EFFORT:-high}"`. To override both agents at once, export these vars before invoking — no agent file edits required.

**Why this matters:** Codex defaults to no reasoning effort, producing shallow reviews equivalent to a quick scan. High effort enables multi-step reasoning over the diff. Using any weaker configuration defeats the purpose of cross-review.

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

**Maintenance note:** When OpenAI ships a stronger model, set `CROSS_REVIEW_MODEL=<new-model>` (e.g., in the shell environment or a `.env` file). Verify first:
```bash
codex exec -m <new-model> -c model_reasoning_effort=high -s read-only --skip-git-repo-check "Return your model name and reasoning effort level as JSON."
```
Confirm the response header shows the new model at high effort. No agent file edits needed — both agents pick up the env var automatically.

**Agents implementing this policy:** `agents/gpt-code-reviewer.md` · `agents/gpt-devils-advocate.md`

## 3. Trigger: `/cross-review`

### 3.1 Dispatch (parallel)

**Default mode (one GPT call — preserves quota for most reviews):**
1. Dispatch Claude critics in parallel: `code-reviewer` + `devils-advocate`.
2. Simultaneously dispatch `gpt-code-reviewer` (highest-value GPT critic).
3. All three receive the same diff/file context. Write sets are empty — read-only.

**Deep mode (two GPT calls — reserve for security-critical, breaking, or new-service reviews):**
1. Dispatch Claude critics in parallel: `code-reviewer` + `devils-advocate`.
2. Simultaneously dispatch both GPT critics in parallel: `gpt-code-reviewer` + `gpt-devils-advocate`.
3. All four receive the same diff/file context. Write sets are empty — read-only.

Trigger deep mode when: the change touches auth/crypto, is Class 4 Breaking, or bootstraps a new service.

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

Use when Claude has been debugging a problem across multiple turns without resolution. `/rescue` counts against the same 5-hour shared quota as reviews — use it deliberately, and cap at ONE attempt per debugging session.

1. Run availability check first: `command -v codex` and `codex login status`. If either fails, skip to step 5.
2. Gather all relevant files and the symptom description.
3. Invoke Codex once — no retries:

```bash
MODEL="${CROSS_REVIEW_MODEL:-gpt-5.5}"
EFFORT="${CROSS_REVIEW_EFFORT:-high}"

codex exec \
  -m "$MODEL" \
  -c model_reasoning_effort="$EFFORT" \
  -s read-only \
  "<symptom description> — files: <list>. Diagnose the root cause and propose a concrete fix. You may read files in read-only sandbox."
```

4. Present Codex's diagnosis to the human. Implement the proposed fix yourself after human confirmation — do not let Codex write to the repo directly.
5. If Codex is unavailable or the one attempt fails: acknowledge, explain, ask the human for additional context to try a different approach. Do not retry.

## 5. Fallback and Quota

1. If `codex` is not on PATH, not authenticated, or exits non-zero: skip GPT critics, log the reason, run Claude critics only. NEVER block the main pipeline — Claude critics are always sufficient to proceed.
2. NEVER retry Codex automatically — one attempt per review, one attempt per `/rescue` session.
3. ChatGPT Plus has a 5-hour shared bucket (CLI + web). Heavy CLI use degrades interactive ChatGPT — trigger cross-review deliberately, not automatically.
4. If the human reports ChatGPT being slow or rate-limited: stop all Codex calls immediately and notify.

## 6. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Running cross-review on every commit | Drains ChatGPT Plus quota; adds latency to normal flow | Reserve for explicit triggers and high-risk changes only |
| Editing model/effort hardcoded in agent files | Creates drift; a missed file silently runs default (shallow) effort | Set `CROSS_REVIEW_MODEL` / `CROSS_REVIEW_EFFORT` env vars — agents pick them up automatically |
| Auto-resolving a critical disagreement between model families | Two models disagreeing on critical/security = genuine ambiguity | Escalate to human; do not merge until addressed |
| Retrying Codex after a quota failure | Quota errors worsen under retries | Log unavailable, proceed with Claude critics, notify human |
| Treating GPT findings as a superset of Claude findings | Different models miss different things; neither is complete | Use intersection for confidence, union for coverage |
| Skipping availability check before Codex call | Network or auth failure will produce a cryptic error mid-review | Always run `command -v codex && codex login status` first |
| Letting Codex write to the repo during /rescue | Codex operates in read-only sandbox; changes must be reviewed | Always use `-s read-only`; implement fixes yourself after human confirmation |

## 7. Critical Rules

1. MUST invoke Codex with `-m "$CROSS_REVIEW_MODEL" -c model_reasoning_effort="$CROSS_REVIEW_EFFORT" -s read-only` — no exceptions, no defaults left implicit.
2. NEVER use Codex with default reasoning effort — it produces reviews equivalent to a quick scan.
3. ALWAYS run availability check before invoking Codex.
4. NEVER block the main pipeline when Codex is unavailable.
5. NEVER auto-resolve critical/blocking cross-model disagreements — escalate to human.
6. NEVER run cross-review as a default commit gate.
7. MUST change model/effort via `CROSS_REVIEW_MODEL` / `CROSS_REVIEW_EFFORT` env vars — never hardcode in individual agent files.
8. NEVER allow Codex to write to the repository — read-only sandbox always.
9. MUST cap review rounds at 1-2 — no Claude↔GPT debate loops.

## 8. Agent Reference

| Agent | Role | Pairs with Claude critic |
|-------|------|--------------------------|
| `gpt-code-reviewer` | Concurrency, numeric, platform, spec-drift, resource lifecycle bugs | `code-reviewer` |
| `gpt-devils-advocate` | Abstraction boundaries, implicit contracts, failure model, composability | `devils-advocate` |
