#!/usr/bin/env sh
# f2s_inventory.sh — v4 GATE 1a. What does this theme ALREADY have?
#
# Why this exists: on one rebuild the theme carried 23 differently-prefixed sections from a previous build.
# The run built 14 new `f2s_` sections alongside them and nothing anywhere recorded which
# of the 23 were supposed to disappear. 13 of the 14 ended up wired to no template at all. The
# rebuild question is not "should I extend this section" — on a full rebuild you replace it. The
# question nobody asked was: what dies, what lives, and what collides.
#
# This script ENUMERATES and detects; it does not classify. Classification is a judgment call that
# needs the design, so every row lands as UNCLASSIFIED and preflight blocks until each is resolved:
#   RETIRE   — the new design replaces this; it must be GONE by the page-integration gate
#   KEEP     — must survive: app-backed regions, and pages the design never covered (cart, blog, 404)
#   CONFLICT — the new design and this would both serve one purpose; a human picks one
#
# Writes .claude/knowledge/architecture/inventory.md (human) + inventory.json (machine).
# Usage: sh f2s_inventory.sh [theme_root]
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1
OUTDIR=".claude/knowledge/architecture"
mkdir -p "$OUTDIR"

python3 - "$OUTDIR" <<'PY'
import json, os, re, sys, glob
out = sys.argv[1]

def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f: return f.read()
    except Exception: return ""

def loads(raw):
    """Shopify JSON files are JSON-with-comments — settings_data.json ships a /* */ licence header
    in most real themes and template JSON permits comments too. Plain json.loads() dies at char 0.
    Strip block comments and whole-line // (never inline, which would eat every https:// URL)."""
    raw = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
    raw = re.sub(r"^\s*//[^\n]*$", "", raw, flags=re.M)
    return json.loads(raw)

sections  = sorted(os.path.basename(p) for p in glob.glob("sections/*.liquid"))
snippets  = sorted(os.path.basename(p) for p in glob.glob("snippets/*.liquid"))
templates = sorted(glob.glob("templates/*.json") + glob.glob("templates/**/*.json", recursive=True))
# Section GROUPS (sections/*.json) and LAYOUTS render sections outside template JSON — header and
# footer live there. Miss these and every stock chrome section reads as an orphan, which buries the
# real signal in noise.
groups  = sorted(glob.glob("sections/*.json"))
layouts = sorted(glob.glob("layout/*.liquid"))

# which sections each template references, and which templates carry app blocks
tpl_uses, app_templates = {}, set()
for t in templates:
    body = read(t)
    if "shopify://apps/" in body: app_templates.add(t)
    try:
        data = loads(body)
        types = {b.get("type") for b in (data.get("sections") or {}).values() if isinstance(b, dict)}
    except Exception:
        types = set(re.findall(r'"type"\s*:\s*"([^"]+)"', body))
    tpl_uses[t] = {x for x in types if x}

used_by = {}
for t, types in tpl_uses.items():
    for ty in types: used_by.setdefault(ty, []).append(os.path.basename(t))

# section groups: same JSON shape as templates
for g in groups:
    body = read(g)
    if "shopify://apps/" in body: app_templates.add(g)
    try:
        data_g = loads(body)
        types = {b.get("type") for b in (data_g.get("sections") or {}).values() if isinstance(b, dict)}
    except Exception:
        types = set(re.findall(r'"type"\s*:\s*"([^"]+)"', body))
    for ty in filter(None, types): used_by.setdefault(ty, []).append(os.path.basename(g))

# layouts: {% section 'name' %} and {% sections 'group' %}
for l in layouts:
    body = read(l)
    for ty in re.findall(r"\{%-?\s*sections?\s+['\"]([^'\"]+)['\"]", body):
        used_by.setdefault(ty, []).append(os.path.basename(l))

def app_backed(path):
    b = read(path)
    return bool(re.search(r'shopify://apps/|"type"\s*:\s*"@app"|\{%-?\s*render\s+[\'"]app[-_]', b))

# prefix families — a prior custom layer usually announces itself with its own prefix
def prefix(name):
    m = re.match(r'^([a-z0-9]+[-_])', name)
    return m.group(1) if m else "(dawn/stock)"

rows = []
for s in sections:
    key = s[:-len(".liquid")]
    rows.append({
        "file": f"sections/{s}", "kind": "section", "handle": key,
        "prefix": prefix(s),
        "used_by": sorted(used_by.get(key, [])),
        "live": bool(used_by.get(key)),
        "app_backed": app_backed(f"sections/{s}"),
        "classification": "UNCLASSIFIED",
    })
for s in snippets:
    rows.append({
        "file": f"snippets/{s}", "kind": "snippet", "handle": s[:-len(".liquid")],
        "prefix": prefix(s), "used_by": [], "live": None,
        "app_backed": app_backed(f"snippets/{s}"),
        "classification": "UNCLASSIFIED",
    })
for t in templates:
    rows.append({
        "file": t, "kind": "template", "handle": os.path.basename(t)[:-len(".json")],
        "prefix": "", "used_by": [], "live": True,
        "app_backed": t in app_templates,
        "classification": "UNCLASSIFIED",
    })

fams = {}
for r in rows:
    if r["kind"] == "section": fams.setdefault(r["prefix"], []).append(r["handle"])

data = {"version": 1, "counts": {
            "sections": len(sections), "snippets": len(snippets), "templates": len(templates),
            "app_backed": sum(1 for r in rows if r["app_backed"]),
            "orphan_sections": sum(1 for r in rows if r["kind"] == "section" and not r["live"]),
        },
        "prefix_families": {k: sorted(v) for k, v in sorted(fams.items())},
        "rows": rows}
json.dump(data, open(os.path.join(out, "inventory.json"), "w"), indent=1)

L = []
A = L.append
A("# Existing theme inventory\n")
A("Every row starts UNCLASSIFIED. Preflight BLOCKS until each is one of "
  "`RETIRE` / `KEEP` / `CONFLICT`. The page-integration gate then asserts every RETIRE row is "
  "actually gone — that assertion is what catches a rebuild that shipped its new sections "
  "alongside the old ones instead of replacing them.\n")
A(f"- sections: **{len(sections)}** · snippets: **{len(snippets)}** · templates: **{len(templates)}**")
A(f"- app-backed files detected: **{data['counts']['app_backed']}** — these are KEEP unless you have "
  "a migration plan; the design file does not show them")
A(f"- sections referenced by no template: **{data['counts']['orphan_sections']}**\n")

A("## Prefix families\n")
A("A prior custom build usually shares one prefix. Two families serving the same purpose is the "
  "duplication signal.\n")
for p, hs in data["prefix_families"].items():
    A(f"- `{p}` — {len(hs)} section(s): {', '.join(hs)}")
A("")

A("## Sections\n")
A("| file | live in | app-backed | classification |")
A("|---|---|---|---|")
for r in rows:
    if r["kind"] != "section": continue
    A(f"| `{r['file']}` | {', '.join(r['used_by']) or '— none —'} | "
      f"{'YES' if r['app_backed'] else ''} | {r['classification']} |")

A("\n## Snippets\n")
A("| file | app-backed | classification |")
A("|---|---|---|")
for r in rows:
    if r["kind"] != "snippet": continue
    A(f"| `{r['file']}` | {'YES' if r['app_backed'] else ''} | {r['classification']} |")

A("\n## Templates\n")
A("| file | app blocks | classification |")
A("|---|---|---|")
for r in rows:
    if r["kind"] != "template": continue
    A(f"| `{r['file']}` | {'YES' if r['app_backed'] else ''} | {r['classification']} |")

open(os.path.join(out, "inventory.md"), "w").write("\n".join(L) + "\n")
print(f"sections={len(sections)} snippets={len(snippets)} templates={len(templates)} "
      f"app_backed={data['counts']['app_backed']} orphans={data['counts']['orphan_sections']}")
print(f"written: {out}/inventory.md and {out}/inventory.json")
PY
