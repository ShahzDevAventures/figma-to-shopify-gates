# Autonomous Mode — run unattended in the background

This skill has two run modes.

- **Interactive** (default for ad-hoc work): the human checkpoints in SKILL.md stay — per-commit
  spot-check, per-task performance approval, mid-run questions.
- **Autonomous** (background/unattended): once the plan is approved, the run executes end-to-end with
  **no mid-run human approvals**, until the PR is open or it has nothing left it's authorized to do.

Select autonomous mode when the user asks for a background/unattended run. The whole design rests on
one principle:

> **Decide-or-assume everything at planning time; never block mid-run. The approved plan is the
> authorization boundary — anything inside it runs; anything that would deviate is parked and
> reported, not silently done and not blocked on.**

## Entry condition

Autonomous mode may start **only after the Preflight Readiness Gate returns GO** (see PREFLIGHT.md).
That gate is where every access, asset, tool, and open decision is resolved up front — it is the one
and only approval point. Maps naturally onto the **Workflow tool** (background by design, notifies on
completion); the full Figma pre-cache is what lets it run without the interactive Figma MCP.

## What changes vs interactive mode

**1. Per-commit human QA → removed; automated gates only.**
The QA gate before each commit drops step 3 (human spot-check). The commit proceeds on the automated
gates alone: `theme check`, `f2s_codehealth.sh` (incl. naming), `f2s_editability.sh`
(structural), `f2s_dupecheck.sh` (advisory), `f2s_measure.py` (box + responsive
integrity), and the independent parity subagent. All human review defers to the **PR**.

**2. Performance pass → auto-apply low-risk, defer the rest.**
No per-task approval. Automatically apply the zero-risk optimizations the skill already mandates
(lazy below-fold, explicit width/height for CLS, `fetchpriority` on the LCP image, dropping a JS
carousel for CSS scroll-snap where behavior allows). **List every judgment-call optimization in the
PR as a recommendation** instead of blocking on it.

**3. Mid-run questions → front-loaded or assumed.**
The run originates no new questions. Anything unresolved at GO is already a `decisions/NNNN-*.md`
with `status: assumed` and a default. If something genuinely new surfaces mid-run, it becomes a fresh
`assumed` decision with a default and a PR flag — the run continues.

## Graceful degradation — park, don't halt

- **A section that fails parity after the 3-revision cap is parked** (`needs-human-review` in
  `tasks.md`), and the run continues with the other sections. One hard section never blocks the run.
- **Systemic circuit-breaker:** if many sections fail their *first* verify, that's a foundation
  problem (wrong font, wrong tokens, drifted preview). Pause the fan-out and write one
  "foundation looks wrong, here's why" report instead of grinding through every section. This is the
  guard against one bad up-front assumption poisoning the whole run.
- **Never silently exceed the plan.** Destructive actions (removing existing sections) are authorized
  *only* by the approved before/after section map. Anything destructive not in that map is parked,
  not done.

## The PR is the review surface — make it carry the weight

Autonomous mode trades early human catches for one end review, so the PR body must let that review be
fast and targeted. Beyond the normal summary/plan/decisions, include:

- **Assumptions made** — every `status: assumed` decision and the default chosen (confirm or correct).
- **Requires human verification** — the things no script can prove: data-source correctness
  (metafield vs shared section setting on a default template), the Theme-Editor "open it and confirm
  blocks reorder" check, and contrast-in-band.
- **Parked sections** — what failed and the last discrepancy list.
- **Merchant must-provide** — fonts/assets/apps/metafields from the readiness gate.
- **Deferred performance recommendations** — the judgment-call items not auto-applied.

## What stays human

Two gates, both at the boundaries (not mid-run):
1. **Plan approval** (with Preflight GO) — the front gate; your real control point.
2. **PR review + merge** — the build pushes and opens the PR autonomously; **merge stays human.**

## Honest limits

- The automated gates are strong but not complete — semantic data-source and Theme-Editor confirmation
  can't be fully automated, so those defects survive to the PR. The richer PR (above) is the
  mitigation, not a cure.
- "Assume a default and continue" can compound; the circuit-breaker is what bounds the blast radius.
- Background reliability depends on the Figma pre-cache being **complete** — verify it at the gate.
