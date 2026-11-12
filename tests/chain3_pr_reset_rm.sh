#!/usr/bin/env bash
# Chain 3: new, commit and open a PR as the agent, reset to pr/N, then rm. The repo and status history must survive rm.
. "$(dirname "$0")/lib.sh"

mkbox
c1="$(commit_push b1 pr.txt)"; note "pr work" working
n="$(open_pr b1)"
check "PR opened through the proxy (got number '$n')" bash -c "[[ '$n' =~ ^[0-9]+$ ]]"
check "PR head is c1" test "$(gh api "repos/$OWNER/$NAME/pulls/$n" --jq .head.sha)" = "$c1"
"$BOX" status "$NAME" >/dev/null # pulls the note to the Mac

step "reset --to pr/$n"
"$BOX" reset "$NAME" --to "pr/$n" || bad "reset pr/$n"
check "HEAD is the PR head" test "$(head_sha)" = "$c1"
check "bridge up" bridge_up

step "rm"
"$BOX" rm "$NAME" || bad "box rm"
check "box gone from the machine list" test -z "$(state)"
check "proxy and bridge jobs and socket gone" no_jobs
check "no proxy or bridge process left" no_procs
check "herdr machine removed" no_herdr_machine
check "repo kept" gh repo view "$OWNER/$NAME"
check "PR kept" test "$(gh api "repos/$OWNER/$NAME/pulls/$n" --jq .state)" = open
check "status history kept on the Mac" grep -q "pr work" "$CFG/status/$NAME.log"
check "box status still prints the history" bash -c "'$BOX' status '$NAME' | grep -q '${c1:0:7}'"
finish
