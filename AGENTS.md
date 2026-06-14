# AI Agent Instructions

This file is the single source of truth for all AI coding assistants working on this project.
Tool-specific files (`CLAUDE.md`) point here.

## Product

<!-- TODO: One paragraph describing this project — what it is, who uses it, the platform/runtime target, and any defining constraints (single- vs multi-user, sandboxed or not, deployment target, scale). -->

## Project Phase

<!-- TODO: Current status of each app/package. -->
- **<app/package name>**: TODO — what's built, what's tested.

## Development Rules

### Two-Step Confirmation First
- Never start the moment a requirement is stated or changed. Every new or modified requirement first passes through an understand-and-confirm step before any code is written. The only exception is trivial mechanical actions whose intent is obvious (e.g. `git push`, fixing a typo, a one-line rename).
- **Step one — reflect and surface, always in the open before building:**
  - Judge whether the request is sound: is it safe? is it efficient? does it fit the project's scale?
  - Consider whether a better approach exists than the one asked for.
  - State your full understanding of the request, your analysis of it (risks, tradeoffs, anything ill-advised), and your concrete recommendation.
- **Step two — act on the outcome:**
  - If the request is uncertain (multiple approaches with tradeoffs, may affect other features, or ill-suited to the project's scale), wait for the user's confirmation before modifying code.
  - If there is a clearly optimal and safe path, you may proceed without waiting for confirmation — but conspicuously notify the user that you are doing so up front, and on completion state plainly what you changed and why it was the better path.
  - Push back on any request that compromises security, correctness, or runtime efficiency, even when explicitly asked.

### Scope Discipline
- Each task must stay within its stated scope. Do not add, refactor, or "improve" anything outside the current request.
- If the current task logically depends on another unbuilt feature, ask the user before implementing it. Never silently introduce adjacent functionality.

### Coding Standards
<!-- TODO: Replace the bullets below with this project's real standards. Keep each one concrete and enforceable, not a platitude. Delete what doesn't apply. -->
- **Source of truth & persistence**: TODO — the single source of truth for state, and how/where it is persisted.
- **Architecture & boundaries**: TODO — module/layer boundaries, dependency injection, what must stay free of UI/framework imports so it remains testable.
- **Language / framework conventions**: TODO — follow existing conventions; note key idioms and any banned APIs or patterns.
- **Security boundary**: TODO — the project's trust boundary; never execute downloaded or arbitrary code; never expose a control surface beyond the intended users.

### Verify & Commit
- After any code change, run the project's verification (e.g. type-check / build / lint) across all affected packages.
- If verification fails, fix the errors first, then verify again.
- After verification passes, automatically commit files that were modified by the agent in the current task and belong to the current task.
- Before committing, inspect dirty files and separate current-task agent edits from unrecognized dirty files. Do not include unrecognized dirty files in commits unless the user explicitly asks to include them.
- If a dirty file's ownership or task relevance cannot be determined safely, stop and ask the user before committing.
- Group commits by coherent change unit. Do not push unless explicitly requested.
- Branching: per-feature work lands on a `feat/*` branch that merges into the mainline. Keep merged `feat/*` branches as historical archives — never delete them (local or remote).
- Commit message format (Conventional Commits):
  ```
  type(scope): short summary

  Detailed description of what changed and why.
  ```
  Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `ci`, `perf`.

### Session Handoff
- `notice.md` files are scoped by directory and record durable handoff information for the next agent.
- Root `notice.md` records global, cross-package, or cross-task project information.
- App/package notices record durable facts for that app/package: architecture, contracts, workflows, credentials, known limitations, and package-specific gotchas.
- Update the relevant `notice.md` only when the session creates or discovers information that remains useful beyond the current task or conversation. Do not record pure Q&A, routine progress, temporary decisions, or workflow session/journal details there.
- Ensure any `notice.md` you touch remains accurate and up-to-date within its directory scope.

### End-of-Session Summary
- At the end of each conversation, output a brief summary in 中文 (Chinese). This summary is user-facing.
  ```
  ## Summary
  - **Done**: work completed this round
  - **Key decisions**: tag each [user] or [self], explain the decision
  - **Commits**: list this round's commits (hash, message, files); note any dirty files left out and why
  - **Open/known risks**: issues introduced or discovered this round (omit if none)
  - **Suggested next steps**: 1-3 concrete actionable items
  ```
