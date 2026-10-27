#!/usr/bin/env sh
# f2s_editability.sh — prove Theme-Editor wiring objectively, per section.
# "Merchant-editable" is only true if it's wired; this catches the structural half deterministically
# so the agent's manual read only has to judge the semantic half (right copy, right DATA SOURCE).
# Usage: sh resources/scripts/f2s_editability.sh [theme_root]   (default: cwd)
# Exit: 0 if all hard gates pass, 1 otherwise. Needs python3 for schema JSON parsing.
#
# HARD gates (per f2s_ section):
#   - {% schema %} present and valid JSON
#   - block loops emit {{ block.shopify_attributes }}  (Theme Editor cannot select blocks without it)
#   - section has a "presets" entry                    (else it never appears in "Add section")
#   - editable text settings (text/textarea/richtext/inline_richtext/html/url) have a "default"
# SOFT signals (reported, agent must review — not auto-failed):
#   - settings declared but never referenced (orphans; may be used in a snippet)
#   - heuristic hardcoded user-facing copy in markup not wired to liquid/locale
#   - default content shipped in templates/*.json and config/settings_data.json

set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "cannot cd to $ROOT"; exit 1; }
PY=$(command -v python3 || command -v python || true)
[ -z "$PY" ] && { echo "python3 required for schema parsing"; exit 1; }

fail=0
red()  { printf '  🔴 %s\n' "$1"; fail=1; }
ok()   { printf '  ✅ %s\n' "$1"; }
warn() { printf '  ⚠️  %s\n' "$1"; }

SECTIONS=$(find sections -name 'f2s_*.liquid' 2>/dev/null | sort)
# Scope (decision 0031/0035): F2S_EDITABILITY_SCOPE=wired hard-gates only the sections a
# template, section group or layout actually references (what ships); unwired legacy library
# sections kept on disk are listed as ⚠️ instead of failing the door. Default "all" = every file.
SCOPE="${F2S_EDITABILITY_SCOPE:-all}"
UNWIRED=""
if [ "$SCOPE" = "wired" ]; then
  WIRED=$( { grep -ho '"type"[[:space:]]*:[[:space:]]*"[^"]*"' templates/*.json templates/**/*.json sections/*.json 2>/dev/null | sed -E 's/.*"([^"]*)"$/\1/';
             grep -hoE "\{%-?[[:space:]]*sections?[[:space:]]+['\"][^'\"]+['\"]" layout/*.liquid 2>/dev/null | sed -E "s/.*['\"]([^'\"]+)['\"]/\1/"; } | sort -u)
  KEEP=""
  for f in $SECTIONS; do
    t=$(basename "$f" .liquid)
    if printf '%s\n' "$WIRED" | grep -qx "$t"; then KEEP="$KEEP $f"; else UNWIRED="$UNWIRED $f"; fi
  done
  SECTIONS="$KEEP"
  [ -n "$UNWIRED" ] && printf '  ⚠️  scope=wired: %s unwired legacy section(s) NOT hard-gated (decision 0031 — listed in HANDOFF):%s\n' "$(printf '%s\n' $UNWIRED | grep -c .)" "$(printf ' %s' $UNWIRED | sed 's#sections/##g')"
fi
# Per-section verification: F2S_EDITABILITY_FILES="sections/a.liquid snippets/b.liquid" gates
# exactly those files (the verifier's step 6 for ONE section); the repo-wide run stays the GATE 8 door.
if [ -n "${F2S_EDITABILITY_FILES:-}" ]; then
  SECTIONS=$(printf '%s\n' $F2S_EDITABILITY_FILES | grep '^sections/' || true)
  ONLY_SNIPPETS=$(printf '%s\n' $F2S_EDITABILITY_FILES | grep '^snippets/' || true)
  [ -z "$SECTIONS" ] && [ -n "$ONLY_SNIPPETS" ] && F2S_ALLOW_EMPTY=1
fi
if [ -z "$SECTIONS" ]; then
  if [ "${F2S_ALLOW_EMPTY:-0}" = "1" ]; then
    echo "RESULT: N/A (no f2s_ sections; explicitly waived via F2S_ALLOW_EMPTY=1)"; exit 0
  fi
  echo "RESULT: FAIL (no f2s_ sections found — a build-phase repo must have sections; pre-build repos set F2S_ALLOW_EMPTY=1)"
  exit 1
fi

echo "================ f2s editability ================"
for f in $SECTIONS; do
  base=$(basename "$f")
  echo "• $base"

  # --- schema present + valid JSON, run the structural checks in one python pass -----------------
  # python emits RED/OK/WARN-prefixed lines; route them through the shell helpers so RED sets exit code.
  pyout=$("$PY" - "$f" <<'PYEOF'
import sys, re, json
f = sys.argv[1]
src = open(f, encoding='utf-8', errors='replace').read()
m = re.search(r'{%-?\s*schema\s*-?%}(.*?){%-?\s*endschema\s*-?%}', src, re.S)
if not m:
    print("RED no {% schema %} block — section is not Theme-Editor configurable"); sys.exit(0)
try:
    schema = json.loads(m.group(1))
except Exception as e:
    print(f"RED {{% schema %}} is invalid JSON: {e}"); sys.exit(0)

# body = everything except the schema block (where liquid references live)
body = src[:m.start()] + src[m.end():]

# 1. content blocks should emit block.shopify_attributes (WARN, not hard — singleton CONFIG blocks
#    like Impulse's `logo`, or @app blocks, legitimately don't render a selectable root element).
loops = re.search(r'for\s+\w+\s+in\s+section\.blocks', body)
if loops:
    if 'shopify_attributes' in body:
        print("OK blocks emit shopify_attributes")
    else:
        btypes = [b.get('type') for b in schema.get('blocks',[]) or []]
        print(f"WARN iterates section.blocks (types: {btypes or 'none'}) without {{{{ block.shopify_attributes }}}} — "
              "REQUIRED if a block renders selectable/reorderable content; fine if these are singleton CONFIG "
              "blocks (e.g. logo) or @app blocks. Confirm which.")

# 2. presets (WARN, not hard: header/footer & group-pinned sections legitimately omit them)
if schema.get('presets'): print("OK has presets")
else: print("WARN no \"presets\" — won't appear in Add-section (fine for header/footer/group sections; needed for content sections)")

# 3. editable text settings need a default (a blank text renders blank on a fresh install).
#    url is SOFT: a blank link still renders the button; merchants often set links themselves.
TEXTY = {'text','textarea','richtext','inline_richtext','html'}
def walk(settings, types):
    miss=[]
    for s in settings or []:
        if not isinstance(s,dict): continue
        if s.get('type') in types and s.get('id') and 'default' not in s:
            miss.append(s['id'])
    return miss
def collect(types):
    out = walk(schema.get('settings'), types)
    for b in schema.get('blocks',[]) or []:
        out += [f"block:{b.get('type')}.{i}" for i in walk(b.get('settings'), types)]
    return out
miss = collect(TEXTY)
if miss: print("RED text settings missing a Figma default (renders blank on fresh install): " + ", ".join(miss))
else: print("OK editable text settings have defaults")
urlmiss = collect({'url'})
if urlmiss: print("WARN url settings without a default (ok if merchant-set; add one if the design implies a destination): " + ", ".join(urlmiss))

# 4. orphan settings (declared id never referenced as settings.<id> in body) — SOFT
ids=set()
for s in schema.get('settings',[]) or []:
    if isinstance(s,dict) and s.get('id'): ids.add(s['id'])
orphans=[i for i in ids if not re.search(r'settings\.'+re.escape(i)+r'\b', body)]
if orphans: print("WARN settings declared but not referenced in this file (check snippets): " + ", ".join(sorted(orphans)))
PYEOF
)
  # route python verdict lines through the shell helpers for consistent formatting
  echo "$pyout" | while IFS= read -r line; do
    case "$line" in
      RED*)  printf '  🔴 %s\n' "${line#RED }" ;;
      WARN*) printf '  ⚠️  %s\n' "${line#WARN }" ;;
      OK*)   printf '  ✅ %s\n' "${line#OK }" ;;
      *)     [ -n "$line" ] && printf '     %s\n' "$line" ;;
    esac
  done
  # the while-subshell can't set fail in POSIX sh; detect RED separately for the exit code
  if printf '%s\n' "$pyout" | grep -q '^RED '; then fail=1; fi

  # --- SOFT heuristic: user-facing copy hardcoded in markup ---------------------------------------
  # text between > and < that is 2+ alpha words and not a liquid output/tag/comment/svg/style.
  hard=$(awk 'BEGIN{inschema=0}
    /{%-?[ ]*schema/{inschema=1} /endschema/{inschema=0; next}
    inschema{next}
    /{%[ ]*comment/{inc=1} /endcomment/{inc=0; next} inc{next}
    /<(script|style|svg)/{ins=1} /<\/(script|style|svg)/{ins=0} ins{next}
    {
      line=$0
      while (match(line, />[^<>{}]*</)) {
        seg=substr(line, RSTART+1, RLENGTH-2)
        gsub(/^[ \t]+|[ \t]+$/,"",seg)
        if (seg ~ /[A-Za-z][A-Za-z][A-Za-z]/ && seg ~ /[A-Za-z]+[ ][A-Za-z]+/ && seg !~ /{{|{%/)
          print seg
        line=substr(line, RSTART+RLENGTH)
      }
    }' "$f" | head -6)
  if [ -n "$hard" ]; then
    warn "possible hardcoded copy (wire to a setting/metafield/locale, or confirm it's structural):"
    printf '       %s\n' "$hard" | sed 's/^ *//' | sed 's/^/       • /'
  fi
done

# --- SNIPPETS: shared components, previously invisible to this gate -------------------------------
# This loop scanned sections only. On an earlier build that meant every hardcoded-copy violation and the
# worst variant-resolution bug lived in snippets/ — cart_drawer.liquid shipped an uneditable
# "Shipping protection $2.99" (a literal price, wrong currency, never charged) and
# product_card.liquid displayed product.price while adding a different variant to the cart.
# Both would have been caught by heuristics this script already owns; it was just looking
# in one directory. Snippets have no {% schema %}, so run only the checks that apply.
SNIPPETS=$(find snippets -name 'f2s_*.liquid' 2>/dev/null | sort)
[ -n "${F2S_EDITABILITY_FILES:-}" ] && SNIPPETS="${ONLY_SNIPPETS:-}"
if [ -n "$SNIPPETS" ]; then
  echo "--------------------------------------------------------"
  echo "shared snippets (no schema of their own — copy + data-source checks only)"
  for f in $SNIPPETS; do
    base=$(basename "$f")
    snip_msgs=""

    # 1. HARD — money/price rendered from the product rather than a resolved variant.
    #    On a multi-variant product product.price is the LOWEST variant price, so the card
    #    can advertise one price and add another to the cart.
    if grep -q 'product\.price\|product\.compare_at_price' "$f" 2>/dev/null; then
      if grep -q 'selected_or_first_available_variant\|current_variant' "$f" 2>/dev/null; then
        snip_msgs="${snip_msgs}RED ${base}: resolves a variant but still prints product.price/compare_at_price — print the resolved variant's price or the cart will disagree with the card\n"
      else
        snip_msgs="${snip_msgs}RED ${base}: prints product.price/compare_at_price with no variant resolution — wrong price on every multi-variant product\n"
      fi
    fi
    if grep -q 'product\.featured_image' "$f" 2>/dev/null && grep -q 'selected_or_first_available_variant\|current_variant' "$f" 2>/dev/null; then
      snip_msgs="${snip_msgs}WARN ${base}: resolves a variant but renders product.featured_image — card image may not match the variant\n"
    fi

    # 2. HARD — a literal currency amount in markup is never merchant-editable and ignores
    #    the shop's currency. Distinct from ordinary copy: it is a commercial claim.
    if grep -Eq '>[^<{]*[$£€][0-9]' "$f" 2>/dev/null; then
      snip_msgs="${snip_msgs}RED ${base}: hardcoded currency amount in markup — must come from a setting/metafield/money filter\n"
    fi

    if [ -n "$snip_msgs" ]; then
      echo "• $base"
      printf '%b' "$snip_msgs" | while IFS= read -r line; do
        case "$line" in
          RED*)  printf '  🔴 %s\n' "${line#RED }" ;;
          WARN*) printf '  ⚠️  %s\n' "${line#WARN }" ;;
        esac
      done
      printf '%b' "$snip_msgs" | grep -q '^RED ' && fail=1
    fi

    # 3. SOFT — same hardcoded-copy heuristic the sections loop uses.
    hard=$(awk '/{%[ ]*comment/{inc=1} /endcomment/{inc=0; next} inc{next}
      /<(script|style|svg)/{ins=1} /<\/(script|style|svg)/{ins=0} ins{next}
      {
        line=$0
        while (match(line, />[^<>{}]*</)) {
          seg=substr(line, RSTART+1, RLENGTH-2)
          gsub(/^[ \t]+|[ \t]+$/,"",seg)
          if (seg ~ /[A-Za-z][A-Za-z][A-Za-z]/ && seg ~ /[A-Za-z]+[ ][A-Za-z]+/ && seg !~ /{{|{%/)
            print seg
          line=substr(line, RSTART+RLENGTH)
        }
      }' "$f" | head -4)
    if [ -n "$hard" ]; then
      [ -z "$snip_msgs" ] && echo "• $base"
      warn "possible hardcoded copy in a SHARED snippet (affects every consumer):"
      printf '       %s\n' "$hard" | sed 's/^ *//' | sed 's/^/       • /'
    fi
  done
fi

# --- SOFT: ship-with-defaults present ------------------------------------------------------------
echo "--------------------------------------------------------"
if [ -z "${F2S_EDITABILITY_FILES:-}" ] && find templates -name '*.json' 2>/dev/null | grep -q . ; then
  empties=$(grep -rl '"settings"[[:space:]]*:[[:space:]]*{[[:space:]]*}' templates/*.json 2>/dev/null | wc -l | tr -d ' ')
  [ "$empties" -eq 0 ] && ok "template JSON sections carry settings (ship-with-defaults)" || warn "$empties template JSON file(s) have sections with empty settings {} — populate Figma defaults so a fresh install renders"
fi
[ -f config/settings_data.json ] && ok "config/settings_data.json present" || warn "no config/settings_data.json — fresh install may render blank"


# --- HARD: metafield decision gate (v2 item 22) ---------------------------------------------------
# A f2s section used on a DEFAULT product template that has text settings but zero
# product.metafields references = per-product copy in shared settings. RED unless a recorded
# decision waives it (grep decisions/ for the section name + "global").
if [ -z "${F2S_EDITABILITY_FILES:-}" ] && ls templates/product*.json >/dev/null 2>&1; then
  PROD_SECTIONS=$(grep -ho '"type"[[:space:]]*:[[:space:]]*"f2s_[a-z0-9_]*"' templates/product*.json 2>/dev/null | sed 's/.*"f2s_/f2s_/;s/"//' | sort -u)
  for sec in $PROD_SECTIONS; do
    f="sections/${sec}.liquid"; [ -f "$f" ] || continue
    HAS_TEXT=$(grep -Ec '"type"[[:space:]]*:[[:space:]]*"(text|textarea|richtext|inline_richtext|html)"' "$f")
    HAS_MF=$(grep -c 'product\.metafields' "$f")
    if [ "$HAS_TEXT" -gt 0 ] && [ "$HAS_MF" -eq 0 ]; then
      if grep -rqi "${sec}.*global\|global.*${sec}" .claude/knowledge/decisions/ 2>/dev/null; then
        warn "$sec: text settings, no metafields — waived by recorded decision (verify it's genuinely global copy)"
      else
        red "$sec: on a default product template with text settings but NO product.metafields — per-product copy will be shared across all products. Wire metafields or record a decisions/ entry stating this copy is genuinely global."
      fi
    fi
  done
fi

echo "--------------------------------------------------------"
echo "NOTE: the script proves STRUCTURE. It cannot prove the right DATA SOURCE —"
echo "  on a DEFAULT template (one product.json for all products), per-product copy must be a"
echo "  product.metafield, NOT a shared section setting. Confirm that by reading the liquid, and"
echo "  open the Theme Editor once to confirm every node appears and repeatable groups reorder."
echo "--------------------------------------------------------"
if [ "$fail" -eq 0 ]; then echo "RESULT: PASS (structural editability gates clean)"; exit 0
else echo "RESULT: FAIL (fix 🔴 before commit/PR)"; exit 1; fi
