#!/usr/bin/env sh
# f2s_deferrals.sh — harvest deliberate-deviation markers into a ledger.
#
# Convention (inspired by ponytail's `ponytail:` tags): any deliberate deviation, shortcut,
# or cross-section dependency the builder cannot resolve gets a greppable marker naming the
# tradeoff AND the trigger for fixing it:
#
#   {% comment %} f2s: image overlay deferred — needs cross-section coordination at
#   page integration {% endcomment %}
#   /* f2s: !important vs Impulse .btn (specificity 0,3,0) — remove when legacy css scoped */
#
# Why: on an earlier build the builder found a real bug in a shared snippet and left a polite "REQUEST"
# comment that nothing ever read. Deviations must land in a queue a human sees, not a graveyard.
# This script is that queue: run at PR time, output pasted into the PR body verbatim.
# Reporting tool — always exits 0.
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1

echo "## Deferral ledger ($(git rev-parse --short HEAD 2>/dev/null || echo 'uncommitted'))"
echo ""
FOUND=0
for f in $(find sections snippets assets -name 'f2s_*' -type f 2>/dev/null | sort); do
  HITS=$(grep -n 'f2s:' "$f" 2>/dev/null | grep -v 'f2s:[a-z_-]*[;{}]' || true)
  [ -z "$HITS" ] && continue
  FOUND=1
  echo "### $f"
  printf '%s\n' "$HITS" | sed 's/^\([0-9]*\):[[:space:]]*/- L\1: /' \
    | sed 's/{%-\{0,1\}[[:space:]]*comment[[:space:]]*-\{0,1\}%}//; s/{%-\{0,1\}[[:space:]]*endcomment[[:space:]]*-\{0,1\}%}//; s|/\*||; s|\*/||' \
    | sed 's/[[:space:]]*$//'
  echo ""
done
if [ "$FOUND" -eq 0 ]; then
  echo "_No f2s: markers found. Either nothing was deferred, or deviations were made"
  echo "silently — the second one is the bug. Builders: every deliberate deviation gets a marker._"
fi
exit 0
