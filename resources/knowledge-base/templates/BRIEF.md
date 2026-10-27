# Section brief — <section handle>

<!--
v4. Written ONCE by figma-researcher at GATE 2, from the cache. Read by figma-builder,
figma-verifier and figma-fixer. It is the ONLY input any of them needs for this section.

The rule this enforces: after GATE 2, no build or verify agent calls Figma. If something you
need is missing here, that is a RESEARCH GAP — record it with
`sh .claude/scripts/f2s_research_gap.sh add <section> <node> "<what is missing>"`,
then return "RE-RESEARCH: <node>". Do not fetch it yourself, and do not return the string
without recording it: on a prior build every RE-RESEARCH existed only in an agent's final
message, and a repo-wide grep found the phrase exactly once — in the instruction to say it.

v3 had no such document, so every agent went back to the MCP for whatever its instructions
didn't carry, which is why a 28-section page cost hundreds of Figma calls.

Every field below is required. "none" is a valid answer; blank is not.
-->

| | |
|---|---|
| **Node** | `<fileKey>__<node-id>` |
| **Figma URL** | <url> |
| **Cache key** | `<key>` |
| **Designed widths** | desktop `<w>` · mobile `<w>` (read from the file — never assumed) |
| **Inventory classification** | RETIRE / KEEP / CONFLICT — from `architecture/inventory.md` |
| **Replaces** | `sections/<existing-file>.liquid` or `— none —` |
| **Complexity** | simple / standard / complex |
| **Depends on** | foundation · `<shared snippet>` · `<other section>` · `— none —` |
| **Runtime requires** | theme settings this section needs, e.g. `cart_type: drawer` — or `— none —` |

**Runtime requires** goes into `spec.json` as `"runtime_requires": {"<key>": <value>}` and is
asserted against the store's real `config/settings_data.json` at the reachability gate. If this
section only renders when some theme setting is on, say so here. A section whose markup never runs
passes every correctness gate while reaching nobody — that is how one build shipped a design no
customer saw for 33 hours, taking store-wide add-to-cart down with it.

## Reference renders

- Desktop: `../../screenshots/<key>@<w>.png`
- Mobile: `../../screenshots/<key>@<w>.png`

Both are committed. The verifier diffs against these; it does not re-render from Figma.

## Spec — must_haves

Verbatim from `get_design_context`. Exact px, type metrics, grid templates, band colours.
Distinct values never share a token: a prior invented scale collapsed two heading sizes and
deleted weight 900 site-wide.

<!-- inline spec.json must_haves, or link: ./spec.json -->

## Annotations (dev-mode)

From `raw/annotations/<key>.json`. The five tags, per the boilerplate's annotation standard:

| Tag | Answer |
|---|---|
| `@section` | |
| `@data` | where each piece of content comes from: setting / metafield / app / fixed |
| `@behavior` | what moves or reacts, or "static" |
| `@states` | empty, loading, sold out, missing image, very long title |
| `@editable` | what the merchant changes, and how many of any repeating item |

`@data` and `@states` are the two whose absence caused the most rework. Missing either =
this section is BLOCKED, not buildable.

## Pinned comments

From `raw/comments/<key>.json`. Designers write intent in comments at least as often as in
dev-mode annotations — a prior run went 20-for-28 nodes finding "nothing" while never once
querying comments.

## Assets

From `assets/`. Figma asset URLs expire in ~7 days, so these are downloaded, not linked.

## Open questions

Routed three ways: here, a pinned Figma comment on the node, and the run's chat output. A
question that lives only in a JSON file is a guess with a paper trail — v2 shipped two specs
whose open questions no human ever saw.

| # | Question | Blocking? | Asked in Figma | Answer |
|---|---|---|---|---|

**A section with an unanswered blocking question is PARKED, not built.**

## Verify

The verifier grades this section against `PARITY_VERIFY.md`'s rubric — the single canonical
list — plus every annotation above explicitly checked off. It may not reword a criterion, and
it may not choose or degrade the method.
