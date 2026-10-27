#!/usr/bin/env sh
# f2s_telemetry.sh — cost-per-accepted-section ledger (v2 item 19).
# Usage: sh f2s_telemetry.sh <section> <role> <model> <tokens> <loop_n> <result PASS|FAIL>
set -u
KB=".claude/knowledge/runs"; mkdir -p "$KB"
F="$KB/telemetry.csv"
[ -f "$F" ] || echo "ts,section,role,model,tokens,loop,result" > "$F"
echo "$(date +%s),$1,$2,$3,$4,$5,$6" >> "$F"
# per-PR summary: awk aggregation
awk -F, 'NR>1{t[$2]+=$5; l[$2]=($6=="PASS"?$5+t[$2]:t[$2]); r[$2]=$7} END{}' "$F" 2>/dev/null || true
