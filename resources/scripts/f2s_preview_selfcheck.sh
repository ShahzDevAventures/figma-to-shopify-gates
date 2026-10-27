#!/usr/bin/env sh
# f2s_preview_selfcheck.sh — a drifted preview is worse than none (v2 item 12).
# Asserts the static preview's CSS is EXTRACTED from the section file, not hand-written:
# every CSS rule in the section's {% stylesheet %} must appear verbatim in the preview HTML.
# Usage: sh f2s_preview_selfcheck.sh <section.liquid> <preview.html>
set -u
SEC="${1:?section.liquid}"; PREV="${2:?preview.html}"
python3 - "$SEC" "$PREV" <<'PYEOF'
import re, sys
sec, prev = open(sys.argv[1]).read(), open(sys.argv[2]).read()
m = re.search(r'{%-?\s*stylesheet\s*-?%}(.*?){%-?\s*endstylesheet\s*-?%}', sec, re.S)
if not m:
    print("⚠️  section has no {% stylesheet %} — preview must inline the section's asset CSS instead; verify manually"); sys.exit(0)
css = m.group(1)
# normalize whitespace, compare rule-by-rule
rules = [r.strip() for r in re.split(r'}', css) if r.strip()]
missing = []
norm_prev = re.sub(r'\s+', ' ', prev)
for r in rules:
    norm_r = re.sub(r'\s+', ' ', r).strip()
    if norm_r and norm_r not in norm_prev:
        missing.append(norm_r[:90])
if missing:
    print(f"🔴 HARNESS INVALID: {len(missing)} section CSS rule(s) absent from preview (hand-written replica?):")
    for x in missing[:6]: print("   ", x)
    print("   Regenerate the preview FROM the section file. Measuring a copy proves nothing (an earlier build: 230px measured vs 166px designed).")
    sys.exit(1)
print(f"✅ preview CSS matches section ({len(rules)} rules) — harness valid")
PYEOF
