
---

## v4 install (2026-08-13) — MANDATORY, run before anything else in this file

<!-- Was headed "v2 additions (2026-07-03)" and never revised for v3, which is how v3's
     pattern-library sync went missing: SKILL.md named a source no step here ever fetched. -->

**`.claude/settings.json` is NOT installed here — it is installed at step 0 of `/build-page`,
before any command runs.** v3 installed it in this file, at step 1, which meant you needed
permission to run the bootstrap that installed the permissions. That chicken-and-egg is why runs
sat prompting.

1. **Install the machinery into the target repo** (idempotent copy from the skill):
   - `resources/scripts/*` → `.claude/scripts/` (chmod +x)
   - `resources/agents/*` → `.claude/agents/`
   - `resources/commands/build-page.md` → `.claude/commands/`
   - `resources/knowledge-base/*.md` → `.claude/knowledge-base/` — **v4, and load-bearing.**
     v3 never copied these, so `PARITY_VERIFY.md` (the canonical QA rubric) and
     `SHOPIFY_BEST_PRACTICES.md` were unreachable at runtime. The verifier fell back to a
     shortened restatement embedded in its own instructions that silently dropped the
     Shopify-mechanics and naming checks; the builder was told to read a path that existed
     nowhere. Agents cite these by path — if they are not installed, the citations are dead.
   - `resources/knowledge-base/templates/*` → `.claude/knowledge/templates/`
   - `resources/templates-v2/MANUAL_SCRIPTS` → `.claude/scripts/MANUAL_SCRIPTS` (the allowlist for
     scripts no gate invokes on purpose; preflight warns about every script that isn't listed here
     and isn't run by something)
   - `resources/templates-v2/routing.json` → `.claude/routing.json` (do not overwrite an existing one)
   - `resources/templates-v2/settings.json` → `.claude/settings.json` (do not overwrite an existing
     one; MERGE its `permissions.allow`/`deny` into any file already there). **Commit it.** This is
     what allows a run to complete unattended: without it the operator is prompted for approval on
     every script, commit and push, which is the difference between "launch it and review the PR"
     and "babysit it for two hours". It is an allowlist plus a deny list for the genuinely
     irreversible (force push, --no-verify, publishing a live theme, pr merge) — never a blanket
     bypass, because those few things SHOULD interrupt someone.
   - `docs/patterns/` from the boilerplate → `.claude/knowledge/patterns/` (the build ladder reads these)
   - `tests/fixtures/` → `.claude/scripts/tests/fixtures/` (the self-test needs them locally)
2. **Arm the hooks for this run:** `sh .claude/scripts/f2s_hooks_mode.sh agent`.

   The repo may be in MAINTAINER mode — the handoff step at the end of every run disarms the hooks
   so the developer who owns the code afterwards is not gated on their own commits. That is
   deliberate: `core.hooksPath` lives in the repo, not in the skill, so a human running `git commit`
   gets the agent's doors whether or not any skill is loaded. Bootstrap re-arms; handoff disarms;
   the mode follows whoever is driving. `f2s_hooks_mode.sh status` says which state you are
   in, and preflight blocks if the hooks are not armed when a run starts.

   Mechanically this is `git config core.hooksPath .claude/hooks` plus writing `.claude/hooks/pre-commit`
   as `#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.claude/scripts/f2s_precommit.sh" "$@"`
   plus `.claude/hooks/commit-msg` as
   `#!/bin/sh\nexec sh "$(git rev-parse --show-toplevel)/.claude/scripts/f2s_precommit.sh" --commit-msg "$@"`.
   chmod +x both. The `--commit-msg` flag is load-bearing (decision 0037): without it the script
   tested `[ -f "$1" ]`, never matched, and the message doors D6/D7 (no trailers, decided prefix)
   silently never ran on any commit of that run.
3. **Evidence is committed (reverses v1) — but only the light kinds (v4.1):** append these rules,
   in this order — do not delete existing .gitignore entries:
   ```
   !.claude/knowledge/extraction/figma/screenshots/
   !.claude/knowledge/extraction/figma/raw/
   .claude/knowledge/runs/**
   !.claude/knowledge/runs/**/
   !.claude/knowledge/runs/**/*.json
   !.claude/knowledge/runs/**/*.md
   !.claude/knowledge/runs/**/*.csv
   !.claude/knowledge/runs/**/*.txt
   !.claude/knowledge/runs/**/*.png
   .claude/knowledge/runs/**/node_modules/
   .claude/knowledge/runs/**/.playwright/
   .claude/knowledge/runs/**/*.webm
   .claude/knowledge/runs/**/*.mp4
   .claude/knowledge/runs/**/*.har
   .claude/knowledge/runs/**/*.trace
   ```
   v4 wrote `!.claude/knowledge/runs/` — one line that un-ignored EVERYTHING under runs/. One rebuild
   committed 7,052 run files (1.6 GB): Playwright videos, HAR captures, trace zips, a vendored
   `node_modules/` under a preview harness. The shape above is proven with `git add -n`: exactly
   json/md/csv/txt/png are tracked; the directory-only negation (`**/`) is required because git
   cannot re-include a file whose parent directory is excluded — which is also why step 4 ignores
   `runs/**` (files) and never `runs/` (the directory). PNGs must be compressed and **under 500 KB**
   (`sips -s format png`, `pngquant`); the pre-commit door D0b rejects anything else under runs/
   because .gitignore is advice and a hook is a door.

   v3 said "REMOVE entries from .gitignore", which is a licence to strip whatever looks
   inconvenient — that is how `node_modules/` gets committed. Scope it to `.claude/knowledge/`
   and leave every other rule alone. (Pre-commit check D0 blocks dependency trees regardless.)

   Reference screenshots, measurement JSON and diff outputs are the audit trail — an earlier build's verify
   baseline was unrecoverable because v1 gitignored it, and gitignored screenshots are also why
   the pipeline kept re-fetching from Figma what it already had. Prune superseded run dirs at page
   completion, never silently.
4. **Run the gate self-test:** `sh .claude/scripts/f2s_gate_selftest.sh` — non-zero =
   bootstrap FAILED. Do not proceed with broken gates.
5. **Placeholder check:** grep `conventions/` for `<command`/`<PM tool` and the registry for `_e.g._`
   rows. Localize now or record why. The pre-commit hook will not accept a first build commit
   while placeholders survive, and `tasks.md` must contain at least the foundation tasks (not the
   empty skeleton) before any section commit.
6. **Instantiate tasks.md** from plans/current.md task list at plan approval — mirroring is not optional.

# Knowledge Base Bootstrap Protocol

This protocol creates and maintains a persistent local knowledge base in the **target project** (the project the skill is operating on, not the skill repository). Run it as a hard, idempotent prelude at the start of every skill invocation.

## Layout created in the target project

```
CLAUDE.md                                  # auto-loaded by Claude Code; managed block bracketed by markers
.claude/knowledge/
├── README.md                              # what each folder is for
├── glossary.md                            # flat domain terms / definitions
├── architecture/                          # overview.md, modules.md, data-flow.md
├── technologies/                          # stack.md, constraints.md
├── conventions/                           # git.md (branch/commit/PR rules) — extensible for future conventions
├── design/                                # tokens.md, tokens.json, components.md, interactions.md, typography.md
├── decisions/                             # NNNN-slug.md, frontmatter status: assumed | decided | superseded
│                                          # 0001-commit-prefix.md is seeded on first run
├── plans/                                 # current.md + archive/<date>-<slug>.md
├── tasks.md                               # ## Todo, ## In progress, ## Done (with owner/branch on in-progress items)
├── runs/                                  # evidence: json/md/csv/txt/png (<500 KB) tracked; video/har/trace ignored
└── extraction/
    └── figma/
        ├── manifest.json                  # cache index
        ├── raw/
        │   ├── nodes/<key>.json
        │   ├── metadata/<key>.json
        │   └── variables/<fileKey>.json
        └── screenshots/                   # tracked (negated in step 3 of the hooks/gitignore section)
```

## Steps (idempotent; safe to re-run every invocation)

### 1. Resolve project root

```
git rev-parse --show-toplevel 2>/dev/null || pwd
```

If neither yields a directory containing one of these sentinels, prompt the user to confirm location before creating anything:

- `package.json`
- `shopify.toml` or any `config/settings_schema.json` (Shopify theme)
- `next.config.*`, `vite.config.*`, `astro.config.*`, `nuxt.config.*`
- `composer.json`
- `pyproject.toml`, `Cargo.toml`, `go.mod`

Refuse silently to bootstrap at `$HOME` or `/`.

### 2. Create the tree if missing

If `.claude/knowledge/` does not exist, create the layout above with empty placeholders. Seed the following:

- `.claude/knowledge/README.md` — copy `templates/README.md`
- `.claude/knowledge/tasks.md` — three section headers `## Todo`, `## In progress`, `## Done`
- `.claude/knowledge/extraction/figma/manifest.json` — copy `templates/manifest.json`
- `.claude/knowledge/conventions/git.md` — copy `templates/conventions/git.md`; fill in the project-management-tool placeholder if the user has one (otherwise leave blank)
- `.claude/knowledge/architecture/f2s_registry.md` — copy `templates/f2s_registry.md` (the code contract; the only `architecture/` file seeded up front — agents append rows as they build)

Do **not** seed any other content in `decisions/`, `plans/`, `glossary.md`, `architecture/` (beyond the registry), `technologies/`, `design/`. Those fill up as the agent learns.

### 2a. First-run commit-prefix prompt

If `.claude/knowledge/decisions/0001-commit-prefix.md` does not exist, ask the user once:

> Should every commit on this project carry a prefix (e.g. `f2s:`, `acme:`)? Reply with the prefix or "none".

Then write `decisions/0001-commit-prefix.md` from `templates/decision-commit-prefix.md` with the user's answer (or empty if "none"). If the prefix is non-empty, update the `CLAUDE.md` Conventions list inside the managed markers with: `Commit prefix: <prefix>`.

This question is asked **once per project**; subsequent runs read the existing decision file.

### 3. Manage root CLAUDE.md

If root `CLAUDE.md` is missing, create it from `templates/CLAUDE.md`.

If present, locate the marker block:

```
<!-- claude-kb:index:start -->
…managed content…
<!-- claude-kb:index:end -->
```

If markers are absent, append the block at end of file. **Never** rewrite content outside the markers. The agent owns the inside of the block; the human owns everything else.

### 4. Update `.gitignore` (append-only)

Append the following lines if not already present (grep-then-append per line):

```
.claude/knowledge/runs/**
.claude/knowledge/extraction/*/screenshots/
```

`runs/**` (the files), never `runs/` (the directory): a directory exclusion cannot be re-included,
and the negations in step 3 of the hooks section depend on it. (v4 wrote `runs/`; one rebuild committed 1.6 GB.)

If the project's `.gitignore` already ignores `.claude/` wholesale, **warn the user**:

> `.claude/` is gitignored at the project level. Knowledge-base markdown will not be tracked. Whitelist with `!.claude/knowledge/**/*.md` if you want to commit it.

Do not silently override.

### 5. Announce on first run

Only when the bootstrap actually created files this run, print a single line:

> Bootstrapped local KB at `.claude/knowledge/`. Root `CLAUDE.md` updated with managed index block.

On subsequent runs (everything already exists), say nothing — bootstrap is invisible when idempotent.

### 6. Do not create a separate init commit

Bootstrap files commit alongside the first real artifact (the first decision, the first plan, the first Figma extraction). This keeps git history meaningful.

## Hard guarantees

- Bootstrap **never** runs `rm -rf .claude/`. It only creates the `knowledge/` subtree and edits `.gitignore` and `CLAUDE.md` between markers.
- Bootstrap **never** writes outside the project root.
- Bootstrap **never** runs without a project sentinel unless the user confirms.

## Risks documented elsewhere

- Stale Figma cache → see `FIGMA_CACHE.md` (figma skill).
- CLAUDE.md bloat → see `CLAUDE_MD_RULES.md`.
- Cross-skill collisions on shared KB files → see `READ_PROTOCOL.md` § Cross-skill collision guard.
