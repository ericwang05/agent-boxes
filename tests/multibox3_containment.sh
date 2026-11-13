#!/usr/bin/env bash
# Two boxes at once: breaking, resetting or removing box A must not interrupt box B.
# A poller inside B hits its health check every second for the whole test; every answer must be 200.
. "$(dirname "$0")/lib.sh"

mkbox; mkbox2
A="$NAME"; B="$NAME2"
t="$(mktemp -d)"
trap 'rc=$?; kill "$poller" 2>/dev/null; rm -rf "$t"; cleanup; exit $rc' EXIT
poller=""
shaA="$(gh api "repos/$OWNER/$A/commits/main" --jq .sha)"

step "start B's poller"
# The log lives inside B (not in a pipe to the Mac), so stopping the poller cannot lose lines. A flag file stops it.
bxo "$B" 'rm -f /tmp/stop /tmp/poll.log; i=0; while [ ! -e /tmp/stop ] && [ $i -lt 600 ]; do curl -s -m 3 -o /dev/null -w "%{http_code}\n" http://localhost:8080/__health | sed "s/^/$(date +%s) /" >>/tmp/poll.log; i=$((i+1)); sleep 1; done' >/dev/null 2>&1 &
poller=$!
sleep 5

ev() { echo "$1 $(date +%s)" >>"$t/events"; }
step "kill A's bridge"; ev bridge-killed
pkill -f "agentbox-bridge mac-side -box $A"
check "launchd brings A's bridge back" wait_bridge_up "$A" 60
step "kill A's proxy"; ev proxy-killed
pkill -f "proxy.py --box $A"
check "launchd brings A's proxy back (A answers again)" wait_bridge_up "$A" 60
step "reset A while B keeps running"; ev reset-start
"$BOX" reset "$A" --to "$shaA" || bad "reset A"
check "A is running again after reset" wait_bridge_up "$A" 30
check "B's jobs untouched by A's reset" bash -c "ls '$LA'/dev.agent-boxes.$B-* | wc -l | grep -q 2"
ev reset-done
step "remove A while B keeps running"
"$BOX" rm "$A" || bad "rm A"
check "A is gone" test -z "$(state)"
check "B still running with its jobs" bash -c "[ \"\$($SANDBOX ls | awk -v n=$B '\$1==n{print \$2}')\" = running ] && ls '$LA'/dev.agent-boxes.$B-* | wc -l | grep -q 2"
check "B's bridge up" bridge_up_of "$B"
ev rm-done

bxo "$B" 'touch /tmp/stop'; wait "$poller" 2>/dev/null
bxo "$B" 'cat /tmp/poll.log' >"$t/poll"
n="$(grep -c . "$t/poll")"; badn="$(awk '$2 != 200' "$t/poll" | grep -c .)"
first="$(head -1 "$t/poll" | cut -d' ' -f1)"; last="$(tail -1 "$t/poll" | cut -d' ' -f1)"
echo "  info poller: $n answers from t+0 to t+$((last - first))s; events (seconds after the poller's first answer):"
while read -r name at; do echo "  info   $name at t+$((at - first))s"; done <"$t/events"
rmdone="$(awk '$1=="rm-done"{print $2}' "$t/events")"
check "B's poller kept running until A was removed (last answer within 5s of it)" test "$last" -ge $((rmdone - 5))
check "every one of the $n answers was 200 ($badn were not)" test "$badn" -eq 0
finish
