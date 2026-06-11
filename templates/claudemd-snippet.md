## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + specialized sub-team agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed. Any logic change gets code-reviewer (and devils-advocate for non-trivial logic) — no "it's just one line" exemption.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate, developer, ui-tester, improvement-agent, gpt-code-reviewer, gpt-devils-advocate, prompt-engineer, agent-architect.
Building/editing agents, prompts, skills, or multi-agent systems → invoke agent-architect + prompt-engineer + prompt-evaluator (using-subteams Section 6.5).
