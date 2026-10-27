#!/usr/bin/env sh
# f2s_precommit.sh — the locked doors (v2 items 6/7/8). Installed by bootstrap as the
# repo's pre-commit hook (core.hooksPath or .git/hooks/pre-commit). NEVER bypass with --no-verify;
# bypasses are logged loudly by the prepare-commit-msg companion if configured.
#
# Blocks a commit when:
#   D0  it stages node_modules/ or other dependency/build artefacts   (v4 — unreviewable PRs)
#   D8  it carries more than one section's files                      (v4 — cross-agent sweep)
#   D1  it adds/modifies >1 NEW f2s section            (big-bang prevention)
#   D2  it adds NEW f2s files while on main            (branch-per-task)
#   D3  a staged section has no spec.json, or the spec's first commit does not PREDATE
#       the section's first commit (retrofit prevention; new files: spec must already be committed)
#   D4  a staged section claims done (registry row updated) without a committed verify artifact
#       under .claude/knowledge/runs/*/<section>/ containing measurement.json + diff summary
#   D5  codehealth or editability exit non-zero
#   D6  commit prefix decision exists and the message (arg $1, when invoked as commit-msg) violates it
#   D7  Co-Authored-By present in the message
set -u
SCRIPTS_DIR="$(git rev-parse --show-toplevel)/.claude/scripts"
KB=".claude/knowledge"
fail=0
die() { printf '🔒 BLOCKED: %s\n' "$1"; fail=1; }

# commit-msg mode (the .claude/hooks/commit-msg shim passes "--commit-msg <file>"): message doors only.
# Before this branch existed the message file never matched [ -f "$1" ], so D6/D7 silently never ran.
if [ "${1:-}" = "--commit-msg" ] && [ -f "${2:-}" ]; then
  MSG=$(cat "$2")
  printf '%s' "$MSG" | grep -qi 'co-authored-by' && die "Co-Authored-By in commit message — forbidden by conventions/git.md"
  PREFIX_DEC="$KB/decisions/0001-commit-prefix.md"
  if [ -f "$PREFIX_DEC" ]; then
    PFX=$(grep -Eo 'prefix:[[:space:]]*[a-z:]+' "$PREFIX_DEC" | head -1 | sed 's/prefix:[[:space:]]*//')
    if [ -n "${PFX:-}" ] && [ "$PFX" != "none" ]; then
      printf '%s' "$MSG" | head -1 | grep -q "^$PFX" || die "commit title missing decided prefix '$PFX' (decisions/0001)"
    fi
  fi
  [ "$fail" -eq 0 ] && exit 0
  echo "Fix the message — do not bypass."; exit 1
fi
STAGED=$(git diff --cached --name-only --diff-filter=ACM)
NEW_SECTIONS=$(git diff --cached --name-only --diff-filter=A | grep -E '^sections/f2s_.*\.liquid$' || true)
TOUCHED_SECTIONS=$(printf '%s\n' "$STAGED" | grep -E '^sections/f2s_.*\.liquid$' || true)
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# D0 — never commit dependency trees or build output (v4). A theme repo that swallows node_modules/
# is unreviewable: the PR is the single review surface, and nobody reviews 30k vendored files. This
# is separate from .gitignore because .gitignore is advice and a hook is a door.
JUNK=$(printf '%s\n' "$STAGED" | grep -E '(^|/)(node_modules|\.DS_Store|__pycache__|\.venv|dist|\.next)(/|$)' || true)
if [ -n "$JUNK" ]; then
  echo "🔴 BLOCKED: commit includes dependency/build artefacts:"
  printf '%s\n' "$JUNK" | head -10 | sed 's/^/     /'
  N_JUNK=$(printf '%s\n' "$JUNK" | grep -c . || true)
  [ "$N_JUNK" -gt 10 ] && echo "     ... and $((N_JUNK - 10)) more"
  echo "   Add them to .gitignore and 'git rm -r --cached' them. Do not --no-verify past this."
  exit 1
fi

# D0b — evidence under .claude/knowledge/runs/ is committed, but only the light kinds (v4.1). One rebuild
#   committed 7,052 run files (1.6 GB) because `!.claude/knowledge/runs/` un-ignored everything:
#   videos, HAR traces, Playwright trace zips, node_modules. .gitignore is advice; this is the door.
#   Allowed: *.json *.md *.csv *.txt and *.png under 500 KB (compress: sips -s format png / pngquant).
RUNS_STAGED=$(printf '%s
' "$STAGED" | grep -E '^\.claude/knowledge/runs/' || true)
if [ -n "$RUNS_STAGED" ]; then
  RUNS_BAD=$(printf '%s
' "$RUNS_STAGED" | grep -Ev '\.(json|md|csv|txt|png)$' || true)
  RUNS_BIG=""
  for f in $(printf '%s
' "$RUNS_STAGED" | grep -E '\.png$' || true); do
    sz=$(git cat-file -s ":$f" 2>/dev/null || echo 0)
    [ "$sz" -gt 512000 ] && RUNS_BIG="$RUNS_BIG $f($((sz/1024))KB)"
  done
  if [ -n "$RUNS_BAD$RUNS_BIG" ]; then
    echo "🔴 BLOCKED: run evidence that must not be committed (v4.1, the 1.6 GB evidence lesson):"
    [ -n "$RUNS_BAD" ] && printf '%s\n' "$RUNS_BAD" | head -10 | sed 's/^/     not json|md|csv|txt|png: /'
    [ -n "$RUNS_BIG" ] && printf '%s\n' $RUNS_BIG | sed 's/^/     png over 500 KB: /'
    echo "   Keep videos/HAR/traces out of runs/ (they are gitignored by bootstrap); compress PNGs under 500 KB."
    exit 1
  fi
fi

# D8 — a commit may carry ONE section's work (v4). Blocks the cross-agent sweep.
#   One build: four commits where one agent's broad `git add`/`git commit -a` scooped a CONCURRENT
#   agent's in-progress files into its own commit — the coordinator was one of the offenders.
#   Cost: wrong content, wrong authorship, one corrective commit, and `git log` permanently unable
#   to say who wrote which file. Two agents declined to fix it, correctly: rewriting history under
#   a live sibling is worse than the mess.
#   A hook cannot see WHICH git command staged a file, so it checks the outcome instead: the staged
#   section-scoped files must all belong to one handle. Shared, additively-edited files (registry,
#   deferrals, decisions, plans) are exempt — agents legitimately interleave there, and separating
#   those edits would destroy a sibling's work.
HANDLES=$(printf '%s\n' "$STAGED" \
  | grep -E '^(sections|snippets)/f2s_[a-z0-9_]+\.liquid$|^assets/f2s_[a-z0-9_]+\.(css|js)$' \
  | sed -E 's#^[a-z]+/f2s_##; s#\.(liquid|css|js)$##' \
  | sort -u)
N_HANDLES=$(printf '%s\n' "$HANDLES" | grep -c . || true)
if [ "${N_HANDLES:-0}" -gt 1 ]; then
  echo "🔴 BLOCKED: this commit carries files for $N_HANDLES different sections:"
  printf '%s\n' "$HANDLES" | sed 's/^/     f2s_/'
  echo "   One section per commit. If a concurrent agent's in-progress files were swept in by a"
  echo "   broad 'git add .' / 'git add -A' / 'git commit -a', unstage theirs — do NOT commit"
  echo "   another agent's work under your name, and do not rewrite history while they are live."
  echo "   Stage explicit paths: git reset && git add <your files>"
  exit 1
fi

# D1 — one new section per commit
N_NEW=$(printf '%s' "$NEW_SECTIONS" | grep -c . || true)
[ "${N_NEW:-0}" -gt 1 ] && die "commit adds $N_NEW new sections — one section per commit (build → verify → commit, per section)"

# D2 — no new f2s files on main
if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
  NEW_CS=$(git diff --cached --name-only --diff-filter=A | grep -c 'f2s_' || true)
  [ "${NEW_CS:-0}" -gt 0 ] && die "new f2s files committed directly to $BRANCH — create a task branch (feat/<section>)"
fi

# D3 — spec exists and predates the build
for f in $TOUCHED_SECTIONS; do
  sec=$(basename "$f" .liquid)
  spec=$(find "$KB/extraction/figma" -path "*${sec#f2s_}*/spec.json" -o -name "spec.json" -path "*$sec*" 2>/dev/null | head -1)
  # fallback: spec registered via sections/<key> dirs whose spec.json declares "section": "<name>"
  if [ -z "$spec" ]; then
    spec=$(grep -rl "\"section\"[[:space:]]*:[[:space:]]*\"$sec\"" "$KB/extraction/figma" 2>/dev/null | grep spec.json | head -1)
  fi
  if [ -z "$spec" ]; then
    # specs may declare the section under "liquid" (nested section object schema)
    spec=$(grep -rl "\"liquid\"[[:space:]]*:[[:space:]]*\"$sec\"" "$KB/extraction/figma" 2>/dev/null | grep spec.json | head -1)
  fi
  if [ -z "$spec" ]; then
    # Multi-section specs (plans/sections.json "liquid": "f2s_a + f2s_b (...)"):
    # one committed spec.json can legitimately cover TWO+ new sections under one plan "key" (e.g.
    # bundle_page -> f2s_bundle_hero + f2s_bundle_widget, decision: build as two
    # thin sections from one spec). The three lookups above all expect a 1:1 name<->path/string
    # match and miss this case even though the spec really does name $sec (spec.json's own
    # "section.liquid" array lists it, just with descriptive text appended after the name, which a
    # plain grep for an exact quoted string can't see). Resolve via the plan row instead, using the
    # same substring-match technique the RUNG lookup below already trusts: find the plan whose
    # "liquid" field mentions $sec, take its "key", and look for that key's spec.json.
    PLAN_KEY=$(python3 -c "
import json
try:
    d = json.load(open('$KB/plans/sections.json'))
    for s in d.get('sections', []):
        if '$sec' in str(s.get('liquid', '')):
            print(s.get('key', ''))
            break
except Exception:
    pass
" 2>/dev/null)
    if [ -n "$PLAN_KEY" ] && [ -f "$KB/extraction/figma/sections/$PLAN_KEY/spec.json" ]; then
      spec="$KB/extraction/figma/sections/$PLAN_KEY/spec.json"
    fi
  fi
  if [ -z "$spec" ]; then
    die "$sec: no spec.json found in $KB/extraction/figma — research the node first (cache_check must pass, then write the spec, THEN build)"
    continue
  fi
  SPEC_FIRST=$(git log --follow --format=%ct --diff-filter=A -- "$spec" | tail -1)
  SEC_FIRST=$(git log --follow --format=%ct --diff-filter=A -- "$f" | tail -1)
  # library-extended rung (plans/sections.json): the file is a boilerplate section extended IN PLACE,
  # so it legitimately predates the spec. The spec must still be committed before the extension lands.
  RUNG=$(python3 -c "
import json,sys
try:
    d=json.load(open('$KB/plans/sections.json'))
    print(next((s.get('rung','') for s in d['sections'] if '$sec' in str(s.get('liquid',''))), ''))
except Exception: print('')" 2>/dev/null)
  if [ "$RUNG" = "library-extended" ] && [ -n "$SPEC_FIRST" ] && [ -n "$SEC_FIRST" ] && [ "$SPEC_FIRST" -gt "$SEC_FIRST" ]; then
    echo "   ℹ️  $sec: library-extended in place (plans/sections.json) — boilerplate file predates the spec by design; spec is committed ($(date -r "$SPEC_FIRST" +%F 2>/dev/null))"
    SEC_FIRST="$SPEC_FIRST"
  fi
  if [ -z "$SPEC_FIRST" ]; then
    # spec not yet committed: only acceptable if it is staged IN AN EARLIER commit — i.e. not acceptable now
    printf '%s\n' "$STAGED" | grep -q "^$spec$" && die "$sec: spec.json is being committed in the SAME commit as the section — commit the spec first (retrofit prevention, see the retrofit post-mortem)" \
      || die "$sec: spec.json exists on disk but was never committed — commit the spec before the build"
  elif [ -n "$SEC_FIRST" ] && [ "$SPEC_FIRST" -gt "$SEC_FIRST" ]; then
    die "$sec: spec.json first committed AFTER the section (spec $SPEC_FIRST > section $SEC_FIRST) — spec was retrofitted"
  fi
done

# D4 — done claims need artifacts: if the registry row for a section changed, require a runs/ artifact
REG="$KB/architecture/f2s_registry.md"
if printf '%s\n' "$STAGED" | grep -q "f2s_registry.md"; then
  for f in $TOUCHED_SECTIONS; do
    sec=$(basename "$f" .liquid)
    ART=$(find "$KB/runs" -type d -name "$sec" 2>/dev/null | head -1)
    if [ -n "$ART" ]; then
      [ -f "$ART/measurement.json" ] || die "$sec: runs artifact exists but has no measurement.json"
      ls "$ART"/*diff* >/dev/null 2>&1 || die "$sec: runs artifact has no diff output — parity is a number from a script, or it doesn't exist"
    fi
  done
fi

# D5 — gates. Run against the INDEX (what this commit actually contains), not the working tree:
#   with several agents building in one tree, a sibling's half-written, uncommitted file (syntax
#   error, no header yet) must not lock this door — its owner meets that door on their own commit.
#   git checkout-index exports the staged state; node_modules is linked so the repo Shopify CLI runs.
#   (decision 0036)
IDX=$(mktemp -d /tmp/cs_index.XXXXXX)
git checkout-index -a -f --prefix="$IDX/" 2>/dev/null
[ -d node_modules ] && ln -s "$(pwd)/node_modules" "$IDX/node_modules"
STAGED_CS_SNIPPETS=$(printf '%s\n' "$STAGED" | grep -E '^snippets/f2s_.*\.liquid$' || true)
# theme check is the slow door (minutes under load); a commit that stages no theme file cannot change
# its result, so those commits (verify artifacts, plans, decisions, telemetry) skip it — everything else
# in codehealth still runs. Any staged file under sections/ snippets/ assets/ templates/ config/ layout/
# locales/ blocks/ runs the full check.
THEME_STAGED=$(printf '%s\n' "$STAGED" | grep -E '^(sections|snippets|assets|templates|config|layout|locales|blocks)/' | head -1)
SKIP_TC=0; [ -z "$THEME_STAGED" ] && SKIP_TC=1
if [ -x "$SCRIPTS_DIR/f2s_codehealth.sh" ]; then
  (cd "$IDX" && F2S_SKIP_THEMECHECK=$SKIP_TC sh "$SCRIPTS_DIR/f2s_codehealth.sh" .) >/tmp/cs_pc_ch.log 2>&1 || { die "codehealth gate failed (on the staged index):"; grep '^🔴' /tmp/cs_pc_ch.log | sed 's/^/    /'; }
fi
if [ -x "$SCRIPTS_DIR/f2s_editability.sh" ] && [ -n "$TOUCHED_SECTIONS$STAGED_CS_SNIPPETS" ]; then
  # scoped to the files THIS commit touches (decision 0035); the repo-wide run is GATE 8's door
  (cd "$IDX" && F2S_EDITABILITY_FILES="$(printf '%s %s' "$TOUCHED_SECTIONS" "$STAGED_CS_SNIPPETS" | tr '\n' ' ')" sh "$SCRIPTS_DIR/f2s_editability.sh" .) >/tmp/cs_pc_ed.log 2>&1 || { die "editability gate failed (this commit's files):"; grep '🔴' /tmp/cs_pc_ed.log | sed 's/^/    /'; }
fi
if [ -x "$SCRIPTS_DIR/f2s_functional.sh" ] && [ -n "$TOUCHED_SECTIONS" ]; then
  (cd "$IDX" && F2S_SKIP_UPLOAD=1 sh "$SCRIPTS_DIR/f2s_functional.sh" .) >/tmp/cs_pc_fn.log 2>&1 || { die "functional gate failed (9-classes, staged index):"; grep '🔴' /tmp/cs_pc_fn.log | sed 's/^/    /'; }
fi
# D5b — Shopify ADMIN upload rules (v4.1, decision 0057), scoped to the theme files THIS commit stages:
#   sections, snippets, config/settings_schema.json. One rebuild passed every gate and the admin rejected 22
#   sections at push. Runs on the staged index like D5; a sibling's untracked file cannot lock this door.
UPLOAD_FILES=$(printf '%s\n' "$STAGED" | grep -E '^(sections|snippets)/.*\.liquid$|^config/settings_schema\.json$' | tr '\n' ' ')
if [ -x "$SCRIPTS_DIR/f2s_upload_validator.sh" ] && [ -n "$(printf '%s' "$UPLOAD_FILES" | tr -d ' ')" ]; then
  (cd "$IDX" && F2S_UPLOAD_FILES="$UPLOAD_FILES" sh "$SCRIPTS_DIR/f2s_upload_validator.sh" .) >/tmp/cs_pc_up.log 2>&1 || { die "upload validator failed — Shopify's admin would reject this commit's files (decision 0057):"; grep '🔴' /tmp/cs_pc_up.log | sed 's/^/    /'; }
fi
rm -rf "$IDX"

# D6/D7 — message checks (when invoked with the message file as $1, i.e. commit-msg hook)
if [ "${1:-}" ] && [ -f "${1:-}" ]; then
  MSG=$(cat "$1")
  printf '%s' "$MSG" | grep -qi 'co-authored-by' && die "Co-Authored-By in commit message — forbidden by conventions/git.md"
  PREFIX_DEC="$KB/decisions/0001-commit-prefix.md"
  if [ -f "$PREFIX_DEC" ]; then
    PFX=$(grep -Eo 'prefix:[[:space:]]*[a-z:]+' "$PREFIX_DEC" | head -1 | sed 's/prefix:[[:space:]]*//')
    if [ -n "${PFX:-}" ] && [ "$PFX" != "none" ]; then
      printf '%s' "$MSG" | head -1 | grep -q "^$PFX" || die "commit title missing decided prefix '$PFX' (decisions/0001)"
    fi
  fi
fi

[ "$fail" -eq 0 ] && exit 0
echo ""
echo "One or more doors are locked. Fix the cause — do not bypass. (--no-verify defeats the entire system.)"
exit 1
