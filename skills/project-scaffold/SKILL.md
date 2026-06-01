---
name: project-scaffold
description: "Bootstrap an empty/new directory into a project skeleton (docs, CLAUDE.md, .gitignore, README) — use only when no source files exist yet."
---

# Project Scaffold

## 1. Overview

1. This skill creates the full documentation and project-skeleton scaffold for a brand-new project.
2. It covers: `CLAUDE.md`, `README.md`, `.gitignore`, `docs/SYSTEM.md`, `docs/CONVENTIONS.md`, `docs/ARCHITECTURE.md`, `docs/BACKLOG.md`, `docs/CHANGELOG.md`, and the `docs/plans/` + `docs/specs/` + `docs/adr/` directory seeds.
3. It does NOT scaffold source-code components (services, modules, endpoints, agents). Use the `scaffolding` skill for that after initialization.

## 2. When to Use

1. User says: "new project", "bootstrap project", "/init-project", "init project", "empty repo", "create project skeleton".
2. The target directory does not yet exist, or it exists but contains only benign pre-existing files (see Step 2 allowlist).
3. NEVER invoke this skill when a project already has source files — use `scaffolding` instead.
4. If the target directory has no source files yet, this skill creates the skeleton; then use `scaffolding` for components.

## 3. Wizard Flow

### Step 1 — Gather parameters (ask all in one message)

**Identity**
1. **Project name** — becomes `<PROJECT_NAME>` in all templates.
2. **One-line goal** — what the project does and who uses it; becomes `<PROJECT_GOAL>`.
3. **Domain** — dev / content / bot / data / api / cli / other.

**Stack**

4. **Primary language/runtime** — TypeScript/Node.js, Python, Go, other; becomes `<STACK>`.
5. **Key frameworks** — e.g. Express, FastAPI, Gin; becomes `<FRAMEWORKS>`.
6. **Persistence** — e.g. SQLite, Postgres, none; becomes `<DATABASE>`.
7. **External APIs** — e.g. OpenAI, Stripe, none; becomes `<EXTERNAL_APIS>`.

**Commands** (enter "none" or "N/A" for anything not applicable)

8. **Install command** — e.g. `npm install`; becomes `<INSTALL_COMMAND>`.
9. **Build command** — e.g. `npm run build`; becomes `<BUILD_COMMAND>`.
10. **Test command** — e.g. `npm test`; becomes `<TEST_COMMAND>`.
11. **Lint command** — e.g. `npm run lint`; becomes `<LINT_COMMAND>`.
12. **Run command** — e.g. `node dist/index.js`; becomes `<RUN_COMMAND>`.
13. **Dev command** — e.g. `npm run dev`; becomes `<DEV_COMMAND>`.

**Project metadata**

14. **Repo URL** — e.g. `https://github.com/org/repo`; becomes `<REPO_URL>`.
15. **License** — e.g. MIT, Apache-2.0, proprietary; becomes `<LICENSE>`.
16. **Target directory** — absolute path where the scaffold will be written.

### Step 2 — Safety check (HARD prerequisite)

1. Run `ls -A <target>` to list all files including dotfiles.
2. If the directory does not exist or the listing is empty — proceed.
3. If the listing contains ONLY files from this allowlist — proceed (never clobber them; skip writing if the file exists, or write `README.scaffold.md` instead of `README.md` and tell the user):
   - `.git/`, `.gitignore`, `LICENSE`, `LICENSE.md`, `README.md`, `.github/`, `.DS_Store`
4. If ANY file outside the allowlist is present — ABORT. Report exactly which files blocked the scaffold. Do not write anything.
   Blockers include but are not limited to: `package.json`, `pyproject.toml`, `go.mod`, `src/`, `*.ts`, `*.py`, `*.go`, any source or config file.

### Step 3 — Create output structure

Create files in this exact order, substituting all gathered placeholder values:

1. `CLAUDE.md` — from `templates/project-init/CLAUDE.md`.
2. `README.md` — from `templates/project-init/README.md` (skip if README.md already exists; write as `README.scaffold.md` instead and notify user).
3. `.gitignore` — from `templates/project-init/dot-gitignore` (rename on copy; skip if `.gitignore` already exists).
4. `docs/SYSTEM.md` — from `templates/project-init/SYSTEM.md`.
5. `docs/CONVENTIONS.md` — from `templates/CONVENTIONS.md` (reuse, no modification needed).
6. `docs/ARCHITECTURE.md` — from `templates/ARCHITECTURE.md`.
7. `docs/BACKLOG.md` — from `templates/BACKLOG.md`.
8. `docs/CHANGELOG.md` — from `templates/CHANGELOG.md`.
9. `docs/plans/active/.gitkeep` — empty file to commit the directory.
10. `docs/plans/completed/.gitkeep` — empty file to commit the directory.
11. `docs/specs/.gitkeep` — empty file to commit the directory (where `brainstorming` writes design specs).
12. `docs/adr/000-adr-template.md` — from `templates/adr-template.md`.

### Step 4 — Confirm and summarize

1. Print the created file tree to the user.
2. List every `<PLACEHOLDER>` that was NOT substituted because no value was gathered — the user must complete these manually.
3. **Hand off to the spec/plan process — this is the expected next step after scaffolding a new project:**
   - For the first feature, run `claude-subteams:brainstorming` → it writes a design spec to `docs/specs/YYYY-MM-DD-<topic>-design.md`.
   - Then `claude-subteams:writing-plans` turns the spec into an implementation plan in `docs/plans/active/`.
   - Then implement via the pipeline (`claude-subteams:using-subteams`).
4. For adding source-code components later (services, modules, endpoints), use the `scaffolding` skill.

## 4. Relationship to `scaffolding` Skill

1. **project-scaffold** — use once, at project start, to create the documentation and config skeleton for a whole new project.
2. **scaffolding** — use repeatedly, for adding components (service, module, endpoint, skill, agent) INTO an already-initialized project.
3. These skills are complementary and non-overlapping. Never use project-scaffold on an existing project. Never use scaffolding to create the initial project skeleton.

## 5. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Running wizard on a directory with source files | Overwrites or misroutes existing work | Run `ls -A` check; abort if blockers present |
| Not using `ls -A` for the safety check | Plain `ls` hides dotfiles like `.env` | Always use `ls -A` |
| Inventing a new template structure | Creates divergence from maintained templates | Always copy from `templates/` and `templates/project-init/` |
| Leaving `<PLACEHOLDER>` values not listed in Step 4 | Broken docs that mislead future contributors | List every unfilled placeholder explicitly |
| Skipping `docs/plans/active` or `docs/plans/completed` | Breaks backlog references in CLAUDE.md and BACKLOG.md | Always create both subdirs |

## 6. Critical Rules

1. NEVER write any file before running `ls -A` on the target directory.
2. NEVER abort for benign pre-existing files (`.git/`, `.gitignore`, `LICENSE`, `README.md`, `.github/`, `.DS_Store`) — skip or rename, never clobber.
3. ALWAYS reuse templates from `templates/` and `templates/project-init/` — do not invent new structure.
4. MUST substitute every placeholder for which a value was gathered; any placeholder with no gathered value MUST be explicitly listed in Step 4 so the user completes it.
5. MUST create both `docs/plans/active/` and `docs/plans/completed/` directories.
6. NEVER use this skill on a project that already contains source files.
7. ALWAYS refer the user to `scaffolding` skill for component-level work after initialization.

## 7. Quick Reference

| Output path | Source template |
|-------------|----------------|
| `CLAUDE.md` | `templates/project-init/CLAUDE.md` |
| `README.md` | `templates/project-init/README.md` |
| `.gitignore` | `templates/project-init/dot-gitignore` |
| `docs/SYSTEM.md` | `templates/project-init/SYSTEM.md` |
| `docs/CONVENTIONS.md` | `templates/CONVENTIONS.md` |
| `docs/ARCHITECTURE.md` | `templates/ARCHITECTURE.md` |
| `docs/BACKLOG.md` | `templates/BACKLOG.md` |
| `docs/CHANGELOG.md` | `templates/CHANGELOG.md` |
| `docs/adr/000-adr-template.md` | `templates/adr-template.md` |
| `docs/plans/active/` | (empty, `.gitkeep`) |
| `docs/plans/completed/` | (empty, `.gitkeep`) |
| `docs/specs/` | (empty, `.gitkeep`) — `brainstorming` writes specs here |

Related skills: `brainstorming` + `writing-plans` (the spec → plan next step), `scaffolding`, `claudemd-engineering`, `decision-context`, `conventions-enforcer`.
