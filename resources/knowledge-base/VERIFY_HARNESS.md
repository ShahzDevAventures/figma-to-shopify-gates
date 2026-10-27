# Verify Harness — Setup & Per-Section Loop

The render+compare loop is the reason this skill hits 90%+ on the first pass instead of ~50%. Build it in the **foundation task, before section 1.** A section authored without it is authored blind.

This doc is the concrete how-to for the SKILL.md sections "Verify Harness (foundation prerequisite)" and "Per-Section Build & Verify Loop".

## 1. Render path — a LADDER WITH A FLOOR, not a fallback chain

Rung 1: `shopify theme dev` (real Liquid + real settings). Use it whenever store auth is available.
Rung 2: the static harness below (real CSS, real DOM, rendered in a real browser).
**There is no rung 3.** Both rungs render pixels; anything that doesn't render is not verification.
If neither rung stands (f2s_env_check.sh FAILs), the run is UNVERIFIED: build if you must,
label everything UNVERIFIED, and say so in the PR. The one time an agent invented a rung 3 —
"read the code and compare to a screenshot", recorded as a decision — all 20 sections passed and
spacing/typography shipped wrong anyway. The method is fixed; only scope is negotiable, by a human.

**Rung 2 requirements** — a **real-CSS static preview generator**. Per section it must:
- inline the actual `f2s_design_tokens.css` + base CSS + the section's real `{% stylesheet %}` block (extract the block by regex `\{%\s*stylesheet\s*%\}(.*?)\{%\s*endstylesheet\s*%\}`), and
- emit markup that **mirrors the section's real DOM and class names**.

Never hand-simplify a section in the preview. A drifted preview hides real bugs and invents fake ones — it is worse than no preview. (On a real first pass the comparison table "passed" in a simplified preview while the real section was correct, and other sections looked broken when only the font was wrong.)

## 2. Correct font (hard gate)

Load the brand font, or a documented condensed near-match (Oswald/Anton for a condensed display face), via `<link>` and a `:root` override of the display token. Record the substitution.

**Verification under the wrong font is invalid.** A wider/narrower substitute fabricates wrapping and vertical-rhythm "spacing" failures and masks real ones. This was ~80% of the "spacing is off everywhere" feedback on a real first pass — it was font width, not spacing values.

## 3. Real images

Download every referenced image/icon node (`get_screenshot` per node, or `download_assets`) into `extraction/figma/sections/<key>/assets/` and wire them in. Figma asset URLs expire (~7 days) — download immediately. Placeholders make spacing/proportion unjudgeable.

## 4. Reference renders

Capture the Figma node screenshot at **1440 and 375** into `extraction/figma/screenshots/<key>@1440.png` and `@375.png`. These are the visual-diff targets. Verification reads these cached PNGs — it does not re-call the MCP.

## 5. Measurement check (deterministic, font-independent)

`resources/scripts/f2s_measure.py` renders the page in headless Chromium (Playwright) and
asserts every `must_haves` entry against the **real computed styles** — the values the browser
actually resolved after the cascade, which is the only place specificity fights and token
substitutions become visible:

```sh
python3 f2s_measure.py \
  --url "$F2S_RENDER_URL/sections/hero" \
  --spec .claude/knowledge/extraction/figma/sections/<key>/spec.json \
  --width 1440 --out runs/<date>/<section>/measurement.json --shot runs/<date>/<section>/render@1440.png
```

Run once per designed breakpoint (`--width 1440`, `--width 430` — read the real frame widths).
It writes measurement.json with a MATCH/CLOSE/DRIFT/MISSING verdict per must_have (±2px on numerics),
records `fonts_status` (verification under unloaded fonts is invalid), exits non-zero on any
DRIFT/MISSING, and a must_have it cannot locate is reported MISSING — never silently skipped.

This catches **box spacing** (padding/margin/gap/grid) regardless of font — e.g. it fails immediately on `padding-right: 38%` where the spec says `310px`. That class of bug should never reach a human reviewer again.

## 6. The loop (per section)

```
research (get_design_context + screenshots@1440/375 + assets)  -> write spec.json (must_haves)
  -> build to spec.json (exact px; never snap to nearest token)
  -> render @1440 and @375 with harness (correct font, real images)
  -> measurement check (deterministic box values)         -- must be ALL PASS
  -> visual diff vs @1440/@375 reference (font-driven)     -- independent parity subagent
  -> gate: discrepancy list empty, both breakpoints        -- else fix and re-run
```

If verify exposes a mismatch `spec.json` didn't predict -> research for that node was incomplete -> re-research **that node only**, update `spec.json`, rebuild.

## 7. Page-level integration (after sections are individually green)

Render the whole page; diff against the full Figma frame. Check section **order**, **inter-section spacing**, and **band transitions** (the rhythm between sections). Sections can each be correct yet wrong when stacked.

**GATE 7 renders the ASSEMBLED pages from the SHIPPED template JSON defaults — never from section
fixtures (root-cause finding of one rebuild's bug list).** Every section on that rebuild passed its 420 verify in
isolation; the page-integration pass then checked mobile with rhythm + integrity measurements only,
and the section-level fixtures (designed can cut-outs, UGC tiles) differed from what
`templates/*.json` actually shipped. The assembled page therefore showed fallback states that no
section verify had ever rendered, and the client found 18 bugs in one review (B-01…B-18). Rule:
the page-level render reads `templates/<page>.json` (section order AND each section's `settings`
exactly as committed) plus the section-group JSON for header/footer, with the cart drawer from
`layout/theme.liquid` (B-15). A visual pass of every assembled page at BOTH designed breakpoints is
mandatory, in the shipped-defaults state; a section fixture is a unit test, not the product.

## 7b. Screenshots of an assembled page (`full_page` lies)

Playwright's `page.screenshot(full_page=True)` **resizes the viewport to the document height before
capture**. Two consequences, both of which produced false "big white gap" bugs on one rebuild's home page:
- `position: sticky` (scroll-stack / pinned sections) renders as if the viewport were the whole
  page — the pinned element sits at the top of a 6000 px "viewport" and the section's scroll
  sequence collapses into blank bands.
- IntersectionObserver / scroll-driven reveals never fire (nothing scrolled), so revealed content
  (product cards, headings with a 0.65 s reveal) is captured mid-transition or not at all —
  Three logged bugs on that rebuild were exactly this artefact and were "not reproducible" once the tool
  was fixed. The DOM measured correctly the whole time (`getBoundingClientRect` showed zero gaps).

**Required method for any page that scrolls:** keep the real viewport (1440×900 / 420×900),
emulate `prefers-reduced-motion: reduce` (`page.emulate_media(reduced_motion="reduce")`) so
reveal transitions resolve instantly rather than being frozen mid-way, scroll to the bottom in
viewport-sized steps **and back to the top** (every observer fires, every lazy image loads), then
take viewport screenshots at each scroll offset and stitch them (`f2s_visualdiff.py` can
crop; stitching is a Pillow paste loop). Record the method in `measurement.json`
(`"screenshot_method": "scroll-stitched, reduced-motion"`) — a verdict taken from a bare
`full_page` capture of a page with sticky or reveal behaviour is UNVERIFIED, not FAIL. Sticky
sections are judged from the per-offset frames (does the pin hold, does the next band take over),
never from a stitched composite, which cannot represent a pin by construction. Fixers must test the
pre-reveal / pre-JS state too (B-18: a leaked global reveal rule only showed while scrolling in).

## §750. Responsive integrity (breakpoints you have no design for)

You can verify **parity** only where you have a comp (375 + 1440). The 750–989 tablet/mid band usually
has no Figma frame, so there is nothing to diff against — verifying "parity" there would invent a
ground truth you don't have. Instead run an **integrity** check:

```sh
python3 f2s_measure.py --url "$URL" --spec <spec> --width 750 --integrity
```

`--integrity` skips the spec checks and asserts the generic invariants instead — **no horizontal
overflow**, **no element wider than the viewport** — proving the layout doesn't *break* between the two
designed breakpoints. This is a separate, cheaper gate: keep it out of the parity score, and report
375/1440 as *parity-verified* vs 750 as *integrity-verified*. If there are genuinely no tablet
designs, confirm once whether the band should follow mobile-extended or desktop-condensed; default to
the theme's existing 750/990 conventions.

## §diff. Advisory image-diff + parity score (the font-driven half, made objective)

The box half is deterministic (`f2s_measure.py`); the font/color/structure half was an
eyeball. Make it a number with
`f2s_visualdiff.py --render <render@bp.png> --reference <reference@bp.png> --out <diff.png>`
— it returns an anti-alias-tolerant **mismatch %** + a **highlight PNG**, which the parity subagent
reasons about instead of comparing raw screenshots unaided. Pillow-only — no ImageMagick, so the
"tool missing, silently skip the diff" failure mode is gone; if Pillow itself is missing, env_check
already put the run in UNVERIFIED mode and no PASS can be claimed. It flags dimension mismatches
rather than silently rescaling (a size mismatch usually means wrong viewport or layout overflow).
Requires matching pixel dimensions, so pin the harness viewport/DPR.
