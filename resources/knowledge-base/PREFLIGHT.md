# Preflight Readiness Gate (plan-mode prerequisite)

Autonomous background runs must not stall mid-flight waiting on something that was missing from the
start. This gate runs **in plan mode** and produces a single **GO / BLOCKED** verdict. Anything
missing is surfaced **once**, at the only approval point, so the user supplies it before the run goes
to background. After GO, the run does not originate new questions (see AUTONOMOUS_MODE.md).

Record the result at `.claude/knowledge/plans/preflight.md` and link it from the plan.

## Keystone — fully pre-cache Figma

Background/headless runs often cannot reach interactively-authenticated MCP servers (the Figma MCP
included). So planning must **pre-fetch and cache everything the build will need**, so the background
build reads only from disk and never needs a live Figma call:

- `get_design_context`, `get_metadata`, `get_variable_defs` for **every** section node.
- Reference screenshots at **1440 and 375** for every section node (desktop **and** the separate
  mobile frame node).
- **Every** image/icon asset downloaded into the section's cache (Figma URLs expire ~7 days — this
  also protects against that).

The gate FAILS if any planned section lacks a cached design-context, both reference screenshots, or
its assets. An incomplete cache = sections the background run will park instead of build.

## Readiness checklist

**Design inputs**
- [ ] Every Figma URL resolves; every section has a desktop **and** a mobile frame. (No mobile frame
      → that section's 375 parity is unverifiable; record as an assumed/parked item now, not mid-run.)
- [ ] Tablet (≈750–989px) designs: present? If **absent**, 750 is an *integrity* check, not parity —
      and ask once how the band should behave (mobile extended vs desktop condensed). See
      AUTONOMOUS_MODE.md / VERIFY_HARNESS §750.
- [ ] Brand font file present **or** a documented condensed near-match chosen and recorded.
- [ ] Assets that can't be exported from Figma (licensed photography, etc.) listed as
      "merchant must provide" in `HANDOFF.md`.

**Shopify / store**
- [ ] Render path decided now: `shopify theme dev` auth available, **or** the static-preview fallback
      is the chosen path. (Don't discover this mid-run.)
- [ ] **All** app-backed sections identified, app names confirmed, app blocks confirmed present in the
      theme — not discovered section-by-section.
- [ ] Metafield namespaces/keys provided, **or** the decision to ship schema placeholders + document
      them is recorded.
- [ ] Template targets + replace-vs-keep decided **per section** (this before/after map is the
      deletion authorization — nothing destructive happens outside it).
- [ ] Dawn version detected (drives classic-blocks vs theme-blocks — see COMPONENT_REUSE §theme blocks).

**Repo / tooling / credentials**
- [ ] Clean working tree; branch base confirmed.
- [ ] `gh` authed non-interactively (so the PR opens at the end without the user).
- [ ] Binaries present: `theme-check` gem, `python3`, headless Chrome (harness), and image-diff tool
      (`compare`/ImageMagick or `pixelmatch`) — confirmed, not assumed. Missing image-diff only
      downgrades visual-diff to advisory; missing theme-check/chrome/python is BLOCKED.

**Decisions that otherwise stop the run**
- [ ] Every "ask the user" point — carousel behavior, content source per node, reusable-vs-one-off,
      ambiguous structure — is answered **or** recorded as a `decisions/NNNN-*.md` with
      `status: assumed` and a sensible default. Nothing in this category is left open at GO.

## Verdict

- **GO** — all hard items satisfied (cache complete, render path chosen, tooling present, every open
      decision answered or assumed). The run may proceed to background.
- **BLOCKED** — list exactly what's missing and what the user must provide. This is the *only*
      mid-process approval; make it complete so the run afterward is uninterrupted.
