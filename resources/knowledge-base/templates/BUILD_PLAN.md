# Build plan — <page/theme> · <date>

<!--
v4. Written by the ORCHESTRATOR after every figma-researcher has finished (GATE 3), from the
briefs and the inventory. This is CHECK-IN 1: the run HALTS here until a human approves it.

Why it exists: v3 asked five questions at intake and then ran to completion. Nothing was ever
shown to the operator until the PR, by which point 28 sections had been built against
interpretations nobody had confirmed. Research was already front-loaded — it just went straight
into the cache and out the other side.

Keep this ONE page. If it does not fit on one screen it is not a plan, it is a report.
-->

**Scope:** <n> sections across <n> template(s) · **Mode:** VERIFIED / UNVERIFIED
**Approval:** ⬜ pending — the run does not build until this is checked

---

## 1. What gets built

| # | Section | Complexity | Source | Depends on | Replaces | Status |
|---|---|---|---|---|---|---|
| 1 | | simple/standard/complex | stock / extended / new | foundation | `sections/<file>` or — | ready / BLOCKED |

**Source** is the build ladder: `stock` = boilerplate section used as-is · `extended` = boilerplate
section with modifications · `new` = written from scratch. Prefer left.

**Depends on** comes from three real places, not guesswork: the foundation (all sections),
shared-snippet ownership (two sections needing one snippet — one owns it), and cross-section
overlaps (sticky headers, bleeds spanning a boundary) which resolve at the page-integration gate.

## 2. What gets retired

From `architecture/inventory.md`. **The page-integration gate asserts every row here is gone.**

| Existing file | Live in | Replaced by | Decision |
|---|---|---|---|

A rebuild that ships new sections *alongside* the old ones has doubled what the merchant edits.
If this table is empty on a theme that already has a custom layer, that is a finding, not a pass.

## 3. What must survive

Apps and anything the design file never drew — the Figma frames do not show these, so they are
invisible to every other step.

| Thing | Where it lives | Why it must survive | Reconnect step |
|---|---|---|---|
| e.g. reviews app | `sections/<file>` app block | merchant's live review data | listed in HANDOFF.md |

## 4. Open questions

Each is pinned as a Figma comment on its frame and listed here. **Blocking questions park their
section; the rest of the page proceeds.**

| # | Section | Question | Blocking? | Asked |
|---|---|---|---|---|

## 5. Permissions this run needs

From `f2s_permcheck.sh`. Approving this plan approves this list — after which the run does
not stop to ask.

- **Figma MCP server:** `<detected server>` — read tools only
- **Git/GitHub:** commit, branch, push to a task branch, open a PR. **Never** force-push, never
  `--no-verify`, never merge.
- **Shopify CLI:** theme dev / check / pull, push to an **unpublished** theme. **Never** push
  `--live`, never publish.
- **Scripts:** `.claude/scripts/f2s_*`
- Full allowlist: `.claude/settings.json` (committed)

## 6. Performance budget

Gated deterministically by `f2s_perf.sh`; the Lighthouse number is advisory only.

- Every image: explicit width/height or an aspect-ratio wrapper (CLS)
- LCP image eager + `fetchpriority="high"`; everything below the fold lazy
- All images through `image_url` (CDN resize)
- No `script_tag`, no undeferred `<script src>`
- Inline CSS budget: **<n>B** per section

## 7. What happens after you approve

1. Preflight → foundation B (shared snippets, now that the section list is known)
2. **First section built and verified → CHECK-IN 2.** One finished section next to its design,
   before the other <n> follow the same interpretation.
3. Remaining sections, then page integration → performance → editability → handoff → PR.

`plans/STATUS.md` stays current throughout. The run stops only at check-in 2, at the three halt
conditions, or when it finishes — and if it ends early it says exactly what it left behind.
