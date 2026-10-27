# Planning Checklist

Use this checklist when starting a new Figma-to-Shopify implementation.

## Knowledge base prerequisites
- [ ] Bootstrap ran: `.claude/knowledge/` exists in the theme repo, root `CLAUDE.md` has the managed index block (see `../resources/knowledge-base/BOOTSTRAP.md`)
- [ ] `.gitignore` contains `.claude/knowledge/runs/**` (not `runs/`) with the v4.1 negations (json/md/csv/txt/png only) and the video/har/trace/node_modules re-ignores — BOOTSTRAP.md step 3
- [ ] If the project gitignores `.claude/` wholesale, the user has been warned
- [ ] Always-read pass complete; agent summarized recovered context to the user (decisions, plans/current.md, tasks.md, design tokens, Figma manifest)
- [ ] Figma cache manifest (`extraction/figma/manifest.json`) inspected; existing cached nodes inventoried before any MCP call

## Required Inputs

- [ ] Figma URL(s)
- [ ] Target Shopify template(s)
- [ ] Theme base confirmed: Dawn, Dawn-derived, or custom OS 2.0
- [ ] Replace existing template or create alternate template
- [ ] Known third-party apps listed
- [ ] Content source expectations confirmed
- [ ] Product metafield strategy confirmed
- [ ] Responsive requirements confirmed
- [ ] Interaction expectations confirmed
- [ ] Reusable vs page-specific section preference confirmed

## Figma Analysis

- [ ] Desktop frame identified
- [ ] Mobile frame identified
- [ ] Tablet frame identified, if available
- [ ] Tokens extracted (cache hit announced if applicable)
- [ ] Components identified
- [ ] Assets identified
- [ ] Interactions identified
- [ ] App-backed candidates identified
- [ ] Figma-to-Shopify mapping table created
- [ ] Every MCP response cached under `.claude/knowledge/extraction/figma/raw/` with corresponding manifest entry
- [ ] Tokens written to `.claude/knowledge/design/tokens.md` and `tokens.json` (with `last_writer` set, `## Sources` appended, not overwritten)
- [ ] Component catalog written to `.claude/knowledge/design/components.md`
- [ ] Interactions written to `.claude/knowledge/design/interactions.md`
- [ ] Mapping table written into `.claude/knowledge/plans/current.md`

## Repository Audit

- [ ] Current template audited
- [ ] Existing sections listed
- [ ] Existing app blocks/sections identified
- [ ] Product card snippets identified
- [ ] Image snippets identified
- [ ] CSS architecture identified
- [ ] JS architecture identified
- [ ] Validation scripts identified
- [ ] Dirty git state checked

## Git workflow setup
- [ ] On `main`, working tree clean (or user has confirmed branching off dirty state)
- [ ] Task branch created: `<type>/<short-description-hyphenated>[-<TASK-ID>]` where type ∈ feat/fix/chore
- [ ] `tasks.md` In-progress item annotated with `owner:` and `branch:` and `started:`
- [ ] First-run commit-prefix prompt answered; `decisions/0001-commit-prefix.md` exists
- [ ] If prefix non-empty, `CLAUDE.md` Conventions block carries `Commit prefix: <prefix>` inside the markers

## Foundation: Verify Harness (BEFORE any section — see `../resources/knowledge-base/VERIFY_HARNESS.md`)
- [ ] Render path working: `shopify theme dev`, or the real-CSS static generator (inlines real `{% stylesheet %}` + mirrors real DOM/classes — no hand-simplified previews)
- [ ] Correct font loaded (brand font, or documented condensed near-match); substitution recorded — **verification under the wrong font is invalid**
- [ ] Real Figma images/icons downloaded to `extraction/figma/sections/<key>/assets/` (URLs expire ~7 days)
- [ ] Reference screenshots captured at **1440 AND 375** per section node
- [ ] Measurement script wired (`resources/scripts/f2s_measure.py`) — emits PASS/FAIL panel + `document.title`

## Per-section build & verify loop (each section — hard gate)
- [ ] Built from `get_design_context` (the code), not `get_metadata`/layer names
- [ ] `spec.json` written (must_haves; exact px, never rounded) — see `templates/section-spec.json`
- [ ] Built to spec; spacing values exact (no snapping to nearest token); line-height + letter-spacing set
- [ ] Rendered at 1440 AND 375 with the harness
- [ ] Measurement check ALL PASS (deterministic box spacing)
- [ ] Independent parity subagent ran (visual diff both breakpoints) — see `../resources/knowledge-base/PARITY_VERIFY.md`
- [ ] Discrepancy list empty before the section is marked done

## Editability (almost everything theme-editable)
- [ ] Theme-Editor Wiring Audit: every text/image is a setting, defaults = Figma values, repeatable groups add/remove/reorder
- [ ] Dynamic product data stays dynamic; build survives edge-case data (long title, no compare-at, sold-out, no selling plan, missing image)
- [ ] `settings_data.json` / template defaults populated so a fresh install renders the design
- [ ] `HANDOFF.md` written (template→page assignments, images/font/apps to upload, documented deviations)

## Page-level gate (after sections individually green)
- [ ] Whole-page render diffed vs full Figma frame: section order, inter-section spacing, band transitions
- [ ] Shared components verified in every context they appear (e.g. home vs PDP)
- [ ] Interaction states + reduced-motion + keyboard verified; contrast checked per band
- [ ] Lint/theme-check clean (only scripts that exist)
