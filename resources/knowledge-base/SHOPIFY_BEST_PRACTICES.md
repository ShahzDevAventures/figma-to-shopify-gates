# Shopify Theme Best Practices (native reference)

Distilled from the Shopify-development skill's `references/themes.md` and folded into this
skill so a Figma→Shopify build never has to leave this skill to know "the Shopify-correct way."
This is the **how-to-build-it-right** companion to the rest of the skill, which governs
**how-to-match-the-design**. When the two ever conflict, fidelity to the design wins on
*appearance*; this file wins on *Shopify mechanics* (data sources, form semantics, performance).

Treat every rule here as a verifier checklist item — the parity subagent and the editability
audit both draw from it.

---

## 1. Liquid is the data layer — never hardcode what an object can give you

Dynamic store data comes from objects, not settings, not literals:

```liquid
{{ product.title }}            {{ product.price | money }}
{{ product.compare_at_price }} {{ product.selected_or_first_available_variant.id }}
{{ collection.products_count }} {{ cart.item_count }}
{{ shop.money_format }}
```

Hardcoding any of `product.title | price | featured_image | url | available | variants`,
or collection/cart counts, is a **build defect** — it desyncs the moment the merchant edits
the product. The Product-Grid and Content-Source rules in SKILL.md enforce this; this is the
canonical list of which fields are "always dynamic."

## 2. Canonical patterns (use these shapes, adapted to the Figma markup)

**Product form with variants** — real add-to-cart, variant-aware, degrades when sold out:

```liquid
{% form 'product', product, id: form_id %}
  {% unless product.has_only_default_variant %}
    {% for option in product.options_with_values %}
      <div class="f2s_product-option">
        <label>{{ option.name }}</label>
        <select name="options[{{ option.name }}]">
          {% for value in option.values %}
            <option value="{{ value }}">{{ value }}</option>
          {% endfor %}
        </select>
      </div>
    {% endfor %}
  {% endunless %}

  <input type="hidden" name="id" value="{{ product.selected_or_first_available_variant.id }}">
  <input type="number" name="quantity" value="1" min="1">

  <button type="submit" {% unless product.available %}disabled{% endunless %}>
    {% if product.available %}Add to Cart{% else %}Sold Out{% endif %}
  </button>
{% endform %}
```

Rules: use `{% form 'product' %}` (never a hand-rolled `<form action>`); drive the selector from
`options_with_values`; submit `selected_or_first_available_variant.id`; honor `has_only_default_variant`
(no selector for single-variant products); `disabled` + "Sold Out" when unavailable. The variant→price/id
update on selection is JS the section owns.

**Pagination** — never render an unbounded loop:

```liquid
{% paginate collection.products by 12 %}
  {% for product in collection.products %}
    {% render 'f2s_product_card', product: product %}
  {% endfor %}
  {% if paginate.pages > 1 %}{% comment %} render paginate.parts {% endcomment %}{% endif %}
{% endpaginate %}
```

**Cart AJAX** — the drawer talks to the standard cart endpoints:

```javascript
fetch('/cart/add.js',    { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ id: variantId, quantity: 1 }) });
fetch('/cart.js').then(r => r.json());                 // read
fetch('/cart/change.js', { method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({ id: lineItemKey, quantity: 2 }) });
```

Reuse the theme's existing cart JS/section-rendering plumbing where it exists (Dawn/Impulse ship it)
rather than introducing a parallel cart stack.

## 3. Rendering: `render`, not `include`

Use `{% render 'f2s_product_card', product: product %}`. `{% render %}` is isolated-scope
and performant; `{% include %}` is deprecated and leaks scope. Pass everything the snippet needs as
explicit arguments — a snippet that reads ambient variables is a bug.

## 4. Metafields are the home for product-specific structured content

```liquid
{{ product.metafields.custom.care_instructions }}
{{ product.metafields.custom.material.value }}          {% comment %} .value for typed metafields {% endcomment %}
{% if product.metafields.custom.featured %}<span class="badge">Featured</span>{% endif %}
```

For a **default** template (one `product.json` serving every product), product-specific copy —
descriptions, materials, shipping, accordion rows, specs, badges, comparison data — **must** come
from `product.metafields`, not section settings. Section settings on a default template are shared
by every product, so they are only correct for page-level marketing copy that is genuinely the same
on every product. This is the single most common architecture defect in a Figma→PDP build: it looks
right on the one product you previewed and is wrong on all the others. See the Content-Source rules
and the metafield contract in `HANDOFF.md`.

## 5. Performance (folds into the Performance Improvement Pass)

- Serve Shopify-hosted images through `image_url: width:` with `srcset`/`sizes`; set explicit
  `width`/`height` to prevent CLS.
- `loading="lazy"` below the fold; eager + `fetchpriority="high"` on the single LCP image only.
- Defer non-critical JS; keep Liquid loops shallow (`paginate`, avoid nested `for` over large arrays).
- Don't ship a JS carousel where CSS scroll-snap suffices; don't import large external fonts without approval.
- Prefer `<img>`/`<picture>` over CSS background images unless fidelity requires it (document why).

## 6. Accessibility

Semantic HTML and heading order (one `<h1>` per page); alt text wired to merchant image fields;
keyboard-operable interactive controls; visible focus states; ARIA only where semantics fall short;
`prefers-reduced-motion` respected; sufficient contrast **checked per band** (the design's color flips
change the contrast math). No copy baked into images unless unavoidable.

## 7. SEO

Descriptive `<title>`/meta description (theme-level, don't clobber); content structured with real
heading levels; `<img alt>` populated; consider schema.org markup (Product/Offer/BreadcrumbList) where
the theme doesn't already emit it — don't duplicate JSON-LD the theme/app already outputs.

## 8. Code quality

Follow Shopify theme guidelines and theme-check; consistent naming (the `f2s_` prefix);
comment non-obvious Liquid; keep sections focused and reusable; section-scoped CSS over global
overrides. Run `shopify theme check` (and `--auto-correct` for mechanical fixes) before every commit
— it is part of the QA gate, not optional.

## 9. CLI quick reference

```bash
shopify theme dev                 # local server at :9292, auto-sync to a dev theme (the render path)
shopify theme check               # lint  (--auto-correct to fix mechanical issues)
shopify theme pull --live         # pull current live theme
shopify theme push --unpublished  # push a new unpublished theme (safe preview)
shopify theme push --only=sections,snippets
```

Only run scripts that actually exist in the repo (`package.json`, theme-check config). Never invent
a build/test command.

## 10. Section schema authoring (the part agents get wrong)

Every section ends with a `{% schema %}` JSON block. It is the merchant-editing contract — get it
right or the Theme-Editor wiring audit fails.

```liquid
{% schema %}
{
  "name": "Hero banner",
  "tag": "section",
  "class": "f2s_hero",
  "settings": [
    { "type": "text",        "id": "eyebrow",  "label": "Eyebrow",  "default": "NEW" },
    { "type": "inline_richtext", "id": "title", "label": "Title",   "default": "Strength, engineered" },
    { "type": "image_picker","id": "image",    "label": "Background image" },
    { "type": "url",         "id": "cta_link", "label": "CTA link" },
    { "type": "color",       "id": "band",     "label": "Band color", "default": "#1a2c4e" },
    { "type": "select",      "id": "align",    "label": "Align",
      "options": [ {"value":"left","label":"Left"}, {"value":"center","label":"Center"} ], "default": "left" }
  ],
  "blocks": [
    { "type": "stat", "name": "Stat", "limit": 4,
      "settings": [ {"type":"text","id":"value","label":"Value"}, {"type":"text","id":"label","label":"Label"} ] }
  ],
  "max_blocks": 12,
  "presets": [ { "name": "Hero banner", "blocks": [ {"type":"stat"}, {"type":"stat"} ] } ],
  "enabled_on": { "templates": ["index"] }
}
{% endschema %}
```

Rules that prevent rework:
- **The merchant-facing `name` is plain English with NO code prefix.** It shows in the Theme Editor
  ("Hero banner", "Featured collection grid") — a merchant must never see `f2s`. The prefix
  belongs on the filename and the `class`, not on `name`. (Gated by `f2s_codehealth.sh`.)
- **Every editable Figma node = one setting**, and its `default` is the **Figma value** (so a fresh
  install renders the design, not blanks). This is what the wiring audit checks. But don't add a
  setting the design never varies — see SKILL.md "YAGNI counterweight".
- **Repeatable groups are `blocks`, not N fixed settings** — merchant must add/remove/reorder. Iterate
  with `{% for block in section.blocks %}` and emit `{{ block.shopify_attributes }}` on each block root
  (required for Theme Editor selection).
- Use the right input type: `text` / `inline_richtext` / `richtext` / `image_picker` / `url` /
  `color` / `color_scheme` / `range` / `select` / `checkbox` / `collection` / `product` / `video` /
  `font_picker`. Don't fake a richtext with a `text`.
- `presets` make the section appear in the Theme Editor "Add section" list with starter blocks —
  include one for every reusable section.
- Scope placement with `enabled_on`/`disabled_on` when a section only belongs on certain templates.
- **User-facing strings belong in locales**, not hardcoded: `{{ 'sections.hero.cta' | t }}` with the
  key defined in `locales/en.default.json`. Schema labels can use `"t:..."` translation keys too.

## 11. Theme blocks & `content_for` (OS 2.0)

Newer OS 2.0 supports app blocks and theme blocks. To let merchants drop app blocks into a section:
`{% content_for 'blocks' %}` inside the section, plus `{"type": "@app"}` in the schema `blocks`.
This is how a styled wrapper hosts a third-party app's block (Judge.me, etc.) without statically
duplicating its output — preferred over hand-embedding vendor markup.

## 12. Metafields & metaobjects — typed access

```liquid
{{ product.metafields.custom.material }}              {# raw — works for simple types #}
{{ product.metafields.custom.material.value }}        {# typed (single/multi-line, number, etc.) #}
{% for row in product.metafields.custom.faq.value %}  {# list & metaobject-reference lists are arrays #}
  {{ row.question.value }} — {{ row.answer.value }}
{% endfor %}
{{ product.metafields.custom.size_chart.value.image }} {# metaobject reference: .value then field #}
```

- Always guard: `{% if product.metafields.custom.material != blank %}…{% endif %}` and provide a
  fallback (often the section setting or a sensible default) so an unpopulated product still renders.
- **Definition matters**: list-type and reference-type metafields return arrays/objects; single-text
  returns a string via `.value`. Mismatching the access pattern to the definition is the usual
  "metafield shows blank" bug.
- Record the exact `namespace.key`, type, and which section consumes it in the metafield contract in
  `HANDOFF.md` — that's how the merchant knows what to create and the next agent knows what's wired.

## 13. Image filters, whitespace, and empty states

```liquid
{{ image | image_url: width: 1200, height: 1200, crop: 'center' }}   {# crop/format params #}
{{ image | image_url: width: 800, format: 'webp' }}
```
- Whitespace control: use `{%- -%}` / `{{- -}}` to trim around tags in tight markup; uncontrolled
  whitespace breaks `inline-block`/flex gaps and inflates HTML.
- `{% liquid %}` for multi-line logic, `{% capture %}` to build a string once — keep template bodies
  readable.
- **Always design the empty/edge state**: no image → render nothing or a placeholder, never a broken
  `<img>`; no blocks → hide the section or show a sensible default; missing compare-at price → no
  strikethrough; sold-out → disabled CTA. The verifier tests these, not just the happy path.

## 14. Navigation is menus (linklists), not settings and not blocks

Header/footer navigation is editable through **Online Store → Navigation** (menus), surfaced to the
theme via the `link_list` setting type — **not** via individual URL settings and **not** via section
blocks. This is the single most common header-editability mistake.

```liquid
{%- assign main_menu = linklists[section.settings.main_menu] -%}
<nav>
  {%- for link in main_menu.links -%}
    <a href="{{ link.url }}" {% if link.active %}aria-current="page"{% endif %}>{{ link.title }}</a>
    {%- if link.links.size > 0 -%}        {# one level of dropdown #}
      <ul>{%- for child in link.links -%}<li><a href="{{ child.url }}">{{ child.title }}</a></li>{%- endfor -%}</ul>
    {%- endif -%}
  {%- endfor -%}
</nav>
```
```json
{ "type": "link_list", "id": "main_menu", "label": "Menu", "default": "main-menu" }
```

- A merchant adds/removes/reorders links in Navigation; the theme renders whatever the chosen menu
  contains. Do **not** build nav as `link1_url/link1_label`, `link2_url/...` fixed slots — that caps the
  link count, duplicates the menu system, and is the anti-pattern an editability review should catch.
  (A small fixed utility bar — e.g. a single "Track order" link — is the only defensible exception, and
  even then a second `link_list` is cleaner.)
- `link.active` / `link.child_active` drive current-page styling; `link.links` gives one nested level
  for dropdowns/mega-menus.
- The Theme-Editor wiring audit's structural script cannot judge this — it's a semantic, read-the-liquid
  check: *is navigation coming from a `link_list`/`linklists`, or from hardcoded URL settings?*

**Theme blocks vs config blocks (so the `shopify_attributes` rule isn't misapplied):** a block that
renders **selectable, reorderable content** must output `{{ block.shopify_attributes }}` on its root
element. A **singleton config block** that only holds settings read elsewhere (e.g. Dawn/Impulse's
`logo` block, or an `@app` block) does not render a selectable root and legitimately omits it. Don't
flag the second as a defect.

---

## 15. Shopify's JSON files are JSON-with-comments — plain parsers die at character 0

`config/settings_data.json` ships a `/* … */` licence header in most real themes, and template JSON
permits comments too. Shopify strips them server-side; `json.loads` / `JSON.parse` do not — they
fail at line 1 column 1, which reads as "this theme is corrupt" when the theme is perfectly fine.
Every tool here that reads theme JSON must strip comments first:

```python
raw = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)      # block comments
raw = re.sub(r"^\s*//[^\n]*$", "", raw, flags=re.M)  # whole-line // only
json.loads(raw)
```

Strip whole-line `//` only, never inline — inline stripping eats the `//` in every `https://` URL in
the file. Found the hard way: the reachability gate reported "settings_data.json does not parse" on a
healthy production theme and read zero of its 124 settings, which would have silently disabled every
setting-dependency check the gate exists to perform.

## Source

Full upstream reference: the Shopify development skill's `references/themes.md` (Liquid object/filter
catalog, directory layout, complete pagination markup, more CLI). This file is the curated subset a
Figma→theme build needs in-hand; read the upstream only when you need an object/filter you don't
remember.

## Real data survives, idealized data doesn't (migrated from v1 reference)

Dynamic product data stays dynamic: title/price/variants/media/availability come from the product
object, never settings. And the build must survive REAL data, not the idealized Figma copy — long
titles that wrap, missing compare-at price, sold-out variants, no selling plan (subscribe UI must
degrade), wrong-aspect images. Verify against edge-case data explicitly; the happy path is the
only path Figma ever shows, and it is the path production never takes for long.
