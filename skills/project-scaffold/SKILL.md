---
name: project-scaffold
description: "Bootstrap an empty directory into a project skeleton (docs, CLAUDE.md, .gitignore, README) — OR retrofit the missing documentation set into an existing project that lacks it. Two modes: Init (empty dir) and Retrofit (existing project, weak/missing docs)."
---

# Project Scaffold

## 1. Overview

1. This skill creates and maintains the documentation skeleton for a project. It has **two modes**:
   - **Init mode** — bootstrap a brand-new project from an empty directory (Sections 3-4).
   - **Retrofit mode** — fill the missing documentation set into an EXISTING project that already has source code but lacks proper docs (Section 8).
2. It covers: `CLAUDE.md`, `README.md`, `.gitignore`, `docs/SYSTEM.md`, `docs/CONVENTIONS.md`, `docs/ARCHITECTURE.md`, `docs/BACKLOG.md`, `docs/CHANGELOG.md`, and the `docs/plans/` + `docs/specs/` + `docs/adr/` directory seeds.
3. It does NOT scaffold source-code components (services, modules, endpoints, agents). Use the `scaffolding` skill for that.
4. **Init vs Retrofit is decided by the safety check (Step 2):** an empty/benign-only directory → Init; a directory with source files → Retrofit (never Init, which would misroute existing work).

## 2. When to Use

1. **Init mode** — user says: "new project", "bootstrap project", "/init-project", "init project", "empty repo", "create project skeleton"; AND the target directory is empty or contains only benign pre-existing files (Step 2 allowlist).
2. **Retrofit mode** — user says: "the docs are a mess", "no documentation here", "add the docs", "set up docs for this project", "retrofit docs", "this project has no CLAUDE.md/SYSTEM.md"; OR the `session-start` hook flagged that a project with source files is missing most of the standard doc set; AND the project already contains source files.
3. NEVER run **Init mode** on a project that already has source files — it is for empty dirs only. Use Retrofit mode instead.
4. For adding source-code components (services, modules, endpoints), use the `scaffolding` skill — that is orthogonal to both modes here.

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

### Step 2 — Safety check + mode routing (HARD prerequisite)

1. Run `ls -A <target>` to list all files including dotfiles.
2. If the directory does not exist or the listing is empty — proceed with **Init mode** (this wizard, Steps 3-4).
3. If the listing contains ONLY files from this allowlist — proceed with **Init mode** (never clobber them; skip writing if the file exists, or write `README.scaffold.md` instead of `README.md` and tell the user):
   - `.git/`, `.gitignore`, `LICENSE`, `LICENSE.md`, `README.md`, `.github/`, `.DS_Store`
4. If ANY file outside the allowlist is present (`package.json`, `pyproject.toml`, `go.mod`, `src/`, `*.ts`, `*.py`, `*.go`, any source or config file) — this is an EXISTING project. Do NOT run Init mode (it would misroute existing work). Switch to **Retrofit mode (Section 8)**, which adds only the missing docs without ever clobbering existing files.

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
   - **Scaffolded `docs/ARCHITECTURE.md` and `docs/CONVENTIONS.md` are STUBS, not documentation.** They carry the sentinel `> STATUS: TEMPLATE — not yet populated` and unfilled placeholders. For greenfield, this is the first structural work — they MUST be populated through the `brainstorming` Architecture Capture flow (decisions captured as ADRs during the interview, then projected into the docs by the orchestrator in-context) BEFORE any structural implementation. `scripts/check-arch-docs.sh <target>` mechanically verifies the stub markers are gone, and the Full+Architecture pipeline blocks IMPLEMENT until it passes (using-subteams Critical Rule 24). Do NOT begin building modules against a stub architecture doc — a confidently wrong or empty architecture doc is read as ground truth by `architecture-guard` and future sessions.
4. For adding source-code components later (services, modules, endpoints), use the `scaffolding` skill.

## 4. Relationship to `scaffolding` Skill

1. **project-scaffold (Init mode)** — use once, at project start, to create the documentation and config skeleton for a whole new project.
2. **project-scaffold (Retrofit mode)** — use on an existing project that has source code but lacks proper docs, to fill the gaps without clobbering anything.
3. **scaffolding** — use repeatedly, for adding source components (service, module, endpoint, skill, agent) INTO an already-initialized project.
4. These skills are complementary and non-overlapping. project-scaffold owns the documentation skeleton (create OR retrofit); scaffolding owns source components. Never use scaffolding to create or repair the documentation skeleton.

## 5. Red Flags

| Pattern | Why It Is Wrong | Correct Action |
|---------|-----------------|----------------|
| Running wizard on a directory with source files | Overwrites or misroutes existing work | Run `ls -A` check; abort if blockers present |
| Not using `ls -A` for the safety check | Plain `ls` hides dotfiles like `.env` | Always use `ls -A` |
| Inventing a new template structure | Creates divergence from maintained templates | Always copy from `templates/` and `templates/project-init/` |
| Leaving `<PLACEHOLDER>` values not listed in Step 4 | Broken docs that mislead future contributors | List every unfilled placeholder explicitly |
| Skipping `docs/plans/active` or `docs/plans/completed` | Breaks backlog references in CLAUDE.md and BACKLOG.md | Always create both subdirs |
| Overwriting a populated `CLAUDE.md`/`README.md` during retrofit | Destroys real project knowledge | Retrofit only fills gaps; never clobber content (Section 8) |
| Running Init mode on a repo with source files | Misroutes existing work, may clobber | Route to Retrofit mode (Step 2 → Section 8) |

## 6. Critical Rules

1. NEVER write any file before running `ls -A` on the target directory.
2. NEVER abort for benign pre-existing files (`.git/`, `.gitignore`, `LICENSE`, `README.md`, `.github/`, `.DS_Store`) — skip or rename, never clobber.
3. ALWAYS reuse templates from `templates/` and `templates/project-init/` — do not invent new structure.
4. MUST substitute every placeholder for which a value was gathered; any placeholder with no gathered value MUST be explicitly listed in Step 4 so the user completes it.
5. MUST create both `docs/plans/active/` and `docs/plans/completed/` directories (Init mode).
6. In **Init mode**, NEVER run on a project that already contains source files — route to Retrofit mode (Section 8) instead.
7. In **Retrofit mode**, NEVER overwrite or truncate an existing doc that has real content — only create absent files or replace empty/near-empty stubs, and ask before touching anything non-trivial.
8. ALWAYS refer the user to `scaffolding` skill for source-component work.

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

## 8. Retrofit Mode (existing project, missing/weak docs)

Use when a project already has source code but its documentation is missing, sparse, or stub-only. Retrofit is **additive and non-destructive** — it never overwrites real content. New projects are not the only ones that lack docs; this mode brings an existing codebase up to the documentation baseline.

### Step R1 — Audit the existing doc set

1. Run `ls -A <target>` and check `docs/`. For each file in the standard set (Section 7 Quick Reference), classify it as:
   - **Present & substantive** — exists with real content → LEAVE UNTOUCHED.
   - **Stub** — missing, empty, or near-empty (< ~5 non-boilerplate lines, or only an unfilled template) → candidate to fill.
2. Read each present-but-thin doc before judging — do not assume from filename. A short but real `README.md` is substantive; an autogenerated empty one is a stub.
3. Produce a gap report: which standard docs are missing, which are stubs, which are fine. Show it to the user before writing anything.

### Step R2 — Infer real values (do not invent)

1. Derive `<PROJECT_NAME>`, `<STACK>`, `<FRAMEWORKS>`, `<DATABASE>`, commands, etc. from the actual repo: `package.json`/`pyproject.toml`/`go.mod`, lockfiles, existing scripts, README fragments, source layout.
2. For anything not inferable with confidence, leave the `<PLACEHOLDER>` and list it for the user — NEVER fabricate architecture, goals, or commands the code does not show.
3. For `SYSTEM.md`/`ARCHITECTURE.md`, describe only what the code actually demonstrates; mark unknowns as "TBD — confirm with maintainer."

### Step R3 — Fill gaps only (non-destructive write)

1. Create ONLY the missing or stub files, from the same templates as Init mode (Section 7).
2. NEVER overwrite or truncate a substantive existing doc. If a doc is thin but has real content, propose additions as a diff and ask before applying.
3. If a file exists as a real doc but in the wrong place (e.g. `CHANGELOG.md` at root vs `docs/`), do not move it silently — note it in the gap report and ask.
4. Create any missing `docs/plans/{active,completed}/`, `docs/specs/`, `docs/adr/` seeds (these are safe — empty dirs).

### Step R4 — Confirm and summarize

1. Print what was created vs left untouched vs flagged-for-user.
2. List every unfilled `<PLACEHOLDER>` for the user to complete.
3. **If `docs/SYSTEM.md` or `docs/ARCHITECTURE.md` were generated, a `doc-agent` audit pass against the actual code is REQUIRED before they count as done** — these two files describe architecture and are the ones a model is most tempted to narrate plausibly-but-wrongly. A confidently wrong architecture doc is worse than no doc: future sessions read it as ground truth. Other generated docs (BACKLOG, CHANGELOG, CONVENTIONS) get an optional `doc-agent` audit; `decision-context` applies going forward.

### Retrofit Critical Rules

1. NEVER overwrite or truncate a doc with real content. Gaps-only.
2. NEVER fabricate facts the code does not support — leave placeholders and flag them. For SYSTEM.md/ARCHITECTURE.md, describe ONLY what the code demonstrably shows; everything else is "TBD — confirm with maintainer."
3. ALWAYS show the gap report and get the go-ahead before writing ANY file — not only borderline ones.
4. When a doc is borderline (thin but real), ask — do not decide to overwrite for the user.
5. A generated `SYSTEM.md`/`ARCHITECTURE.md` is NOT done until a `doc-agent` audit has checked it against the real code (Step R4.3).

Related skills: `brainstorming` + `writing-plans` (the spec → plan next step), `scaffolding`, `claudemd-engineering`, `decision-context`, `conventions-enforcer`.
