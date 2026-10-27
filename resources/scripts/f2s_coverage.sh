#!/usr/bin/env sh
# f2s_coverage.sh — v4. "Did we build EVERYTHING?" — the question no other gate asks.
#
# Every gate in this skill answers "is what we built correct?". A section that was never built
# passes all of them, because there is nothing to fail. On one build the product page had its own Figma
# frames; extraction pulled only the home page's; nothing anywhere compared the two lists. The
# client found it.
#
# Correctness gates are the interesting ones to write, which is exactly why only those got written.
#
# Requires design/figma_page_inventory.json — the list of what the DESIGN contains, written at the
# Figma audit before extraction begins. Its absence is not a reason to skip this check; its absence
# IS the failure, because it means nobody wrote down what "everything" is.
#
#   { "pages": [ { "template": "product",
#                  "frames": [ {"node": "123:45", "label": "PDP hero", "breakpoint": "desktop"} ] } ] }
#
# Checks:
#   V1  every frame in the design inventory has a spec that names it        [FAIL]  extraction
#   V2  every spec'd section is referenced by its page's template           [FAIL]  assembly
#   V3  a spec whose section no template references anywhere                [FAIL]  orphan
#   V4  a template carrying f2s sections absent from the inventory  [WARN]  unplanned
#
# Usage: sh f2s_coverage.sh [theme_root]
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1

python3 <<'PY'
import glob, json, os, re, sys

def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f: return f.read()
    except Exception: return ""

def loads(raw):
    raw = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
    raw = re.sub(r"^\s*//[^\n]*$", "", raw, flags=re.M)
    return json.loads(raw)

INV = ".claude/knowledge/design/figma_page_inventory.json"
fails, warns = [], []

raw = read(INV)
if not raw:
    print("================ coverage gate ================")
    print(f"🔴 {INV} is missing.")
    print("   Nobody has written down what the design contains, so 'did we build everything?'")
    print("   cannot be answered — and that is the failure, not a reason to skip the check.")
    print("   Produce it at the Figma audit: every page, every designed frame, both breakpoints.")
    print("COVERAGE: FAIL")
    sys.exit(1)
try:
    inv = loads(raw)
except Exception as e:
    print(f"🔴 {INV} does not parse ({e})"); sys.exit(1)

# ---------- what got extracted: node id -> spec ----------
# Node ids live in the extraction MANIFEST (entries[key].nodeId / mobileNodeId / masterNodeId), the
# section type in plans/sections.json (machine-readable plan). Specs may repeat them; both are read.
PHASE = os.environ.get("F2S_COVERAGE_PHASE", "assembly")   # extraction | assembly
def norm_types(v):
    out = []
    for s in (v if isinstance(v, list) else [v]):
        if isinstance(s, dict): s = s.get("liquid") or s.get("type") or ""
        if not isinstance(s, str): continue
        s2 = re.sub(r"^(sections?/)", "", s.strip())
        out += [m.replace(".liquid", "") for m in re.findall(r"[a-z][a-z0-9_-]+(?:\.liquid)?", s2.split("(")[0])]
    return [o for o in out if o and o not in ("sections", "snippets", "assets", "new", "extended", "stock", "dawn", "preset", "and", "or", "the", "a", "app", "block", "slot", "embed", "hero")]

plan_types = {}
try:
    for s in loads(read(".claude/knowledge/plans/sections.json")).get("sections", []):
        plan_types[s["key"]] = norm_types(s.get("liquid", ""))
except Exception: pass

spec_by_node, specs, key_of_spec = {}, [], {}
for p in glob.glob(".claude/knowledge/extraction/figma/sections/*/spec.json"):
    try: s = loads(read(p))
    except Exception: continue
    if not isinstance(s, dict): continue
    key = os.path.basename(os.path.dirname(p))
    specs.append((p, s)); key_of_spec[id(s)] = key
    for k in ("nodeId", "node", "figma_node"):
        if isinstance(s.get(k), str): spec_by_node[s[k]] = s
    fig = s.get("figma") if isinstance(s.get("figma"), dict) else {}
    for k in ("desktop", "mobile", "node"):
        if isinstance(fig.get(k), str): spec_by_node[fig[k]] = s
try:
    man = loads(read(".claude/knowledge/extraction/figma/manifest.json")).get("entries", {})
except Exception: man = {}
spec_by_key = {os.path.basename(os.path.dirname(p)): s for p, s in specs}
for key, e in man.items():
    s = spec_by_key.get(key)
    if not s: continue
    for k in ("nodeId", "mobileNodeId", "masterNodeId"):
        if isinstance(e.get(k), str): spec_by_node[e[k]] = s

def section_of(spec):
    key = key_of_spec.get(id(spec), "")
    types = plan_types.get(key) or []
    if not types:
        sec = spec.get("section")
        types = norm_types(sec.get("liquid") if isinstance(sec, dict) else (sec or spec.get("liquid") or ""))
    return types

# ---------- what each template references ----------
tpl_types = {}
for f in glob.glob("templates/*.json") + glob.glob("templates/**/*.json", recursive=True):
    name = os.path.basename(f)[:-len(".json")]
    tpl_types[name] = set(re.findall(r'"type"\s*:\s*"([^"]+)"', read(f)))
group_types = set()
for f in glob.glob("sections/*.json"):
    group_types |= set(re.findall(r'"type"\s*:\s*"([^"]+)"', read(f)))
for f in glob.glob("layout/*.liquid"):
    group_types |= set(re.findall(r"\{%-?\s*sections?\s+['\"]([^'\"]+)['\"]", read(f)))
    group_types |= set(re.findall(r"\{%-?\s*section\s+['\"]([^'\"]+)['\"]", read(f)))
    group_types |= set(re.findall(r"\{%-?\s*render\s+['\"]([^'\"]+)['\"]", read(f)))

all_referenced = set(group_types)
for s in tpl_types.values(): all_referenced |= s

planned_sections = set()
n_frames = 0

# Accept both inventory shapes: list of {template, frames:[{node,label}]} (skill template) and the
# audit's dict {template_key: {template, frames:{desktop,mobile}, sections:[{key,desktop,mobile}]}}.
pages = inv.get("pages", [])
if isinstance(pages, dict):
    norm = []
    for pkey, pg in pages.items():
        frames = []
        for sec in pg.get("sections", []):
            for bp in ("desktop", "mobile"):
                if isinstance(sec.get(bp), str):
                    frames.append({"node": sec[bp], "label": f"{sec.get('key','?')} ({bp})", "key": sec.get("key")})
        norm.append({"template": os.path.basename(str(pg.get("template", pkey))).replace(".json", ""), "frames": frames})
    pages = norm

assembly_fail = fails if PHASE == "assembly" else warns
for page in pages:
    tpl = page.get("template", "?")
    for fr in page.get("frames", []):
        n_frames += 1
        node, label = str(fr.get("node", "?")), fr.get("label", "")
        spec = spec_by_node.get(node) or (spec_by_key.get(fr.get("key")) if fr.get("key") else None)
        if not spec:
            fails.append(f"[{tpl}] frame {node} ({label}) was NEVER EXTRACTED — no spec names this node. "
                         f"This is how an entire page silently goes unbuilt.")
            continue
        secs = section_of(spec)
        if not secs:
            fails.append(f"[{tpl}] frame {node} ({label}) has a spec that names no section")
            continue
        planned_sections.update(secs)
        refs = tpl_types.get(tpl, set()) | group_types
        if not any(s in refs for s in secs):
            assembly_fail.append(f"[{tpl}] {secs[0]} was built from frame {node} but the '{tpl}' template does "
                         f"not reference it — extracted, specced, built, and unreachable"
                         + (" (templates assemble at GATE 7)" if PHASE != "assembly" else ""))

# V3 — specs whose section nothing references at all
for p, s in specs:
    secs = section_of(s)
    if secs and not any(x in all_referenced for x in secs):
        assembly_fail.append(f"{secs[0]}: has a spec but NO template, section group or layout references it (orphan)")

# V4 — sections shipped that the design inventory never planned
for tpl, types in tpl_types.items():
    for t in types:
        if t.startswith("f2s") and t not in planned_sections:
            warns.append(f"[{tpl}] references {t}, which is not in the design inventory — unplanned, "
                         f"or the inventory is stale")

print("================ coverage gate ================")
print(f"design frames: {n_frames}  ·  specs found: {len(specs)}  ·  templates: {len(tpl_types)}")
for w in warns: print(f"⚠️  {w}")
for f_ in fails: print(f"🔴 {f_}")
print("-----------------------------------------------")
if fails:
    print(f"COVERAGE: FAIL ({len(fails)} blocking, {len(warns)} advisory)")
    print("A section that does not exist passes every correctness gate ever written.")
    sys.exit(1)
print(f"COVERAGE: PASS ({len(warns)} advisory)")
PY
