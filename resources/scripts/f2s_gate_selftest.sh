#!/usr/bin/env sh
# f2s_gate_selftest.sh — prove the gates themselves work before trusting them (v2 item 2).
# Runs codehealth + editability against known-good and known-bad fixture trees and asserts:
#   known-good  -> exit 0        known-bad -> exit 1        empty tree -> exit 1 (no vacuous pass)
# Any assertion failure = the GATE is broken -> exit 1 and bootstrap/preflight must BLOCK.
# Usage: sh f2s_gate_selftest.sh [skill_root]   (default: dir containing this script/../..)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL_ROOT="${1:-$HERE/../..}"
SKILL_ROOT=$(cd "$SKILL_ROOT" 2>/dev/null && pwd || echo "$SKILL_ROOT")
SCRIPTS="$SKILL_ROOT/resources/scripts"
FIX="$SKILL_ROOT/tests/fixtures"
# Installed layout (.claude/scripts/ in a target repo): gates live in $HERE, fixtures in $HERE/tests/fixtures
[ -d "$SCRIPTS" ] || SCRIPTS="$HERE"
# Installed layout takes precedence when no skill_root arg is given: a target repo may ship its OWN
# tests/fixtures (an agency boilerplate theme may), and testing the gates against a foreign fixture tree
# produced a false FAIL on one rebuild (decision 0023). Fixtures shipped beside the
# installed gates are the ones these gates were written for.
[ -n "${1:-}" ] || [ ! -d "$HERE/tests/fixtures/known-good" ] || FIX="$HERE/tests/fixtures"
[ -d "$FIX" ] || FIX="$HERE/tests/fixtures"
[ -d "$FIX/known-good" ] || { echo "SELFTEST FAIL: fixtures missing at $FIX"; exit 1; }

fails=0
check() { # check <desc> <expected_exit> <actual_exit>
  if [ "$2" -eq "$3" ]; then echo "  ✅ $1 (exit $3)"; else echo "  🔴 $1 — expected exit $2, got $3"; fails=$((fails+1)); fi
}

# theme-check may be unavailable in dev envs; the selftest asserts the OTHER gates' behavior.
# codehealth will RED on missing theme checker in both trees, so we test it in "no-themecheck" tolerant
# mode: known-good must not fail on anything EXCEPT the theme-checker line; we detect that by grepping.
run_codehealth() { ( cd "$1" && sh "$SCRIPTS/f2s_codehealth.sh" . > /tmp/cs_st_ch.log 2>&1 ); echo $?; }
run_editability() { ( cd "$1" && F2S_ALLOW_EMPTY="${2:-0}" sh "$SCRIPTS/f2s_editability.sh" . > /tmp/cs_st_ed.log 2>&1 ); echo $?; }

echo "================ gate self-test ================"

# --- editability: the unambiguous assertions --------------------------------------------------
e=$(run_editability "$FIX/known-good"); check "editability known-good passes" 0 "$e"
[ "$e" -ne 0 ] && sed 's/^/       /' /tmp/cs_st_ed.log | head -20
e=$(run_editability "$FIX/known-bad");  check "editability known-bad fails" 1 "$e"
EMPTY=$(mktemp -d); mkdir -p "$EMPTY/sections"
e=$(run_editability "$EMPTY");          check "editability empty tree fails (no vacuous pass)" 1 "$e"
e=$(run_editability "$EMPTY" 1);        check "editability empty tree passes only with explicit waiver" 0 "$e"
rm -rf "$EMPTY"

# --- codehealth: assert known-bad fails; known-good may only fail on the theme-checker line ----
c=$(run_codehealth "$FIX/known-bad");   check "codehealth known-bad fails" 1 "$c"
c=$(run_codehealth "$FIX/known-good")
if [ "$c" -eq 0 ]; then
  echo "  ✅ codehealth known-good passes (exit 0)"
else
  NONCHECKER_REDS=$(grep -c '^🔴' /tmp/cs_st_ch.log)
  CHECKER_REDS=$(grep -c '^🔴.*theme.check' /tmp/cs_st_ch.log || true)
  if [ "$NONCHECKER_REDS" -eq "${CHECKER_REDS:-0}" ]; then
    echo "  ⚠️  theme-check gem not installed, so the codehealth gate skipped its Liquid lint step (tolerated here; install theme-check for the full run)"
  else
    echo "  🔴 codehealth known-good fails on non-checker gates:"; grep '^🔴' /tmp/cs_st_ch.log | sed 's/^/       /'
    fails=$((fails+1))
  fi
fi

# --- upload validator (v4.1, decision 0057): Shopify ADMIN rules theme-check misses ---------
# known-good must pass; known-good-upload holds the LEGAL shapes that look suspicious (pipes inside
# string literals, nested comments, comments that mention {% doc %}/{% schema %}, 3-value ranges,
# /collections/all url default, t: keys, {% doc %} examples) and must pass with zero false positives;
# known-bad-upload must fail AND every rule must fire — a rule that never fires is documentation.
run_upload() { ( cd "$1" && sh "$SCRIPTS/f2s_upload_validator.sh" . > /tmp/cs_st_up.log 2>&1 ); echo $?; }
if [ -x "$SCRIPTS/f2s_upload_validator.sh" ]; then
  u=$(run_upload "$FIX/known-good");        check "upload validator known-good passes" 0 "$u"
  if [ -d "$FIX/known-good-upload" ]; then
    u=$(run_upload "$FIX/known-good-upload"); check "upload validator known-good-upload passes (no false positives on legal shapes)" 0 "$u"
    [ "$u" -ne 0 ] && grep '🔴' /tmp/cs_st_up.log | sed 's/^/       /'
  else echo "  🔴 fixtures/known-good-upload missing at $FIX"; fails=$((fails+1)); fi
  if [ -d "$FIX/known-bad-upload" ]; then
    u=$(run_upload "$FIX/known-bad-upload");  check "upload validator known-bad-upload fails" 1 "$u"
    for r in U-a U-b U-c U-d U-e U-f U-g; do
      if grep -q "🔴.*\[$r\]" /tmp/cs_st_up.log; then echo "  ✅ upload rule $r fires on known-bad-upload"
      else echo "  🔴 upload rule $r never fired on known-bad-upload — the rule is dead"; fails=$((fails+1)); fi
    done
    grep -q 'RESULT: FAIL' /tmp/cs_st_up.log && [ "$u" -eq 0 ] && { echo "  🔴 upload validator prints RESULT: FAIL but exits 0"; fails=$((fails+1)); }
  else echo "  🔴 fixtures/known-bad-upload missing at $FIX"; fails=$((fails+1)); fi
else
  echo "  🔴 f2s_upload_validator.sh missing beside the gates — v4.1 install incomplete"; fails=$((fails+1))
fi

# --- RESULT/exit consistency: the exact bug the forensic audit found ---------------------------
# ORDER IS LOAD-BEARING: run known-bad FIRST, then read ITS log. Reading the log before this run
# reads the PREVIOUS run's output (the empty-tree-with-waiver case, which passes), so ED_SAYS_FAIL
# is always 0 and this assertion can never fire — v3 shipped exactly that, meaning the check written
# to catch "prints FAIL but exits 0" was itself a vacuous pass.
e=$(run_editability "$FIX/known-bad")
grep -q 'RESULT: FAIL' /tmp/cs_st_ed.log && ED_SAYS_FAIL=1 || ED_SAYS_FAIL=0
if [ "$ED_SAYS_FAIL" -eq 1 ] && [ "$e" -eq 0 ]; then
  echo "  🔴 editability prints RESULT: FAIL but exits 0 — the exit-0 bug is live"; fails=$((fails+1))
else
  echo "  ✅ RESULT text and exit code agree"
fi

echo "------------------------------------------------"
if [ "$fails" -eq 0 ]; then echo "SELFTEST: PASS — gates are trustworthy"; exit 0
else echo "SELFTEST: FAIL ($fails) — GATES ARE BROKEN; fix gates before any build. Do NOT proceed."; exit 1; fi
