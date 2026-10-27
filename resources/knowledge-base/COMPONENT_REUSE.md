# Component Reuse — the snippet-vs-schema boundary

The dominant cause of duplicated, hard-to-maintain theme code is each parallel section
builder re-authoring the same card/button/badge/heading because it could not see the others'
work (worktree isolation guarantees it). The fix is not "reuse harder" — it is to **draw the
reuse boundary where Shopify actually supports it** and build the shared layer *once, up front*.

## The one rule

> **Reuse at the snippet (rendering) layer. Accept duplication at the schema (block) layer.**

- A **block** owns its `{% schema %}` `settings`. Liquid has **no** `include`/`$ref` for schema
  JSON, so two sections that need the same "stat" block copy the JSON. **This duplication is
  expected and fine — do not fight it.** Trying to DRY block schemas is exactly what makes reuse
  "cause more issues."
- The **snippet a block renders** is the reuse primitive. `{% render %}` is isolated-scope and
  takes explicit args. Dawn itself renders shared snippets (`card-product`, `responsive-image`,
  `icon`, `price`) from many sections/blocks. This is safe, idiomatic, and low-risk **when the
  snippet is context-independent.**

So: the block stays per-section and owns its settings; the *thing it renders* is a shared snippet
that receives data as arguments. Nothing is shared at the schema layer; everything is shared at the
rendering layer.

## The 4-point safe-snippet contract

A kit snippet is reuse-safe only if all four hold. A snippet that violates any of them is the
"reuse caused bugs" failure mode — fix the snippet, don't abandon reuse.

1. **Explicit args only.** It reads *nothing* ambient — never `block.settings`, `section.settings`,
   `product`, or page globals directly. Everything arrives as a `render` argument.
2. **Per-instance styling is passed in as a value** (a color/size threaded through and applied via a
   CSS custom property), so the snippet doesn't bake in one section's look.
3. **The caller emits `{{ block.shopify_attributes }}`** on the block root; the snippet renders the
   inner content. (A snippet can't know it's inside a block.)
4. **No `{% stylesheet %}` in the snippet** — that tag only works in sections. Shared-snippet CSS
   lives in a shared asset file decided in the foundation phase. (This is the one real seam: shared
   rendering does not automatically bring shared styles, so plan the CSS home up front.)

### Good

```liquid
{%- comment -%} f2s_card.liquid — context-independent, all data via args {%- endcomment -%}
<article class="f2s-card" style="--f2s-card-accent: {{ accent | default: '#1a2c4e' }}">
  {%- if image -%}{% render 'f2s_responsive_image', image: image, sizes: sizes %}{%- endif -%}
  <h3 class="f2s-card__title">{{ title }}</h3>
  {%- if body -%}<p class="f2s-card__body">{{ body }}</p>{%- endif -%}
</article>
```
```liquid
{%- comment -%} caller (a block in a section) {%- endcomment -%}
{%- for block in section.blocks -%}
  <div {{ block.shopify_attributes }}>
    {%- render 'f2s_card',
        title: block.settings.title, body: block.settings.body,
        image: block.settings.image, accent: section.settings.accent, sizes: '(min-width:990px) 33vw, 100vw' -%}
  </div>
{%- endfor -%}
```

### Bad (looks reusable, breaks on reuse)

```liquid
{%- comment -%} reaches for ambient context — works in ONE section, breaks everywhere else {%- endcomment -%}
<article class="f2s-card">
  <h3>{{ block.settings.title }}</h3>     {# ✗ ambient block — undefined when rendered from a section setting #}
  <img src="{{ section.settings.image | image_url: width: 600 }}">  {# ✗ ambient section #}
  {% stylesheet %}.f2s-card{ }{% endstylesheet %}            {# ✗ stylesheet tag in a snippet — no-op #}
</article>
```

## Component kit — build the shared layer in the foundation phase (before parallel build)

`design/components.md` (the repeated-component catalog from Figma analysis) is a **build
deliverable, not just a doc.** In the foundation phase, before any section fans out:

1. Extract the repeated components (button, card, badge, eyebrow+title cluster, icon-row, media
   frame, price, rating) from the catalog.
2. Decide which become **shared snippets + shared component CSS**, each satisfying the contract above.
3. **Build them once.** Register each in `architecture/f2s_registry.md`.
4. Section builders **assemble from the kit and are forbidden from re-authoring kit components.** A
   section that reimplements a kit snippet is a verify failure (see PARITY_VERIFY rubric).

Mid-build, if two sections discover a *new* shared need, it routes to the kit **owner** (like hot
files) — never two parallel builders each inventing it. Don't try to pre-build everything; cover the
obvious repeats and let the owner add the rest.

## Reuse the base theme too, not only `f2s_`

The registry tracks this skill's files; the biggest reuse miss is rebuilding what **Dawn already
ships** (image snippet, card, slider web components, color schemes, utility classes). Before building
any snippet, decide: **extend Dawn's primitive · wrap it · build new** — and **build-new requires a
one-line justification.** The `f2s_` prefix governs *new* files; it is not a mandate to
reimplement the base theme.

## Theme blocks (`/blocks/`) — version gate

The newer reusable-block system (block types in `/blocks/`, `{% content_for "blocks" %}`,
`"type": "@theme"`/`"@app"`, `closest.*`) is the only native way to share a *block definition* across
sections — but it is version-sensitive (older Dawn-derived themes don't support it), the object-access
patterns differ from classic blocks, and theme-check/tooling support lagged. **Use it only if the
detected Dawn version cleanly supports it and tooling validates it.** Otherwise stay on classic
sections + shared snippets. `@app` blocks via `content_for` remain the preferred way to host a
third-party app inside a styled wrapper (see SHOPIFY_BEST_PRACTICES §11).
