#!/usr/bin/env sh
# f2s_preflight.sh — plan-mode readiness gate as a SCRIPT, not a doc (v2 items 9/10).
# Emits GO or BLOCKED to stdout AND writes .claude/knowledge/plans/preflight.md.
# Autonomous runs MUST refuse to start on BLOCKED. Waivers = a decisions/*.md entry naming the check.
# Usage: sh f2s_preflight.sh [theme_root]
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1
KB=".claude/knowledge"; OUT="$KB/plans/preflight.md"
SCRIPTS="$(dirname "$0")"
mkdir -p "$KB/plans"
blocked=0; report=""
line() { report="$report\n$1"; echo "$1"; }
blk() { line "🔴 BLOCKED — $1"; blocked=1; }
ok()  { line "✅ $1"; }
wrn() { line "⚠️  $1"; }

line "# Preflight — $(date +%F)"
line ""

# 0a. PERMISSIONS (v4) — first, because everything downstream is unattended or it is not a run.
#     one build ran end to end with no settings.json: every script, commit and push prompted,
#     and nobody knew until a human was already sitting there clicking.
if sh "$SCRIPTS/f2s_permcheck.sh" . >/tmp/cs_pf_perm.log 2>&1; then
  ok "permissions: the run can proceed unattended"
else
  blk "permissions NOT ready — the run would sit prompting. See /tmp/cs_pf_perm.log"
  sed 's/^/     /' /tmp/cs_pf_perm.log | grep -E '🔴|Add rules' | head -8
fi

# 0b. EXISTING-THEME LEDGER (v4) — what dies, what lives, what collides.
#     one rebuild carried 23 live sections from a previous build; the run added 14 more and nothing
#     recorded which of the 23 were meant to go. 13 of the 14 ended up wired to no template at all.
INV="$KB/architecture/inventory.json"
if [ ! -f "$INV" ]; then
  blk "no inventory — run 'sh .claude/scripts/f2s_inventory.sh' before extraction"
else
  UNCLASS=$(python3 -c "
import json;d=json.load(open('$INV'))
print(sum(1 for r in d.get('rows',[]) if r.get('classification')=='UNCLASSIFIED'))" 2>/dev/null || echo "?")
  if [ "${UNCLASS:-?}" = "?" ]; then blk "inventory.json unreadable"
  elif [ "$UNCLASS" -gt 0 ]; then
    blk "$UNCLASS inventory row(s) still UNCLASSIFIED — each must be RETIRE, KEEP or CONFLICT before building. Edit architecture/inventory.md."
  else
    RET=$(python3 -c "
import json;d=json.load(open('$INV'))
print(sum(1 for r in d.get('rows',[]) if r.get('classification')=='RETIRE'))" 2>/dev/null || echo 0)
    ok "inventory classified ($RET marked RETIRE — page integration will assert they are gone)"
  fi
fi

# 0c. OPEN RESEARCH GAPS (v4) — a returned string is not a record.
#     one build: agents dutifully returned "RE-RESEARCH: <node>"; grep found the phrase exactly once in
#     the whole repo — in the instruction telling them to say it. Every gap was spoken and lost.
if sh "$SCRIPTS/f2s_research_gap.sh" >/tmp/cs_pf_rg.log 2>&1; then
  ok "$(head -1 /tmp/cs_pf_rg.log)"
else
  blk "open research gaps — re-extract those nodes before building against guesses"
  sed 's/^/     /' /tmp/cs_pf_rg.log | head -6
fi

# 0d. ORPHANED GATE SCRIPTS (v4) — a script no door runs is documentation.
#     one build: f2s_deferrals.sh — the harvester that surfaces deliberate deviations — was
#     invoked by nothing at all, while the deviations it would have surfaced shipped. dupecheck
#     likewise, while a duplicate section went out.
if [ -d .claude/scripts ]; then
  ORPHANS=""
  for s in .claude/scripts/f2s_*.sh .claude/scripts/f2s_*.py; do
    [ -e "$s" ] || continue
    base=$(basename "$s")
    # invoked by another script, by the command, or explicitly declared manual?
    if grep -rqF "$base" .claude/scripts/ --include="*.sh" --exclude="$base" 2>/dev/null; then continue; fi
    if grep -rqF "$base" .claude/commands/ .claude/agents/ 2>/dev/null; then continue; fi
    if grep -qF "$base" .claude/scripts/MANUAL_SCRIPTS 2>/dev/null; then continue; fi
    ORPHANS="$ORPHANS $base"
  done
  if [ -n "$ORPHANS" ]; then
    wrn "script(s) invoked by no gate, command or agent:$ORPHANS"
    wrn "  wire each into a gate, or list it in .claude/scripts/MANUAL_SCRIPTS with a reason"
  else
    ok "no orphaned gate scripts"
  fi
fi

# 0e. SHOPIFY ADMIN UPLOAD RULES (v4.1, decision 0057) — advisory here, a hard door in functional.sh,
#     the pre-commit hook (D5b) and GATE 8. One rebuild passed every gate and the admin rejected
#     22 sections on upload; at preflight most of the theme is still the boilerplate, so this only warns.
if [ -x "$SCRIPTS/f2s_upload_validator.sh" ]; then
  if sh "$SCRIPTS/f2s_upload_validator.sh" . >/tmp/cs_pf_upload.log 2>&1; then
    ok "upload validator: no Shopify admin rejections in the current tree"
  else
    wrn "upload validator: the admin would reject file(s) already in the tree — fix before the first push (hard fail at commit/GATE 8):"
    grep '🔴' /tmp/cs_pf_upload.log | head -6 | sed 's/^/     /'
  fi
else
  wrn "f2s_upload_validator.sh not installed — v4.1 gate missing; re-run bootstrap"
fi

# 0. measurement capability — decides VERIFIED vs UNVERIFIED for the entire run.
#    Earlier-build lesson: this environment question was answered with a waiver (decision 0007) and the
#    run passed everything while measuring nothing. There is no waiver here: fail = the run may
#    build but may never claim PASS, and the flag file below is how every later step knows.
if sh "$SCRIPTS/f2s_env_check.sh" >/tmp/cs_pf_env.log 2>&1; then
  ok "environment can measure — parity claims permitted"
  rm -f "$KB/plans/UNVERIFIED.flag"
else
  wrn "environment CANNOT measure — run is UNVERIFIED (see /tmp/cs_pf_env.log for the exact fix)"
  wrn "building is allowed; PASS/parity claims are NOT; the PR must open with 'parity NOT verified'"
  date +%F > "$KB/plans/UNVERIFIED.flag"
fi

# 1. gate self-test: broken gates block EVERYTHING (the exit-0 lesson)
if sh "$SCRIPTS/f2s_gate_selftest.sh" >/tmp/cs_pf_st.log 2>&1; then ok "gate self-test: gates are trustworthy"
else blk "gate self-test FAILED — gates are broken; nothing they bless can be trusted. See /tmp/cs_pf_st.log"; fi

# 2. manifest populated with complete entries
MAN="$KB/extraction/figma/manifest.json"
if [ ! -f "$MAN" ]; then blk "no Figma manifest — extraction has not run"
else
  N=$(python3 -c "import json;print(len(json.load(open('$MAN')).get('entries',{})))" 2>/dev/null || echo 0)
  if [ "$N" -eq 0 ]; then blk "manifest has ZERO entries (the empty-shell failure seen on one audit) — run extraction per node"
  else
    ok "manifest has $N entries"
    INCOMPLETE=0
    for key in $(python3 -c "import json;print('\n'.join(json.load(open('$MAN'))['entries'].keys()))"); do
      sh "$SCRIPTS/f2s_cache_check.sh" "$key" "$KB" >/dev/null 2>&1 || { INCOMPLETE=$((INCOMPLETE+1)); wrn "cache incomplete: $key"; }
    done
    [ "$INCOMPLETE" -gt 0 ] && blk "$INCOMPLETE node(s) have incomplete caches — spec.json will be refused for them"
  fi
fi

# 2b. DESIGN COVERAGE (v4) — did extraction pull everything the design contains?
#     Every other check here asks whether what we have is correct. This is the only one that asks
#     whether anything is MISSING. One build's product page had its own frames, extraction pulled only
#     the home page's, and no gate compared the lists — the client found it.
if F2S_COVERAGE_PHASE=extraction sh "$SCRIPTS/f2s_coverage.sh" . >/tmp/cs_pf_cov.log 2>&1; then
  ok "design coverage: every designed frame has a spec (assembly half re-checked at GATE 8)"
else
  blk "design coverage FAILED — frames in the design have no spec, or built sections reach no template"
  grep -E '^🔴' /tmp/cs_pf_cov.log | head -6 | sed 's/^/     /'
fi

# 3. breakpoint coverage: every planned page needs BOTH designed breakpoints in the manifest
#    (one design file shipped with no desktop homepage frame; that is a BLOCKED fact, not a footnote)
if [ -f "$MAN" ]; then
  MISS_BP=$(python3 -c "
import json
m=json.load(open('$MAN'))
bad=[k for k,e in m.get('entries',{}).items() if not (e.get('breakpoints') and 'desktop' in e['breakpoints'] and ('mobile' in e['breakpoints'] or e.get('mobile_waiver')))]
print(len(bad)); [print('  '+b) for b in bad]" 2>/dev/null | head -8)
  FIRST=$(printf '%s' "$MISS_BP" | head -1)
  [ "${FIRST:-0}" != "0" ] && blk "$FIRST node(s) missing a designed breakpoint (desktop or mobile). Get the frame designed, or record a decisions/ waiver naming the node and the single-breakpoint plan."
fi

# 4. Figma structural audit result present and passing (run f2s_figma_audit.js via the
#    Figma connector/MCP; it writes design/figma_audit.json)
FA="$KB/design/figma_audit.json"
if [ ! -f "$FA" ]; then blk "no Figma structural audit — run resources/scripts/f2s_figma_audit.js against the file and save the JSON to $FA"
else
  VERDICT=$(python3 -c "import json;print(json.load(open('$FA')).get('verdict','?'))" 2>/dev/null)
  case "$VERDICT" in
    GO) ok "Figma structural audit: GO" ;;
    BLOCKED)
      # Waiver channel (header rule: a decisions/*.md entry naming the check). Scope, never method:
      # the operator accepts literal values where the file binds no token; rendering/measuring is unchanged.
      WV=$(grep -l -E '^waives:[[:space:]]*figma_audit' "$KB"/decisions/*.md 2>/dev/null | head -1)
      if [ -n "$WV" ]; then ok "Figma structural audit: BLOCKED — WAIVED by $(basename "$WV") (operator scope decision at plan approval; fix-list stays in $FA for the designer)"
      else blk "Figma structural audit: BLOCKED — send the designer fix-list in $FA before building against this file, or record a decisions/ entry with 'waives: figma_audit' after the operator approves the plan"; fi ;;
    *) blk "Figma audit verdict unreadable in $FA" ;;
  esac
fi

# 5. fonts: a typography decision must exist (brand font available OR documented near-match)
if grep -rqi "font" "$KB/design/typography.md" 2>/dev/null; then ok "typography decision on file"
else blk "no design/typography.md — verification under an undecided font is invalid"; fi

# 6. render path
if command -v shopify >/dev/null 2>&1; then ok "shopify CLI present (theme dev render path)"
else wrn "no shopify CLI — static preview generator will be the render path; ensure it passes its self-check"; fi

# 7. tooling
for t in python3 git; do command -v $t >/dev/null 2>&1 && ok "$t present" || blk "$t missing"; done
command -v gh >/dev/null 2>&1 && ok "gh present" || wrn "gh missing — PR creation will need manual auth"
# decision 0025: the repo-local Shopify CLI (`npm install`, ./node_modules/.bin/shopify) is the preferred
# linter — the gem is frozen at 1.15.0 and false-flags Dawn 15. Any one of the three satisfies codehealth.
if [ -x ./node_modules/.bin/shopify ]; then ok "theme check: repo-local Shopify CLI present (preferred, decision 0025)"
elif command -v shopify >/dev/null 2>&1; then ok "theme check: global Shopify CLI present (repo-local preferred — npm install)"
elif command -v theme-check >/dev/null 2>&1; then wrn "theme check: only the theme-check gem (1.15.0) — false UnknownFilter errors on Dawn 15; npm install the repo CLI (decision 0025)"
else blk "no theme checker — npm install (repo Shopify CLI, decision 0025) or 'gem install theme-check'; codehealth hard gate depends on it"; fi

# 8. hooks installed
HP=$(git config core.hooksPath || true)
if [ -n "$HP" ] && [ -x "$HP/pre-commit" ]; then ok "pre-commit hook installed ($HP)"
elif [ -x .git/hooks/pre-commit ]; then ok "pre-commit hook installed (.git/hooks)"
else blk "hooks not armed — the repo is in MAINTAINER mode (normal after a handoff). An agent run needs the doors: sh .claude/scripts/f2s_hooks_mode.sh agent"; fi

# 9. placeholder check (v2 item 21)
if grep -rq '<command' "$KB/conventions/" 2>/dev/null || grep -q '_e.g._' "$KB/architecture/f2s_registry.md" 2>/dev/null; then
  wrn "template placeholders survive in conventions/registry — localize before first build commit (bootstrap enforces at commit time)"
fi

line ""
if [ "$blocked" -eq 0 ]; then line "## VERDICT: GO"; else line "## VERDICT: BLOCKED — resolve 🔴 items or record explicit decisions/ waivers"; fi
printf '%b\n' "$report" > "$OUT"
echo ""; echo "written: $OUT"
exit $blocked
