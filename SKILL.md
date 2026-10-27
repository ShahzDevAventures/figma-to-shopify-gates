---
name: figma-to-shopify-gates
description: Convert Figma designs into verified, merchant-editable Shopify OS 2.0 theme code through mechanically enforced gates. Use for full page/theme builds from Figma on Dawn or custom OS 2.0 themes. Entry point is the /build-page command; every gate is a script whose exit code decides. v4 (2026-08-13) — permissions proven before the run, existing-theme ledger, per-section briefs, an approvable plan, performance gate, and a completion contract, after the orphaned-sections audit. v4.1 (2026-10-12) — fixes ported from the most recent rebuild (measure spec shapes, coverage, staged-index pre-commit, commit-msg door, repo-CLI theme check), Shopify admin upload validator gate, bypassPermissions template, scoped runs/ evidence, assembled-page harness rules.
---

# Figma → Shopify Theme Implementation (v4)

You are Claude Code in a Shopify theme repo. The pipeline below is the ENTIRE hot path.
How-to detail lives in `resources/knowledge-base/` — consult it when a step needs depth, but the
sequence and its stops are complete as written here.

**The one law:** a gate is a script. Exit 0 = door open. Non-zero = door locked. You never reason
your way past a locked door; you fix the cause. Parity, "done", and "PASS" exist only as committed
artifacts with paths — never as your opinion.

**How a run behaves:** it runs unattended between two planned stops. Questions are asked once at
intake, never mid-run; a section that can't proceed is PARKED and the others continue. Two
check-ins are scheduled and announced in advance (the plan; the first finished section). Four
things halt everything: broken self-test, BLOCKED Figma audit, BLOCKED preflight, unapproved plan.
Progress is mirrored in `plans/STATUS.md`. Full contract: `resources/commands/build-page.md`.

**Never-zones — no waiver form exists for these, and none may be invented:**
- The VERIFICATION METHOD. Two acceptable methods, both render real pixels (VERIFY_HARNESS.md).
  Can't render → the run is UNVERIFIED and says so everywhere, PR included. v2's collapse was one
  "decision" that substituted reading code for rendering it: 20/20 sections "passed", spacing and
  fonts shipped wrong. Waivers may shrink SCOPE (park a section — a human's call, recorded);
  they may never touch METHOD.
- Spec before build, enforced by git order (pre-commit hook).
- Builder ≠ verifier. Different model/invocation. Always. **And you never finish a subagent's
  work yourself** — see the failure contract below.
- Exact values. Figma's 310px reaches the browser as 310px. Tokens exist only where Figma variable
  defs define them; distinct spec values never share a token (a prior invented scale collapsed two
  heading sizes and silently deleted weight 900 site-wide).
- No `--no-verify`. A blocked commit has a real cause.

**The subagent failure contract (v4).** A subagent that stalls, errors, or returns nothing: retry
once, then PARK the section and move on. **You may never finish its work yourself.** Doing so makes
you both builder and verifier for that section — the self-grading failure every gate here exists to
prevent. On one build three commits record exactly this ("builder stalled before its gates",
"orchestrator finished it") and the output was then verified by the same context that wrote it.
Parked-and-reported beats built-and-self-approved.

**The completion contract (v4).** A run that ends before GATE 8 must terminate with a VERDICT that
names every section left unwired, unverified, or unbuilt. On one rebuild the run stopped mid-loop;
`STATUS.md`'s last line read `Verified/committed: 0` while 14 finished section files sat on disk
wired to no template, beside 17 verify directories that made it look like success. A snapshot is
not a verdict. Ending silently is a failure mode with its own gate.

---

## Pipeline (run via /build-page; order is load-bearing)

**GATE 0 — Permissions, environment, self-test.**
`sh .claude/scripts/f2s_permcheck.sh` — settings.json present, committed, `defaultMode:
auto`, deny list intact, and the **configured** Figma MCP server actually allowlisted. v3
allowlisted `mcp__figma__*`, which matches no server that exists, so every Figma call prompted;
one build ran with no settings.json at all. Non-zero → fix before starting; a run that sits prompting
is not a run. Then `f2s_env_check.sh` — can this environment MEASURE? FAIL → the run is
UNVERIFIED end-to-end (flag file written; verifier and PR inherit it). Then
`f2s_gate_selftest.sh` — broken gates → STOP: nothing a broken gate blesses can be trusted.

**GATE 1a — Existing-theme ledger.** `sh .claude/scripts/f2s_inventory.sh` → every existing
section, snippet, template and app-backed region into `architecture/inventory.md` + `.json`. Each
row is then classified **RETIRE** (the design replaces it — it must be gone by GATE 7) · **KEEP**
(must survive: apps, and the pages the design never drew — cart, blog, 404) · **CONFLICT** (both
would serve one purpose; a human picks). Preflight blocks on any UNCLASSIFIED row. On a rebuild the
question is never "should I extend this" — it is what dies, what lives, and what collides. One rebuild carried 23 live sections from a prior build, gained 14 more, and nothing recorded which of the 23
were meant to go; 13 of the 14 ended up wired to nothing.

**GATE 1b — Figma readiness audit (structure AND semantics).** Run
`resources/scripts/f2s_figma_audit.js` against the target nodes, save JSON to
`.claude/knowledge/design/figma_audit.json`. Two halves:
*Structure* — can values be transcribed? text-style ≥ 0.5, token binding ≥ 0.4, auto-layout ≥ 0.6.
BLOCKED → send the designer fix-list and STOP; an ambiguous source caps achievable parity.
*Semantics* — do we know how it works? Per frame, the five annotation tags: `@section @data @behavior @states @editable`. Missing `@data`
or `@states` on a frame = a blocking gap for that frame only.
Verdicts: `BLOCKED` (fix the source) · `GO_ANNOTATIONS_PARTIAL` (build answered sections; the rest
pause as questions) · `GO`. The audit emits `askDesigner[]` — one plain-language question per gap,
already addressed to its frame. Post them as pinned Figma comments verbatim; never send a designer
a node id and a tag name. Process: the design-side checklist in HOW_TO_USE.md.

**GATE 2 — Foundation A: can this machine measure?** Render path proven per the VERIFY_HARNESS
ladder, correct font per `design/typography.md` loaded and reported (verification under the wrong
font is invalid and historically caused ~80% of "spacing is off" noise), real images, measure.py
proven working. Tokens CSS generated ONLY from cached Figma variable defs — one file-scoped call,
no section research needed — never an invented scale. Any generated reset/base CSS must lose to
section CSS (no broad selector may outrank a section's own class selectors — a prior base reset
silently defeated correct letter-spacing in four sections).

*This moved ahead of research in v4.* Research is the expensive step; v3 spent all 28 agents and
only then discovered whether anything could be verified. VERIFIED vs UNVERIFIED is now settled
before that spend, and the plan can state the render path as fact rather than hope.

**GATE 3 — Extraction → one brief per section.** figma-researcher per node writes ALL raw payloads
(design-context, variable defs, screenshots at the DESIGNED widths — read from the file, never
assumed — every asset, **dev-mode annotations AND pinned comments**) plus the manifest entry, then
assembles `sections/<key>/BRIEF.md` from them: spec, both screenshots, annotations, comments,
assets, ledger classification, open questions. `f2s_cache_check.sh <key>` must pass per node
— it now requires annotations and comments to be declared and cached, so "the designer annotated
nothing" is a recorded fact rather than an omission. Prose summaries are not a cache.

**After this gate no build or verify agent calls Figma.** The brief is the one input. If an agent
needs something the brief lacks, that is a research gap: **record it with
`f2s_research_gap.sh add <section> <node> <reason>`, then return `RE-RESEARCH: <node>`.**
v3 gave agents paths and instructions but no single document, so each went back to the MCP for
whatever it was missing — which is why a 28-section page cost hundreds of Figma calls.

**Recording it is not optional, and this is the correction v4 owes one build.** There, agents returned
`RE-RESEARCH` exactly as instructed and a repo-wide grep found the phrase once — in the instruction
telling them to say it. No file, no id, no gate, no way to notice a dropped one; the orchestrator
happened to rescue them by hand. This skill routes its escape hatch through that channel from four
places, so it is the busiest lossy path in the system. A returned string is not a record. Preflight
refuses to pass while any gap is open.

**GATE 4 — The plan. ★ CHECK-IN 1 — the run HALTS for approval.**
`plans/BUILD_PLAN.md`, one page: every section with complexity, ladder source, `depends_on`, and
what it replaces · the RETIRE list · what must survive (apps, undesigned pages) · open questions ·
the permission set · the performance budget. `sections.json` gains `depends_on[]` so build order is
machine-checked, not narrative. Research was already front-loaded in v3 — it just went into the
cache and out the other side, and nothing reached the operator until the PR.

**GATE 5 — Preflight.** `f2s_preflight.sh` → GO or BLOCKED written to `plans/preflight.md`.
Autonomous runs may not start before GO. Checks: permissions, inventory fully classified,
environment, self-test, manifest completeness, both breakpoints per page, Figma audit verdict,
typography decision, render path, hooks installed, placeholders purged.

**GATE 6 — Foundation B: shared surface.** Shared snippets and the component kit, with a single
owner per hot file from here on. This is deliberately AFTER the plan: what's shared is only knowable
once the section list is approved, and building shared infrastructure for sections that get parked
at check-in 1 is waste. New projects START from your own boilerplate theme if you keep one (a
section catalog covering the recurring families, a tokens structure, a component kit); its section
catalog and `docs/patterns/` are the build ladder's reading list, synced to `.claude/knowledge/patterns/`
at bootstrap. Without a boilerplate every section is ladder rung 3 (new) and the pattern library
starts with this build.

**LOOP — per section** (triage per `.claude/routing.json`; `sections.json` tracks state so a stopped
run resumes at the first not-done section instead of silently ending — 5 of 28 specced sections were
simply never built on a prior run):
1. *Triage:* simple → lite loop (deterministic gates only; any failure auto-promotes).
   standard → full loop. complex (overlay/interactive/app-backed) → full loop, second verifier on
   2nd failure. BLOCKED (open questions) → skip, report, continue.
2. *Build* (figma-builder, reads the brief): ladder rung stock → extended → new, recorded in the
   spec; exact spec px; everything merchant-editable with Figma-valued defaults;
   `block.shopify_attributes` in block loops; file header; registry row in the same commit;
   deviations get `f2s:` markers — a deviation without a marker is a silent guess; one
   section per commit on a task branch.
3. *Verify* (figma-verifier; MUST differ from the builder): measure.py computed-style check +
   visualdiff.py mismatch % at BOTH designed breakpoints, then codehealth + editability +
   functional gates, then **the canonical rubric in `.claude/knowledge-base/PARITY_VERIFY.md`** —
   read it, do not work from memory or a summary. The verifier may not reword a criterion; disputed
   spec items fail the section into re-research. Artifact committed to `runs/<date>/<section>/` or
   the verdict is UNVERIFIED.
4. *Fix* (figma-fixer): enumerated discrepancies only; spec-wrong → RE-RESEARCH that node;
   two failed loops on one discrepancy → park + report.
5. *Re-verify scoped:* discrepancy items + pixel-diff regression only.
6. Log every loop: `f2s_telemetry.sh <section> <role> <model> <tokens> <loop> <result>`.

**★ CHECK-IN 2 — after the first section is verified.** One finished section beside its design,
before the rest follow the same interpretation. Foundation A already proved the machinery at GATE 2;
this stop is about judgment, not plumbing — and it is worth taking even when nothing is broken.

**GATE 7 — Page integration** (strong model, all sections green): assembled page vs full frame —
order, inter-section rhythm, band transitions, cross-section deferrals (overlaps deferred with
markers get resolved HERE) — plus two assertions: the template's `order` contains EXACTLY the
planned sections, **and every inventory row marked RETIRE is gone.** The second is what catches a
rebuild that shipped its new sections alongside the old ones. At undesigned widths (750–989):
integrity check (`measure.py --integrity`), never invented "parity".

**GATE 8 — Reachability, editability, performance, handoff.**
`f2s_reachability.sh` PASS — **this is where "done" is redefined.** Done is not "committed
and the gates are green"; it is "a customer can reach it". The gate asserts every built section is
referenced by a template, section group or layout; that every `settings.*` a section reads exists in
the theme's config; and that every requirement a spec DECLARES (`runtime_requires`) matches the
store's actual value. On one build a section passed four gates and reached no customer for 33 hours,
because one theme setting meant its markup never ran — and the script it needed never loaded, so
add-to-cart was dead store-wide. Nothing in that build was wrong; nothing checked it was *live*.
Declare requirements per section rather than hardcoding features: the same gap swallows currency
selectors, predictive search, announcement bars and any custom setting a theme invents.
`f2s_coverage.sh` PASS again here (assembly half). `f2s_editability.sh` PASS
(sections AND snippets — the worst v2 defects hid in snippets). `f2s_functional.sh` PASS
(the nine production bug classes). `f2s_perf.sh` PASS — CLS-safe images, eager LCP image,
lazy below the fold, CDN resizing, no render-blocking scripts; the Lighthouse number is advisory and
never gates. `f2s_deferrals.sh` output harvested into the ledger. HANDOFF.md: metafield
contract, **apps to reconnect (from the KEEP list)**, fonts, deviations with spec citations.

**Then disarm the gates:** `f2s_hooks_mode.sh maintainer`. The doors are justified by "no
human is judging this"; once the repo belongs to a developer that justification is gone, but the
enforcement does not know — it lives in `core.hooksPath`, in the repo, so it fires on every human
commit regardless of which skill is loaded. Left armed it blocks a hand-edited section for having
no Figma spec, fails an unrelated commit on pre-existing debt anywhere in the tree, and refuses a
deliberate two-section refactor. Friction does not produce compliance, it produces `--no-verify`
and hand-built workarounds — a prior run had three agents independently inventing the same one.
Bootstrap re-arms on the next run, so the mode follows whoever is driving, and the mode is recorded
in `.claude/HOOKS_MODE` because gates that are silently off are worse than gates that block.

**GATE 9 — PR, the single review surface.** Per-section side-by-sides (Figma left, render right,
both breakpoints), mismatch % from committed artifacts, the deferral ledger
(`f2s_deferrals.sh` output pasted verbatim), retired-section list, BLOCKED sections with
their open questions, UNVERIFIED banner if the flag is set, performance results, telemetry summary,
reviewer plan.

**AFTER MERGE — drift watch.** Verification is a snapshot, not a state: on a prior project all 20
verified sections were later edited by Shopify-admin syncs, deleting verified work (an annotated
animation among it) with nothing noticing. Any `shopify[bot]` commit touching `f2s_*` files
invalidates that section's verify artifact — re-run measure.py + visualdiff.py on the touched
sections (manually or via CI) before the next claim that the theme matches the design.

---

## Layout
- `resources/scripts/` — all gates + hook (installed to `.claude/scripts/` by bootstrap):
  permcheck, inventory, coverage, env_check, gate_selftest, cache_check, research_gap, preflight,
  precommit, hooks_mode, codehealth, editability, functional (9-classes), reachability, perf, measure.py,
  visualdiff.py, preview_selfcheck, deferrals, telemetry, dupecheck.
  Preflight warns on any script here that no gate, command or agent invokes — a script no door
  runs is documentation, and on one build the deviation harvester was invoked by nothing at all while
  the deviations it would have surfaced shipped.
- `resources/agents/` — researcher/builder/verifier/fixer (installed to `.claude/agents/`)
- `resources/commands/build-page.md` — the entry point
- `resources/templates-v2/routing.json` — role→model routing; judgment roles stay strong
- `resources/templates-v2/settings.json` — the permission set, installed at step 0 of /build-page
- `resources/knowledge-base/` — BOOTSTRAP, READ_PROTOCOL, FIGMA_CACHE, VERIFY_HARNESS,
  PARITY_VERIFY, AUTONOMOUS_MODE, PREFLIGHT, COMPONENT_REUSE, SHOPIFY_BEST_PRACTICES, GIT_WORKFLOW.
  **Installed to `.claude/knowledge-base/` by bootstrap** — agents cite these by path, and in v3
  they were never copied, so the citations were dead.
- `resources/knowledge-base/templates/` — BRIEF.md, BUILD_PLAN.md, spec, registry, conventions
- Pattern library: your boilerplate's `docs/patterns/`, synced to `.claude/knowledge/patterns/` at
  bootstrap — how we've built each section type before, good and bad examples from real audits
- `tests/fixtures/` — known-good/known-bad trees for the gate self-test
- `archive/v1-FULL_REFERENCE.md` — v1 text, for humans only. Agents do not read it: two documents
  claiming authority is how an agent picks whichever supports what it already wanted to do.
