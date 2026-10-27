---
description: Full Figma→Shopify page build with locked gates. Usage: /build-page <figma-url> <target-template> [interactive]
---
# /build-page — the one button

You are the ORCHESTRATOR (strong model per .claude/routing.json). Run this pipeline in order.
Every gate is a script whose exit code decides — you never override a non-zero exit with judgment.

## THE AUTONOMY CONTRACT (read before anything else)

**This command runs unattended between two SCHEDULED stops.** The operator is not sitting there.
A run that pauses on section 4 to ask something has failed at its job even if every line it wrote
was correct — but a run that builds 28 sections against an interpretation nobody confirmed has
failed differently. v4 resolves that with two planned check-ins and no ad-hoc ones.

- **Ask everything at step 0, in one batch.** After that you do not ask again.
- **Two scheduled stops, both announced in advance:** the plan (GATE 4) and the first verified
  section (after the loop's first pass). Everything is batched into them.
- **A blocked section is parked, not a stop.** Record it, continue with the rest of the page, and
  report the whole list at the end. One unanswerable question must never hold 27 buildable
  sections hostage.
- **Four things may halt the entire run:** a failing gate self-test (broken gates bless nothing),
  a BLOCKED Figma structural audit (an ambiguous source caps parity — the fix is upstream), a
  BLOCKED preflight (the environment can't do the work), and an unapproved build plan. Each halts
  with a plain-English shopping list of exactly what to fix.
- If you catch yourself about to ask permission mid-run: park it as an assumption with a default,
  write it to the assumptions list, and keep going.

## THE FAILURE CONTRACT (v4 — the stalled-builder collapse)

A subagent that stalls, errors, or returns nothing: **retry once, then PARK the section and move
on.** You may never finish a subagent's work yourself.

This is not about effort or politeness. If you build a section and then assess it, the verification
is self-grading and worth nothing — exactly the failure the artifact requirement exists to prevent.
On one build three commits record it happening: *"finish + land UGC section (builder stalled before its
gates)"*, *"build bundle builder JS + registry (orchestrator finished it)"*. The work looked
complete and had never been independently checked. **Parked-and-reported beats
built-and-self-approved.** An orchestrator that "just does" the sections inline has silently
deleted the gate while appearing to run the pipeline.

## THE COMPLETION CONTRACT (v4 — the orphaned sections)

If this run ends for ANY reason before GATE 7 — interrupted, out of budget, halted, crashed —
`plans/STATUS.md`'s final write must be a **VERDICT**, not a snapshot:

```markdown
# RUN ENDED — <date> <time> — INCOMPLETE
Reached: per-section loop (11 of 28)
NOT WIRED: 10 sections built and committed but referenced by no template — <list>
NOT VERIFIED: 3 sections with no committed artifact — <list>
NEVER STARTED: 14 sections — <list>
To resume: /build-page --resume (picks up at the first not-done section)
```

On one rebuild the run stopped mid-loop and the last line of STATUS.md read
`Verified/committed: 0` while 14 finished section files sat on disk wired to no template, beside
17 verify directories that made the run look successful. Nobody could tell how far it got.
**Sections built but not wired are the single most expensive silent failure this pipeline has.**

## AGENTS ARE MANDATORY, NOT AN OPTIMIZATION

You are an orchestrator. **You do not personally research, build, or verify.** Spawn subagents via
the Task tool for every one of those roles, every time, even when doing it yourself feels faster.
`figma-researcher` per node (parallel batches), `figma-builder` per section, `figma-verifier` per
section (different invocation from its builder), `figma-fixer` on non-empty discrepancy lists.
Track them; do not fire-and-forget. When one fails, apply the failure contract above.

## PROGRESS REPORTING

Maintain `.claude/knowledge/plans/STATUS.md`, rewritten at every gate boundary and after every
section — the file someone opens to answer "how far did it get?" without reading the repo:

```markdown
# Run status — <date> <time>
Phase: per-section loop (7 of 28 sections)
Verified: 6 · Parked: 1 · Remaining: 21 · Mode: VERIFIED
Now: f2s_pdp_gallery — verify loop 2
Parked: f2s_legend_band (open question: overlay behaviour — asked in Figma <date>)
Last gate: preflight GO (<date>)
```

Print one line to chat at each of: gate passed/failed · each section reaching verified/parked ·
phase transitions · each check-in · run end. No more, no less. Silence for twenty minutes then a
wall of text is the failure mode being fixed here; so is narrating every file write.

---

## 0. Permissions FIRST, then intake
**Before any other command runs:** copy `resources/templates-v2/settings.json` →
`.claude/settings.json`, commit it, then `sh .claude/scripts/f2s_permcheck.sh`. Non-zero →
STOP and print what's missing. v3 installed this at step 1 (bootstrap), so you needed permission to
run the bootstrap that installed the permissions; one build ran end to end without it and prompted
on every script, commit and push.

Then ask, in one batch, plain English: Figma URL(s)? Target template(s)? Replace or add-alongside?
Known apps (reviews/bundles/etc.)? Where should product copy live (metafields vs settings — explain
the difference in one sentence)? Record answers as decisions/. Anything unanswered → status:
assumed + a default, listed in the plan. Then say what you're about to do and roughly how long.
Do not ask "shall I proceed?".

## 1. Bootstrap (idempotent)
Run BOOTSTRAP.md: KB layout, install `.claude/scripts/`, `.claude/agents/`, `.claude/commands/`,
**`.claude/knowledge-base/`** (the rubric and best-practices docs agents cite by path), pre-commit
hook (core.hooksPath), routing.json, gitignore negations scoped to `.claude/knowledge/`,
placeholder check, sync boilerplate patterns to `.claude/knowledge/patterns/`.

## 2. Gate: environment + self-test
`f2s_env_check.sh` — FAIL → the whole run is UNVERIFIED: continue, but every artifact and
the PR say so. `f2s_gate_selftest.sh` — non-zero = HALT. Broken gates bless nothing.

## 3. Existing-theme ledger
`sh .claude/scripts/f2s_inventory.sh` → `architecture/inventory.md` + `.json`. Classify
every row RETIRE / KEEP / CONFLICT. Apps and undesigned pages (cart, blog, 404) are KEEP unless a
migration plan says otherwise — the Figma file does not show them, so no other step will catch them.

## 4. Figma readiness audit + page inventory
`f2s_figma_audit.js` → `design/figma_audit.json`. BLOCKED → output the designer fix-list
verbatim and HALT. GO_ANNOTATIONS_PARTIAL → post each `askDesigner[]` item as a pinned Figma
comment, park those sections, continue. GO → proceed.

**Also write `design/figma_page_inventory.json`** — every page, every designed frame, both
breakpoints. This is the list "did we build everything?" is measured against, and it must be
written BEFORE extraction, by someone looking at the whole file. One build's product page had its own frames; extraction pulled only the home page's; no gate compared the lists because no list existed.
Its absence is a preflight failure, not a skippable step.

## 5. Foundation A — can this machine measure?
Render path proven, correct font loaded and reported, real images, measure.py working, tokens CSS
from cached variable defs only. Settles VERIFIED vs UNVERIFIED **before** the expensive research
step, so a run that can't be verified isn't discovered after 28 agents have already run.

## 6. Extraction → one brief per section (figma-researcher, parallel batches)
One subagent per node. Each writes raw payloads including **annotations and pinned comments**,
registers the manifest entry, assembles `sections/<key>/BRIEF.md`, and ends with a `cache_check`
PASS line quoted. Commit cache + briefs. Nodes with blocking open questions are parked here.
**After this step, no agent calls Figma.** A gap in a brief is a research gap: `RE-RESEARCH: <node>`.

## 7. The plan — ★ CHECK-IN 1, the run HALTS
Write `plans/BUILD_PLAN.md` from the briefs and the inventory (template in
`.claude/knowledge/templates/`). One page: sections with dependencies and what each replaces, the
RETIRE list, what must survive, open questions, permissions, performance budget. Populate
`sections.json` with `depends_on[]`.

Present it and STOP. Do not build until it is approved. This is the fourth halt condition.

## 8. Gate: preflight
`f2s_preflight.sh` — BLOCKED → print the shopping list, HALT.

## 9. Foundation B — shared surface
Shared snippets and the component kit, now that the approved section list is known. Single owner
for hot files from here on.

## 10. Per-section loop (pipeline, not barrier; triage per routing.json)
Classify simple/standard/complex. For each: builder subagent (reads the brief) → verifier subagent
(MUST be a different invocation; reads `.claude/knowledge-base/PARITY_VERIFY.md` for the canonical
rubric) → fixer on non-empty discrepancy list → scoped re-verify. Two verify failures on one
discrepancy → park + report, move on. Log every loop to telemetry.csv. Update sections.json and
STATUS.md after each section so a killed run resumes at the first not-done section.

**★ CHECK-IN 2 after the first section is verified.** Show it beside its design and stop. The rest
of the loop follows the same interpretation, so this is the cheapest moment to correct it.

## 11. Page integration gate (strong model, after all buildable sections are green)
Assembled page vs full Figma frame: section order, inter-section rhythm, band transitions,
cross-section deferrals resolved. **Render the ASSEMBLED pages from the shipped `templates/*.json`
defaults (order + settings as committed), not from section fixtures, with a visual pass at both
breakpoints; screenshots of scrolling pages are scroll-stitched under reduced motion, never
`full_page=True`** (VERIFY_HARNESS.md §7/§7b). **Two assertions:** the template `order` contains EXACTLY the
planned sections, and every inventory RETIRE row is gone. Template JSON assembly happens here, by
the integration agent only — this is the step whose absence left one rebuild's sections orphaned.

## 12. Reachability + editability + functional + performance + handoff
`reachability.sh` PASS — **done means a customer can reach it**, not "committed and green". Every
built section referenced by a template/group/layout; every `settings.*` it reads present in the
theme's config; every `runtime_requires` a spec declares matching the store's real value.
`coverage.sh` PASS (assembly half). `editability.sh` PASS (sections AND snippets), `functional.sh`
PASS (nine classes + class U), `upload_validator.sh` PASS (Shopify ADMIN upload rules theme-check
misses — on one rebuild every gate was green and the admin rejected 22 sections), then the
real `shopify theme check --fail-level error` via the repo CLI (decision 0025) and, when store
credentials exist, a real `shopify theme push --unpublished` dry-run whose output is grepped for
"error" before anything is called uploadable (post-mortem notes: "pushed with errors" hides behind
`| tail -1`; push section code BEFORE the template that uses its new settings). `perf.sh` PASS
(CLS-safe images, eager LCP image, lazy below fold, CDN resize, no render-blocking scripts;
Lighthouse advisory only). `deferrals.sh` harvested into the ledger —
and re-triage any row logged against a section that has just become customer-visible: a flag raised
while a component reached nobody is a different risk once it ships. HANDOFF.md: metafield contract,
apps to reconnect from the KEEP list, fonts, deviations with spec citations. Registry complete.

## 12b. Hand the repo back — disarm the gates
`sh .claude/scripts/f2s_hooks_mode.sh maintainer`, as the last thing before the PR.

The gates exist because an unattended agent cannot be trusted to judge. A developer can. They live
in the repo (`core.hooksPath`), not in the skill, so without this step every human commit after
handoff runs the agent's doors — spec-before-build on a hand-edited section, whole-tree scans
failing on pre-existing debt, one-section-per-commit on a deliberate two-section refactor. That is
not safety, it is a maintainer fighting the tooling, and the reliable outcome is `--no-verify`
becoming routine. Bootstrap re-arms automatically on the next run, so the mode follows whoever is
driving.

Say so in the PR and in HANDOFF.md: gates are off, `f2s_hooks_mode.sh status` reports the
mode, the gate scripts still run by hand, and any future agent run re-arms them.

## 13. PR (the single review surface)
Branch pushed, `gh pr create` with: per-section side-by-sides (Figma left, render right, both
breakpoints), mismatch % per section from committed artifacts, the deferral ledger verbatim,
retired sections, assumptions, parked sections with their open questions, UNVERIFIED banner if
applicable, performance results, telemetry summary, reviewer test plan.
Then: "Review the pictures. Left is the design, right is what was built. Approve, or comment on
what looks off." — plus the completion report.

Never: bypass a hook, state a parity number without an artifact path, edit a hot file from a
section agent, **do a subagent's job inline**, **end a run without a verdict**, or halt outside the
four halt conditions.
