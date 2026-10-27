---
id: 0001
title: Commit message prefix for this project
status: decided
date: <YYYY-MM-DD>
sources:
  - first-run prompt by skill
tags:
  - git
  - conventions
---

# Commit message prefix

## Decision

Use the prefix **`<prefix>`** (or leave empty for no prefix) on every commit title. Example: `<prefix> add hero section`.

If empty, commit titles start directly with the subtask name (e.g. `add hero section`).

## Context

Asked once at first invocation in this project. The agent prepends this prefix to every commit title for the lifetime of the project. To change, edit this file and flip `status` to `superseded`, then create a new decision (`0002-commit-prefix.md` or similar) pointing back via `supersedes: 0001`.

## Consequences

- Every commit on this project includes the prefix (or none if empty).
- The prefix is mirrored into the root `CLAUDE.md` Conventions list when non-empty (see `CLAUDE_MD_RULES.md`).
- File/CSS/JS prefixes are a separate concern — this decision only governs commit-message text.

## Alternatives considered

- **No prefix.** Cleanest history, least friction. Use this for personal projects or open-source repos with no project-management tool integration.
- **Project-name prefix** (e.g. `f2s:`). Useful when the repo houses multiple sub-projects or when historical convention demands it.
- **Conventional Commits scope-prefix** (e.g. `feat(cart): ...`). Out of scope for this project; the type already lives in the branch name.
