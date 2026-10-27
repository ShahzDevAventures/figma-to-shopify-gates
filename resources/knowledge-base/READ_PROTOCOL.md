# Read-Before-Write Protocol

A hard step at the start of every skill run, **after bootstrap, before planning or any MCP call.**

## Always read (cheap, small)

- Root `CLAUDE.md` — but only the content inside the `<!-- claude-kb:index:start -->` … `<!-- claude-kb:index:end -->` markers.
- `.claude/knowledge/README.md`
- `.claude/knowledge/glossary.md`
- `.claude/knowledge/technologies/stack.md`
- `.claude/knowledge/conventions/git.md` — branch/commit/PR rules for this project.
- All files in `.claude/knowledge/decisions/` whose frontmatter has `status: decided` or `status: assumed`. Skip `superseded`. (This includes `0001-commit-prefix.md`, which governs commit-message prefix.)
- `.claude/knowledge/plans/current.md`
- `.claude/knowledge/tasks.md`

## Read on demand

Per skill, when relevant to the request:

- **frontend-product-implementation**: `architecture/overview.md`, `architecture/modules.md`, `design/components.md`.
- **figma-shopify-theme-implementation**: `design/tokens.md`, `design/tokens.json`, `design/interactions.md`, `design/typography.md`, `extraction/figma/manifest.json`, `architecture/f2s_registry.md` (the code contract — read before modifying any `f2s_` file), `SHOPIFY_BEST_PRACTICES.md` (Shopify mechanics — read before building any data-driven section).

## Summarize before acting

After the read pass, the agent must produce a one-paragraph summary back to the user covering:

1. What the project is (from CLAUDE.md / glossary).
2. What's already decided that bears on the current request (cite decision IDs).
3. What's currently in flight (`tasks.md` In-progress section, `plans/current.md`).
4. What looks stale or contradictory.

This is the user's chance to correct the agent's mental model before any planning question is asked.

## Write order rule

During a single run, **only these paths may be written**:

- `tasks.md` — append/update todos as work proceeds.
- `plans/current.md` — refine the active plan.
- `runs/` — per-run evidence. json/md/csv/txt/png (<500 KB) are committed; video/HAR/trace/node_modules are ignored (BOOTSTRAP.md step 3, v4.1).
- `extraction/` — Figma cache writes (see `FIGMA_CACHE.md`).

These paths are **only updated at phase boundaries** (end of plan-mode; end of a logical implementation phase; end of a page or feature):

- `architecture/`
- `design/` (except `runs/` scratch)
- `decisions/`
- `glossary.md`
- `technologies/`
- Root `CLAUDE.md` (managed block)

This keeps git history readable: one commit per phase boundary contains all the durable knowledge captured during that phase.

## Cross-skill collision guard

Files that both skills may write (notably `design/tokens.md`, `design/tokens.json`, `architecture/overview.md`):

- Each shared markdown file has frontmatter:
  ```yaml
  ---
  last_writer: <skill-name>
  last_written: <ISO8601>
  ---
  ```
- Each shared markdown file ends with a `## Sources` subsection listing per-block authorship:
  ```
  ## Sources
  - frontend-product-implementation, 2026-05-07: tokens.color.brand.*
  - figma-shopify-theme-implementation, 2026-05-08: tokens.spacing.*
  ```
- If `last_writer` differs from the current skill, **append, don't overwrite.** Surface the conflict to the user explicitly:
  > `design/tokens.md` was last written by `<other-skill>` on `<date>`. I'm appending; resolve manually if needed.

For `tokens.json`, treat it as an additive merge keyed by token path. Never delete a key written by another skill without user confirmation.

## Decision/assumption status flips

When the user confirms a previously-assumed decision, **flip the status field in place** — do not rename the file. Same for supersession:

```yaml
---
id: 0007
title: Use Tailwind v4 over v3
status: superseded   # was: decided
date: 2026-05-07
superseded_by: 0012
---
```

The new superseding decision points back via `supersedes: 0007`.

## When the agent must re-read

If a single run spans multiple long phases (e.g. plan → implement → verify across hours of work), re-read the always-read set at the start of each phase. Decisions may have been recorded mid-run; the agent must not act on a stale snapshot.
