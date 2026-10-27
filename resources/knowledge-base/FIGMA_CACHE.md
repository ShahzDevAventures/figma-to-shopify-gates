# Figma Extraction Cache Protocol

The Figma MCP is expensive. Repeated calls for the same node across sessions waste time and tokens. This protocol caches every MCP response on disk and routes all reads through a manifest. **Default behavior: read from cache when an entry exists. Re-fetch only on explicit triggers.**

## Cache location

```
.claude/knowledge/extraction/figma/
├── manifest.json                          # the only write path; tracks every cached response
├── raw/
│   ├── nodes/<key>.json                   # get_design_context responses
│   ├── metadata/<key>.json                # get_metadata responses
│   ├── annotations/<key>.json             # dev-mode annotations (v4 — required, [] is a valid answer)
│   ├── comments/<key>.json                # pinned comments on/near the node (v4 — required)
│   └── variables/<fileKey>.json           # get_variable_defs responses
├── screenshots/<key>@<designed-w>.png      # COMMITTED; reference render, desktop
├── screenshots/<key>@<designed-w>.png      # COMMITTED; reference render, mobile
└── sections/<key>/                         # derived per-section build+verify inputs
    ├── BRIEF.md                            # v4 — THE input for builder/verifier/fixer (see below)
    ├── spec.json                           # distilled must_haves
    └── assets/                             # downloaded image/icon nodes used by the section
```

Widths are the **designed** frame widths read from the file, never assumed 1440/375 — an earlier build
designed at 430/440 and hardcoded widths made diffs impossible.

## Derived per-section artifacts

Raw MCP responses are the cache; the **build and the verifier consume distilled artifacts** derived from them — produced once during a section's Research step and re-read thereafter (no new MCP calls):

- **`sections/<key>/BRIEF.md`** (v4) — the single document the builder, verifier and fixer each read for this section. It is assembled once by the researcher and never regenerated from Figma. It carries: the spec's must_haves, both reference screenshots, the dev-mode annotations, the pinned comments, the asset list, the section's `inventory.md` classification (RETIRE/KEEP/CONFLICT), and the open questions. **After GATE 2 no build or verify agent calls Figma at all** — if an agent needs something the brief lacks, that is a research gap and the node goes back for re-extraction rather than the agent fetching it itself. This is what stopped the pipeline re-hitting the MCP once per agent per section.

- **`sections/<key>/spec.json`** — the section's checkable `must_haves` extracted *verbatim* from `get_design_context` (band color, exact spacing map, type metrics, structure, gotchas, image list, and a separate `breakpoints."375"` block). This is the single source of truth for plan, build, and goal-backward verify. Committed.
- **`screenshots/<key>@1440.png` and `@375.png`** — reference renders at **both** breakpoints. Verification diffs the build against these; it does **not** re-call the MCP. Capture both whenever a section node is researched (the mobile frame is its own node — research it too).
- **`sections/<key>/assets/`** — real images/icons downloaded per node (Figma asset URLs expire in ~7 days, so download immediately; gitignore if large).

**Freshness for derived artifacts** follows the same triggers as raw (user refresh, age, design-shift). Additionally: if **goal-backward verification exposes a mismatch the `spec.json` did not predict**, treat that node's research as incomplete — re-fetch and rebuild `spec.json` for *that node only*, not the whole page.

## Cache key

For node-scoped calls (`get_design_context`, `get_metadata`, `get_screenshot`):

```
<fileKey>__<nodeIdNormalized>
```

Where `nodeIdNormalized` replaces `:` with `-` so the key is filesystem-safe and matches the Figma URL form (`node-id=123-45`).

For `get_variable_defs`, key is `<fileKey>` alone (variables are file-scoped, not node-scoped).

## URL parsing

Extract `fileKey` and `nodeId` from any of these URL shapes:

- `figma.com/design/:fileKey/:fileName?node-id=:nodeId` — convert `-` to `:` for the API form, keep `-` for the cache key.
- `figma.com/design/:fileKey/branch/:branchKey/:fileName` — use `branchKey` as the effective fileKey.
- `figma.com/board/:fileKey/:fileName?node-id=:nodeId` — FigJam; cache under `extraction/figma/` with `kind: figjam` in the manifest entry.

## Manifest schema (`manifest.json`)

```json
{
  "version": 1,
  "entries": {
    "<key>": {
      "fileKey": "AbCdEf",
      "nodeId": "123:45",
      "kind": "design",
      "url": "https://figma.com/design/AbCdEf/Foo?node-id=123-45",
      "label": "Homepage hero (desktop)",
      "calls": {
        "design_context": {
          "path": "raw/nodes/AbCdEf__123-45.json",
          "cached_at": "2026-05-07T12:00:00Z",
          "etag": "sha256:..."
        },
        "metadata": {
          "path": "raw/metadata/AbCdEf__123-45.json",
          "cached_at": "2026-05-07T12:00:01Z",
          "etag": "sha256:..."
        },
        "screenshot": {
          "path": "screenshots/AbCdEf__123-45.png",
          "cached_at": "2026-05-07T12:00:02Z"
        },
        "annotations": {
          "path": "raw/annotations/AbCdEf__123-45.json",
          "cached_at": "2026-05-07T12:00:04Z"
        },
        "comments": {
          "path": "raw/comments/AbCdEf__123-45.json",
          "cached_at": "2026-05-07T12:00:05Z"
        }
      },
      "breakpoints": { "desktop": 1440, "mobile": 375 },
      "assets": [],
      "annotations": [],
      "comments": [],
      "consumed_by": [
        "plans/current.md",
        "design/components.md#hero"
      ]
    }
  },
  "variables": {
    "AbCdEf": {
      "path": "raw/variables/AbCdEf.json",
      "cached_at": "2026-05-07T12:00:03Z",
      "etag": "sha256:..."
    }
  }
}
```

`etag` = SHA-256 of the response body. Used to detect "we re-fetched and it's identical, no need to rewrite the file or its `cached_at`."

`consumed_by` = list of KB files that used this entry. Useful for impact analysis when the entry is refreshed.

## Read-vs-fetch policy

**Default: always read cache when an entry exists.**

Re-fetch is triggered only when one of these conditions holds:

1. **User says so.** Keywords: `refresh figma cache`, `re-fetch <node>`, `pull <node> again`. Invalidate matching entries before the call.
2. **Cache miss.** Node/file not in manifest → fetch, write, commit.
3. **Age limit exceeded.** `cached_at` older than `cache_max_age_days` (default **30**). Re-fetch, hash-compare, only rewrite the raw file and update `cached_at` if the hash changed.
4. **Design-shift signal.** User mentions Figma was updated, or a previously-extracted token doesn't appear in current `design_context` output.

## Cache hit announcement

The agent must explicitly announce cache hits before acting on cached data. Format:

> Using cached Figma context for `<label>` (cached `<date>`). Pass `refresh figma` to force re-fetch.

This makes stale data visible. The user can correct in real time.

## Write rules

- **Manifest is the only write path.** Never write a raw file (`raw/...`, `screenshots/...`) without updating the corresponding manifest entry in the same operation.
- On cache hit (no fetch), **do not touch the manifest.** Reading must be free of side effects.
- On re-fetch with identical hash: keep the file, do **not** update `cached_at`. Otherwise stale-cache detection becomes useless.
- On re-fetch with different hash: rewrite raw file, update `cached_at` and `etag`, append to `consumed_by` if a new KB file is being produced.

## Committed vs gitignored

| Path | Tracked? | Why |
|---|---|---|
| `manifest.json` | committed | Single source of truth for what's cached. |
| `raw/nodes/*.json` | committed | Designer intent; diffs cleanly; the actual cost win. |
| `raw/metadata/*.json` | committed | Same. |
| `raw/variables/*.json` | committed | Same. |
| `raw/annotations/*.json` | committed | Designer intent. The most expensive thing to re-fetch and the easiest to lose. |
| `raw/comments/*.json` | committed | Same — and comments are where designers actually write intent. |
| `screenshots/*.png` | **committed** | See below. |
| `sections/*/BRIEF.md` | committed | The build/verify contract for that section. |

**Screenshots are committed (v4 — this reverses v3 and resolves a contradiction).** v3's BOOTSTRAP
said to un-ignore screenshots because evidence must be committed, while this file said to gitignore
them as "regenerable in-session". Both were live, so behaviour depended on which document an agent
read. Gitignored screenshots do not survive a new session, a fresh clone, or a branch switch — so
the verifier finds no reference, and the pipeline re-hits the Figma MCP to rebuild something it
already had. That is a large part of the "why does this call Figma so often" problem. They are also
the audit trail: an earlier build's verify baseline was unrecoverable for exactly this reason. Compress PNGs
and prune superseded run dirs at page completion, never silently.

If the team has secrecy concerns (unreleased copy in Figma), they can additionally gitignore `extraction/figma/raw/`. Default-commit is the right cost tradeoff.

## Invocation pattern (pseudocode)

```
function getDesignContext(url):
    (fileKey, nodeId) = parseUrl(url)
    key = `${fileKey}__${nodeId.replace(':', '-')}`
    manifest = readManifest()
    entry = manifest.entries[key]

    if entry?.calls?.design_context and not refreshRequested(key):
        announceCacheHit(entry.label, entry.calls.design_context.cached_at)
        return readJson(entry.calls.design_context.path)

    response = mcp.figma.get_design_context(fileKey, nodeId)
    writeRawAndUpdateManifest(key, "design_context", response)
    return response
```

The same pattern applies to `get_metadata`, `get_screenshot`, `get_variable_defs`, with appropriate manifest fields.

## Failure modes to guard against

- **Manifest corruption.** If `manifest.json` fails to parse, do not silently overwrite. Surface the error and ask the user before proceeding.
- **Orphaned raw files.** Files in `raw/` not referenced by manifest. The agent does not delete them automatically — flags during a sweep at end-of-run.
- **Sensitive content.** If the user flags a node as containing unreleased copy, mark `sensitive: true` in the manifest entry; the agent must surface this whenever the entry is consumed.
