#!/usr/bin/env sh
# f2s_codehealth.sh — print the objective code-health signal table for a theme.
# Turns the one-off "I ran the numbers" audit into a repeatable, gateable check.
# Usage: sh resources/scripts/f2s_codehealth.sh [theme_root]   (default: cwd)
# Exit code: 0 if all hard gates pass, 1 if any hard gate fails. Soft signals never fail the build.
#
# Hard gates (🔴): theme check ran & clean, 0 in-tree backups, 0 position-named files,
#                  !important within budget, every !important justified with an inline reason.
# Soft signals: section/snippet counts, liquid/css volume, bundled-image count — reported for review.

set -u
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "cannot cd to $ROOT"; exit 1; }

# ---- tunable budgets (raise/lower per project, but never silently) -------------------------------
IMPORTANT_BUDGET="${F2S_IMPORTANT_BUDGET:-40}"   # total !important across f2s CSS
BUNDLED_IMG_BUDGET="${F2S_BUNDLED_IMG_BUDGET:-15}" # raw png/jpg in assets/ (prefer CDN/picker)
# -------------------------------------------------------------------------------------------------

fail=0
red()  { printf '🔴 %s\n' "$1"; fail=1; }
ok()   { printf '✅ %s\n' "$1"; }
warn() { printf '⚠️  %s\n' "$1"; }

count_files() { find $1 -type f -name "$2" 2>/dev/null | wc -l | tr -d ' '; }

SECTIONS=$(find sections -name 'f2s_*.liquid' 2>/dev/null | wc -l | tr -d ' ')
SNIPPETS=$(find snippets -name 'f2s_*.liquid' 2>/dev/null | wc -l | tr -d ' ')
LIQUID_LINES=$(find sections snippets -name 'f2s_*.liquid' 2>/dev/null -exec cat {} + | wc -l | tr -d ' ')
CSS_LINES=$(find assets -name 'f2s_*.css' 2>/dev/null -exec cat {} + | wc -l | tr -d ' ')
# !important lives in TWO places and this gate used to see only one of them. On an earlier build it
# reported "11 (budget 40)" — a comfortable pass — while the true count was 75, because 64
# sat inside {% stylesheet %} blocks in the section files. A budget that measures a sixth of
# the thing it governs is not a budget. Count both scopes.
IMPORTANT_CSS=$(grep -rho '!important' assets/f2s_*.css 2>/dev/null | wc -l | tr -d ' ')
IMPORTANT_INLINE=$(grep -rho '!important' sections/f2s_*.liquid snippets/f2s_*.liquid 2>/dev/null | wc -l | tr -d ' ')
IMPORTANT=$((IMPORTANT_CSS + IMPORTANT_INLINE))
BUNDLED_IMG=$( { find assets -name 'f2s_*.png' -o -name 'f2s_*.jpg' -o -name 'f2s_*.jpeg' 2>/dev/null; } | wc -l | tr -d ' ')
BACKUPS=$( { find . -name '*.legacy' -o -name '*.bak' -o -name '*.old' -o -name '*.orig' 2>/dev/null; } | grep -v '/.git/' | grep -v 'tests/fixtures/' | wc -l | tr -d ' ')
# position/sequence-named files (feature_1, section_2, block3, etc.) — name by PURPOSE not position
MISNAMED=$(find sections snippets assets -type f 2>/dev/null | grep -Ei 'f2s_[a-z_]*([_-]?[0-9]+)\.(liquid|css|js)$' | wc -l | tr -d ' ')
# bare / generic section filenames — the name must say what the section DOES (f2s_home_hero),
# not be the bare prefix or a placeholder word (f2s_section/_block/_content).
BARENAME=$(find sections -name 'f2s_*.liquid' 2>/dev/null | sed -E 's#.*/##' \
  | grep -Ei '^f2s_?(section|block|content|component|item|element|wrapper|new|temp|tmp|main|default)?\.liquid$' | wc -l | tr -d ' ')
# merchant-facing schema "name" must be plain English with NO code prefix — a merchant should never see "f2s".
PREFIXED_NAME=$(grep -rEil '"name"[[:space:]]*:[[:space:]]*"[^"]*f2s' sections/f2s_*.liquid 2>/dev/null | wc -l | tr -d ' ')

echo "================ f2s code health ================"
printf '%-26s %s\n' "Signal" "Value"
printf '%-26s %s\n' "sections / snippets" "$SECTIONS / $SNIPPETS"
printf '%-26s %s\n' "liquid lines / css lines" "$LIQUID_LINES / $CSS_LINES"
printf '%-26s %s\n' "!important count" "$IMPORTANT (budget $IMPORTANT_BUDGET) [css $IMPORTANT_CSS + inline $IMPORTANT_INLINE]"
printf '%-26s %s\n' "bundled images" "$BUNDLED_IMG (budget $BUNDLED_IMG_BUDGET)"
printf '%-26s %s\n' "in-tree backups" "$BACKUPS"
printf '%-26s %s\n' "position-named files" "$MISNAMED"
printf '%-26s %s\n' "bare/generic names" "$BARENAME"
printf '%-26s %s\n' "schema names w/ prefix" "$PREFIXED_NAME"
echo "--------------------------------------------------------"

# ---- hard gates ---------------------------------------------------------------------------------
# 1. theme check ran AND clean.
# Prefer the standalone `theme-check` gem: no CLI auth, no environment, runs offline.
# Shopify CLI 3.x wrapped `theme check` and now demands `--environment` even with `--path .`
# (errors "Please provide a valid environment"), so the gem is the reliable gate.
# Decision 0025 (most recent rebuild, 2026-09): the repo-local Shopify CLI is preferred when present.
# The standalone gem is frozen at 1.15.0 and predates Dawn 15's `inline_asset_content` filter, so it
# reports ~370 false UnknownFilter errors on every Dawn 15 file. CLI 3.90 `theme check --path .` runs
# offline without --environment and understands current Liquid. Gem remains the fallback.
if [ -x ./node_modules/.bin/shopify ]; then
  if [ "${F2S_SKIP_THEMECHECK:-0}" = "1" ]; then
    ok "shopify theme check skipped — no theme files in this commit (knowledge/artifact-only; the hook sets this)"
  elif ./node_modules/.bin/shopify theme check --path . --fail-level error >/tmp/f2s_themecheck.log 2>&1; then
    ok "shopify theme check (repo CLI $(./node_modules/.bin/shopify version 2>/dev/null | tail -1)): no errors"
  else
    red "shopify theme check (repo CLI): errors — see /tmp/f2s_themecheck.log"
  fi
elif command -v theme-check >/dev/null 2>&1; then
  theme-check . >/tmp/f2s_themecheck.log 2>&1 && ok "theme-check: clean" || red "theme-check: offenses — see /tmp/f2s_themecheck.log"
elif command -v shopify >/dev/null 2>&1; then
  if shopify theme check --path . >/tmp/f2s_themecheck.log 2>&1; then
    ok "shopify theme check: clean"
  else
    red "shopify theme check could not run / offenses — see /tmp/f2s_themecheck.log"
    echo "    'Please provide a valid environment' is a CLI 3.x regression. Fix: install the standalone gem —"
    echo "    'gem install theme-check && theme-check .' (no auth/env needed). Or configure an env in shopify.theme.toml."
  fi
else
  red "no theme checker found — install the 'theme-check' gem (preferred) or Shopify CLI; linting is a required gate"
fi

# 2. no in-tree backups (git history is the backup)
[ "$BACKUPS" -eq 0 ] && ok "no in-tree backups" || red "$BACKUPS in-tree backup file(s) (.legacy/.bak/.old) — delete; git is the backup"

# 3. no position-named files
[ "$MISNAMED" -eq 0 ] && ok "no position-named files" || red "$MISNAMED file(s) named by position (feature_1, section_2) — rename by purpose"

# 3a. no bare/generic section filenames — the name must say what the section DOES
[ "$BARENAME" -eq 0 ] && ok "section filenames are descriptive" || red "$BARENAME bare/generic section name(s) (f2s_section/_block/_content) — rename f2s_<area>_<purpose> (e.g. f2s_home_hero)"

# 3b. merchant-facing schema "name" carries no code prefix
[ "$PREFIXED_NAME" -eq 0 ] && ok "schema names are merchant-readable (no prefix)" || red "$PREFIXED_NAME section(s) whose schema \"name\" shows 'f2s' — merchants must see plain English (e.g. \"Hero banner\"), not the code prefix"

# 4. !important budget + every one justified with an inline reason
if [ "$IMPORTANT" -le "$IMPORTANT_BUDGET" ]; then ok "!important within budget ($IMPORTANT/$IMPORTANT_BUDGET)"; else red "!important over budget ($IMPORTANT/$IMPORTANT_BUDGET) — scope CSS / raise specificity instead"; fi
# unjustified = an !important line with no nearby /* ... */ reason comment
UNJUST=$(grep -rn '!important' assets/f2s_*.css 2>/dev/null | grep -v '/\*' | wc -l | tr -d ' ')
[ "${IMPORTANT}" -eq 0 ] || { [ "$UNJUST" -eq 0 ] && ok "every !important has an inline reason" || warn "$UNJUST !important without an inline /* why */ reason — annotate or remove"; }

# 5. bundled-image soft cap (prefer image_picker + CDN; bundled only for brand-fixed decorative)
[ "$BUNDLED_IMG" -le "$BUNDLED_IMG_BUDGET" ] && ok "bundled images within budget" || warn "bundled images over soft budget ($BUNDLED_IMG/$BUNDLED_IMG_BUDGET) — prefer image_picker/CDN; document each bundled asset"


# 6. registry drift — every f2s_ file must have a registry row (spec v2 item 20)
REG=".claude/knowledge/architecture/f2s_registry.md"
# Under a git index the count is files git KNOWS (tracked or staged): a concurrent agent's untracked
# in-progress file has no registry row yet by definition and must not lock a sibling's commit door.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  CS_FILES=$(git ls-files --cached -- sections snippets assets scripts 2>/dev/null | grep -c '/f2s_' | tr -d ' ')
else
  CS_FILES=$(find sections snippets assets scripts -type f -name 'f2s_*' 2>/dev/null | wc -l | tr -d ' ')
fi
if [ -f "$REG" ]; then
  REG_ROWS=$(grep -c '^| *f2s_' "$REG" 2>/dev/null | tr -d ' ')
  [ "${REG_ROWS:-0}" -ge "$CS_FILES" ] && ok "registry rows cover f2s files ($REG_ROWS rows / $CS_FILES files)" \
    || red "registry drift: $CS_FILES f2s files but only ${REG_ROWS:-0} registry rows — update $REG in the same commit"
else
  [ "$CS_FILES" -eq 0 ] && warn "no registry yet (no f2s files either)" || red "no f2s_registry.md but $CS_FILES f2s files exist"
fi

# 7. required header fields in every f2s_ section/snippet (first 25 lines)
HDR_MISS=0
for f in $(find sections snippets -name 'f2s_*.liquid' 2>/dev/null); do
  head -25 "$f" | grep -q 'Purpose:' && head -25 "$f" | grep -q 'Spec:' && head -25 "$f" | grep -q 'Data:' \
    || { HDR_MISS=$((HDR_MISS+1)); [ "$HDR_MISS" -le 5 ] && echo "     missing header fields: $f"; }
done
[ "$HDR_MISS" -eq 0 ] && ok "all f2s liquid files carry Purpose/Spec/Data headers" \
  || red "$HDR_MISS file(s) missing required header fields (Purpose:/Spec:/Data: in first 25 lines)"

# 8. duplication signals (v4 — ADVISORY, but it now actually RUNS).
#    f2s_dupecheck.sh was invoked by nothing at all in v3: named in the verifier's rubric,
#    executed by no door, while a duplicate section shipped. A script no gate runs is documentation.
DUP="$(dirname "$0")/f2s_dupecheck.sh"
if [ -f "$DUP" ]; then
  if sh "$DUP" . >/tmp/f2s_dupecheck.log 2>&1; then
    ok "dupecheck: no duplication signals"
  else
    warn "dupecheck signals (advisory — the verifier must address them, they do not block):"
    grep -E '^(🔴|⚠️|  )' /tmp/f2s_dupecheck.log 2>/dev/null | head -6 | sed 's/^/     /'
  fi
fi

echo "--------------------------------------------------------"
if [ "$fail" -eq 0 ]; then echo "RESULT: PASS (hard gates clean)"; exit 0
else echo "RESULT: FAIL (fix 🔴 before commit/PR)"; exit 1; fi
