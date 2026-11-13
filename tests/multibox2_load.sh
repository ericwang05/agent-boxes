#!/usr/bin/env bash
# Two boxes at once, many simultaneous requests: all succeed, nothing crosses between boxes, and one box
# hitting its stream cap does not starve the other.
. "$(dirname "$0")/lib.sh"

mkbox; mkbox2
A="$NAME"; B="$NAME2"
t="$(mktemp -d)"
trap 'rc=$?; rm -rf "$t"; cleanup; exit $rc' EXIT

health_burst() { bxo "$1" bash -s <<'EOF'
seq 50 | xargs -P50 -I{} curl -s -m 20 -o /dev/null -w '%{http_code}\n' http://localhost:8080/__health | sort | uniq -c
EOF
}
api_burst() { # box repo: 20 parallel reads of its own repo; prints which repo name came back
  bxo "$1" bash -s <<EOF
. ~/.box-env
seq 20 | xargs -P20 -I{} sh -c 'curl -s -m 30 -H "Authorization: token \$GH_TOKEN" http://localhost:8080/ghapi/repos/$OWNER/$2 | jq -r .name' | sort | uniq -c
EOF
}
norm() { sed -E 's/^ +//' "$1"; }

step "50 simultaneous health checks in each box, both boxes at the same time"
health_burst "$A" >"$t/ha" & health_burst "$B" >"$t/hb" & wait
check "A: all 50 answered 200" test "$(norm "$t/ha")" = "50 200"
check "B: all 50 answered 200" test "$(norm "$t/hb")" = "50 200"

step "20 simultaneous GitHub reads in each box: every answer is for that box's own repo"
api_burst "$A" "$A" >"$t/aa" & api_burst "$B" "$B" >"$t/ab" & wait
check "A got 20 answers, all for A's repo" test "$(norm "$t/aa")" = "20 $A"
check "B got 20 answers, all for B's repo" test "$(norm "$t/ab")" = "20 $B"

step "A holds 120 connections open (its cap is 64 streams); B must not notice"
pidA="$(pgrep -f "agentbox-bridge mac-side -box $A" | head -1)"
bxo "$A" bash -s >/dev/null 2>&1 <<'EOF2' &
for i in $(seq 120); do ( exec 3<>/dev/tcp/127.0.0.1/8080; sleep 40 ) & done
wait
EOF2
holder=$!
# Prove the load really reached the cap: the bridge counts the most streams open at once and how many it turned away.
cap_hit() { local f="$CFG/logs/status/$A.json"; [ "$(jq -r '.peak // 0' "$f" 2>/dev/null)" -ge 64 ] && [ "$(jq -r '.rejected_by.max_streams // 0' "$f" 2>/dev/null)" -ge 1 ]; }
wait_cap() { local i; for i in $(seq 25); do cap_hit && return 0; sleep 1; done; return 1; }
check "A hit its cap: peak open streams >= 64 and some rejected for max_streams" wait_cap
health_burst "$B" >"$t/hb2"
check "B: all 50 health checks still 200 while A is saturated" test "$(norm "$t/hb2")" = "50 200"
check "B's bridge is up" bridge_up_of "$B"
wait "$holder" 2>/dev/null
check "A recovers within 45s of the connections closing" wait_bridge_up "$A" 45
pidA2="$(pgrep -f "agentbox-bridge mac-side -box $A" | head -1)"
if [ "$pidA" = "$pidA2" ]; then echo "  info A's bridge survived the flood (same process)"; else echo "  info A's bridge restarted during the flood (launchd brought it back)"; fi
finish
