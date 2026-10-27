#!/usr/bin/env sh
# f2s_functional.sh — the nine-classes gate.
#
# 105 post-build fix commits across five projects reduce to nine repeating bug classes
# (HANDOFF.md). Six are grep-detectable. Before this script they lived only as prose in
# SHOPIFY_BEST_PRACTICES.md — and an earlier build's audit showed prose gets read ~sometimes while
# scripts run every time. Each check names its class and the production incident behind it.
#
# RED = blocks commit (via precommit D5). WARN = printed, never blocks — heuristics that
# cry wolf get bypassed, and a bypassed gate is worse than none.
# Ownership note: hardcoded copy/currency + snippet price checks live in f2s_editability.sh.
# This script owns the BEHAVIOR classes. One check, one home — competing gates are how
# contradictions breed.
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1
fail=0
red()  { printf '  🔴 %s\n' "$1"; fail=1; }
ok()   { printf '  ✅ %s\n' "$1"; }
warn() { printf '  ⚠️  %s\n' "$1"; }

echo "================ f2s functional gate (9-classes) ================"

SECTIONS=$(find sections -name 'f2s_*.liquid' 2>/dev/null | sort)

# ---- CLASS U — Shopify ADMIN upload rules theme-check does not enforce (v4.1, decision 0057) -------
# Incident: one rebuild passed every gate (theme-check 0 errors) and the admin rejected 22
# sections on upload — range step grids, blank/unresolvable url defaults, label caps, an unclosed
# comment inside {% liquid %}, a filter pipe in a render argument. RED: each line is a real rejection.
# The pre-commit hook runs the same validator scoped to the staged files (D5b) and sets
# F2S_SKIP_UPLOAD=1 here so the whole-tree run is not repeated inside one commit.
if [ "${F2S_SKIP_UPLOAD:-0}" = "1" ]; then
  ok "class U: upload validator ran scoped by the pre-commit hook (D5b)"
elif [ -x "$(dirname "$0")/f2s_upload_validator.sh" ]; then
  if sh "$(dirname "$0")/f2s_upload_validator.sh" . >/tmp/cs_fn_upload.log 2>&1; then
    ok "class U: no Shopify admin upload rejections ($(grep -c '⚠️' /tmp/cs_fn_upload.log | tr -d ' ') advisory)"
  else
    red "class U: Shopify admin upload would reject this theme (decision 0057) — see /tmp/cs_fn_upload.log"
    grep '🔴' /tmp/cs_fn_upload.log | head -12 | sed 's/^/     /'
  fi
else
  red "class U: f2s_upload_validator.sh missing beside this script — bootstrap did not install v4.1 gates"
fi

if [ -z "$SECTIONS" ]; then
  [ "$fail" -eq 0 ] && { echo "RESULT: N/A (no f2s sections; upload validator clean)"; exit 0; }
  echo "RESULT: FAIL (no f2s sections, but the upload validator found admin rejections)"; exit 1
fi

# ---- CLASS A — price/image without variant resolution (sections; snippets are in editability) ----
# Incident: homepage card showed $29, PDP said $39 — product.price is the LOWEST variant price.
A_BAD=""
for f in $SECTIONS; do
  if grep -q 'product\.price\|product\.compare_at_price' "$f" 2>/dev/null \
     && ! grep -q 'selected_or_first_available_variant\|current_variant\|card_variant' "$f" 2>/dev/null; then
    A_BAD="$A_BAD $(basename $f)"
  fi
done
[ -n "$A_BAD" ] && red "class A: product.price/compare_at_price with no variant resolution in:$A_BAD" \
                || ok  "class A: no unresolved product.price reads in sections"

# ---- CLASS H — JS bound to DOMContentLoaded with no editor-lifecycle path ----------------------
# Incident: merchant reorders sections in the theme editor, JS dies silently, merchant just
# reloads and quietly loses trust. Present in ALL five audited projects, reported in none.
H_BAD=""
for f in $(find assets -name 'f2s_*.js' 2>/dev/null) $SECTIONS; do
  if grep -q 'DOMContentLoaded' "$f" 2>/dev/null \
     && ! grep -q 'shopify:section:load\|currentScript' "$f" 2>/dev/null; then
    H_BAD="$H_BAD $(basename $f)"
  fi
done
[ -n "$H_BAD" ] && red "class H: DOMContentLoaded-only init (dies on theme-editor re-render) in:$H_BAD — use shopify:section:load or a currentScript-scoped IIFE" \
                || ok  "class H: all JS survives theme-editor re-render"

# ---- CLASS G — carousel traps -------------------------------------------------------------------
# G1 incident: thumbs-linked Swiper with loop:true creates clone slides; clicking a thumbnail
# selected the WRONG product image in production.
G1=$(grep -l 'thumbs' $SECTIONS 2>/dev/null | while read -r f; do
  grep -q 'loop:[[:space:]]*true' "$f" && basename "$f"; done)
[ -n "$G1" ] && red "class G: thumbs-linked carousel with loop:true (clone slides break index mapping) in: $G1" \
             || ok  "class G: no looped thumbs-linked carousels"
# G2: overflow set on exactly one axis coerces the other to auto → stray scrollbar. WARN.
G2=""
for f in $SECTIONS $(find assets -name 'f2s_*.css' 2>/dev/null); do
  X=$(grep -c 'overflow-x' "$f" 2>/dev/null); X=${X:-0}
  Y=$(grep -c 'overflow-y' "$f" 2>/dev/null); Y=${Y:-0}
  [ "$X" -gt 0 ] && [ "$Y" -eq 0 ] && G2="$G2 $(basename $f)"
done
[ -n "$G2" ] && warn "class G: overflow-x without overflow-y (other axis coerces to auto — check for stray scrollbars) in:$G2"

# ---- CLASS D — block/product loops with no empty state ------------------------------------------
# 43% of all historical fix commits. WARN not RED: presets with default blocks mitigate, and a
# hard fail on 69% of existing sections would get the gate bypassed. New sections should guard.
D_BAD=""
for f in $SECTIONS; do
  if grep -Eq 'for .* in (section\.blocks|.*collection.*\.products)' "$f" 2>/dev/null \
     && ! grep -Eq 'size[[:space:]]*==[[:space:]]*0|== blank|\.size > 0|request\.design_mode' "$f" 2>/dev/null; then
    D_BAD="$D_BAD $(basename $f)"
  fi
done
[ -n "$D_BAD" ] && warn "class D: block/product loop with no empty-state branch or design_mode hint in:$D_BAD" \
                || ok  "class D: loops carry empty-state handling"

# ---- CLASS C — variant picker with no price-update path -----------------------------------------
# Incident: buy box printed the Liquid-rendered price once; variant changes never updated it. WARN.
C_BAD=""
for f in $SECTIONS; do
  if grep -Eq 'variant.*picker|name="id"|data-variant' "$f" 2>/dev/null \
     && grep -q 'money' "$f" 2>/dev/null \
     && ! grep -Eq 'variant.*json|data-variant-json|shopify:section:load|variantChange|variant:change' "$f" 2>/dev/null; then
    C_BAD="$C_BAD $(basename $f)"
  fi
done
[ -n "$C_BAD" ] && warn "class C: variant selection present but no visible price-update hook in:$C_BAD — confirm the theme JS actually updates the rendered price"

echo "--------------------------------------------------------"
if [ "$fail" -eq 0 ]; then echo "RESULT: PASS (functional classes clean; heed ⚠️  warns)"; exit 0
else echo "RESULT: FAIL (fix 🔴 — each maps to a shipped production defect)"; exit 1; fi
