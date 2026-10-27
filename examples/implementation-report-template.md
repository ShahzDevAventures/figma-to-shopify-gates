# Implementation Report: <Page Name>

> **KB-aware:** in the target theme repo, persist a copy of this report at `.claude/knowledge/plans/archive/<YYYY-MM-DD>-<page-slug>.md` once the page ships. Update `.claude/knowledge/tasks.md` (move tasks from `## In progress` to `## Done`). Promote any new convention into the root `CLAUDE.md` Conventions list (see `../resources/knowledge-base/CLAUDE_MD_RULES.md`); promote new tokens, components, or interactions into the `design/` folder.

**Branch**: `<type>/<short-description>[-<TASK-ID>]`
**PR URL**: <opened via `gh pr create` after the last subtask commits — no `Co-Authored-By:` in body>

## Completed

- ...

## Files Added

- ...

## Files Modified

- ...

## Figma Mapping

| Figma Section | Shopify Section | Data Source | Notes |
|---|---|---|---|
| ... | ... | ... | ... |

## App-Backed Sections

| Figma Section | App | Original Location | New Wrapper | Duplicate Removed |
|---|---|---|---|---|
| ... | ... | ... | ... | yes/no |

## Content Source Decisions

| Content | Source | Reason |
|---|---|---|
| ... | ... | ... |

## Interactions

| Section | Interaction | Implementation |
|---|---|---|
| ... | ... | ... |

## Validation

- JSON templates valid: yes/no
- Liquid syntax checked: yes/no
- Theme check/lint: passed/failed/not available
- Mobile checked: yes/no
- Desktop checked: yes/no

## Performance Notes

- ...

## Commits Created

One per subtask (or one grouped commit per tightly-coupled group). Titles = subtask names; description bullets list each subtask if grouped. Per-project prefix from `decisions/0001-commit-prefix.md` is prepended when non-empty. **No `Co-Authored-By:` trailers anywhere.**

- `<commit subject 1>`
- `<commit subject 2>`
- ...

## Git workflow checks

- [ ] All subtask commits passed automated tests + automated QA + human QA before staging
- [ ] No `Co-Authored-By:` trailers in any commit (`git log --format=%B <branch> ^main | grep -i "co-authored"` returns empty)
- [ ] No `--amend`, `--no-verify`, or force-push used (unless user explicitly requested)
- [ ] Branch pushed only after the last subtask commit
- [ ] PR opened via `gh pr create` with: summary, plan-archive link, decisions list, reviewer test plan
- [ ] User notified of PR URL with explicit request for human Code Review and QA

## Knowledge base updates

- [ ] `design/tokens.md` / `tokens.json` updated (with `last_writer` and `## Sources`)
- [ ] `design/components.md` updated for any new repeated component
- [ ] `design/interactions.md` updated for any new interaction
- [ ] `decisions/NNNN-*.md` written for any decision with consequences (status `decided`)
- [ ] `assumed`-status decisions reviewed; flipped to `decided` or `superseded` where appropriate
- [ ] `plans/current.md` archived to `plans/archive/<date>-<slug>.md`
- [ ] `tasks.md` updated (`## In progress` → `## Done`)
- [ ] `extraction/figma/manifest.json` records every node consumed during this page (`consumed_by` field)
- [ ] Root `CLAUDE.md` managed block updated only if a project-wide convention or KB index entry changed
- [ ] `CLAUDE.md` line count under the 150-line soft cap
