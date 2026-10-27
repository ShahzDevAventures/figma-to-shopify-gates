# When to Update CLAUDE.md vs a Deeper KB File

CLAUDE.md is the **index, not the content.** Claude Code auto-loads it at session start, so it must stay small and high-signal. Keep it under ~150 lines (soft cap; warn at end-of-run if exceeded).

## Trigger rules

| Trigger | CLAUDE.md? | KB file? |
|---|---|---|
| New domain term used twice | No | `glossary.md` |
| New cross-cutting convention (file naming, lint rule, commit prefix like `f2s_`) | **Yes** | mirror in `architecture/overview.md` if structural |
| Project commit prefix configured (non-empty) | **Yes** (one Conventions bullet: `Commit prefix: <prefix>`) | `decisions/0001-commit-prefix.md` |
| Project commit prefix is empty / "none" | No | `decisions/0001-commit-prefix.md` (still recorded as the answered decision) |
| Branch-naming spec or PR workflow tweaked for this project | No (general rule lives in `conventions/git.md`) | `conventions/git.md` |
| New module / feature folder | No | `architecture/modules.md` |
| New tech / library adopted | No | `technologies/stack.md` |
| Design token added/changed | No | `design/tokens.md` + `tokens.json` |
| Decision with consequences | No | `decisions/NNNN-*.md` |
| Renaming project, changing high-level mission | **Yes** | No |
| First-time bootstrap | **Yes** (create) | Yes (seed all, including `conventions/git.md` and prefix decision) |
| Adding a new top-level KB folder | **Yes** (update index) | Yes (the folder itself) |
| Marking the project as archived / read-only | **Yes** (banner inside markers) | No |

## One-line heuristic

> CLAUDE.md changes when the **map** changes. KB files change when the **territory** changes.

If a fact would matter to a human reading the project for the first 5 seconds, it goes in CLAUDE.md. Everything else goes deeper.

## What lives inside the managed block

The managed block in `CLAUDE.md` (between `<!-- claude-kb:index:start -->` and `<!-- claude-kb:index:end -->`) contains, in order:

1. **One-line description.** Project name + what it is.
2. **Two-sentence summary.** What it does, who it's for.
3. **Stack line.** Primary language(s), framework(s), runtime. One line.
4. **Conventions.** 3–8 bullets — project-wide rules the agent must obey on every turn (file naming, commit prefix, lint policy, etc.). Add a bullet only when a convention is genuinely cross-cutting.
5. **Knowledge base index.** Pointer table:
   ```
   - Architecture: .claude/knowledge/architecture/overview.md
   - Tech stack: .claude/knowledge/technologies/stack.md
   - Conventions: .claude/knowledge/conventions/git.md
   - Design tokens: .claude/knowledge/design/tokens.md
   - Decisions: .claude/knowledge/decisions/
   - Active plan: .claude/knowledge/plans/current.md
   - Tasks: .claude/knowledge/tasks.md
   - Glossary: .claude/knowledge/glossary.md
   ```
6. **Open questions** (optional). Up to 3 high-priority ambiguities the user needs to resolve. If a question is answered, demote it into a decision and remove it here.

Anything outside the markers is human-owned. The agent **never** touches it.

## Soft cap enforcement

At end of every run, count lines in `CLAUDE.md`. If > 150, surface a warning:

> CLAUDE.md is at <N> lines. Consider demoting Conventions or Open Questions into `architecture/overview.md` or `decisions/`.

The agent must not silently truncate. Demotion is a deliberate act with the user's consent.

## What does **not** belong in CLAUDE.md

- Detailed architecture descriptions (→ `architecture/`).
- Long lists of dependencies with versions (→ `technologies/stack.md`).
- Decision rationale (→ `decisions/NNNN-*.md`).
- Per-feature plans or task lists (→ `plans/`, `tasks.md`).
- Anything that changes more often than weekly.
