# F2S Component Registry

Single source of truth for every `f2s_` file in this theme. One row per file. Any agent that
creates or materially changes a file updates its row **in the same commit**. A fresh agent onboards by
reading this table — it should not need to grep the tree or re-open Figma to know what a file does, what
it depends on, and what namespace it owns.

Drift between a file and its row is a verify failure (see SKILL.md → Code Documentation & Multi-Agent
Collaboration). The design contract is each section's `spec.json`; this table + the in-file header are
the **code** contract between agents.

## Sections

| File | Purpose | Inputs (settings / metafields / objects) | Depends on (snippets/assets) | Owns (CSS ns / JS sel) | Used on | Owner/branch |
|------|---------|------------------------------------------|------------------------------|------------------------|---------|--------------|
| _e.g._ `f2s_hero.liquid` | Homepage hero, layered text/figure | settings: eyebrow,title,cta; — | `f2s_responsive_image` | `.f2s_hero*` / `data-f2s-hero` | index | agent-home / feat/home-hero |

## Snippets

| File | Purpose | Args (required → optional) | Reads metafields/objects | Used by |
|------|---------|----------------------------|--------------------------|---------|
| _e.g._ `f2s_product_card.liquid` | Reusable product card | `product` → `badge` | product.* | hero, grid, recommendations |

## Assets (CSS / JS)

| File | Purpose | Namespace it owns | Loaded on (template/condition) | Depends on |
|------|---------|-------------------|--------------------------------|------------|
| _e.g._ `f2s_design_tokens.css` | Global tokens | `--f2s-*` | all (theme.liquid) | — |
| _e.g._ `f2s_product.css` | PDP styles | `.f2s_buybox*`, `.f2s_pdp*` | `template.name == 'product'` | tokens |

## Hot shared files (single-owner — see SKILL.md rule)

These are edited only by the orchestrator/designated owner; section agents **request** changes.

- `assets/f2s_design_tokens.css`
- `layout/theme.liquid`, `sections/*-group.json`
- `config/settings_schema.json`, `config/settings_data.json`
- `locales/*.json`
- shared snippets listed above
- template JSON (`index.json`, `product.json`, `collection.json`) — assembled by the integration agent

## Metafield contract (mirror of HANDOFF.md)

| namespace.key | Type | Consumed by | Fallback |
|---------------|------|-------------|----------|
| _e.g._ `custom.shipping_note` | single_line_text | `f2s_product_buybox` | section setting |
