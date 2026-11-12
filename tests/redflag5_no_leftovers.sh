#!/usr/bin/env bash
# Red flag 5: rm and panic must leave nothing behind (a surviving proxy keeps the real tokens loaded).
# One repo, two rounds: new then rm, then reset (revive) then panic then rm.
. "$(dirname "$0")/lib.sh"
require_no_other_boxes

gone() { # label
  check "$1: box gone from machine list" test -z "$(state)"
  check "$1: launchd plists and socket gone" no_jobs
  check "$1: launchd has no job for it" bash -c "! launchctl list | grep -q 'dev.agent-boxes.$NAME-'"
  check "$1: no proxy or bridge process" no_procs
  check "$1: herdr machine removed" no_herdr_machine
}

mkbox
check "jobs and processes exist while running" has_jobs
sha="$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)"

step "round 1: rm"
"$BOX" rm "$NAME" || bad "rm"
gone "after rm"
check "repo kept" gh repo view "$OWNER/$NAME"

step "revive with reset, then panic"
"$BOX" reset "$NAME" --to "$sha" || bad "reset (revive)"
check "revived and running" is_state running
"$BOX" panic
check "panic: box stopped" is_state stopped
check "panic: jobs and socket gone" no_jobs
check "panic: no proxy or bridge process" no_procs
check "panic: herdr machine disabled or gone (no live pane server)" bash -c "! herdr machine list --json | jq -e --arg l '$NAME' '[.. | objects | select(.label? == \$l and .enabled? == true)] | length > 0' >/dev/null"

step "round 2: rm after panic"
"$BOX" rm "$NAME" || bad "rm after panic"
gone "after panic and rm"
finish
