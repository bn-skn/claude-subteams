## Development Methodology

For development tasks use the claude-subteams plugin (orchestrator + 9 specialized agents).
Invoke skill "claude-subteams:using-subteams" before significant development work.
For small fixes — act directly, invoke code-review after if logic changed.
Available agents: code-reviewer, test-engineer, architecture-guard, design-critic, prompt-evaluator, doc-agent, researcher, security-auditor, devils-advocate.
