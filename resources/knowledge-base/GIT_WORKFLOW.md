# Git Workflow Protocol

Strict, non-negotiable rules for branch, commit, and PR behavior. The point is to enable parallelism: multiple agents and/or developers working on the same project simultaneously without stepping on each other.

## Hard rules (MUST)

1. **Never** include `Co-Authored-By:` (or any "Co-authored" mention) in commits or PR bodies. Strip the default Claude trailer; never emit one.
2. **Never** push without all subtasks committed and all QA gates passed for each.
3. **Never** combine unrelated subtasks in a single commit.
4. **Never** bypass tests/QA to expedite a commit (no `--no-verify`).
5. **Never** amend or force-push without explicit user request.
6. **Never** create a branch on top of a dirty working tree without user confirmation.
7. **Never** open a PR to `main` from `main` itself (refuse and start a branch).

## Branch naming

```
<type>/<short-description-hyphenated>[-<TASK-ID>]
```

- `<type>` ∈ `feat` | `fix` | `chore` (only these three)
- `<short-description-hyphenated>` — lowercase, hyphenated, 3–6 words, no scope-prefix punctuation
- `<TASK-ID>` — appended **only** when the user references a project-management ticket (JIRA, ClickUp, Linear, etc.). Preserve original casing (e.g. `CALC-033`)

### Type selection

- `feat` — new functionality, new pages, new sections, new components.
- `fix` — bug repair, regression patch, broken-state recovery.
- `chore` — dependency upgrades, refactors with no behavior change, tooling, KB scaffolding.

### Examples

- `feat/calculatorlist-pagination-CALC-033`
- `fix/userpanel-form-responsiveness`
- `chore/upgrade-tailwind-to-v4`

## Commit conventions

- **One subtask → one commit.** A commit may bundle multiple subtasks **only** when their interdependence is unambiguous (e.g. introducing a type and its first user — splitting would break the build).
- **Title** = the subtask name verbatim. For grouped commits: a short combined name in the title; one bullet per subtask in the description.
- **Description** is omitted for single-subtask commits.
- **No trailers.** No `Co-Authored-By:`, no `Signed-off-by:` unless the user has set up signing intentionally.
- **Optional per-project prefix.** If a non-empty prefix is configured at `.claude/knowledge/decisions/0001-commit-prefix.md`, prepend `<prefix> ` to every commit title (e.g. `f2s: add hero section`). Default: no prefix.

### Examples

Single subtask:

```
add cart drawer component
```

Grouped subtasks (tightly coupled):

```
introduce CartItem type and first usage

- add CartItem type
- wire CartItem into cart drawer
```

With configured prefix `f2s:`:

```
f2s: add cart drawer component
```

## QA gates (must pass before any commit)

In order, no skipping:

1. **Automated tests** — the project's test command (`npm test` / `bun test` / `pnpm test` / `pytest` / `theme check` / etc.). Detect from the project's package manifest or build config.
2. **Automated QA** — lint, type-check, formatter, schema validators. Detect via `package.json` scripts (`lint`, `typecheck`, `format:check`), `tsconfig.json`, or stack-specific tools (Shopify `theme check`, ESLint, Stylelint, Prettier).
3. **Human QA** — agent prompts the user to spot-check the subtask in the running app/preview. Wait for explicit confirmation before staging.

If any gate fails, **fix** the underlying issue and re-run all gates. Never commit on a failing gate.

## Per-task workflow

### 1. Plan approved

Plan exists at `.claude/knowledge/plans/current.md`. User has approved (in conversation, via `ExitPlanMode`, or implicit on a quick task).

### 2. Create branch

```bash
git checkout main
git pull --ff-only
git checkout -b <branch>
```

If `git status --porcelain` shows uncommitted changes on `main`, stop and ask the user. Do **not** stash silently.

Update `.claude/knowledge/tasks.md` In-progress section with the new branch name and (if known) the agent owner:

```
## In progress
- [ ] R-007 Implement pagination — owner: agent-A, branch: feat/calculatorlist-pagination-CALC-033, started: 2026-05-07
```

### 3. Subtask loop

For each subtask listed in `plans/current.md`:

1. Implement the subtask end-to-end.
2. Run automated tests + automated QA. If anything fails, fix and re-run until green.
3. Ask the user for human-QA sign-off — explicitly. Wait for confirmation. (Browser preview, manual flow check, theme inspector, etc.)
4. Stage **only** the files for this subtask:
   ```bash
   git add <files>
   ```
   Never `git add -A` or `git add .` — too easy to capture stray files.
5. Commit. Compose the message per the rules above. Pass via heredoc to preserve formatting:
   ```bash
   git commit -m "$(cat <<'EOF'
   <commit title>

   <description bullets if grouped>
   EOF
   )"
   ```
   No `Co-Authored-By:` line. No `--amend`. No `--no-verify`.
6. Move the line in `tasks.md` from `## In progress` to `## Done`.

### 4. Task completion

After the last subtask commits:

1. Push:
   ```bash
   git push -u origin <branch>
   ```
2. Open a PR via `gh pr create`:
   ```bash
   gh pr create --title "<task title>" --body "$(cat <<'EOF'
   ## Summary

   <one-paragraph description of what shipped>

   ## Plan

   - `.claude/knowledge/plans/archive/<YYYY-MM-DD>-<slug>.md`

   ## Decisions made

   - `.claude/knowledge/decisions/NNNN-...md`

   ## Test plan

   - [ ] <reviewer-facing check 1>
   - [ ] <reviewer-facing check 2>
   EOF
   )"
   ```
   The body **must not** contain any "Co-authored" reference, any `🤖 Generated with` line, or any other auto-attribution.
3. Tell the user the PR URL and explicitly request human **Code Review** and **QA** before merge.

## Parallelism support

- Each task lives on its own branch off `main`. Multiple agents or developers can run concurrently with no in-flight collision.
- `tasks.md` records owner + branch for in-progress tasks so two parties don't grab the same item.
- Shared KB files (`design/tokens.md`, `architecture/overview.md`, `extraction/figma/manifest.json`) keep their existing collision guards: `last_writer` frontmatter, append-don't-overwrite, additive manifest merges.
- A long-running task that depends on another in-flight task should rebase or wait for the other PR to merge — never edit the other branch.

## What gets persisted to the KB

- `tasks.md` — owner/branch/started annotations on In-progress items; lines move to Done after each commit.
- `decisions/0001-commit-prefix.md` — first-run answer to "what commit prefix should this project use?" (empty allowed).
- `decisions/NNNN-*.md` — any non-trivial choice made during the task.
- `plans/archive/<date>-<slug>.md` — the just-completed plan, archived from `plans/current.md`.
- `conventions/git.md` — project-specific copy of these rules with concrete examples (TASK-ID format, prefix value, etc.). Seeded from `templates/conventions/git.md`.

## Failure modes to guard against

- **Test failure mid-task.** Do not commit a partial fix and move on. Fix the failure, re-run gates, then commit.
- **Pre-commit hook failure.** Investigate; fix the underlying issue. Do **not** pass `--no-verify`. Create a new commit (not `--amend`).
- **PR template injecting Co-authored content.** If the repo has a `.github/pull_request_template.md`, the agent must remove any auto-attribution before opening the PR.
- **Dirty `main`.** Always check `git status` before branching. Never stash without telling the user.
- **Two agents on the same task.** Read `tasks.md` In-progress before starting. If the same task is already owned, pick another or coordinate via the user.
