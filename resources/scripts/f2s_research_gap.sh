#!/usr/bin/env sh
# f2s_research_gap.sh — v4. Give RE-RESEARCH somewhere to land.
#
# The bug this closes: agents were told to return "RE-RESEARCH: <node>" when a spec or brief could
# not answer something. They complied. On one build, `grep -rn "RE-RESEARCH"` across the whole repo
# returned exactly ONE hit — the instruction telling them to say it. Every gap was spoken aloud in
# a final message and then gone: no file, no id, no gate, no way to notice a dropped one. The
# orchestrator rescued them by hand that time, which is the only reason it did not cost anything.
#
# v4 made this worse before this script existed: the section brief, the fixer, the builder and the
# "no agent calls Figma after GATE 3" rule ALL route their escape hatch through RE-RESEARCH, so the
# busiest channel in the pipeline was also the only one with no artifact.
#
# A returned string is not a record. This is the record.
#
# Usage:
#   f2s_research_gap.sh add <section> <node> <reason...>   record a gap (prints its id)
#   f2s_research_gap.sh close <id> [note...]               mark one resolved
#   f2s_research_gap.sh list                               show all
#   f2s_research_gap.sh                                    report OPEN gaps; exit 1 if any
set -u
LEDGER=".claude/knowledge/plans/research-gaps.md"
CMD="${1:-check}"

ensure() {
  [ -f "$LEDGER" ] && return 0
  mkdir -p "$(dirname "$LEDGER")"
  cat > "$LEDGER" <<'EOF'
# Research gaps (RE-RESEARCH ledger)

Every `RE-RESEARCH: <node>` an agent returns MUST be recorded here by
`f2s_research_gap.sh add`. A gap that exists only in an agent's final message is not
tracked — it is a dropped requirement with a plausible-sounding paper trail.

Preflight and the page-integration gate both refuse to pass while any row is OPEN.

| id | status | section | node | reason | resolution |
|---|---|---|---|---|---|
EOF
}

case "$CMD" in
  add)
    shift
    SECTION="${1:?usage: add <section> <node> <reason...>}"; shift
    NODE="${1:?usage: add <section> <node> <reason...>}"; shift
    REASON="$*"
    [ -n "$REASON" ] || { echo "a gap needs a reason — what could the brief not answer?" >&2; exit 2; }
    ensure
    N=$(grep -c '^| RG-' "$LEDGER" 2>/dev/null || true)
    ID=$(printf 'RG-%03d' $((N + 1)))
    # pipes would break the table row
    SAFE=$(printf '%s' "$REASON" | tr '|' '/' | tr -d '\n')
    printf '| %s | OPEN | %s | %s | %s | |\n' "$ID" "$SECTION" "$NODE" "$SAFE" >> "$LEDGER"
    echo "$ID recorded in $LEDGER"
    echo "This section is now BLOCKED until $ID is closed. Do not guess the value."
    ;;
  close)
    shift
    ID="${1:?usage: close <id> [note...]}"; shift
    NOTE="$(printf '%s' "$*" | tr '|' '/' | tr -d '\n')"
    [ -f "$LEDGER" ] || { echo "no ledger at $LEDGER" >&2; exit 1; }
    grep -q "^| $ID |" "$LEDGER" || { echo "no such gap: $ID" >&2; exit 1; }
    TMP=$(mktemp)
    awk -v id="$ID" -v note="$NOTE" -F'|' '
      $0 ~ "^\\| " id " \\|" { sub(/\| OPEN \|/, "| CLOSED |"); sub(/\| *\| *$/, "| " note " |") }
      { print }' "$LEDGER" > "$TMP" && mv "$TMP" "$LEDGER"
    echo "$ID closed"
    ;;
  list)
    [ -f "$LEDGER" ] && cat "$LEDGER" || echo "no ledger yet (no gaps recorded)"
    ;;
  check|"")
    if [ ! -f "$LEDGER" ]; then echo "✅ research gaps: none recorded"; exit 0; fi
    OPEN=$(grep -c '^| RG-[0-9]* | OPEN |' "$LEDGER" 2>/dev/null || true)
    if [ "$OPEN" -eq 0 ]; then
      TOTAL=$(grep -c '^| RG-' "$LEDGER" 2>/dev/null || true)
      echo "✅ research gaps: $TOTAL recorded, 0 open"
      exit 0
    fi
    echo "🔴 $OPEN OPEN research gap(s) — sections depending on them may not be built or shipped:"
    grep '^| RG-[0-9]* | OPEN |' "$LEDGER" | sed 's/^/   /'
    echo "   Re-extract the node and close with: f2s_research_gap.sh close <id> <note>"
    exit 1
    ;;
  *)
    echo "usage: f2s_research_gap.sh [add|close|list|check]" >&2; exit 2 ;;
esac
