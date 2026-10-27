#!/usr/bin/env sh
# f2s_reachability.sh — v4. "Done" means a customer can reach it.
#
# Every other gate in this skill answers "is what we built CORRECT?". None answered "can anyone
# SEE it?" — so a section that renders to nobody passes everything. On one build a section passed four
# gates and reached no customer for 33 hours, because a theme setting meant its markup never ran.
#
# THIS GATE IS DELIBERATELY GENERIC. That build's specific miss was a cart drawer on a store whose
# setting selected a notification cart instead — but that is one instance of a general class, and
# encoding "check cart_type" would catch exactly one bug forever. The general class is: a section's
# rendering depends on a value this gate can read, and nobody asserted it. Currency selectors,
# predictive search, announcement bars, sticky headers, quick-add, age gates, and any custom
# `settings.*` a theme invents all fail the same way.
#
# Checks:
#   R1  every built section is referenced by a template, section group, or layout   [FAIL]
#   R2  every `settings.<key>` a section reads EXISTS in config/settings_data.json  [FAIL]
#       (a missing key renders nil — conditionals silently take the empty branch)
#   R3  every requirement the spec DECLARES matches the theme's actual value        [FAIL]
#   R4  a setting dependency the section reads but the spec never declared          [WARN]
#   R5  a section whose whole body sits behind one conditional (renders-empty risk)  [WARN]
#
# Declare requirements in spec.json:
#   "runtime_requires": { "cart_type": "drawer", "predictive_search_enabled": true }
# The keys are whatever THIS theme uses. Nothing here is hardcoded to a feature.
#
# Usage: sh f2s_reachability.sh [theme_root]
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1

python3 <<'PY'
import glob, json, os, re, sys

def read(p):
    try:
        with open(p, encoding="utf-8", errors="replace") as f: return f.read()
    except Exception: return ""

def loads(raw):
    """Shopify's JSON files are JSON-with-comments. settings_data.json ships a /* */ licence
    header in most real themes, and template JSON permits comments too — Shopify strips them
    server-side. Plain json.loads() dies at char 0 on the very first file it meets, which reads
    as 'the theme is broken' when the theme is completely fine. Strip block comments and
    whole-line // comments (never inline //, which would eat the https:// in every URL)."""
    raw = re.sub(r"/\*.*?\*/", "", raw, flags=re.S)
    raw = re.sub(r"^\s*//[^\n]*$", "", raw, flags=re.M)
    return json.loads(raw)

fails, warns, notes = [], [], []

sections = sorted(glob.glob("sections/f2s_*.liquid"))
if not sections:
    print("⚠️  no f2s_ sections found — nothing to check")
    sys.exit(0)

# ---------- what the theme actually has switched on ----------
settings, settings_src = {}, "config/settings_data.json"
raw = read(settings_src)
if raw:
    try:
        d = loads(raw)
        cur = d.get("current")
        if isinstance(cur, dict):
            settings = {k: v for k, v in cur.items() if not isinstance(v, (dict, list))}
        elif isinstance(cur, str):
            # `current` naming a preset — resolve it
            settings = {k: v for k, v in (d.get("presets", {}).get(cur, {}) or {}).items()
                        if not isinstance(v, (dict, list))}
            notes.append(f"settings resolved via preset '{cur}'")
    except Exception as e:
        fails.append(f"{settings_src} does not parse ({e}) — every setting dependency below is unverifiable")
else:
    fails.append(f"{settings_src} missing — cannot verify any setting a section depends on")

# ---------- R1: is anything pointing at these sections? ----------
referenced = set()
for f in (glob.glob("templates/*.json") + glob.glob("templates/**/*.json", recursive=True)
          + glob.glob("sections/*.json")):
    for t in re.findall(r'"type"\s*:\s*"([^"]+)"', read(f)): referenced.add(t)
for f in glob.glob("layout/*.liquid"):
    for t in re.findall(r"\{%-?\s*sections?\s+['\"]([^'\"]+)['\"]", read(f)): referenced.add(t)
# a section rendered by another section counts as reachable
for f in glob.glob("sections/*.liquid") + glob.glob("snippets/*.liquid"):
    for t in re.findall(r"\{%-?\s*(?:render|include|section)\s+['\"]([^'\"]+)['\"]", read(f)):
        referenced.add(t)

# Legacy library sections the operator chose to KEEP on disk unwired (decision 0031) were not built
# on this run: they are listed in HANDOFF, not gated. "Built" = has a spec (extraction) or is not
# marked KEEP-UNWIRED in the inventory.
unwired_ok = set()
try:
    inv = loads(read(".claude/knowledge/architecture/inventory.json"))
    for r in inv.get("rows", []):
        if "KEEP-UNWIRED" in str(r.get("note", "")) or "unwired" in str(r.get("note", "")).lower():
            unwired_ok.add(os.path.basename(r.get("file", ""))[:-len(".liquid")])
except Exception: pass
for path in sections:
    handle = os.path.basename(path)[:-len(".liquid")]
    if handle in unwired_ok and handle not in referenced:
        warns.append(f"{handle}: legacy library section kept unwired by decision 0031 (HANDOFF §Legacy files)")
        continue
    if handle not in referenced:
        fails.append(f"{handle}: BUILT BUT UNREACHABLE — no template, section group, or layout "
                     f"references it. It passed every correctness gate and renders to nobody.")

# ---------- R2/R3/R4: setting dependencies ----------
# the GLOBAL settings object only: not `section.settings.x`, `block.settings.x`, `entry.settings.x`,
# `cfg.settings.x` (any dotted owner) — and never inside Liquid comment blocks
SET_RE = re.compile(r"(?<![\w.])settings\.([a-zA-Z0-9_]+)")
def strip_comments(s):
    return re.sub(r"\{%-?\s*comment\s*-?%\}.*?\{%-?\s*endcomment\s*-?%\}", "", s, flags=re.S)
for path in sections:
    handle = os.path.basename(path)[:-len(".liquid")]
    body = read(path)

    # a section's own schema settings are `section.settings.x` — exclude those; we want THEME settings
    theme_keys = set()
    for m in SET_RE.finditer(strip_comments(body)):
        start = max(0, m.start() - 8)
        if body[start:m.start()].rstrip().endswith(("section.", "block.")): continue
        theme_keys.add(m.group(1))

    spec = {}
    for cand in (f".claude/knowledge/extraction/figma/sections/{handle}/spec.json",
                 f".claude/knowledge/specs/{handle}.json"):
        if os.path.exists(cand):
            try: spec = loads(read(cand))
            except Exception: pass
            break
    declared = spec.get("runtime_requires") or {}

    for k in sorted(theme_keys):
        if settings and k not in settings:
            fails.append(f"{handle}: reads `settings.{k}`, which does not exist in {settings_src} — "
                         f"it resolves to nil, so any conditional on it silently takes the empty branch")
        elif k not in declared:
            warns.append(f"{handle}: depends on `settings.{k}` (currently {settings.get(k)!r}) but the "
                         f"spec never declared it — add \"runtime_requires\": {{\"{k}\": <required value>}}")

    for k, want in declared.items():
        if not settings: continue
        got = settings.get(k, "<absent>")
        if got != want:
            fails.append(f"{handle}: requires `settings.{k}` == {want!r}, theme has {got!r} — "
                         f"this section will not render as designed on this store")

    # ---------- R5: whole body behind one conditional ----------
    stripped = re.sub(r"\{%-?\s*comment.*?endcomment\s*-?%\}", "", body, flags=re.S)
    stripped = re.sub(r"\{%-?\s*schema.*?endschema\s*-?%\}", "", stripped, flags=re.S).strip()
    m = re.match(r"\{%-?\s*(?:if|unless)\s+(.+?)-?%\}", stripped)
    if m and stripped.rstrip().endswith(("{% endif %}", "{%- endif -%}", "{% endunless %}", "{%- endunless -%}")):
        warns.append(f"{handle}: entire body sits behind `{m.group(1).strip()}` — it can render zero "
                     f"bytes while passing every other gate. Assert the condition holds on this store.")

print("================ reachability gate ================")
for n in notes: print(f"   {n}")
print(f"sections: {len(sections)}  ·  theme settings read: {len(settings)}")
for w in warns: print(f"⚠️  {w}")
for f_ in fails: print(f"🔴 {f_}")
print("---------------------------------------------------")
if fails:
    print(f"REACHABILITY: FAIL ({len(fails)} blocking, {len(warns)} advisory)")
    print("A section nobody can reach is not done, however green its other gates are.")
    sys.exit(1)
print(f"REACHABILITY: PASS ({len(warns)} advisory)")
PY
