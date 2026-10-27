# Git conventions for this project

> Project-specific copy of the canonical rules. Edit the placeholders below; the canonical reference lives in the skill's `resources/knowledge-base/GIT_WORKFLOW.md`.

## Branch naming

```
<type>/<short-description-hyphenated>[-<TASK-ID>]
```

- `<type>` ∈ `feat` | `fix` | `chore`
- `<short-description-hyphenated>` — lowercase, 3–6 hyphenated words.
- `<TASK-ID>` — optional. Project-management tool: <PM tool name, e.g. JIRA / ClickUp / Linear / none>. Format: <e.g. `PROJ-NNN`, leave blank if unused>.

Examples:
- `feat/<example>-<TASK-ID>`
- `fix/<example>`
- `chore/<example>`

## Commit messages

- One subtask per commit (or a tightly-coupled group with each subtask listed in the description).
- Title = subtask name verbatim.
- **No Co-Authored-By trailers.** Ever.
- Optional prefix for this project: see `.claude/knowledge/decisions/0001-commit-prefix.md`.

## QA gates

Before every commit:
1. Run automated tests: `<command, e.g. npm test>`
2. Run automated QA: `<command, e.g. npm run lint && npm run typecheck>`
3. Human QA — agent prompts user; user confirms.

## PR workflow

When the task branch is complete:
1. Push: `git push -u origin <branch>`
2. Open PR via `gh pr create` with body that includes:
   - Summary (one paragraph)
   - Link to archived plan in `.claude/knowledge/plans/archive/`
   - Decision file paths in `.claude/knowledge/decisions/`
   - Test-plan checklist for reviewers
3. Request human **Code Review** and **QA**.

## Hard rules

- No `Co-Authored-By:`.
- No `--no-verify`.
- No `--amend` or force-push without explicit user request.
- No combining unrelated subtasks in one commit.
- No branching off a dirty working tree without confirmation.
