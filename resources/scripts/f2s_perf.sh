#!/usr/bin/env sh
# f2s_perf.sh — v4 GATE 7b. Mobile performance as a GATE, not a pass.
#
# v1 had a "Performance Improvement Pass"; v2/v3 compression dropped it entirely while README kept
# advertising it. This restores it as a script, because a prose pass is what got dropped.
#
# Deterministic checks only — things that are true or false by reading the code. Lighthouse/
# PageSpeed numbers on a preview theme are too noisy to gate on (cold CDN, dev middleware, no
# real traffic), so a score is ADVISORY and reported separately; it never decides this gate.
#
# Checks, per f2s_ section:
#   1. <img> without width+height and without an aspect-ratio wrapper   -> CLS risk        [FAIL]
#   2. above-fold/LCP image with loading="lazy"                          -> delays LCP     [FAIL]
#   3. raw <img src> not going through Shopify's image_url/img_url       -> no CDN resize  [FAIL]
#   4. render-blocking <script> with neither defer nor async             -> blocks parse   [FAIL]
#   5. `| script_tag` (blocks parsing, no upside)                        ->                [FAIL]
#   6. `| stylesheet_tag` (render-blocking, but it IS Dawn's per-section ->                [WARN]
#      convention — failing every section on the platform's own idiom is how a gate
#      gets switched off, so this reports and does not block)
#   7. per-section inline CSS weight over budget                         ->                [WARN]
#   8. <img> below the fold without loading="lazy"                       ->                [WARN]
# Usage: sh f2s_perf.sh [theme_root] [css_budget_bytes]
set -u
ROOT="${1:-.}"; BUDGET="${2:-24576}"
cd "$ROOT" || exit 1

python3 - "$BUDGET" <<'PY'
import glob, os, re, sys
budget = int(sys.argv[1])
fails, warns = [], []

files = sorted(glob.glob("sections/f2s_*.liquid"))
if not files:
    print("⚠️  no f2s_ sections found — nothing to measure")
    sys.exit(0)

IMG = re.compile(r"<img\b[^>]*>", re.I | re.S)
def attr(tag, name):
    m = re.search(rf'{name}\s*=\s*(["\'])(.*?)\1', tag, re.I | re.S)
    return m.group(2) if m else None
def has(tag, name):
    return re.search(rf'\b{name}\b', tag, re.I) is not None

for f in files:
    name = os.path.basename(f)
    try:
        body = open(f, encoding="utf-8", errors="replace").read()
    except Exception:
        continue

    imgs = IMG.findall(body)
    for i, tag in enumerate(imgs):
        w, h = attr(tag, "width"), attr(tag, "height")
        wrapped = re.search(r"aspect-ratio|padding-(?:top|bottom)\s*:", body, re.I)
        if not (w and h) and not wrapped:
            fails.append(f"{name}: <img> #{i+1} has no width/height and no aspect-ratio wrapper — layout shift (CLS)")

        src = attr(tag, "src") or ""
        if src and "image_url" not in src and "img_url" not in src and not src.startswith("{{"):
            fails.append(f"{name}: <img> #{i+1} src bypasses image_url/img_url — no CDN resize, full-size download")

        lazy = (attr(tag, "loading") or "").lower() == "lazy"
        prio = (attr(tag, "fetchpriority") or "").lower() == "high"
        # first image in the first section of a page is the LCP candidate; flag lazy+high conflicts
        # and lazy-loaded priority images, which is the classic "LCP got slower" mistake.
        if lazy and prio:
            fails.append(f"{name}: <img> #{i+1} is both loading=lazy and fetchpriority=high — contradictory; the LCP image must not be lazy")
        if i == 0 and lazy and re.search(r"hero|banner|above", name, re.I):
            fails.append(f"{name}: hero/banner first image is loading=lazy — this is the LCP element, it must load eagerly with fetchpriority=high")
        if i > 0 and not lazy and not prio:
            warns.append(f"{name}: <img> #{i+1} is not lazy — everything below the first viewport should be loading=lazy")

    for m in re.finditer(r"<script\b([^>]*)>", body, re.I):
        a = m.group(1)
        if "src=" in a.lower() and not has(a, "defer") and not has(a, "async") and 'type="module"' not in a.lower():
            fails.append(f"{name}: <script src> without defer/async — blocks HTML parsing")

    if re.search(r"\|\s*script_tag", body):
        fails.append(f"{name}: uses `| script_tag` — blocks parsing and has no upside; use <script src=... defer>")
    if re.search(r"\|\s*stylesheet_tag", body):
        warns.append(f"{name}: `| stylesheet_tag` is render-blocking — fine as Dawn's per-section convention, "
                     f"but if this section is below the fold its CSS is delaying first paint for nothing")

    css = "".join(re.findall(r"\{%-?\s*style\s*-?%\}(.*?)\{%-?\s*endstyle\s*-?%\}", body, re.S | re.I))
    css += "".join(re.findall(r"<style[^>]*>(.*?)</style>", body, re.S | re.I))
    if len(css.encode()) > budget:
        warns.append(f"{name}: inline CSS {len(css.encode())}B over budget {budget}B — move shared rules to a token/base file")

print("================ performance gate ================")
print(f"sections measured: {len(files)}  ·  css budget: {budget}B/section")
for w in warns: print(f"⚠️  {w}")
for f_ in fails: print(f"🔴 {f_}")
print("--------------------------------------------------")
if fails:
    print(f"PERF: FAIL ({len(fails)} blocking, {len(warns)} advisory)")
    print("These are code facts, not score noise. Fix them; a Lighthouse run will not argue.")
    sys.exit(1)
print(f"PERF: PASS ({len(warns)} advisory)")
PY
RC=$?

echo ""
echo "Advisory score (never gates this check):"
echo "  npx lighthouse <preview-url> --only-categories=performance --form-factor=mobile"
echo "  Record the number in the PR. A preview theme scores lower than production — the number is"
echo "  a trend line across runs, not a pass mark."
exit $RC
