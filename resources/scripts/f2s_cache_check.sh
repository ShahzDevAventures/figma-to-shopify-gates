#!/usr/bin/env sh
# f2s_cache_check.sh — "no spec without cache" (v2 items 4/5/11).
# Validates that a Figma node's extraction is COMPLETE on disk before spec.json may be written.
# Required per node (all seven):
#   1. manifest entry with cached_at
#   2. raw design-context JSON  (raw/nodes/<key>.json, non-trivial size)
#   3. reference screenshot at the DESIGNED desktop width   (screenshots/<key>@<w>.png)
#   4. reference screenshot at the DESIGNED mobile width    (widths come from the manifest entry,
#      NOT hardcoded 1440/375 — one design file was drawn at 430/440 and hardcoded widths made diffs impossible)
#   5. assets/ dir for the node (may be empty only if manifest entry says "assets": [])
#   6. dev-mode annotations, declared + cached  (raw/annotations/<key>.json)
#   7. pinned comments, declared + cached       (raw/comments/<key>.json)
# 6 and 7 are v4. v3 instructed researchers to fetch both, gave them no cache location, and never
# checked — so they were silently dropped and re-fetched, which is most of this pipeline's Figma cost.
# Usage: sh f2s_cache_check.sh <nodeKey> [kb_root]     kb_root default .claude/knowledge
# Exit 0 = complete (spec creation allowed). Exit 1 = incomplete (spec creation REFUSED).
set -u
KEY="${1:?usage: f2s_cache_check.sh <nodeKey> [kb_root]}"
KB="${2:-.claude/knowledge}"
FIG="$KB/extraction/figma"
MAN="$FIG/manifest.json"
PY=$(command -v python3 || command -v python)
[ -z "$PY" ] && { echo "python3 required"; exit 1; }

"$PY" - "$MAN" "$FIG" "$KEY" <<'PYEOF'
import json, os, sys
man_path, fig, key = sys.argv[1], sys.argv[2], sys.argv[3]
def fail(msg):
    print(f"🔴 CACHE INCOMPLETE for {key}: {msg}")
    print("   Run the extraction step for this node (design-context + variable defs + both-breakpoint")
    print("   screenshots + assets) and register it in the manifest. spec.json creation is REFUSED.")
    sys.exit(1)
if not os.path.exists(man_path): fail("manifest.json missing entirely")
man = json.load(open(man_path))
entries = man.get("entries", {})
if key not in entries: fail("no manifest entry")
e = entries[key]
if not e.get("cached_at"): fail("entry has no cached_at")
raw = os.path.join(fig, "raw", "nodes", f"{key}.json")
if not os.path.exists(raw): fail(f"raw design-context missing: {raw}")
if os.path.getsize(raw) < 500: fail(f"raw design-context suspiciously small ({os.path.getsize(raw)}B) — a summary is not a cache")
bps = e.get("breakpoints") or {}
waiver = e.get("mobile_waiver")  # path to a decisions/*.md entry when the file designs NO mobile frame
if "desktop" not in bps or ("mobile" not in bps and not waiver):
    fail('entry lacks "breakpoints": {"desktop": <w>, "mobile": <w>} — record the DESIGNED frame widths (or set "mobile_waiver": "decisions/NNNN-....md" when the design file has no mobile frames)')
if waiver and not os.path.exists(os.path.join(os.path.dirname(os.path.dirname(fig)), waiver)):
    fail(f"mobile_waiver cites missing decision file: {waiver}")
missing = []
for label, w in bps.items():
    png = os.path.join(fig, "screenshots", f"{key}@{w}.png")
    if not os.path.exists(png): missing.append(png)
if missing: fail("reference screenshot(s) missing: " + ", ".join(missing))
assets_dir = os.path.join(fig, "assets", key)
declared = e.get("assets")
if declared is None: fail('entry lacks "assets": [...] (empty list is fine if node has no images)')
if declared and not os.path.isdir(assets_dir): fail(f"assets declared but {assets_dir} missing")
for a in declared or []:
    if not os.path.exists(os.path.join(assets_dir, a)): fail(f"declared asset missing: {a}")

# 6/7. ANNOTATIONS and PINNED COMMENTS (v4). v3 told researchers to fetch both and then had
# nowhere to put them and no check requiring them — so they were dropped and re-fetched every
# time, which is a large part of why this pipeline hammered the Figma MCP. Both must be DECLARED
# (an empty list is a fine answer; a missing key is not) and both must have a raw file on disk,
# so "the designer annotated nothing" is a recorded fact rather than an omission nobody noticed.
for kind, human in (("annotations", "dev-mode annotations"), ("comments", "pinned comments")):
    if e.get(kind) is None:
        fail(f'entry lacks "{kind}": [...] — fetch {human} for this node and declare them '
             f'(use [] to record that the node genuinely has none)')
    rawf = os.path.join(fig, "raw", kind, f"{key}.json")
    if not os.path.exists(rawf):
        fail(f"{human} declared but raw file missing: {rawf}")

mob = bps.get("mobile", f"WAIVED per {e.get('mobile_waiver')}")
print(f"✅ cache complete for {key} (desktop {bps['desktop']} / mobile {mob}, "
      f"{len(declared or [])} assets, {len(e.get('annotations') or [])} annotations, "
      f"{len(e.get('comments') or [])} comments)")
PYEOF
