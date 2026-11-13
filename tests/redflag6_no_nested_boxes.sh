#!/usr/bin/env bash
# Red flag 6: an agent inside a box cannot make boxes or repos of its own.
. "$(dirname "$0")/lib.sh"

mkbox
count_machines() { "$SANDBOX" ls | grep -c .; }
m0="$(count_machines)"

step "no way to make a box from inside"
for tool in box docker podman nerdctl security; do
  check "no '$tool' command in the box" box_fails "command -v $tool"
done
# OrbStack's guest tools (orb, orbctl, mac) ARE installed, but --isolated removes the socket they need to reach the Mac.
check "no docker or orbstack socket" box_fails 'ls /var/run/docker.sock /run/orbstack* 2>/dev/null | grep -q .'
check "'mac echo' (run a command on the Mac) does not run" test "$(bx 'timeout 10 mac echo HELLO-FROM-MAC 2>&1' | grep -c '^HELLO-FROM-MAC$')" = 0
check "'orb list' cannot see the Mac's machines" test "$(bx 'timeout 10 orb list 2>&1' | grep -c box-base)" = 0
bx "timeout 20 orb create debian $NAME-nested >/dev/null 2>&1"
check "'orb create' made no machine" test "$("$SANDBOX" ls | grep -c "$NAME-nested")" = 0
guard "$NAME-nested"; "$SANDBOX" rm "$NAME-nested" >/dev/null 2>&1 # only matters if the check above failed
check "no agent-boxes config or Keychain data in the box" box_fails 'ls ~/.config/agent-boxes ~/Library 2>/dev/null | grep -q .'
check "nothing listens on 127.0.0.1:32222 (the Mac's orb ssh port)" box_fails 'timeout 3 bash -c "echo > /dev/tcp/127.0.0.1/32222"'
check "the Mac's orb ssh port is not reachable by name" box_fails 'timeout 3 bash -c "echo > /dev/tcp/host.orb.internal/32222"'
gw="$(bx "ip route 2>/dev/null | awk '/default/ { print \$3; exit }'" | tr -d '[:space:]')"
if [ -n "$gw" ]; then
  check "gateway $gw: no ssh, no orb ssh port" bash -c "! $SANDBOX exec $NAME 'timeout 3 bash -c \"echo > /dev/tcp/$gw/22\"' && ! $SANDBOX exec $NAME 'timeout 3 bash -c \"echo > /dev/tcp/$gw/32222\"'"
else skip "could not read the default gateway"; fi
check "sudo blocked" box_fails 'sudo -n true'

step "no way to make a repo from inside"
check "create a repo for the user -> 403" test "$(code POST /ghapi/user/repos '{"name":"evil"}')" = 403
check "create a repo in an org -> 403" test "$(code POST /ghapi/orgs/x/repos '{"name":"evil"}')" = 403
check "fork its own repo -> 403" test "$(code POST "/ghapi/repos/$OWNER/$NAME/forks")" = 403
check "make a repo with a git push to a new URL fails" fails_on "$NAME" "cd ~/$NAME && GIT_TERMINAL_PROMPT=0 git push https://github.com/$OWNER/$NAME-evil HEAD:refs/heads/main"
check "no new repo appeared" bash -c "! gh repo view $OWNER/$NAME-evil"

step "none of that made a new box"
check "machine count unchanged ($m0)" test "$(count_machines)" = "$m0"
finish
