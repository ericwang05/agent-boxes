#!/usr/bin/env bash
# Two boxes at once: box A cannot reach box B (network, proxy, repo), and their tokens, logs and sockets stay separate.
. "$(dirname "$0")/lib.sh"

mkbox; mkbox2
A="$NAME"; B="$NAME2"
ipA="$(ip_of "$A")"; ipB="$(ip_of "$B")"
check "both running, different IPs ($ipA, $ipB)" bash -c "[ -n '$ipA' ] && [ -n '$ipB' ] && [ '$ipA' != '$ipB' ]"
check "A's bridge is up" bridge_up_of "$A"
check "B's bridge is up" bridge_up_of "$B"
check "control: A can open a TCP connection to github.com:443" bxo "$A" 'timeout 4 bash -c "echo > /dev/tcp/github.com/443"'

step "network: neither box can reach the other (any of these ports)"
for port in 22 80 443 8080 32222 5000; do
  check "A -> B:$port blocked" fails_on "$A" "timeout 4 bash -c 'echo > /dev/tcp/$ipB/$port'"
  check "B -> A:$port blocked" fails_on "$B" "timeout 4 bash -c 'echo > /dev/tcp/$ipA/$port'"
done
check "A -> B http blocked" fails_on "$A" "curl -s -m 3 -o /dev/null http://$ipB"

step "proxy: A's proxy serves only A"
fakeA="$(bxo "$A" '. ~/.box-env; echo $GH_TOKEN' | tr -d '[:space:]')"
fakeB="$(bxo "$B" '. ~/.box-env; echo $GH_TOKEN' | tr -d '[:space:]')"
check "the two fake tokens differ and look fake" bash -c "[ '$fakeA' != '$fakeB' ] && [[ '$fakeA' == FAKE-GH-* ]] && [[ '$fakeB' == FAKE-GH-* ]]"
check "A's proxy refuses B's fake token (403)" test "$(bxo "$A" "curl -s -m 20 -o /dev/null -w '%{http_code}' -H 'Authorization: token $fakeB' http://localhost:8080/ghapi/repos/$OWNER/$A")" = 403
check "A's own token on A's repo works (200, control)" test "$(code GET "/ghapi/repos/$OWNER/$A")" = 200
check "A cannot read B's repo through its proxy (403)" test "$(code GET "/ghapi/repos/$OWNER/$B")" = 403
check "A cannot clone B's repo through its proxy (403)" test "$(code GET "/gh/$OWNER/$B/info/refs?service=git-upload-pack")" = 403
check "A cannot push to B's repo straight at GitHub (no real token)" fails_on "$A" "cd ~/$A && GIT_TERMINAL_PROMPT=0 git push https://github.com/$OWNER/$B HEAD:refs/heads/stolen"
check "B's repo has no stray branch" bash -c "! gh api repos/$OWNER/$B/branches/stolen"

step "state: nothing is shared"
check "A holds no trace of B's fake token" fails_on "$A" "grep -rqs 'FAKE-GH-$B' ~ /etc"
check "B holds no trace of A's fake token" fails_on "$B" "grep -rqs 'FAKE-GH-$A' ~ /etc"
check "A's proxy log only names A" test "$(jq -r .box "$CFG/logs/$A.proxy.log" | sort -u)" = "$A"
check "B's proxy log only names B" test "$(jq -r .box "$CFG/logs/$B.proxy.log" | sort -u)" = "$B"
check "two separate sockets" bash -c "[ -S '$CFG/run/$A.sock' ] && [ -S '$CFG/run/$B.sock' ] && [ '$A' != '$B' ]"
check "two separate pairs of jobs" bash -c "ls '$LA'/dev.agent-boxes.$A-* '$LA'/dev.agent-boxes.$B-* | wc -l | grep -q 4"
finish
