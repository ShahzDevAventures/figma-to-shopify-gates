#!/usr/bin/env sh
# f2s_hooks_mode.sh — v4. Whose repo is this right now?
#
# The gates exist because an unattended agent cannot be trusted to judge. That premise is correct
# for an agent and false for the developer who maintains the code afterwards — but the enforcement
# does not know the difference, because it lives in the REPO (core.hooksPath), not in the skill.
# Changing which skill Claude loads does nothing: a human running `git commit` gets the same doors.
#
# So the phase change is a repo state change:
#   agent       — doors locked. Every gate blocks. This is what an unattended run requires.
#   maintainer  — doors REMOVED. A developer's commits are not gated at all.
#
# Maintainer mode is deliberately "gone", not "advisory": a warning printed on every commit is
# noise to someone who can already see the problem, and tooling that nags gets bypassed rather
# than heeded. The gates come back automatically the next time bootstrap runs.
#
# The mode is RECORDED, because the one thing worse than gates that block is gates that are
# silently off. A prior build shipped with core.hooksPath unset on every fresh clone while the
# docs promised "a pre-commit hook runs these for you" — nobody could tell which state they were in.
#
# Nothing here is destructive: disarming unsets local git config and RENAMES hooks aside.
# Usage: sh f2s_hooks_mode.sh [agent|maintainer|status]
set -u
CMD="${1:-status}"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1
MARK=".claude/HOOKS_MODE"
HOOKDIR=".claude/hooks"

record() {
  mkdir -p .claude
  {
    echo "mode: $1"
    echo "set_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "by: ${USER:-unknown}"
    echo "$2"
  } > "$MARK"
}

case "$CMD" in
  maintainer)
    git config --unset core.hooksPath 2>/dev/null || true
    for h in pre-commit commit-msg; do
      if [ -e ".git/hooks/$h" ] && grep -q f2s ".git/hooks/$h" 2>/dev/null; then
        mv ".git/hooks/$h" ".git/hooks/$h.f2s-disabled"
        echo "  moved aside: .git/hooks/$h"
      fi
    done
    record maintainer "note: gates are OFF. Commits are not checked. Re-arm before any agent run
      with: sh .claude/scripts/f2s_hooks_mode.sh agent
      The gate scripts still work by hand: sh .claude/scripts/f2s_codehealth.sh ."
    echo "✅ MAINTAINER mode — hooks removed. Your commits are not gated."
    echo "   Recorded in $MARK. Re-arm with: sh .claude/scripts/f2s_hooks_mode.sh agent"
    ;;
  agent)
    [ -d "$HOOKDIR" ] || { echo "🔴 $HOOKDIR missing — run bootstrap first" >&2; exit 1; }
    for h in pre-commit commit-msg; do
      [ -e ".git/hooks/$h.f2s-disabled" ] && mv ".git/hooks/$h.f2s-disabled" ".git/hooks/$h"
      [ -f "$HOOKDIR/$h" ] && chmod +x "$HOOKDIR/$h"
    done
    git config core.hooksPath "$HOOKDIR"
    record agent "note: gates are ON. Every commit is checked; --no-verify is never the answer."
    echo "✅ AGENT mode — hooks armed at $HOOKDIR"
    ;;
  status)
    HP=$(git config core.hooksPath 2>/dev/null || true)
    if [ -n "$HP" ] && [ -x "$HP/pre-commit" ]; then STATE="AGENT (armed at $HP)"
    elif [ -x .git/hooks/pre-commit ] && grep -q f2s .git/hooks/pre-commit 2>/dev/null; then STATE="AGENT (armed at .git/hooks)"
    else STATE="MAINTAINER (no gates on commit)"; fi
    echo "hooks: $STATE"
    if [ -f "$MARK" ]; then sed 's/^/  /' "$MARK"; else
      echo "  (no $MARK — mode was never set deliberately, which is its own problem:"
      echo "   core.hooksPath is LOCAL config and does not clone, so a fresh clone silently has"
      echo "   no gates while the docs promise they run. Set the mode explicitly.)"
    fi
    ;;
  *) echo "usage: f2s_hooks_mode.sh [agent|maintainer|status]" >&2; exit 2 ;;
esac
