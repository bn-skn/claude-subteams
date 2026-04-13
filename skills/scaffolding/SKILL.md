---
name: scaffolding
description: Use when creating new services, modules, API endpoints, skills, or agents from templates
type: flexible
---

# Scaffolding

## Overview

Consistent project structure reduces onboarding time and eliminates configuration guesswork. Use templates to scaffold new components with the right defaults.

**Core principle:** Every new component MUST follow the established templates. NEVER create ad-hoc structures.

## When to Use

- Creating a new service or bot
- Adding a new module to an existing project
- Building a new API endpoint
- Creating a new skill for this plugin
- Creating a new agent definition

## Service/Bot Template

### Folder Structure
```
my-service/
  src/
    index.ts          # Entry point
    config.ts         # Configuration loading
    routes/           # API route definitions
    handlers/         # Request handlers
    services/         # Business logic
    utils/            # Shared utilities
  tests/
    unit/             # Unit tests
    integration/      # Integration tests
  .env.example        # Environment variable template
  package.json        # Dependencies and scripts
  tsconfig.json       # TypeScript configuration
  Dockerfile          # Container definition
  README.md           # Service documentation
```

### Scaffolding Checklist
1. Create folder structure as shown above
2. Initialize package.json with required scripts: `start`, `build`, `test`, `lint`
3. Configure tsconfig.json with strict mode enabled
4. Create .env.example with all required variables (no real values)
5. Add health check endpoint at `GET /health`
6. Add basic error handling middleware
7. NEVER include secrets or real credentials in scaffolded files
8. Reference the plugin's `templates/` directory for base configurations

## Module Template

### Files to Create
1. `src/modules/<name>/<name>.ts` -- Main module implementation
2. `src/modules/<name>/<name>.test.ts` -- Unit tests
3. `src/modules/<name>/index.ts` -- Public exports
4. `src/modules/<name>/README.md` -- Module documentation

### Module Checklist
1. Export a clear public API via index.ts
2. Include at least one test covering the primary function
3. Document the module's purpose and usage in README.md
4. MUST follow existing naming conventions in the project
5. NEVER create circular dependencies between modules

## API Endpoint Template

### Files to Create
1. `src/routes/<resource>.routes.ts` -- Route definitions
2. `src/handlers/<resource>.handler.ts` -- Request handler logic
3. `src/validation/<resource>.schema.ts` -- Input validation schema
4. `tests/integration/<resource>.test.ts` -- Integration tests

### Endpoint Checklist
1. Define route with appropriate HTTP method and path
2. Add input validation using Zod or similar schema library
3. Implement handler with proper error handling
4. Return consistent response format across all endpoints
5. Write integration test covering happy path and error cases
6. MUST validate all user input before processing
7. MUST return appropriate HTTP status codes
8. NEVER expose internal error details to clients

### Response Format
```json
{
  "success": true,
  "data": {},
  "error": null
}
```

## Skill Template

### File to Create
`skills/<category>/<skill-name>/SKILL.md`

### YAML Frontmatter
```yaml
---
name: skill-name
description: Use when [specific trigger condition]
type: flexible
---
```

### Skill Structure Checklist
1. Start with YAML frontmatter (name, description, type)
2. Add Overview section explaining the skill's purpose
3. Add "When to Use" section with specific trigger conditions
4. Add numbered checklists for each procedure
5. Add "Critical Rules" with NEVER/ALWAYS/MUST statements
6. Add "Quick Reference" table summarizing key information
7. Keep length between 50-150 lines
8. MUST use English throughout
9. NEVER include code examples longer than 15 lines

## Agent Template

### File to Create
`agents/<agent-name>.md`

### YAML Frontmatter
```yaml
---
name: agent-name
description: Brief description of agent's role
type: agent
---
```

### Agent Definition Checklist
1. Start with YAML frontmatter (name, description, type)
2. Define the agent's role and responsibilities
3. Specify input requirements (what the agent receives)
4. Define output contract (what the agent produces)
5. List skills the agent may invoke
6. Define escalation rules (when to ask for help)
7. MUST include output format specification
8. NEVER allow agents to operate outside their defined scope

## Critical Rules

- NEVER create files without following the appropriate template
- ALWAYS check the plugin's `templates/` directory for base configurations first
- MUST include tests for every new module and endpoint
- MUST include .env.example when environment variables are needed
- ALWAYS use strict TypeScript configuration for new services

## Quick Reference

| Component | Template Source | Key Files |
|-----------|---------------|-----------|
| Service | This skill (section above) | index.ts, config.ts, package.json |
| Module | This skill (section above) | module.ts, module.test.ts, index.ts |
| Endpoint | This skill (section above) | routes.ts, handler.ts, schema.ts |
| Skill | This skill (section above) | SKILL.md |
| Agent | This skill (section above) | agent-name.md |
| Project docs | Plugin `templates/` dir | CONVENTIONS.md, BACKLOG.md, ARCHITECTURE.md, CHANGELOG.md, adr-template.md |
