#!/usr/bin/env sh
# f2s_permcheck.sh — v4. Prove the run can proceed unattended BEFORE it starts.
#
# v3's failure: settings.json allowlisted "mcp__figma__*", which matches no server that exists.
# MCP permission rules match the normalized server name exactly and there is no lowercase "figma"
# server, so every Figma call fell through and prompted. On one build the file was absent entirely.
# Neither was detectable until a human was already sitting there clicking.
#
# v4.1 (most recent rebuild, 2026-09): `defaultMode: auto` was NOT honoured by the Claude desktop app and
# re-introduced per-command prompts; `bypassPermissions` + the deny list is what ran unattended.
# The deny list is what keeps bypass safe — check 5 is therefore the load-bearing one.
#
# Checks: settings.json present · committed · defaultMode bypassPermissions (auto warned) · deny list intact ·
#         at least one configured Figma MCP server is actually allowlisted ·
#         representative pipeline commands are covered.
# Exit 0 = the run can proceed unattended. Non-zero = fix before starting.
# Usage: sh f2s_permcheck.sh [theme_root]
set -u
ROOT="${1:-.}"; cd "$ROOT" || exit 1
S=".claude/settings.json"
fails=0
bad() { echo "🔴 $1"; fails=$((fails+1)); }
ok()  { echo "✅ $1"; }
wrn() { echo "⚠️  $1"; }

echo "================ permission preflight ================"

# 1. present
if [ ! -f "$S" ]; then
  bad "$S is MISSING — this is the missing-permissions failure. Copy resources/templates-v2/settings.json"
  echo "   into $S and commit it. Without it every script, commit and push prompts."
  echo "======================================================"
  exit 1
fi
ok "$S present"

# 2. parses
if ! python3 -c "import json,sys;json.load(open('$S'))" 2>/dev/null; then
  bad "$S does not parse as JSON — it is being ignored wholesale"
  exit 1
fi
ok "$S parses"

# 3. committed — an uncommitted file makes the run non-reproducible across machines
if git ls-files --error-unmatch "$S" >/dev/null 2>&1; then ok "$S is committed"
else bad "$S is NOT committed — a run that prompts on one machine and not another is not reproducible. git add it."; fi

# 4. defaultMode
MODE=$(python3 -c "import json;print(json.load(open('$S')).get('permissions',{}).get('defaultMode',''))" 2>/dev/null)
case "$MODE" in
  bypassPermissions) ok "defaultMode: bypassPermissions (v4.1 default — the deny list below is what keeps it safe)" ;;
  auto) wrn "defaultMode: auto — NOT honoured by the Claude desktop app on the most recent rebuild (2026-09): every compound Bash call prompted. Use bypassPermissions + the deny list (resources/templates-v2/settings.json)" ;;
  acceptEdits) wrn "defaultMode: acceptEdits — covers file edits but NOT Bash; expect prompts on scripts. bypassPermissions is the v4.1 default." ;;
  "") bad "no permissions.defaultMode set" ;;
  *) wrn "defaultMode: $MODE — not the v4.1 default (bypassPermissions); confirm this is deliberate" ;;
esac
# under bypassPermissions the allowlist is moot but the deny list is not: --no-verify and a live
# publish are one keystroke away for an unattended agent. Also require the Bash(*) note the last rebuild needed.
grep -qF '"Bash(*)"' "$S" || wrn "allow list has no \"Bash(*)\" — multi-command gate scripts never match single-program patterns; every compound call prompts when bypass is not honoured (see $bash_note in the settings template)"

# 5. deny list intact — the allowlist is only safe because these stay denied
MISSING_DENY=$(python3 - "$S" <<'PY' 2>/dev/null
import json,sys
need=["--force","--no-verify","--live","publish","pr merge","reset --hard","rm -rf"]
d=" ".join(json.load(open(sys.argv[1])).get("permissions",{}).get("deny",[]))
print(",".join(n for n in need if n not in d))
PY
)
if [ -n "${MISSING_DENY:-}" ]; then bad "deny list is missing protection for: $MISSING_DENY"
else ok "deny list intact (force-push, --no-verify, live publish, pr merge, hard reset, rm -rf)"; fi

# 6. Figma server — the v3 bug. Compare CONFIGURED servers against ALLOWLISTED ones.
CONFIGURED=$(python3 - <<'PY' 2>/dev/null
import json,os,glob
names=set()
for p in [os.path.expanduser("~/.claude.json")]:
    try:
        d=json.load(open(p))
        names.update((d.get("mcpServers") or {}).keys())
        for proj in (d.get("projects") or {}).values():
            names.update((proj.get("mcpServers") or {}).keys())
    except Exception: pass
for p in glob.glob(".mcp.json"):
    try: names.update((json.load(open(p)).get("mcpServers") or {}).keys())
    except Exception: pass
# normalize the way the tool namespace does: non [A-Za-z0-9_-] -> _
import re
print("\n".join(sorted(re.sub(r"[^A-Za-z0-9_-]","_",n) for n in names if "figma" in n.lower())))
PY
)
ALLOWED=$(python3 - "$S" <<'PY' 2>/dev/null
import json,sys,re
a=json.load(open(sys.argv[1])).get("permissions",{}).get("allow",[])
print("\n".join(sorted({m.group(1) for r in a if (m:=re.match(r"mcp__([^_]+(?:_[^_]+)*?)__",r))})))
PY
)
# v4.1: Figma MCP servers commonly present (settings.json $comment): Figma (desktop app),
#   figma-console (REST/Desktop Bridge), plugin_figma_figma (official plugin). A claude.ai connector
#   is NOT listed in ~/.claude.json, so the scan above cannot see it; it is proven by its allowlist
#   prefix instead. Add your connector's server id via F2S_FIGMA_SERVERS="Figma <connector-id> ...".
KNOWN="${F2S_FIGMA_SERVERS:-Figma figma-console plugin_figma_figma}"
echo "   configured Figma servers : ${CONFIGURED:-<none in ~/.claude.json or .mcp.json — connectors are not listed there>}"
echo "   allowlisted MCP servers  : $(echo "$ALLOWED" | tr '\n' ' ')"
MATCH=0
if [ -n "${CONFIGURED:-}" ]; then
  for c in $CONFIGURED; do
    for a in $ALLOWED; do [ "$c" = "$a" ] && MATCH=1 && ok "Figma server '$c' is allowlisted"; done
  done
fi
if [ "$MATCH" -eq 0 ]; then
  for k in $KNOWN; do
    for a in $ALLOWED; do [ "$k" = "$a" ] && MATCH=1 && ok "known Figma server '$k' is allowlisted (v4.1 known-prefix list)"; done
  done
fi
if [ "$MATCH" -eq 0 ]; then
  bad "NO configured Figma server is allowlisted — every Figma call will prompt (the v3 bug)."
  echo "   Add rules to $S using the tool names THIS server publishes (run /mcp to list them):"
  for c in ${CONFIGURED:-<your-figma-server>}; do
    echo "     \"mcp__${c}__<design-context-tool>\", \"mcp__${c}__<screenshot-tool>\", ..."
  done
  [ -z "${CONFIGURED:-}" ] && echo "   (none detected — connect a Figma MCP server first, then re-run)"
fi

# 7. representative pipeline commands
NEEDED="git commit|git push|gh pr create|shopify theme|python3|node|sh .claude/scripts"
MISSING=""
for n in "git commit" "git push" "gh pr create" "shopify theme" "sh .claude/scripts"; do
  grep -qF "$n" "$S" || MISSING="$MISSING  $n"
done
if [ -n "$MISSING" ]; then wrn "allowlist may not cover:$MISSING"
else ok "core pipeline commands covered (git, gh, shopify, scripts)"; fi

echo "------------------------------------------------------"
if [ "$fails" -eq 0 ]; then echo "PERMCHECK: PASS — the run can proceed unattended"; exit 0
else echo "PERMCHECK: FAIL ($fails) — fix the 🔴 items above; do NOT start a run that will sit prompting."; exit 1; fi
