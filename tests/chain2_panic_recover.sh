#!/usr/bin/env bash
# Chain 2: new, panic, then reset to the current commit. Does a box come back whole after a panic?
. "$(dirname "$0")/lib.sh"

# box panic stops EVERY box, so refuse to run next to real work.
if [ -n "$(other_running)" ] && [ "${BOX_TEST_ALLOW_PANIC:-}" != 1 ]; then
  echo "refusing: panic would stop these running boxes: $(other_running | tr '\n' ' ')" >&2
  echo "stop them first, or set BOX_TEST_ALLOW_PANIC=1" >&2
  exit 2
fi

step "new $NAME"
"$BOX" new "$NAME" || { bad "box new"; finish; }
check "box is running" is_state running
check "proxy and bridge jobs exist" has_jobs
check "bridge to proxy is up" bridge_up
sha="$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)"
[ -n "$sha" ] || { bad "could not read main sha"; finish; }

step "panic"
"$BOX" panic
check "box is stopped" is_state stopped
check "jobs and socket are gone" no_jobs

step "reset to $sha"
"$BOX" reset "$NAME" --to "$sha" || { bad "box reset"; finish; }
check "box is running again" is_state running
check "proxy and bridge jobs are back" has_jobs
check "bridge to proxy is up again" bridge_up
check "box HEAD is the commit we reset to" test "$(head_sha)" = "$sha"
check "no tracked file modified or deleted" bx "cd ~/$NAME && test -z \"\$(git diff HEAD --name-only --diff-filter=MD)\""
check "LAN is still blocked" bash -c "! $SANDBOX exec $NAME 'curl -s -m 3 -o /dev/null http://192.168.1.1'"
check "web is still reachable" bx 'curl -s -m 5 -o /dev/null https://github.com'
check "sudo still blocked" bash -c "! $SANDBOX exec $NAME 'sudo -n true'"
finish
