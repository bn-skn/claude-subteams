---
name: codebase-improvement
description: "Proactive codebase analysis and improvement proposal generation. Dispatches improvement-agent to find optimization opportunities across code, deps, tests, architecture, and logs."
---

# Codebase Improvement

## 1. Dispatch Protocol

1. This skill dispatches to the **improvement-agent** for read-only analysis.
2. Agent model: sonnet.
3. Agent tools: Read, Grep, Glob, Bash (read-only commands only).
4. ALWAYS provide: target directory, focus areas, depth level.
5. Agent returns proposals — never writes code or makes changes.

## 2. When to Use

| Scenario | Use This Skill |
|----------|---------------|
| Periodic codebase health check | Yes |
| Before major refactoring — find what to prioritize | Yes |
| After log-analyzer reports issues — drill deeper | Yes |
| Sprint planning — identify tech debt to address | Yes |
| Quick bug fix on known issue | No — fix directly |
| Feature implementation | No — use developer agent |

## 3. Analysis Modes

### Quick Scan (5 min)
Focus: code smells, TODOs, outdated deps.
```
Depth: quick
Focus: code-health, dependencies
```

### Standard Analysis (15 min)
Focus: all 7 dimensions, prioritized proposals.
```
Depth: standard
Focus: all
```

### Deep Audit (30 min)
Focus: full analysis + log correlation + architecture review.
```
Depth: deep
Focus: all
Include: logs from last 7 days, git history (churn analysis)
```

## 4. Integration with Other Agents

The improvement-agent works best as part of a chain:

```
improvement-agent ──proposals──> orchestrator ──approved──> developer
                                     │
                                     ├──> code-reviewer (validates fix)
                                     └──> test-engineer (covers the fix)
```

**With log-analyzer (persistent agent):**
```
log-analyzer (21:00 daily) ──report──> inter_agent_messages
improvement-agent (on-demand) ──reads report──> deeper proposals
```

**With GitNexus:**
```
improvement-agent finds: "core.ts is 400 lines, god file"
gitnexus_impact({target: "processMessage"}) ──blast radius──>
improvement-agent: "Split into 3 modules, here's the safe order"
```

## 5. Brief Template

When dispatching the improvement-agent:

```
Task: Analyze [project/directory] for improvement opportunities
Codebase: [path]
Depth: [quick | standard | deep]
Focus: [all | code-health | dependencies | tests | architecture | performance | logs | dx]
Context: [any recent issues, goals, or constraints]
Logs path: [path to logs/ if available]
Exclude: [directories or files to skip]
```

## 6. Acting on Proposals

After receiving proposals from improvement-agent:

1. **Review proposals yourself** — the agent may overestimate or underestimate severity.
2. **Present P0/P1 to user** immediately — these are production risks.
3. **Queue P2/P3** in BACKLOG.md or docs/TODO.md for sprint planning.
4. **For approved proposals:**
   - Spawn developer agent with the specific proposal as brief
   - After implementation — code-reviewer + test-engineer
   - Standard pipeline applies

## 7. Automation Opportunities

### Scheduled Analysis (cron)
Run weekly via persistent agent or cron task:
```bash
# Sunday 04:00 — after log-analyzer (21:00 Sat) and memory-manager (03:00 Sun)
node dist/schedule-cli.js create "Run improvement-agent on claudebot codebase, depth: standard" "0 4 * * 0" CHAT_ID
```

### Post-Deploy Check
After deploying changes, run quick scan to verify no new issues:
```
Depth: quick
Focus: code-health, dependencies
Context: Just deployed [feature]. Check for regressions.
```

### Pre-Sprint Planning
Before each sprint, run deep analysis to inform priorities:
```
Depth: deep
Focus: all
Context: Planning next sprint. Need prioritized tech debt items.
```

## 8. Critical Rules

1. improvement-agent is READ-ONLY. It NEVER modifies files. If it tries — that's a bug.
2. ALWAYS review proposals before acting. Agent findings are suggestions, not commands.
3. P0 findings go to user immediately — don't queue them.
4. Proposals MUST have file:line references. Reject vague proposals.
5. Don't run deep analysis more than once per week on the same codebase — diminishing returns.
6. When in doubt about a proposal's validity — spawn code-reviewer to get a second opinion.
