#!/usr/bin/env sh
# f2s_dupecheck.sh — find duplicated / unnecessary code (ADVISORY).
# Answers "is the AI rewriting the same thing across sections / shipping code nothing uses?"
# Usage: sh resources/scripts/f2s_dupecheck.sh [theme_root]   (default: cwd)
#
# IMPORTANT scope rule (see COMPONENT_REUSE.md): reuse lives at the SNIPPET layer; duplication at
# the SCHEMA (block) layer is EXPECTED and is NOT flagged. This script deliberately excludes
# {% schema %} blocks so it never fights the documented boundary.
#
# This script is ADVISORY by default — it reports signals and exits 0. Set F2S_DUPE_STRICT=1
# to make exact-duplicate snippet bodies a hard fail (exit 1). Soft signals never fail the build.
# Needs python3.

set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "cannot cd to $ROOT"; exit 1; }
PY=$(command -v python3 || command -v python || true)
[ -z "$PY" ] && { echo "python3 required"; exit 1; }
STRICT="${F2S_DUPE_STRICT:-0}"

echo "================ f2s duplication / dead-code (advisory) ================"

"$PY" - "$STRICT" <<'PYEOF'
import sys, os, re, glob, hashlib
from collections import defaultdict

strict = sys.argv[1] == "1"
hard_fail = False

def read(p):
    try: return open(p, encoding="utf-8", errors="replace").read()
    except Exception: return ""

def strip_schema(src):  # exclude {% schema %}..{% endschema %} — schema dup is allowed
    return re.sub(r'{%-?\s*schema\s*-?%}.*?{%-?\s*endschema\s*-?%}', '', src, flags=re.S)

def norm(s):  # normalize whitespace for similarity hashing
    return re.sub(r'\s+', ' ', s).strip()

# ---- 1. Near/exact-duplicate SNIPPET bodies ------------------------------------------------------
snips = sorted(glob.glob("snippets/f2s_*.liquid"))
bodies = {}
for f in snips:
    b = norm(strip_schema(read(f)))
    if len(b) >= 80:  # ignore trivially small snippets
        bodies[f] = b
seen = defaultdict(list)
for f, b in bodies.items():
    seen[hashlib.sha1(b.encode()).hexdigest()].append(f)
dups = [v for v in seen.values() if len(v) > 1]
if dups:
    for grp in dups:
        print("🔴 EXACT-DUPLICATE snippet bodies (consolidate to one): " + ", ".join(grp))
        if strict: hard_fail = True
else:
    print("✅ no exact-duplicate snippet bodies")

# ---- 2. Repeated CSS rule blocks across f2s CSS (copy-paste patterns) --------------------
css_files = sorted(glob.glob("assets/f2s_*.css"))
rule_re = re.compile(r'([^{}]+)\{([^{}]+)\}')
blocks = defaultdict(list)   # normalized declaration body -> [(file, selector)]
for f in css_files:
    for sel, body in rule_re.findall(read(f)):
        decls = norm(body)
        if decls.count(":") >= 3:   # only non-trivial rules (3+ declarations)
            blocks[decls].append((f, norm(sel)))
rep = {k: v for k, v in blocks.items() if len({sel for _, sel in v}) > 1 and len(v) > 1}
if rep:
    print(f"⚠️  {len(rep)} CSS declaration block(s) repeated under different selectors "
          "— candidates to hoist into a shared component class or token:")
    for decls, where in list(rep.items())[:6]:
        sels = ", ".join(sorted({s for _, s in where})[:4])
        print(f"     • {{{decls[:70]}...}}  in: {sels}")
else:
    print("✅ no repeated multi-declaration CSS blocks")

# ---- 3. Unused schema settings (declared id never referenced in this file's body) ----------------
# (orphan settings = code nothing renders; the editability script also flags these, repeated here
#  as part of the dead-code picture.)
unused_total = 0
for f in sorted(glob.glob("sections/f2s_*.liquid")):
    src = read(f)
    m = re.search(r'{%-?\s*schema\s*-?%}(.*?){%-?\s*endschema\s*-?%}', src, re.S)
    if not m: continue
    import json
    try: schema = json.loads(m.group(1))
    except Exception: continue
    body = src[:m.start()] + src[m.end():]
    ids = set()
    for s in schema.get("settings", []) or []:
        if isinstance(s, dict) and s.get("id"): ids.add(s["id"])
    orphans = [i for i in ids if not re.search(r'settings\.' + re.escape(i) + r'\b', body)]
    if orphans:
        unused_total += len(orphans)
        print(f"⚠️  {os.path.basename(f)}: setting(s) declared but never rendered "
              f"(dead unless used in a snippet): {', '.join(sorted(orphans))}")
if unused_total == 0:
    print("✅ no obviously-unused section settings")

# ---- 4. Dead Liquid: empty {% if %} / {% for %} bodies -------------------------------------------
dead = 0
for f in sorted(glob.glob("sections/f2s_*.liquid") + glob.glob("snippets/f2s_*.liquid")):
    src = strip_schema(read(f))
    for m in re.finditer(r'{%-?\s*(if|for|unless)\b.*?-?%}\s*({%-?\s*end\1)', src, re.S):
        dead += 1
if dead:
    print(f"⚠️  {dead} empty if/for/unless block(s) — dead control flow, remove")
else:
    print("✅ no empty control-flow blocks")

print("-------------------------------------------------------------------------------")
print("NOTE: schema (block) duplication is intentionally NOT flagged — that's the documented")
print("      reuse boundary (COMPONENT_REUSE.md). Reuse snippets; copy schema.")
if hard_fail:
    print("RESULT: FAIL (exact-duplicate snippets, strict mode)"); sys.exit(1)
print("RESULT: ADVISORY (review ⚠️ / 🔴 above; not a hard gate unless F2S_DUPE_STRICT=1)")
PYEOF
exit $?
