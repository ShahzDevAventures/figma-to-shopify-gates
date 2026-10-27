# `.claude/knowledge/` — Local Knowledge Base

This folder is maintained by Claude Code skills (`frontend-product-implementation`, `figma-shopify-theme-implementation`). It survives across sessions so the agent doesn't re-derive the same context every time.

## Layout

| Path | Purpose |
|---|---|
| `glossary.md` | Flat list of domain terms and project-specific definitions. |
| `architecture/` | `overview.md`, `modules.md`, `data-flow.md`. High-level structure. |
| `technologies/` | `stack.md`, `constraints.md`. What's used and why. |
| `conventions/` | `git.md` (branch / commit / PR rules). Extensible for future conventions (lint, naming, etc.). |
| `design/` | `tokens.md`, `tokens.json`, `components.md`, `interactions.md`, `typography.md`. Visual language. |
| `decisions/` | `NNNN-slug.md`. ADR-style records with `status: assumed \| decided \| superseded` frontmatter. |
| `plans/` | `current.md` (active plan) + `archive/<date>-<slug>.md` (past plans). |
| `tasks.md` | Live task list with `## Todo`, `## In progress`, `## Done` sections. |
| `runs/` | **Gitignored.** Per-session scratch space. |
| `extraction/figma/` | Cached Figma MCP responses. `manifest.json` is the index; `raw/` holds JSON; `screenshots/` is gitignored. |

## What gets committed

- All markdown and JSON in this folder, **except**:
  - `runs/` — only json/md/csv/txt/png (<500 KB) are tracked; video/HAR/trace/node_modules stay ignored (v4.1, after one rebuild's 1.6 GB evidence commit).
  - `extraction/*/screenshots/` (gitignored — large binaries, regenerable).

If your project's `.gitignore` ignores `.claude/` wholesale, whitelist with:

```
!.claude/knowledge/**/*.md
!.claude/knowledge/**/*.json
```

## Decisions vs assumptions

A decision file with `status: assumed` is the agent's best guess pending user confirmation. When confirmed, the agent flips the status to `decided` in place — no rename. Supersession sets `status: superseded` and the new record points back via `supersedes: NNNN`.

## Merge conflicts

- `tasks.md`: flat lists under each header — line-level resolvable.
- `extraction/figma/manifest.json`: keyed by stable cache-key — entries merge additively.
- `design/tokens.json`: additive merge by token path; agent surfaces conflicts when `last_writer` differs.

## Refreshing cached Figma data

Pass `refresh figma` (or `re-fetch <node>`) to invalidate matching manifest entries on the next run. By default the agent reads from cache whenever an entry exists.
