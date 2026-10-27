---
name: figma-shopify-theme-implementation
description: Use this skill to convert Figma designs into reusable, high-fidelity Shopify OS 2.0 theme code. It is designed for Dawn or Dawn-derived themes, supports Figma MCP analysis, section/block decomposition, Shopify CDN image best practices, app-backed section preservation, metafield/theme-setting decisions, branch-per-task and subtask-per-commit git workflow with QA-gated commits and PR-on-completion, and a final mobile-focused performance pass.
---

# Figma to Shopify Theme Implementation Skill

You are Claude Code operating inside a Shopify theme repository.

Your job is to convert one or more Figma designs into production-ready Shopify OS 2.0 theme code with high visual fidelity, clean theme architecture, strong mobile performance, and maintainable section/block schemas.

This skill is reusable across different Shopify projects, Figma files, stores, themes, pages, and app integrations.

## Core Priorities

1. Use Figma as the visual source of truth — and extract that truth from **`get_design_context` (the generated code)**, not from `get_metadata` (names/sizes only). Metadata is for navigation; the design-context code is the spec (exact colors, type metrics, paddings, gaps, grid templates, and structural tricks like `opacity-0` spacer columns or absolute overlays). **Never infer structure from layer names.**
2. Use Shopify OS 2.0 architecture correctly: templates, sections, blocks, snippets, assets, and schema settings.
3. Preserve existing app functionality when the design depends on third-party app content.
4. Focus first on visuals and functional parity, then app integrations, then performance refinements.
5. **Almost everything is theme-editable. Default to merchant-editable; hardcoding is the exception that must be justified.** Every text, image, icon, link, color accent, and repeatable group maps to a section setting, block setting, theme setting, product/collection field, metafield, metaobject, or app output. Only structural scaffolding and brand-fixed tokens are hardcoded. See Content Source Decision Rules — and the Theme-Editor Wiring Audit gate.
6. **Done = the rendered section matches the Figma node, proven by verification — not "tasks committed."** A section is complete only when it passes the Per-Section Build & Verify Loop (rendered at desktop **and** mobile, with the correct font, measurement-checked and visually diffed against the cached reference, against `must_haves` extracted in research). Tasks-complete + theme-check-clean is necessary but **not** sufficient.
7. Follow the Git workflow in the dedicated section below: branch per task, commit per subtask, push only at task completion, then open a PR.
8. Prefix every new file, section, block, snippet, asset, CSS module, JavaScript selector, and custom identifier with `f2s_` where practical. (This is the **file/CSS/JS** prefix; the optional commit-message prefix is configured separately per project — see Git workflow section.)

> **Why these exist (failure modes they prevent):** building from metadata/assumptions ships the wrong *structure* (flat grid vs quadrant, 2-col vs 3-col, cream vs navy band); verifying without the correct font fabricates "spacing is off everywhere"; defining done as "committed" passes sections that don't match; and "looks editable" without a wiring audit ships hardcoded copy. All four happened on a real first pass that landed ~50%. The loops below are mandatory because skipping them is exactly how that happens.

---

## Run Modes — Interactive vs Autonomous

This skill runs in one of two modes; pick at plan time.

- **Interactive (default).** The human checkpoints below stay: per-commit spot-check, per-task
  performance approval, mid-run questions.
- **Autonomous (background/unattended).** Selected when the user asks for a background run. Once the
  plan is approved, it executes end-to-end with **no mid-run approvals** until the PR is open. Full
  protocol in `resources/knowledge-base/AUTONOMOUS_MODE.md`. The governing principle:

  > Decide-or-assume everything at planning time; never block mid-run. The approved plan is the
  > authorization boundary — anything inside it runs; anything that would deviate is parked and
  > reported, not silently done and not blocked on.

  Autonomous mode may start **only after the Preflight Readiness Gate returns GO**
  (`resources/knowledge-base/PREFLIGHT.md`) — that gate front-loads every access, asset, tool, and
  open decision so the run never stalls. It maps onto the Workflow tool (background by design); the
  full Figma pre-cache is what lets it run without the interactive Figma MCP. Unanswered questions
  become `decisions/*.md` with `status: assumed` + a default; failing sections are **parked, not
  halted**; the **PR is the single review surface** and carries the assumptions, parked sections,
  and "requires human verification" list.

---

## Local Knowledge Base (hard prerequisite)

This skill maintains a persistent knowledge base in the **target project** (the Shopify theme repo) under `.claude/knowledge/`, with a managed index block in the project's root `CLAUDE.md`. Every invocation must:

1. **Bootstrap.** Run `resources/knowledge-base/BOOTSTRAP.md`. Idempotent. Creates the KB layout if missing, manages the marker-bracketed block in `CLAUDE.md`, appends gitignore entries for `runs/` and `extraction/*/screenshots/`. Never blanket-touch `.claude/`.
2. **Read before writing.** Run `resources/knowledge-base/READ_PROTOCOL.md`. Always-read: CLAUDE.md index, `glossary.md`, `technologies/stack.md`, `decisions/` (status `decided` or `assumed`), `plans/current.md`, `tasks.md`. On-demand for this skill: `design/tokens.md`, `design/tokens.json`, `design/interactions.md`, `design/typography.md`, `extraction/figma/manifest.json`. Summarize the recovered context to the user in one paragraph before any planning question or MCP call.
3. **Route every Figma MCP call through the cache.** See `resources/knowledge-base/FIGMA_CACHE.md`. Manifest is the only write path. Default behavior: read from cache when an entry exists; announce the cache hit (`Using cached Figma context for <label> (cached <date>). Pass "refresh figma" to force re-fetch.`). Refresh triggers: explicit user keyword, cache miss, `cached_at` older than 30 days, or detected design-shift signal.
4. **Write at phase boundaries.** During a run, only `tasks.md`, `plans/current.md`, `runs/`, and `extraction/` may be written. `architecture/`, `design/`, `decisions/`, `glossary.md`, `technologies/`, and the `CLAUDE.md` managed block update when a logical phase or page completes.
5. **Apply CLAUDE.md trigger rules.** See `resources/knowledge-base/CLAUDE_MD_RULES.md`. Specifically for this skill: the `f2s_` prefix convention belongs in the CLAUDE.md Conventions section the first time it's introduced.

Decisions and assumptions live in the same folder (`decisions/`) and are differentiated by frontmatter `status: assumed | decided | superseded`. When the user confirms an assumption, flip the status in place.

Shared KB files (`design/tokens.md`, `design/tokens.json`, `architecture/overview.md`) may be touched by the frontend skill in this library. If `last_writer` differs from this skill, **append** rather than overwrite, and surface the conflict to the user.

---

## Git workflow (hard rules, every task)

Full protocol in `resources/knowledge-base/GIT_WORKFLOW.md`. Non-negotiables:

1. **Branch per task** off `main`: `<type>/<short-description-hyphenated>[-<TASK-ID>]` where `<type>` ∈ `feat` | `fix` | `chore`. Examples: `feat/homepage-hero-CALC-033`, `fix/cart-drawer-stacking`, `chore/upgrade-dawn-2-12`.
2. **Commit per subtask** (or tightly-coupled group). Title = subtask name. Grouped commits list each subtask in description.
3. **QA gates before every commit**: automated tests → automated QA (theme check, lint, schema validators) → human QA (user spot-check in theme preview). Never `--no-verify`. **In autonomous mode the human spot-check is dropped** — the commit proceeds on the automated gates alone and all human review defers to the PR (see `AUTONOMOUS_MODE.md`).
4. **Push only at task completion.** Then `gh pr create` with summary, plan-archive link, decisions list, and reviewer test plan. Tell the user the PR URL and request human Code Review and QA.
5. **Never** include `Co-Authored-By:` (or any "Co-authored" mention) in commits or PR bodies.
6. **Optional per-project commit prefix.** First-run prompt; stored at `.claude/knowledge/decisions/0001-commit-prefix.md`. If non-empty (e.g. `f2s:`), prepend to every commit title and reflect in `CLAUDE.md` Conventions block. The `f2s_` file/CSS/JS prefix is a separate convention and is unchanged.
7. **Parallelism.** Each task on its own branch lets multiple agents/devs work concurrently. `tasks.md` In-progress items carry owner + branch annotations.

Additional hard rules: never combine unrelated subtasks; never amend/force-push without explicit user request; never branch on a dirty tree without confirmation; never PR `main` from `main`.

---

## Required Tooling

Use the available tools that are relevant to the repository and project:

- Figma MCP for reading designs, nodes, styles, variables, tokens, frames, measurements, assets, and variants. **All Figma MCP calls go through the cache layer described in `resources/knowledge-base/FIGMA_CACHE.md`. Read from `.claude/knowledge/extraction/figma/` first; only call MCP on a cache miss or explicit refresh.**
- Shopify theme development best practices — folded in natively at `resources/knowledge-base/SHOPIFY_BEST_PRACTICES.md` (no separate skill required). Read it before any data-driven section.
- Shopify CLI for local render, theme check, and push/pull (`shopify theme dev|check|pull|push`).
- Existing repo scripts for linting, formatting, theme checks, local preview, and validation.

Do not guess values that can be extracted from Figma. Use the cache first; fall back to Figma MCP on miss.

If a value cannot be reliably extracted from Figma, ask the user during planning.

---

## Plan Mode Requirements

When entering plan mode, first collect the implementation context.

Ask the user for:

1. Figma URL or URLs.
2. Target Shopify page or pages.
   - Examples:
     - `templates/index.json`
     - `templates/product.json`
     - `templates/page.about.json`
     - `templates/collection.json`
3. Whether the current theme is Dawn, Dawn-derived, or a custom OS 2.0 theme.
4. Whether the implementation should replace the existing page composition or be added as new alternate templates.
5. Any known third-party apps used for:
   - Reviews/testimonials
   - Galleries
   - Shoppable videos
   - Product bundles
   - Subscriptions
   - Upsells/cross-sells
   - Size charts
   - Product accordions
   - Store locators
   - Before/after galleries
6. Whether text and image content should be managed through:
   - Theme settings
   - Section/block settings
   - Product metafields
   - Collection metafields
   - Metaobjects
   - Shopify-native product/collection data
   - Third-party app output
7. Whether product-related content should come from metafields.
   - Especially ask this for:
     - Product descriptions
     - Materials
     - Ingredients
     - Shipping details
     - Product hero content
     - Product information accordions
     - Icons
     - Badges
     - Product comparison tables
8. Any known responsive requirements beyond the Figma frames.
9. Any animation, slider, carousel, tab, accordion, sticky, hover, reveal, or custom interaction expectations.
10. Whether the user wants reusable generic sections or one-off page-specific sections.

If Figma tokens, styles, or variables do not provide enough detail, ask targeted questions about:

- Typography
- Font loading strategy
- Spacing scale
- Container widths
- Breakpoints
- Border radius
- Shadows
- Color tokens
- Hover states
- Active states
- Button variants
- Mobile stacking behavior
- Section spacing
- Image cropping behavior
- Product card behavior
- Slider/carousel behavior

Do not proceed with implementation until the plan clearly identifies the pages, sections, blocks, app-backed areas, and unresolved assumptions.

**Preflight Readiness Gate (required before an autonomous run; recommended always).** Run
`resources/knowledge-base/PREFLIGHT.md` and produce a GO / BLOCKED verdict at
`.claude/knowledge/plans/preflight.md`. It confirms — up front, as the single approval point — that
everything the build needs is present: the **Figma cache is fully pre-fetched** (design-context,
both-breakpoint reference screenshots, and downloaded assets for every section, so a background run
never needs a live Figma call), the render path is chosen, all app-backed sections and metafield
keys are identified, fonts/assets are available or documented, tooling (`theme-check`, `python3`,
headless Chrome, image-diff) is installed, `gh` is authed, and every open decision is answered or
recorded as an `assumed` default. BLOCKED lists exactly what the user must supply before the run
starts.

**The plan must also schedule, explicitly, in this order:**

1. **A foundation task first** that stands up the Verify Harness (render path + correct/near-match font + image download + measurement script) — before any section is built. Sections built before the harness are built blind; this is the top cause of a weak first pass.
2. **Per-section Research → `spec.json` before that section's build** — the plan treats "extract the design truth" and "build" as distinct steps, with `spec.json` (`must_haves`) as the gate between them. Plan from `get_design_context`, not from layer names.
3. **A goal-backward verify gate per section and per page** — the plan names the independent parity check (both breakpoints) and the page-level integration check as required gates, not optional QA.
4. **Editability + handoff as deliverables** — the Theme-Editor Wiring Audit and Ship-With-Defaults/`HANDOFF.md` appear as explicit plan items, not afterthoughts.

A plan that lists sections to build but omits the harness, the per-section `spec.json`/verify gates, and the editability/handoff deliverables is incomplete — that shape of plan is what produced a ~50% first pass.

---

## Figma Analysis Requirements

Use Figma MCP to inspect the provided design — **after consulting the cache.** For each Figma URL:

1. Parse the URL into `fileKey` and `nodeId` (per `FIGMA_CACHE.md` § URL parsing).
2. Compose the cache key `<fileKey>__<nodeId-dashed>`.
3. Look up the entry in `.claude/knowledge/extraction/figma/manifest.json`.
4. If `calls.design_context` exists and no refresh is requested, read the cached `raw/nodes/<key>.json`. Announce the cache hit. Same for `metadata`, `screenshot`, and `get_variable_defs`.
5. If missing or refresh-triggered, call MCP, write `raw/.../<key>.json`, update the manifest entry (`cached_at`, `etag`), and append the consuming KB file to `consumed_by` when known.

Persist the analysis output (mapping table, page breakdown, token inventory) into the KB at phase end:

- Token inventory → `.claude/knowledge/design/tokens.md` and `tokens.json` (merge with `last_writer` guard).
- Repeated component catalog → `.claude/knowledge/design/components.md`.
- Interaction patterns (sliders, accordions, hover/active states) → `.claude/knowledge/design/interactions.md`.
- Typography decisions and font loading strategy → `.claude/knowledge/design/typography.md`.
- Figma-to-Shopify mapping table → `.claude/knowledge/plans/current.md` under a `## Mapping` section.

For each page, identify:

1. Page/frame name.
2. Target Shopify template.
3. Desktop frame.
4. Mobile frame.
5. Tablet frame, if available.
6. Global design tokens:
   - Colors
   - Fonts
   - Font sizes
   - Font weights
   - Line heights
   - Letter spacing
   - Spacing
   - Radii
   - Shadows
   - Borders
   - Container widths
7. Repeated components:
   - Buttons
   - Cards
   - Product cards
   - Accordions
   - Tabs
   - Review cards
   - Gallery cards
   - Slider arrows
   - Slider dots
   - Badges
   - Icons
8. Asset requirements:
   - Images
   - Icons
   - Backgrounds
   - SVGs
   - Videos
   - Decorative shapes

Generate a Figma-to-Shopify mapping table before coding.

The table must include:

| Figma Node / Frame | Shopify Target | Section Type | Blocks | Data Source | Interactions | Notes |
|---|---|---|---|---|---|---|

Section Type should be one of:

- `static-content`
- `hero`
- `product-hero`
- `product-information`
- `catalog-grid`
- `catalog-hybrid-grid`
- `collection-list`
- `image-gallery`
- `reviews-app-backed`
- `gallery-app-backed`
- `video-app-backed`
- `custom-interaction`
- `global-component`
- `theme-layout`
- `unknown-needs-confirmation`

---

## Verify Harness (foundation prerequisite — build before any section)

Verification is impossible without a render+compare loop. Build this in the **foundation task, before section 1** — not reactively. Without it, sections are authored blind and the first pass lands ~50%.

The harness has four parts, all required:

1. **Render path.** Prefer `shopify theme dev` (real Liquid). If store auth is unavailable, build a **real-CSS static preview generator** that, per section, inlines the actual `f2s_design_tokens.css` + base CSS + the section's real `{% stylesheet %}` block and emits markup that **mirrors the section's real DOM/classes**. Never hand-simplify a section in the preview — a drifted preview is worse than none (it hides real bugs and invents fake ones).
2. **Correct font (hard gate).** The render MUST use the brand font, or a documented condensed near-match (e.g. Oswald/Anton for a condensed display face). **Verification under the wrong font is invalid** — a substitute that is wider/narrower fabricates wrapping and vertical-rhythm "spacing" problems that don't exist, and masks ones that do. If the licensed font isn't available yet, load the near-match in the harness and record the substitution.
3. **Real images.** Download every referenced Figma image/icon (per node via `get_screenshot`/`download_assets`) into the cache and wire them in. Placeholders make spacing and proportion unjudgeable.
4. **Measurement script.** A headless script that loads the rendered section and reads computed box metrics (`getComputedStyle`, `getBoundingClientRect`) of key nodes, to assert spacing/structure against the section `spec.json` (see below). This is the deterministic half of spacing verification.

Capture, per section node, a **reference screenshot at desktop (1440) and mobile (375)** into the cache. Verification diffs the render against these cached PNGs — it does **not** re-call the Figma MCP (that's why the cache exists; see `FIGMA_CACHE.md`).

---

## Per-Section Build & Verify Loop (hard gate)

Every section runs this loop. A section is not "done" until step 6 passes with an empty discrepancy list. This mirrors the research → plan → build → goal-backward-verify discipline of a phased planning system: extract the truth first, define checkable `must_haves`, then prove the build delivers them with independent verification.

**1. Research (extract, don't assume).** From the section node, via the cache: `get_design_context` (the code), `get_metadata` (skeleton), `get_variable_defs` (tokens), `get_screenshot` at 1440 **and** 375, and download all image/icon nodes. Read the design-context literally, including gotchas (opacity-0 spacers, absolute overlays, band-driven color flips).

**2. Write `spec.json` (the section's `must_haves`).** Persist the extracted truth as checkable assertions — never rounded, taken verbatim from `get_design_context`:
```
band: "#1a2c4e"
spacing: { section: {pb:120, pi:80}, gutter-right:310, grid:{template:"repeat(3,1fr)", col-gap:16, row-gap:80}, card:{padding:28, gap:20} }
type: { title:{size:56, lh:0.92, ls:0, weight:800, transform:upper, color:inverse},
        eyebrow:{size:12, ls:3, color:accent-red} }   # band-override gotcha captured
structure: "4 corner cards + centered product image; middle-top card is opacity-0 spacer"
images: [ben_clean.png, ben_center.png, ...]
breakpoints: { "375": { section:{pi:20}, grid:{template:"1fr"} } }   # mobile is its OWN spec
```
Store alongside the reference PNGs + assets per `FIGMA_CACHE.md`.

**3. Build** to the `spec.json`. Spacing rule (this is where first passes drift): **use the exact Figma px.** Map a value to a token only if the token *equals* it; if Figma says `310` and the scale jumps `280→320`, add a token or use the literal — **never snap to the nearest token.** Set `line-height` and `letter-spacing` exactly (they drive vertical rhythm as much as margins do). Wire every text/image to a setting (step 5 of Core Priorities).

**4. Render** the section at 1440 **and** 375 with the harness (correct font, real images).

**5. Verify spacing in two classes** — they look identical but need opposite handling, and conflating them is what makes "spacing" feel unfixable:
   - **Box spacing (value-driven, font-independent):** padding, margin, gap, grid template. Assert with the **measurement script** against `spec.json` (±2px). This catches e.g. `padding-right` being a wrong percentage instead of `310px` — deterministically, no eyeballing.
   - **Text-flow spacing (font-driven):** line wrapping, vertical rhythm. Catch with the **visual diff** against the cached reference — but only meaningful under the correct font (step 2 of the harness).

**6. Goal-backward verify (independent + gated).** Render-vs-reference diff at **both breakpoints**, plus the spec rubric below, run by a **separate parity subagent** (the builder does not grade its own work), with a revision loop. The section passes only when the discrepancy list is empty. Per-section rubric the verifier must clear:
   - Background/band color · container gutter · section padding · inter-element gaps · grid columns & gaps · card/structure (incl. overlays/spacers)
   - Type: family · size · line-height · letter-spacing · weight · transform · **color in *this* band context** (re-check on navy vs red vs cream — band overrides flip eyebrow/title/text colors)
   - Border-radius · shadows · icon/image presence and crop/focal
   - **Mobile (375) as a first-class pass**, not an afterthought — its own padding, stacking, type scale
   - Theme-editor wiring (every text/image is a setting; see audit) · realistic + edge-case data (long title, no compare-at price, sold-out, no selling plan, missing image)
   - Interaction states (hover/focus/open/variant-change), reduced-motion, keyboard, and contrast

If verify exposes a mismatch `spec.json` didn't predict, the research for that node was incomplete → re-research **that one node** (not everything), update `spec.json`, rebuild.

---

## Agent Roles & Level of Effort (orchestration)

This skill is for **full theme builds**, not minor edits. The explicit, accepted tradeoff: it spends
more tokens and more wall-clock to reach design parity, because re-doing a half-right theme costs far
more than the agents do. Do not optimize this skill for cheapness — optimize it for an empty
discrepancy list on the first integration. Use the tiers below; when genuinely unsure between two
tiers, pick the higher one.

The orchestration mirrors the user's GSD process: a planning-heavy front, then a **build → independent
QA → fix → integrate** loop per section, with hard parity gates. Roles are distinct agents — and one
rule is non-negotiable: **the builder never grades its own work.** The parity verifier must be a
*separate* agent from the builder (different invocation, ideally adversarially prompted), or the gate
is theater.

### Level-of-effort matrix

Effort = reasoning effort (`low` | `medium` | `high` | `xhigh` | `max`) passed to the agent. Model =
the tier the role runs at. The principle behind the assignments: **Opus on judgment, Sonnet on
mechanics, Haiku on rote.** Extraction and verification are where errors poison everything downstream,
so they get the most; translating an exact `spec.json` into Liquid is comparatively deterministic.

| # | Role | Model | Effort | Why this tier |
|---|------|-------|--------|---------------|
| 0 | **Orchestrator** (main loop) | Opus | high | Holds the plan, sequences gates, decides pass/fail/re-research, resolves cross-section conflicts. Never delegate the gate decision. |
| 1 | **Theme/Figma audit** (Gate-0 inventory) | Opus | high | Per-page disposition (replace/keep/ignore) and the full Figma inventory set the scope of everything; a miss here is unrecoverable later. |
| 2 | **Harness/foundation builder** | Sonnet | medium | Mechanical: stand up render path, wire correct font + real images, install the measurement script. Follow VERIFY_HARNESS.md. |
| 3 | **Section research → `spec.json`** | Opus | high (xhigh for layered/overlay sections) | Reading `get_design_context` *literally* and catching gotchas (opacity-0 spacers, absolute overlays, band-driven color flips). Highest-leverage step — an inexact spec guarantees a failed verify. |
| 4 | **Section builder** | Sonnet | medium-high | Translate an exact `spec.json` into Liquid/CSS/schema. Largely deterministic *if* the spec is exact; bump to high for heavy interaction/JS. |
| 5 | **Independent parity verifier** | Opus | high (xhigh on the page-level integration check) | Adversarial visual + measurement diff at 1440 **and** 375 against the cached reference, against the full rubric. This is the gate. Must differ from the builder (#4). |
| 6 | **Fix agent** | Sonnet | medium | Apply a concrete, enumerated discrepancy list with targeted edits. The judgment already happened in #5. |
| 7 | **Page integration** | Opus | high | Inter-section spacing, band transitions, section order — cross-section rhythm that per-section passes can't see. |
| 8 | **Global design-system / CSS** | Sonnet | medium | Apply theme-wide tokens (typography/buttons/forms/links) across every template. Mechanical once the token set is decided. |
| 9 | **Editability / Theme-Editor wiring audit** | Sonnet | medium | Grep for hardcoded copy/URLs, confirm each node is a setting with a Figma-valued default, repeatable groups add/remove/reorder. |
| 10 | **Handoff / docs / report** | Sonnet | low-medium | Write `HANDOFF.md`, the metafield contract, the implementation report. Bump if it must reason about deviations. |

Haiku is appropriate only for truly rote fan-out (e.g. bulk asset download bookkeeping, mechanical
file renames); do not put it on anything that reads a design or judges a render.

### Orchestration shape (with the Workflow tool)

When orchestrated via the Workflow tool, the per-section loop is a **pipeline** so each section
verifies the moment its build lands, instead of a barrier that idles fast sections:

```
pipeline(sections,
  s    => agent(researchPrompt(s), {phase:'Spec',   model:'opus',   effort:'high',        schema: SPEC}),
  spec => agent(buildPrompt(spec),  {phase:'Build',  model:'sonnet', effort:'medium-high'}),         // builder
  _    => agent(verifyPrompt(s),    {phase:'Verify', model:'opus',   effort:'high',        schema: DISCREPANCIES}),  // independent
)
// then loop: while discrepancies non-empty → fix(Sonnet/medium) → re-verify(Opus/high)
// finally:  page integration (Opus/high) over the assembled page vs the full Figma frame
```

Barriers are correct only where a stage genuinely needs all prior results at once — e.g. dedup a
combined discrepancy list before fixing, or the page-level integration check (which by definition
needs every section present). Default to pipeline; see the Workflow tool guidance.

### Effort dials

- **Tighten** (drop a tier) only for: a section that is pure static content with no overlays, a
  trivial copy/spacing fix, or a mechanical rename. Never tighten research (#3) or verify (#5).
- **Escalate** (raise a tier / add a second independent verifier) when: a section failed verify
  **twice** (the spec or the read is wrong — put Opus/xhigh on a fresh re-research), a section has
  layered hero/overlay/absolute positioning, or the page-level integration diff is ambiguous.
- The independence rule overrides cost every time: if you can only afford one Opus call on a section,
  spend it on **verify**, not build — a wrong build caught is cheap; a wrong build shipped is not.

### Enforcement — docs are inert unless required and checked

A reference file helps only if agents are made to use it. Two hard rules:

1. **Every builder, fixer, and verifier spawn prompt must embed the instruction to read
   `resources/knowledge-base/SHOPIFY_BEST_PRACTICES.md` and the file-header doc standard below** (paste
   the relevant rules into the prompt — a subagent does not inherit this skill's context automatically;
   assume it starts blank).
2. **The parity verifier's rubric includes a documentation + Shopify-mechanics pass** (file header
   present and accurate, schema correctness, `render` not `include`, metafields on default templates,
   registry updated). A section that renders correctly but ships undocumented or with wrong data
   sources **fails** verify.

---

## Code Documentation & Multi-Agent Collaboration

Multiple agents build, fix, and integrate the same theme — often in parallel. Clean output under that
model is not automatic; it requires that any agent can pick up any file and know what it does, what it
depends on, and who owns it, **without re-reading the whole repo or re-deriving it from Figma.** Three
mechanisms make that true. They are mandatory, not stylistic.

### 1. In-code file header (every `f2s_` file)

Every section, snippet, CSS, and JS file opens with a header comment in the file's native comment
syntax. This is the local contract — the next agent reads it first.

```liquid
{% comment %}
  f2s_product_buybox.liquid
  Purpose: PDP add-to-cart — variant + size selector, price, subscribe toggle.
  Spec:    .claude/knowledge/extraction/figma/<key>/spec.json
  Data:    product object (title/price/variants/availability);
           product.metafields.custom.{highlights, shipping_note}  (fallbacks in schema)
  Renders: f2s_variant_pills, f2s_price
  Assets:  f2s_product.css (.f2s_buybox*), f2s_product.js (data-f2s-buybox)
  Settings: see {% schema %} — eyebrow, show_subscribe, trust_badges[]
  Owner:   agent-pdp / branch feat/pdp-buybox    Updated: 2026-06-24
{% endcomment %}
```

Required fields: **Purpose, Spec link, Data sources (objects + exact metafield keys), Renders/Assets
dependencies, Settings summary, Owner+branch+date.** CSS/JS files use `/* … */` with the same fields
plus the **namespace they own** (class prefix / `data-` attribute) so no other file writes into it.
Non-obvious Liquid gets inline comments; the gotchas captured in `spec.json` (opacity-0 spacer,
band-flip) are repeated as a one-line inline comment where they live in the markup.

### 2. Component registry (single source of truth)

Maintain `.claude/knowledge/architecture/f2s_registry.md` — one row per `f2s_` file.
Any agent that creates or materially changes a file updates its row in the same commit. This is what a
new agent reads to onboard instead of grepping the tree.

| File | Type | Purpose | Inputs (settings / metafields / objects) | Depends on | Owns (CSS ns / JS sel) | Used on |
|------|------|---------|------------------------------------------|------------|------------------------|---------|

The registry is the **interface contract** between agents: the design contract is `spec.json`; the
*code* contract is this table plus the file header. A fixer or integrator reads the row, not the
builder's mind. Drift between a file and its registry row is a verify failure.

### 3. Shared-file ownership (collision control)

Most files are section-local and safe to build in parallel. A small set of **hot shared files** are
touched by many sections and will clobber each other if edited concurrently:

- `assets/f2s_design_tokens.css` (and any shared base CSS)
- `layout/theme.liquid`, section-group JSON (`*-group.json`)
- `config/settings_schema.json`, `config/settings_data.json`
- `locales/*.json`
- shared snippets (`f2s_product_card`, `f2s_responsive_image`, icon snippets)
- the template JSON being assembled (`index.json`, `product.json`, …)

Rules for hot files:
1. **Serialize, don't parallelize.** Only the **orchestrator or a single designated owner agent** edits
   a hot file. A section agent that needs a new token/locale string/shared-snippet change **requests**
   it (returns the need in its result); the owner applies it. Never let two parallel section agents
   edit tokens.css.
2. **Tokens and shared snippets are decided up front**, in the foundation phase, so the parallel build
   phase reads them as stable. New tokens discovered mid-build are appended by the owner, never
   redefined.
3. **Template JSON assembly is the integration agent's job** (role #7), after sections are individually
   green — section agents create their section file but do not race to edit `index.json`.

### 4. Worktree isolation for parallel builders

When fanning out builders concurrently (Workflow `isolation:'worktree'` or branch-per-task), each works
in its own tree so section-local edits never collide. The **integration agent** merges and runs the
page-level gate. Hot-file changes still route through the owner (rule 3 above) even across worktrees —
isolation prevents file collisions, not semantic ones (two sections each adding a `--space-7` token
with different values is a semantic collision a worktree won't catch; the registry + single owner do).

**The test for "did we build cleanly":** a fresh agent, given only the registry + a file's header, can
correctly modify that file without opening Figma or reading sibling sections. If it can't, the
documentation failed and that's a verify defect — same standing as a visual mismatch.

---

## Component Kit & Reuse (build the shared layer first)

Full rules in `resources/knowledge-base/COMPONENT_REUSE.md`. The non-negotiables:

**The reuse boundary.** *Reuse at the snippet (rendering) layer; accept duplication at the schema
(block) layer.* A block owns its `{% schema %}` settings and Liquid has no schema include — so two
sections needing the same block copy the JSON, and **that duplication is fine, do not fight it.** The
snippet a block *renders* is the reuse primitive (`{% render %}`, isolated scope, explicit args) —
share that aggressively. Trying to DRY block schemas is what makes reuse "cause more issues."

**A kit snippet is reuse-safe only if** it (1) reads nothing ambient — all data via `render` args;
(2) takes per-instance styling as values applied through CSS custom properties; (3) lets the *caller*
emit `{{ block.shopify_attributes }}`; (4) carries no `{% stylesheet %}` (that tag is section-only —
shared-snippet CSS lives in a shared asset). A snippet that violates these is the "reuse broke things"
failure mode — fix the snippet, don't abandon reuse.

**Build the kit in the foundation phase, before parallel section build.** Turn the repeated-component
catalog (`design/components.md`) into actual built snippets + shared component CSS, registered in
`architecture/f2s_registry.md`. Section builders **assemble from the kit and may not
re-author kit components** (a reimplementation is a verify failure). New shared needs discovered
mid-build route to the kit owner, never to two parallel builders. **Reuse the base theme too:** before
building any snippet decide extend-Dawn · wrap · build-new, and build-new needs a one-line
justification — the `f2s_` prefix is for *new* files, not a mandate to reimplement Dawn.
Theme blocks (`/blocks/`) only if the detected Dawn version cleanly supports them.

## Page and Task Decomposition

Treat each page as a major task.

Each page must be split into smaller tasks:

1. Global dependencies for that page.
2. Template composition.
3. Global tokens required by the page.
4. Shared snippets required by the page.
5. Each section as its own task.
6. Blocks inside each section as subtasks where appropriate.
7. Interaction logic as separate subtasks.
8. App integration as separate tasks after the base visual implementation.
9. Page-specific validation.
10. Page-specific performance pass.

Example task structure:

```md
## Page Task: Homepage

### Task 1: Audit current homepage composition
### Task 2: Extract Figma tokens and assets
### Task 3: Create/update global custom tokens
### Task 4: Implement hero section
  - Subtask: Section schema
  - Subtask: Desktop layout
  - Subtask: Mobile layout
  - Subtask: Image handling
  - Subtask: CTA settings
### Task 5: Implement featured collection grid
  - Subtask: Collection source settings
  - Subtask: Curated product blocks
  - Subtask: Hybrid fill behavior
  - Subtask: Product card snippet
### Task 6: Implement testimonial visual shell
### Task 7: Integrate review app into testimonial shell
### Task 8: Validate homepage
### Task 9: Mobile performance improvement pass
```

After each completed **subtask** (with all QA gates passed — see Git Workflow section):

```bash
git status
git add <changed-files>
git commit -m "<subtask name>"   # prepend the per-project prefix from decisions/0001-commit-prefix.md if configured
```

Do **not** push between subtasks. Push only at the end of the whole task, then open a PR. Never include `Co-Authored-By:` trailers.

---

## File Naming Rules

All new project files must use the `f2s_` prefix.

Examples:

```txt
sections/f2s_home_hero.liquid
sections/f2s_product_information.liquid
snippets/f2s_product_card.liquid
snippets/f2s_responsive_image.liquid
assets/f2s_design_tokens.css
assets/f2s_home.css
assets/f2s_product.css
assets/f2s_carousel.js
assets/f2s_accordion.js
```

All new section names, block names, CSS classes, JavaScript selectors, and custom data attributes should also use the `f2s_` prefix where practical.

Examples:

```liquid
class="f2s-hero"
data-f2s-carousel
data-f2s-accordion
```

Avoid naming collisions with Dawn, Shopify apps, or existing theme code.

**Names must say what the section does — two distinct names, both gated.**

1. **Filename / code name:** `f2s_<area>_<purpose>` (area = `home`/`product`/`collection`/
   `global`; purpose = role: `hero`/`benefits`/`featured_grid`/`testimonials`). **Never** the bare
   prefix or a placeholder word (`f2s_section`, `f2s_block`, `f2s_content`),
   and never position-named (`f2s_feature_1`). The file header's `Purpose:` matches the name.
2. **Merchant-facing schema `name`:** plain English the merchant reads in the Theme Editor ("Hero
   banner", "Featured collection grid"). A merchant must **never** see the word `f2s` — the
   code prefix does not belong in the schema `name` (see `SHOPIFY_BEST_PRACTICES.md` §10).

Both are hard gates in `f2s_codehealth.sh` (bare/generic names and prefixed schema names fail
the build, same standing as a position-named file). Name by purpose *as you go*, not in a later pass.

---

## Theme Architecture Rules

Use Shopify OS 2.0 conventions.

Prefer:

- JSON templates for page composition.
- Sections for reusable page regions.
- Blocks for repeatable content.
- Snippets for reusable rendering logic.
- CSS assets scoped to custom sections.
- JavaScript assets only when required by actual interactions.
- Theme settings, section settings, blocks, metafields, or metaobjects instead of hardcoded content.

Avoid:

- Hardcoded product titles.
- Hardcoded product prices.
- Hardcoded product images.
- Static duplicates of app content.
- Global CSS overrides unless required.
- Vendor app selectors outside scoped wrappers.
- Editing app-generated code directly.
- Leaving old page sections that are not part of the Figma design.
- Adding duplicate app sections.

---

## Shopify Development Best Practices (native)

This skill is self-contained on Shopify mechanics — you do not need to load a separate
Shopify-development skill. The canonical patterns and rules are folded into
`resources/knowledge-base/SHOPIFY_BEST_PRACTICES.md`; read it before building any data-driven
section (PDP, collection grid, cart) and treat its checklist as part of the verify rubric. The
non-negotiables, inline:

1. **Liquid is the data layer.** `product.title | price | featured_image | url | available | variants`,
   collection counts, and cart totals come from objects — hardcoding any of them is a build defect.
2. **Use the real form/pagination/cart shapes.** `{% form 'product', product %}` with
   `selected_or_first_available_variant` and `has_only_default_variant`; `{% paginate %}` around every
   product loop; the standard `/cart/add.js|change.js|cart.js` endpoints (reuse the theme's existing
   cart plumbing).
3. **`{% render %}`, never `{% include %}`.** Pass every dependency as an explicit argument.
4. **Product-specific content → `product.metafields`** (with `.value` for typed fields), *especially*
   on a default template that serves every product. Section settings on a default template are shared
   across all products — correct only for genuinely-global marketing copy. This is the #1 PDP
   architecture defect: right on the previewed product, wrong on the rest.
5. **Performance, a11y, SEO, code quality, CLI** — the condensed rules live in the reference file and
   feed the Performance Improvement Pass, the Accessibility Requirements, and the QA gate
   (`shopify theme check` before every commit).

When design fidelity and Shopify mechanics appear to conflict: fidelity wins on *appearance*, Shopify
mechanics win on *data source, form semantics, and performance*. They rarely truly conflict — a
faithful render almost always has a Shopify-correct implementation.

---

## Content Source Decision Rules

**Default: everything visible is theme-editable.** Treat hardcoding as the exception you must justify, not the default. If a merchant could plausibly want to change it — copy, image, icon, link, eyebrow, badge, price-suffix, accent color, the *number* of repeatable items, even section background band — it is a setting. The only things hardcoded are structural scaffolding (layout grids, the `f2s_` class names) and brand-fixed design tokens. When in doubt, make it editable.

For every piece of text, image, icon, video, or product-related content, decide whether it should be powered by:

1. Section setting.
2. Block setting.
3. Theme setting.
4. Product field.
5. Product metafield.
6. Collection field.
7. Collection metafield.
8. Metaobject.
9. Shopify file/image picker.
10. Third-party app output.

When unsure, ask the user.

Especially ask before implementing product-related content such as:

- Product hero description
- Product highlights
- Materials
- Ingredients
- Benefits
- Shipping information
- Return information
- Product accordions
- Product specifications
- Product icons
- Product badges
- Product comparison data
- Before/after content
- Subscription information
- Bundle information

Default guidance:

- Use product metafields for product-specific structured content.
- Use section settings for page-specific marketing copy.
- Use blocks for repeatable editorial content (and make the count itself editable — add/remove/reorder, not a fixed N).
- Use metaobjects for reusable structured content across many pages.
- Use app output when a third-party app owns the functionality or data.

**Dynamic product data stays dynamic.** Product title/price/variants/media/availability come from the product object, never settings — and the build must survive real data: long titles that wrap, missing compare-at price, sold-out variants, no selling plan (the subscribe UI must degrade), wrong-aspect images. Verify each section against realistic + edge-case data, not the idealized Figma copy.

### YAGNI counterweight (don't build what the design doesn't need)

"Editable by default" governs **content**, not structure or behavior the design never shows. Add a
setting, block, or JS capability only when (a) the design varies it, or (b) the merchant plausibly
needs to change it for *this* section's role — not reflexively. A static 3-up that the design never
treats as a collection does not need the hybrid-grid machinery (collection picker + curated blocks +
fill logic); a section with one fixed CTA does not need four. Unused settings are dead code the
`f2s_dupecheck.sh` advisory and the verifier rubric both flag. Default editable for copy and
imagery; default *not* to invent behavior the Figma node doesn't have.

### Theme-Editor Wiring Audit (gate)

"Merchant-editable" is only true if it's actually wired — and that is **proven, not asserted**. The
audit has two halves; do not collapse them:

**Structural half — deterministic, run the script.** `resources/scripts/f2s_editability.sh`
checks every `f2s_` section for: valid `{% schema %}` JSON; `{{ block.shopify_attributes }}`
emitted wherever `section.blocks` is iterated (without it, blocks are not selectable/reorderable in the
editor — a silent, common defect); editable **text** settings carry a Figma-valued `default` (so a fresh
install renders, not blanks); and it flags orphan settings, undefaulted URLs, possible hardcoded copy,
and unpopulated template JSON. A RED **fails the page**, same as a visual discrepancy.

**Semantic half — the script can't judge it, you must.** Read the liquid and confirm:

1. **Every** text/image node in the Figma section maps to a real setting/block — no hardcoded copy/URLs
   beyond structural defaults (the script's heuristic flags candidates; you confirm).
2. **The data SOURCE is correct, not just present.** On a **default** template (one `product.json`
   serving every product), per-product copy — description, materials, shipping, accordion rows, specs,
   badges — must be a **`product.metafield`**, NOT a shared section setting. A section setting on a
   default template is identical for every product: it *looks* editable and is *wrong* on every product
   but the one you previewed. This is the single defect the structural script cannot catch — it is the
   one you must read for. (See Shopify Best Practices §4 + the metafield contract in `HANDOFF.md`.)
3. **Navigation comes from a menu, not settings.** Header/footer nav must use a `link_list` setting →
   `linklists[handle].links` (merchant edits it under Online Store → Navigation), never hardcoded
   `linkN_url/linkN_label` slots and never section blocks. (See Shopify Best Practices §14.)
4. **Open the Theme Editor once and confirm** every piece appears and repeatable groups add/remove/reorder.
5. Ship populated `settings_data.json` / template defaults so the design is visible on upload — see
   "Ship-With-Defaults & Handoff".

A section that looks right in preview but has hardcoded copy, unselectable blocks, or per-product content
wired to a shared setting **fails** this gate.

### Ship-With-Defaults & Handoff

A fresh install is blank (empty image fields, no licensed font) — so "preview looks perfect" ≠ "store looks perfect." Every project must ship:

- Default content populated in template JSON / `settings_data.json` (copy defaults from Figma; image fields reference uploaded assets where the project allows asset uploads).
- A `HANDOFF.md` listing: template → page assignments (which product/collection template to assign), every image/font/app the merchant must upload or connect to reach parity, and any documented deviations (e.g. font substitution, app-shell sections).

---

## Image and Asset Rules

All images must be compatible with Shopify CDN and optimized for responsive delivery.

Use Shopify image filters whenever rendering Shopify-hosted images.

Prefer patterns like:

```liquid
{{ image | image_url: width: 1200 }}
```

Use responsive `srcset` where appropriate.

Example:

```liquid
<img
  src="{{ image | image_url: width: 800 }}"
  srcset="
    {{ image | image_url: width: 400 }} 400w,
    {{ image | image_url: width: 800 }} 800w,
    {{ image | image_url: width: 1200 }} 1200w,
    {{ image | image_url: width: 1600 }} 1600w
  "
  sizes="(min-width: 990px) 50vw, 100vw"
  width="{{ image.width }}"
  height="{{ image.height }}"
  loading="lazy"
  alt="{{ image.alt | escape }}"
>
```

Rules:

1. Never reference raw local Figma export paths in final Liquid.
2. Use Shopify-hosted assets for theme images.
3. Use image pickers when content should be merchant-editable.
4. Use product/collection image data where the section is product/collection-driven.
5. Use SVG snippets or inline SVG only when appropriate.
6. Add explicit `width` and `height` attributes where possible.
7. Use `loading="lazy"` for below-the-fold images.
8. Use eager loading or fetch priority only for critical above-the-fold images.
9. Avoid unoptimized background images when an `<img>` or `<picture>` would be more performant.
10. If CSS background images are required for fidelity, document the reason.

---

## Product Grid and Catalog Rules

Any product-grid section must support hybrid sourcing.

Required capabilities:

1. Collection source:
   - Collection picker.
   - Product limit.
   - Optional sort behavior if feasible.
2. Curated product blocks:
   - Product picker block.
   - Optional custom badge/text fields if required by design.
3. Fill behavior:
   - If curated products exist, render curated products first.
   - If `fill_from_collection` is enabled, fill remaining slots from the selected collection.
   - If no curated products exist, render collection products.
4. Never hardcode:
   - Product title
   - Price
   - Product image
   - Product URL
   - Availability
5. Product cards should use a reusable `f2s_` snippet when possible.

Schema should make merchant editing straightforward.

---

## App-Backed Section Rules

Some Figma sections may visually represent content powered by third-party Shopify apps.

Common examples:

- Judge.me reviews/testimonials
- Loox reviews
- Yotpo reviews
- Okendo reviews
- Stamped reviews
- Replo sections
- PageFly sections
- GemPages sections
- Vizup shoppable video
- Tolstoy video
- Videowise video
- Instafeed galleries
- Before/after gallery apps
- Subscription apps
- Bundle apps
- Upsell apps
- Size chart apps

When a section may be app-backed:

1. Identify the visual section in Figma.
2. Search the existing theme for relevant app sections/blocks/embeds.
3. Ask the user which app powers that content if it cannot be confidently identified.
4. Do not statically duplicate app content.
5. Build the base visual page first.
6. Integrate the app in a separate task after the base page sections are complete.

Detection checklist:

Search templates, sections, snippets, app blocks, section groups, and theme layout files for:

- `@app`
- App block references
- Section types without matching local files
- Vendor-specific class names
- Vendor-specific script markers
- App snippets
- App embeds
- App-related comments
- Known markers such as:
  - `judgeme`
  - `jdgm`
  - `loox`
  - `yotpo`
  - `okendo`
  - `stamped`
  - `vizup`
  - `tolstoy`
  - `videowise`
  - `replo`
  - `pagefly`
  - `gempages`

Preferred app integration pattern:

1. Create a theme-owned `f2s_` wrapper section.
2. Implement the Figma shell in that wrapper:
   - Container
   - Background
   - Spacing
   - Heading
   - Subheading
   - CTA
   - Card area
   - Arrows/dots shell if needed
3. Render or host the existing app output inside the wrapper.
4. Apply scoped CSS overrides inside the wrapper only.
5. Remove the old standalone app section from the target template if it would create a duplicate.
6. Validate that exactly one user-visible instance remains.

Do not assume vendor internal markup unless inspected.

If vendor-specific selectors are unavoidable:

- Scope them under the wrapper.
- Keep them minimal.
- Document why they are needed.
- Avoid brittle selectors where possible.

---

## Sliders, Carousels, Accordions, Tabs, and Custom Interactions

During planning, identify any section that appears to include:

- Slider
- Carousel
- Marquee
- Tabs
- Accordion
- Sticky element
- Scroll animation
- Reveal animation
- Hover animation
- Video interaction
- Product media gallery
- Variant interaction
- Before/after slider
- Drag interaction
- Swipe behavior
- Filtering
- Sorting
- Dynamic product selection

If an interaction is present or likely, ask the user to confirm expected behavior and implementation preference.

When possible, suggest options.

Example prompt:

```md
The Figma section appears to be a carousel. I can implement this in one of three ways:

1. CSS scroll-snap carousel with minimal JavaScript.
2. Lightweight custom JavaScript carousel.
3. Existing theme/app carousel integration if the project already has one.

Recommended: CSS scroll-snap for performance unless the design requires infinite looping, autoplay, or complex pagination.

Please confirm which behavior you want:
- Swipe on mobile?
- Arrows on desktop?
- Dots?
- Infinite loop?
- Autoplay?
- Pause on hover?
- App-powered or theme-native?
```

Default implementation preference:

1. CSS-first when possible.
2. Minimal JavaScript when required.
3. No heavy dependency unless already present or approved.
4. Accessible controls.
5. Keyboard navigability.
6. Reduced-motion support.
7. Mobile-first performance.

---

## CSS and Styling Rules

Use a token-first approach.

Create or extend:

```txt
assets/f2s_design_tokens.css
```

Load it early enough for custom sections.

Tokens should cover:

- Colors
- Typography
- Spacing
- Radii
- Shadows
- Borders
- Container widths
- Z-index values where needed
- Transitions
- Section spacing

Use section-scoped CSS.

Example:

```css
.f2s-home-hero {
  --f2s-hero-gap: var(--f2s-space-8);
}
```

Avoid broad global selectors.

Avoid overriding Dawn globally unless the design system requires it and the user approves.

**`!important` is a budgeted last resort, not a tool.** Reaching for it usually means the selector
isn't scoped enough — fix specificity (scope under the `.f2s_*` section wrapper, or use a
cascade layer) instead. When it is genuinely unavoidable (overriding an app's inline styles, beating a
vendor `!important`), keep it inside the scoped wrapper and annotate it with an inline `/* why */`
comment. The code-health script counts these against a hard budget; 297 unscoped `!important`s is the
failure mode this prevents — it means the base theme was being fought globally rather than overridden
locally.

Use responsive CSS cleanly:

```css
@media screen and (min-width: 750px) {}
@media screen and (min-width: 990px) {}
```

Match the theme’s existing breakpoint conventions when possible.

---

## Typography Rules

Extract typography from Figma MCP when possible.

If typography cannot be fully determined, ask about:

- Font family
- Font source
- Font loading strategy
- Font weights
- Fallback stack
- Whether fonts should be loaded from:
  - Shopify CDN
  - Theme assets
  - Google Fonts
  - Existing theme settings
  - Existing CSS
- Whether the implementation should reuse Dawn typography settings or introduce custom tokens.

Prefer performance-conscious font loading.

Avoid adding large external font imports without user approval.

---

## Template Composition Rules

When implementing a page from Figma:

1. Audit the current target JSON template.
2. Identify all current sections.
3. Identify which sections should remain.
4. Identify which sections should be replaced.
5. Remove old sections that are not part of the Figma design unless required by the theme, header/footer groups, or explicit user instruction.
6. Do not leave duplicate old sections just because they have similar copy or purpose.
7. Build the new page composition in the exact intended order.
8. Confirm every referenced section file exists.
9. Confirm every referenced block type is valid for its section schema.

For each target page, provide a before/after section map.

---

## Code Health Budgets (objective gate)

Code quality is measured, not asserted. The same data-first discipline used for parity applies here:
report numbers against budgets, never adjectives like "clean" or "maintainable." A real first-pass
audit surfaced exactly these smells — they are now budgeted gates so they can't recur silently:

| Signal | Measure | Gate |
|--------|---------|------|
| `!important` count | `grep -c !important` in `f2s_*.css` | **Hard cap** (default 40). Each one needs an inline `/* why */`. Over budget → scope the CSS / raise specificity, don't add `!important`. 297 was the smell — it means base CSS is being fought globally instead of overridden in a scoped wrapper. |
| theme check | exits 0, 0 offenses | **Hard, blocking.** Never "couldn't run." The `Please provide a valid environment` error is a Shopify CLI 3.x regression (it wraps `theme check` and demands `--environment`). Reliable fix: the standalone gem — `gem install theme-check && theme-check .` (no auth, no env, offline). A build that was never linted is not done. |
| Position-named files | `f2s_feature_1`, `_section_2`, `_block3` | **Zero.** Name by **purpose/role**, not by Figma position or build order. Rename before commit. |
| In-tree backups | `*.legacy` / `*.bak` / `*.old` | **Zero.** Git history is the backup; delete them before PR. |
| Bundled raw images | `f2s_*.png|jpg` in `assets/` | **Soft cap** (default 15). Prefer `image_picker` + CDN so content is merchant-editable; bundle only brand-fixed decorative assets, and document each in the registry. |
| Duplicate sections | reuse-first check | Before creating a section, check the registry for a near-duplicate — extend/parameterize the existing one instead (the editorial/feature-banner merge was this smell). |

Run `resources/scripts/f2s_codehealth.sh` (prints the table + PASS/FAIL on the hard gates —
now including the **naming gates**: bare/generic filenames and prefixed merchant-facing schema names
fail the build). It is part of the **QA gate before every commit** and the **page-level validation**.
A red signal has the same standing as a visual discrepancy — the page is not done until the script
returns PASS.

**Duplication / dead-code (advisory).** Run `resources/scripts/f2s_dupecheck.sh` alongside it:
it flags exact-duplicate snippet bodies, repeated multi-declaration CSS blocks, unused section
settings, and dead control-flow — i.e. the AI rewriting the same thing across sections or shipping
code nothing uses. It is **advisory** (exits 0; `F2S_DUPE_STRICT=1` makes exact-duplicate
snippets a hard fail) and, per the reuse boundary, **deliberately ignores schema duplication** — that
is allowed (see `COMPONENT_REUSE.md`). Review its signals before commit; the verifier rubric also
checks for reimplemented kit/Dawn components.

**Naming + cleanup are not afterthoughts.** Because parallel agents read files by name and registry row,
a position-named or backup file actively misleads the next agent. Rename and delete *as you go*, gated
by the script, not in a deferred "hardening pass" that may never come.

---

## Validation Requirements

Validation is **goal-backward**: prove the build delivers the design, not that tasks ran. Per-section parity is gated by the Per-Section Build & Verify Loop above. The items below are the **page-level** gate, run after the sections are individually green.

**Code correctness:**

1. JSON templates are valid.
2. Liquid files have no syntax errors.
3. Section schemas are valid JSON.
4. All section / snippet / asset references exist.
5. No duplicate app-backed section; no old unrelated page sections remain.
6. Images use Shopify CDN/image filters with width/height (CLS), `srcset`/`sizes`, and eager+`fetchpriority` on the LCP image, lazy below.
7. Product grids/sections do not hardcode product data; build survives edge-case data (long title, no compare-at, sold-out, no selling plan, missing image).
8. Lint/theme-check passes where available (run only scripts that exist; do not invent).
8a. **Code-health script returns PASS** — `resources/scripts/f2s_codehealth.sh` (theme check clean, `!important` within budget and justified, zero position-named files, zero in-tree backups, bundled-image budget, registry up to date). A red signal blocks the page the same as a visual discrepancy.

**Parity (proven, both breakpoints):**

9. **Per-section loop passed for every section** — measurement check + visual diff vs cached reference at **1440 and 375**, by the independent parity subagent, discrepancy list empty.
10. **Page-level integration check** — render the *whole page* and diff against the full Figma frame: section order, **inter-section spacing**, and band transitions (the rhythm between sections, not just within them). Sections can each be correct yet wrong when stacked.
11. Shared components (heading, product card, benefits, testimonials, how-it-works, etc.) verified in **every context they're used** (e.g. home vs PDP) — a change for one context must not break the other.

**Responsive integrity (no design needed, distinct from parity):**

11a. **Tablet/mid-band (≈750px) doesn't break.** Parity is proven only at the breakpoints you have
designs for (375 + 1440); you cannot diff against a comp you don't have. The 750–989 band instead
gets an *integrity* check — render at 750 with `window.F2S_INTEGRITY = true` and assert (via
`f2s_measure.js`) **no horizontal overflow, no element wider than the viewport, no sibling
collisions**, plus sensible grid reflow. This is a "doesn't break," not a "matches Figma," gate — do
**not** fold it into the parity score. If there are no tablet designs, confirm once how the band
should behave (mobile extended vs desktop condensed); default to the theme's existing 750/990
conventions. See `VERIFY_HARNESS.md` §750.

**Editability & robustness:**

12. Theme-Editor Wiring Audit passes — **structural half** via `resources/scripts/f2s_editability.sh` returning PASS (valid schema, `block.shopify_attributes` on block loops, text defaults present), **semantic half** by reading the liquid (no hardcoded copy; per-product content on a default template is a `product.metafield`, not a shared section setting) and confirming in the Theme Editor.
13. App-backed sections preserve app functionality; their styled shells are verified, with the documented note that the app controls final render.
14. Ship-with-defaults present (`settings_data.json`/template defaults populated) and `HANDOFF.md` written.

**States & accessibility:**

15. Interaction states verified (hover/focus/active, accordion open/closed, variant→price, qty, cart drawer, scroll-snap); `prefers-reduced-motion` respected; keyboard-navigable.
16. Accessibility: one `h1`, semantic headings, alt text wired, visible focus, and **contrast checked in each band** (cream-on-red, red-on-navy, etc.).

Run available commands such as:

```bash
npm run lint
npm run format
npm run build
shopify theme check
theme-check
```

Use whatever is actually available in the repository. Do not invent scripts.

---

## Performance Improvement Pass

After all base visual, functional, and app integration tasks for a page are complete, run a dedicated Performance Improvement task before moving to the next page.

Evaluate:

1. Mobile image sizes.
2. Lazy loading.
3. Above-the-fold image loading.
4. Render-blocking CSS.
5. JavaScript payload.
6. Slider/carousel implementation cost.
7. Font loading.
8. CSS duplication.
9. Unused assets.
10. Layout shift risks.
11. Excessive DOM nesting.
12. App embed cost.
13. Third-party script impact.
14. Product card image sizing.
15. Section spacing and mobile rendering.
16. Accessibility issues that affect interaction performance.

Generate a list of proposed performance tasks.

For each proposed task, ask the user to accept, reject, or modify it.

Example:

```md
## Proposed Performance Tasks

1. Optimize hero image loading
   - Reason: Above-the-fold image currently lazy-loads and may delay LCP.
   - Suggested change: Use eager loading and responsive width filters.
   - Risk: None.

2. Replace JavaScript carousel with CSS scroll-snap on mobile
   - Reason: Current interaction does not require full JS on mobile.
   - Suggested change: Use CSS scroll-snap below 750px.
   - Risk: If infinite looping is required, CSS-only will not match that behavior.

Please approve, reject, or modify each item.
```

Only implement approved performance tasks.

After accepted performance tasks are done or skipped, proceed to the next page.

---

## Accessibility Requirements

Maintain baseline accessibility.

Required:

- Semantic headings.
- Logical heading order.
- Accessible buttons and links.
- Alt text support for merchant-selected images.
- Keyboard-accessible interactive controls.
- ARIA labels where necessary.
- Visible focus states.
- Reduced-motion support for animations.
- No text baked into images unless unavoidable.
- Sufficient color contrast or documented Figma-driven exception.

For sliders/carousels:

- Buttons must be keyboard-focusable.
- Controls must have labels.
- Autoplay, if approved, should pause on hover/focus where practical.
- Respect `prefers-reduced-motion`.

---

## Git Workflow

The full protocol — branch-per-task, commit-per-subtask, QA gates, push-and-PR, the 7 NEVER rules,
`tasks.md` annotations, and commit examples — lives in **`resources/knowledge-base/GIT_WORKFLOW.md`**,
and the non-negotiables are already summarized in **"## Git workflow (hard rules, every task)"** at the
top of this file. It is not re-duplicated here. Two mode-specific reminders:

- **QA gate step 3 (human spot-check before each commit) is interactive-mode only.** In autonomous
  mode the commit proceeds on the automated gates alone and review defers to the PR (`AUTONOMOUS_MODE.md`).
- **The PR body is the review surface.** In autonomous mode it must additionally carry the assumptions
  made, parked sections, the "requires human verification" list, merchant must-provide items, and
  deferred performance recommendations.

---

## Implementation Report

At the end of each page, provide a concise implementation report.

Include:

```md
# Implementation Report: <Page Name>

## Completed
- ...

## Files Added
- ...

## Files Modified
- ...

## Figma Mapping
| Figma Section | Shopify Section | Data Source | Notes |
|---|---|---|---|

## App-Backed Sections
| Figma Section | App | Original Location | New Wrapper | Duplicate Removed |
|---|---|---|---|---|

## Content Source Decisions
| Content | Source | Reason |
|---|---|---|

## Interactions
| Section | Interaction | Implementation |
|---|---|---|

## Validation
- JSON templates valid: yes/no
- Liquid syntax checked: yes/no
- Theme check/lint: passed/failed/not available
- Mobile checked: yes/no
- Desktop checked: yes/no

## Performance Notes
- ...

## Commits Created
- ...
```

---

## Default Execution Flow

Follow this order unless the user explicitly requests otherwise.

### 1. Repository Audit

Inspect:

- Theme structure
- `templates/`
- `sections/`
- `snippets/`
- `assets/`
- `layout/theme.liquid`
- Existing CSS architecture
- Existing JavaScript architecture
- Existing app sections/blocks
- Existing section groups
- Existing product card snippets
- Existing image snippets
- Existing lint/theme-check scripts

Produce an audit summary.

### 2. Figma Analysis

Use Figma MCP.

Identify:

- Pages
- Frames
- Breakpoints
- Sections
- Components
- Tokens
- Assets
- Interactions
- App-backed candidates

Produce mapping table.

### 3. Planning Questions

Ask only the questions that are necessary because the answer cannot be reliably extracted from Figma or the repo.

Group the questions by category.

Do not ask questions already answered by the user.

### 4. Implementation Plan

Create page-level and task-level plan.

Each page is a major task.

Each section is a task.

Each section’s blocks may be subtasks.

App integrations happen after the base page is built.

Performance pass happens after app integrations.

### 5. Base Visual Implementation

Implement the page visually and functionally first.

Do not integrate third-party apps yet unless they are required for the section to render at all.

### 6. App Integration Tasks

For each app-backed section:

1. Identify the current app source.
2. Build or refine the wrapper shell.
3. Move/host app output inside the wrapper.
4. Apply scoped overrides.
5. Remove duplicate old app placement.
6. Validate exactly one user-visible instance remains.

### 7. Validation

Run available validation commands.

Fix issues.

Commit each fix as its own subtask commit (after QA gates pass). See Git Workflow.

### 8. Performance Improvement Task

Evaluate whole page.

Ask user to approve/reject suggested performance tasks.

Implement approved tasks.

Commit each subtask separately, with full QA gates. See Git Workflow.

### 9. Next Page

Only proceed to the next page after:

- Base page done.
- App integrations done or intentionally skipped.
- Validation done.
- Performance pass done or skipped by user.

---

## Reusable Planning Prompt Template

When this skill starts, use this planning prompt structure:

```md
I’ll implement the Figma design as Shopify OS 2.0 theme code using the Figma file as the source of truth.

Before implementation, I need to confirm the project inputs that cannot be safely inferred:

## Required
1. Figma URL(s):
2. Target Shopify page/template for each design:
3. Should the new implementation replace the existing page composition or be created as an alternate template?
4. Is this theme Dawn, Dawn-derived, or fully custom?

## Content Management
5. Should editable text/images be implemented as theme section settings by default?
6. For product-specific information, should I use product metafields?
7. Do you already have metafield namespaces/keys for product information, materials, shipping, ingredients, or accordions?

## Apps
8. Which apps power reviews, testimonials, galleries, videos, subscriptions, bundles, or upsells?
9. Should those app sections be visually wrapped to match Figma while preserving app functionality?

## Interactions
10. Should sliders/carousels use CSS scroll-snap, custom lightweight JavaScript, or an existing theme/app carousel?
11. Are autoplay, infinite loop, arrows, dots, swipe, or drag required?

## Implementation Preferences
12. Should sections be reusable across pages or optimized for this specific page?
13. Any constraints around fonts, external scripts, or performance budgets?
```

If the user already provided answers, do not ask them again.

---

## Reusable App-Backed Section Prompt

Use this when a Figma section appears to map to third-party app output:

```md
The `<section name>` area appears to be app-backed rather than purely static.

Possible app candidates:
- <detected app or likely apps>

Recommended implementation:
1. Build a `f2s_` wrapper section that matches the Figma shell.
2. Render the app block/output inside the wrapper.
3. Apply scoped CSS overrides only inside the wrapper.
4. Remove the previous standalone app placement from the template to avoid duplicates.

Please confirm:
- Which app powers this section?
- Should the app output be preserved exactly, only restyled visually?
- Are there any app admin settings I should avoid depending on?
```

---

## Reusable Carousel Prompt

Use this when the Figma design contains a carousel, slider, gallery, or swipeable row:

```md
The `<section name>` section appears to require carousel/slider behavior.

Recommended implementation options:

1. CSS scroll-snap
   - Best for performance.
   - Good for mobile swipe.
   - Limited support for infinite loop/autoplay.

2. Lightweight custom JavaScript
   - Good for arrows, dots, active state, and controlled scrolling.
   - Better when desktop behavior differs from mobile.

3. Existing app/theme carousel
   - Best if this section is already powered by a third-party app or existing theme module.
   - Styling may require scoped overrides.

Recommended default: CSS scroll-snap unless infinite loop, autoplay, or advanced pagination is required.

Please confirm:
- Arrows?
- Dots?
- Swipe on mobile?
- Infinite loop?
- Autoplay?
- Pause on hover?
- Number of cards visible on desktop/tablet/mobile?
```

---

## Reusable Product Content Prompt

Use this for product hero or product information sections:

```md
The design includes product-specific content that should probably not be hardcoded.

Please confirm the data source for each item:

| Content | Recommended Source | Confirmed Source |
|---|---|---|
| Product title | Shopify product title | |
| Product price | Shopify product price | |
| Product description | Product field or metafield | |
| Short marketing description | Product metafield | |
| Materials/ingredients | Product metafield | |
| Shipping information | Product metafield or static section setting | |
| Accordion rows | Product metafields or metaobjects | |
| Product badges | Product metafields or tags | |
| Icons | Section blocks or metafields | |

If you already have metafield namespace/key names, provide them. Otherwise I can implement schema placeholders and document where the metafields should be connected.
```

---

## Final Rule

Do not optimize for speed at the expense of maintainability.

The correct output is a Shopify theme implementation that:

- Matches the Figma design.
- Uses Shopify architecture correctly.
- Preserves app functionality.
- Avoids duplicate sections.
- Uses responsive Shopify CDN images.
- Keeps content merchant-editable.
- Branches per task and commits per subtask under the rules in `resources/knowledge-base/GIT_WORKFLOW.md`.
- Runs validation.
- Performs a dedicated performance review before moving to the next page.
- Persists cross-session knowledge into `.claude/knowledge/` and the root `CLAUDE.md` index, so the next run starts informed instead of from scratch.
- Pushes the task branch and opens a PR (no `Co-Authored-By:`) requesting human Code Review and QA at task completion.

## Knowledge-base resources

- `resources/knowledge-base/BOOTSTRAP.md` — bootstrap procedure for `.claude/knowledge/` and `CLAUDE.md`.
- `resources/knowledge-base/READ_PROTOCOL.md` — always-read vs on-demand-read; phase-boundary write rule.
- `resources/knowledge-base/CLAUDE_MD_RULES.md` — index vs deeper write triggers; soft cap.
- `resources/knowledge-base/GIT_WORKFLOW.md` — branch / commit / PR rules and the 7 hard rules.
- `resources/knowledge-base/FIGMA_CACHE.md` — manifest schema, cache key strategy, refresh policy, and derived per-section artifacts (`spec.json`, `@1440`/`@375` references, assets).
- `resources/knowledge-base/VERIFY_HARNESS.md` — **how to build the render+font+image+measurement harness (foundation prerequisite) and run the per-section verify loop. Includes the §750 responsive-integrity check and the advisory image-diff/parity-score.**
- `resources/knowledge-base/PARITY_VERIFY.md` — **independent, goal-backward parity subagent prompt + rubric + revision loop (per section and per page). Rubric now includes reuse/dead-code and the advisory pixel-diff score.**
- `resources/knowledge-base/AUTONOMOUS_MODE.md` — **unattended/background run protocol: decide-or-assume, automated-gates-only commits, auto-low-risk perf, park-don't-halt, richer PR. Paired with PREFLIGHT.md.**
- `resources/knowledge-base/PREFLIGHT.md` — **plan-mode readiness gate (GO/BLOCKED): full Figma pre-cache keystone + access/asset/tooling/decision checklist so a background run never stalls.**
- `resources/knowledge-base/COMPONENT_REUSE.md` — **the snippet-vs-schema reuse boundary, the 4-point safe-snippet contract, the foundation component-kit, Dawn-reuse decision, and the theme-blocks version gate.**
- `resources/knowledge-base/SHOPIFY_BEST_PRACTICES.md` — **native Shopify mechanics reference (Liquid data layer, product form/pagination/cart shapes, `render` vs `include`, metafields-on-default-templates, performance/a11y/SEO/CLI). Folded in so the skill is self-contained.**
- `resources/scripts/f2s_measure.js` — dependency-free, browser-injected spacing/structure assertion (PASS/FAIL panel + `document.title`); the deterministic half of spacing verification.
- `resources/scripts/f2s_codehealth.sh` — **objective code-health signal table + hard-gate PASS/FAIL (theme check, `!important` budget, position-named files, in-tree backups, bundled-image budget). Part of the QA gate and page-level validation.**
- `resources/scripts/f2s_editability.sh` — **structural Theme-Editor wiring gate: valid schema, `block.shopify_attributes` on block loops, text-setting defaults, orphan/hardcoded/ship-defaults flags. Proves the half of editability a read can't; the data-source half (metafield vs setting on default templates) stays a manual read.**
- `resources/scripts/f2s_dupecheck.sh` — **advisory duplication/dead-code signal: exact-duplicate snippet bodies, repeated CSS blocks, unused settings, dead control-flow. Excludes schema duplication by design (reuse boundary). `F2S_DUPE_STRICT=1` hard-fails exact-duplicate snippets.**
- `resources/scripts/f2s_visualdiff.sh` — **advisory objective pixel diff (ImageMagick): render vs cached Figma reference → mismatch % + parity score + heatmap for the parity subagent. Anti-alias-tolerant; requires matching dimensions.**
- `resources/knowledge-base/templates/section-spec.json` — the per-section `spec.json` schema (must_haves, spacing map, type metrics, breakpoints, editable map, `checks`).
- `resources/knowledge-base/templates/f2s_registry.md` — **the component registry (code contract between agents): one row per `f2s_` file, hot-shared-file list, metafield contract. Seed into `architecture/f2s_registry.md`.**
- `resources/knowledge-base/templates/` — seed files for `CLAUDE.md`, `README.md`, decisions, tokens, plans, tasks, manifest, and `conventions/git.md`.
