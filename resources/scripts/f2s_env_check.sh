#!/usr/bin/env sh
# GATE -1 — can this environment actually MEASURE?
#
# Why this exists: on an earlier build the whole pipeline ran green while unable to render
# anything. decisions/0007 recorded "no headless browser, no theme dev, no ImageMagick"
# and verification silently degraded to one model reading another model's code. Every
# section passed; spacing and typography drifted anyway, because nothing ever compared
# a rendered pixel to the design. A verifier that cannot measure is not a verifier.
#
# So this runs FIRST, and its verdict is binary: either the run can produce real
# measurements, or the run is not allowed to emit the word PASS.
#
# Exit 0 = measurement possible. Exit 1 = measurement impossible (with the exact fix).

set -u
ok=1
say() { printf '%s\n' "$*"; }

say "== measurement capability check =="

# --- Node + Playwright + a real browser binary -------------------------------
if command -v node >/dev/null 2>&1; then
  say "  node                 OK ($(node -v))"
else
  say "  node                 MISSING  → install Node 18+ (https://nodejs.org)"
  ok=0
fi

if node -e "require.resolve('playwright')" >/dev/null 2>&1 \
   || node -e "require.resolve('playwright-core')" >/dev/null 2>&1; then
  say "  playwright           OK"
else
  say "  playwright           MISSING  → npm i -D playwright"
  ok=0
fi

# A cached browser is what actually matters; playwright without a browser still fails.
if ls "${PLAYWRIGHT_BROWSERS_PATH:-$HOME/Library/Caches/ms-playwright}" 2>/dev/null | grep -q chromium \
   || ls "$HOME/.cache/ms-playwright" 2>/dev/null | grep -q chromium; then
  say "  chromium binary      OK"
else
  say "  chromium binary      MISSING  → npx playwright install chromium"
  ok=0
fi

# --- Python + Pillow (replaces the ImageMagick dependency) -------------------
PY=""
for c in python3 python; do command -v "$c" >/dev/null 2>&1 && { PY="$c"; break; }; done
if [ -n "$PY" ]; then
  say "  python               OK ($($PY -V 2>&1))"
  if "$PY" -c "import PIL" >/dev/null 2>&1; then
    say "  pillow               OK"
  else
    say "  pillow               MISSING  → $PY -m pip install pillow"
    ok=0
  fi
else
  say "  python               MISSING  → install Python 3.9+"
  ok=0
fi

# ImageMagick is deliberately NOT required any more. The old visualdiff shelled out to
# `magick`/`compare`, which is absent on most machines — that single missing dependency
# is what disabled pixel diffing on an earlier build. Pillow does the same job and ships with pip.
command -v magick >/dev/null 2>&1 && say "  imagemagick          present (unused; Pillow is the diff engine)"

# --- A render target: preview server OR static harness ----------------------
if [ -n "${F2S_RENDER_URL:-}" ]; then
  say "  render target        OK (F2S_RENDER_URL=$F2S_RENDER_URL)"
elif command -v shopify >/dev/null 2>&1; then
  say "  render target        shopify CLI present — 'shopify theme dev' must be RUNNING"
  say "                       and its URL exported as F2S_RENDER_URL."
  say "                       If OAuth cannot complete here, use the static harness instead."
  ok=0
else
  say "  render target        MISSING  → export F2S_RENDER_URL=<url>, or build the"
  say "                       static harness (see VERIFY_HARNESS.md). Never substitute"
  say "                       'read the code and judge' — that is what failed on an earlier build."
  ok=0
fi

say ""
if [ "$ok" -eq 1 ]; then
  say "RESULT: PASS — this environment can measure. Parity claims are permitted."
  exit 0
fi
cat <<'EOF'
RESULT: FAIL — this environment cannot measure.

You may still build, but the run is now in UNVERIFIED mode and must behave accordingly:
  - No section may be reported as PASS or "parity verified".
  - measurement.json must record  "method": "UNVERIFIED — no render capability"
  - The PR must open with: parity NOT verified, listing what was unmeasurable.
There is no waiver decision for this gate. A waiver here is how a build ships green and
wrong; record the limitation in the output instead of authorising yourself past it.
EOF
exit 1
