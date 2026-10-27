# Parity Verify — Independent, Goal-Backward Section Check

Modeled on GSD's separation of build from verification (gsd-plan-checker / gsd-verifier): **the agent that built a section must not be the agent that signs off on it.** Verification is goal-backward — it asks "does the render deliver the `spec.json` `must_haves` at both breakpoints?", not "did the tasks run?"

Spawn one parity subagent per section (and one per page for integration). It returns a structured discrepancy list; the orchestrator runs a revision loop (max 3) until the list is empty, then the section is done.

## When to spawn

- **Per section:** after build + measurement check passes, before marking the section done.
- **Per page:** after all sections are individually green (integration check).

The measurement check (`f2s_measure.py`) is the deterministic pre-filter; the parity subagent handles the visual/judgment half and confirms the deterministic half independently.

## Inputs to give the subagent

- `spec.json` for the section (the `must_haves`)
- The cached reference PNGs: `<key>@1440.png` and `<key>@375.png`
- The rendered PNGs of the build at 1440 and 375 (with the measurement panel visible)
- The section's liquid file path

## Subagent prompt (fill and pass to Task, subagent_type: `figma-verifier`)

<!-- v4: was `general-purpose`, which contradicted routing.json and the builder≠verifier rule —
     a generic subagent inherits no model routing and no verifier instructions. -->


```
<objective>
Independently verify that a built Shopify section matches its Figma spec at BOTH breakpoints.
You did not build this; do not be charitable. Your job is to find every discrepancy.
</objective>

<inputs>
- spec.json (the must_haves): {path}
- Figma reference: {key}@1440.png, {key}@375.png
- Built render: {render-1440.png}, {render-375.png}  (measurement panel is top-left)
- Section liquid: {liquid path}
</inputs>

<method>
1. Read the measurement panel in each render. Any non-PASS is an automatic FAIL — list each.
2. Overlay-compare render vs reference at 1440, then at 375. For EACH rubric item below,
   state MATCH or MISMATCH with the observed vs expected value.
3. Re-check colors IN THE BAND CONTEXT (navy/red/cream flip eyebrow/title/text colors).
4. Treat 375 as a first-class pass, not a reflow of desktop.
5. If a `f2s_visualdiff.py` heatmap + parity score is provided, read it first: anything the
   pixel diff flags red is a guided place to look — but the score is advisory, not a substitute for
   the rubric judgment.
</method>

<rubric>
- Background / band color
- Container gutter · section padding · inter-element gaps · grid columns & gaps
- Component structure (cards, quadrant, overlays, spacers) and order
- Type: family · size · line-height · letter-spacing · weight · transform · color-in-band
- Border-radius · shadows
- Icon/image presence, crop, focal point
- Mobile (375): padding, stacking, type scale — verified separately
- Interaction states present (hover/focus/open/variant→price) and reduced-motion/keyboard
- Contrast in this band (e.g. cream-on-red, red-on-navy)
- Editability (structural): `f2s_editability.sh` PASS for this section — valid schema, `{{ block.shopify_attributes }}` on any `section.blocks` loop, text settings have Figma defaults
- Editability (semantic): visible text/images are settings/blocks, not hardcoded; and on a DEFAULT template, per-product copy is a `product.metafield`, not a shared section setting (read the liquid — the script can't catch this)
- Shopify mechanics (read SHOPIFY_BEST_PRACTICES.md): `render` not `include`; `{% form 'product' %}` with `selected_or_first_available_variant`/`has_only_default_variant`; product-specific copy from `product.metafields` (NOT section settings on a default template); valid `{% schema %}` with Figma-valued defaults and repeatable groups as blocks; empty/edge states handled (no image, sold-out, no compare-at)
- Documentation & registry: file opens with the required header block (Purpose/Spec/Data/Deps/Owns/Settings/Owner); the file's row in `architecture/f2s_registry.md` exists and matches reality. Undocumented or registry-drifted = FAIL even if it renders correctly.
- Reuse & dead code: the section does NOT reimplement a kit/Dawn component (it renders the shared snippet); shared snippets obey the safe-snippet contract (COMPONENT_REUSE.md); no unused settings, dead control-flow, or behavior the design never shows (YAGNI). `f2s_dupecheck.sh` signals are addressed. Schema duplication across sections is allowed — do NOT flag it.
- Naming: filename is `f2s_<area>_<purpose>` (not bare/generic/position-named) and the merchant-facing schema `name` is plain English with no `f2s` prefix (`f2s_codehealth.sh` PASS).
- Annotations discharged: EVERY entry in the brief's `@section/@data/@behavior/@states/@editable` tables and EVERY pinned comment is explicitly checked off as satisfied or listed as a discrepancy. An annotation nobody checked is an unbuilt requirement — an annotated animation shipped missing this way.
- Inventory obligation: if the brief's classification is RETIRE, the section it replaces is named in the brief and is scheduled for removal; if CONFLICT, the recorded decision is cited. A new section that silently duplicates a live one is a FAIL even at perfect pixel parity — it doubles what the merchant edits and what you maintain, and the two drift within weeks.
</rubric>

<output>
## VERDICT: PASS | FAIL
## DISCREPANCIES (empty if PASS)
- [breakpoint] [rubric item] expected <x> got <y> — <where>
## NOTES
- anything the spec.json failed to predict (signals incomplete research for that node)
</output>
```

## Revision loop (orchestrator)

```
build -> measurement check -> parity subagent
  PASS -> section done
  FAIL -> fix the listed discrepancies -> re-render -> parity subagent  (max 3 iterations)
  still failing at 3 -> surface to user with the remaining list and a recommendation
```

If a NOTE says the `spec.json` failed to predict something, re-research **that node only**, update `spec.json`, and rebuild — the cache was incomplete, not wrong everywhere.

## Page-level integration subagent

Same pattern, inputs = full-page render vs the full Figma frame screenshot. Rubric: section order, **inter-section spacing**, band transitions/rhythm, shared components consistent across the contexts they appear in.
