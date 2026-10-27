# figma-to-shopify-gates

A playbook for turning a Figma design into a merchant-editable Shopify Online Store 2.0 theme,
run by Claude Code, where every checkpoint is a script and the script's exit code decides.

The playbook is a Claude Code skill. `SKILL.md` is the entry point the agent reads; `HOW_TO_USE.md`
is the entry point for the person running it. The agent orchestrates four roles (researcher,
builder, verifier, fixer) as separate subagents, and the builder of a section is never the one who
verifies it. Nothing is "done" on the agent's say-so: parity is a number from a measurement script
with a committed artifact, and a section counts as shipped only when a customer can reach it.

## What it produces

- Sections, snippets and assets under an `f2s_` prefix, each with a file header and a registry row
- Every text, image, link and colour accent wired to a setting, block or metafield, with the Figma
  value as the default
- A per-section spec, brief and verification artifact (measurements, renders, pixel diff) in the
  theme repo's `.claude/knowledge/` folder
- A build plan you approve before anything is built, and a handoff document at the end
- A pull request with Figma-vs-render side-by-sides at both breakpoints as the single review surface

## The gates, in pipeline order

| Gate | Script | Asks |
|---|---|---|
| 0 | `f2s_permcheck.sh` | Can the run proceed without prompting a human? Permissions file present, committed, deny list intact, Figma MCP server allowlisted |
| 0 | `f2s_env_check.sh` | Can this machine render and measure? If not, the whole run is marked UNVERIFIED |
| 0 | `f2s_gate_selftest.sh` | Do the gates themselves work? Known-good passes, known-bad fails, empty tree fails |
| 1a | `f2s_inventory.sh` | What does the theme already contain? Every row is classified RETIRE, KEEP or CONFLICT by a human |
| 1b | `f2s_figma_audit.js` | Can the design be read mechanically? Text styles, variable bindings, auto-layout, annotations |
| 2 | `f2s_preview_selfcheck.sh` | Is the static render harness real, or a hand-simplified copy? |
| 3 | `f2s_cache_check.sh` | Is this node's extraction complete, annotations and comments included? |
| 3 | `f2s_research_gap.sh` | Did an agent hit a gap in a brief, and was it recorded rather than returned as a string? |
| 5 | `f2s_preflight.sh` | Is it safe to start building? Rolls up every gate above plus manifest completeness |
| loop | `f2s_precommit.sh` | Git hook: spec committed before build, one section per commit, no evidence over 500 KB |
| loop | `f2s_measure.py` | Computed styles and box metrics of the render against the spec, at both designed widths |
| loop | `f2s_visualdiff.py` | Pixel mismatch percentage, render against the cached Figma reference |
| loop | `f2s_codehealth.sh` | theme-check clean, file headers present, registry row current, naming rules |
| loop | `f2s_editability.sh` | Can a merchant actually edit this? Sections and snippets, defaults equal Figma values |
| loop | `f2s_functional.sh` | Nine production bug classes, plus the admin upload rules |
| loop | `f2s_telemetry.sh` | Records role, model, tokens and result per loop |
| 7 | `f2s_coverage.sh` | Did we build everything the design contains, and is every built section in a template? |
| 8 | `f2s_reachability.sh` | Can a customer reach it? Templates reference it, settings it reads exist, runtime requirements match the store |
| 8 | `f2s_upload_validator.sh` | Would the Shopify admin reject this theme on upload? Rules theme-check does not enforce |
| 8 | `f2s_perf.sh` | CLS-safe images, eager LCP image, lazy below the fold, CDN resizing, no render-blocking scripts |
| 8 | `f2s_deferrals.sh` | Harvests every deliberate deviation marker into the PR ledger |
| 8 | `f2s_dupecheck.sh` | Advisory: duplicated code and dead snippets |
| 8 | `f2s_hooks_mode.sh` | Whose repo is this now? Disarms the hooks at handoff, re-arms on the next run |

## How a run works

```
/build-page <figma-url> <target-template>
```

1. Intake. Permissions are installed and proven, then every question is asked once, in one batch.
2. Inventory. Existing sections, snippets and templates are listed; you classify each row.
3. Readiness audit. The Figma file is checked for structure and annotations. BLOCKED stops the run.
4. Foundation A. The render path, fonts and tokens are proven before any research is spent.
5. Extraction. One researcher per node writes a brief: spec, screenshots, annotations, comments,
   assets, open questions. After this step no agent calls Figma again.
6. Check-in 1: the plan. One page listing every section, what it replaces, dependencies, open
   questions and the performance budget. The run halts until you approve it.
7. Preflight, then shared snippets.
8. Per-section loop: build, verify (different agent), fix the enumerated discrepancies, re-verify.
   A section with unanswerable questions is parked; the rest continue.
9. Check-in 2: the first verified section beside its design. The run halts.
10. Remaining sections, then page integration against the full frame.
11. Reachability, editability, functional, upload validation and performance gates.
12. Hooks disarmed for the maintainer, then the PR. A run that ends early for any reason must
    write a verdict naming every section left unbuilt, unwired or unverified.

## What it requires

- Claude Code, with subagents enabled
- A Figma MCP server (desktop app, console bridge or the official plugin), and a Figma file that
  passes the readiness audit: text on text styles, fills bound to variables, frames on auto-layout
- Shopify CLI (`shopify theme check`; `shopify theme dev` is the preferred render path)
- theme-check, either the repo-local CLI or the gem
- Python 3 with Pillow, and Playwright for real-pixel measurement
- Node for the Figma audit script
- `gh` for opening the PR (optional)

## What it does not do

- It does not design. A value the file does not specify is a parked question, not a guess.
- It does not ship the boilerplate theme or pattern library it refers to. Without one, every
  section is built new and the pattern library starts with your first run.
- It does not verify without rendering. If nothing on the machine can render, every verdict says
  UNVERIFIED and so does the PR.
- It does not treat a Lighthouse score as a gate. The deterministic performance checks gate;
  Lighthouse is reported.
- It does not publish or push to a live theme. Those commands are on the deny list.
- It does not replace your review. Two check-ins are scheduled and the plan is yours to approve.
- It is not for single-section changes or bug fixes on a working theme. The intake and gates are
  sized for whole pages.

## History

The playbook went from v1 to v4.1 through post-mortems on three builds at a Shopify agency. v1
was prose. v2 added the render harness and an independent verifier after a first pass landed at
about half parity. v3 locked the verification method after a measured audit found that a
"decision" to read code instead of rendering it had passed twenty sections with wrong spacing
and fonts. v4 added proven permissions, the existing-theme ledger, per-section briefs, the
approvable plan, the performance gate and the completion contract after a run left fourteen built
sections wired to nothing. v4.1 added the admin upload validator after a theme that passed every
gate was rejected by Shopify on upload. Each version replaced a rule that was ignored with a
script that cannot be. Client names have been removed from the war stories; the lessons stay.

## Layout

```
SKILL.md                      agent entry point: the pipeline and its stops
HOW_TO_USE.md                 operator guide: requirements, halts, troubleshooting
CHANGELOG.md                  v4.1 changes
resources/scripts/            the gates
resources/agents/             researcher, builder, verifier, fixer
resources/commands/           /build-page
resources/knowledge-base/     bootstrap, harness, rubric, Shopify best practices, templates
resources/templates-v2/       permissions template, role-to-model routing
tests/fixtures/               known-good and known-bad trees for the self-test
examples/                     planning checklist, implementation report template
archive/                      the v1 text, for reference
```

Run the self-test before trusting anything:

```bash
sh resources/scripts/f2s_gate_selftest.sh
```

## Author

Shahz Siddiqui
https://shahzsiddiqui.vercel.app
https://www.linkedin.com/in/shahz-siddiqui-lead

Written and used at Sirge, a Shopify agency. MIT licence.
