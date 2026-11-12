#!/usr/bin/env bash
# Chain 4b: box new --fork (fork somebody else's repo into your account), then reset.
# Forks octocat/Hello-World (GitHub's public demo repo); the fork is named after the box and deleted at the end.
. "$(dirname "$0")/lib.sh"

mkbox --fork octocat/Hello-World
def="$(gh api "repos/$OWNER/$NAME" --jq .default_branch)"
check "it is a fork of octocat/Hello-World" test "$(gh api "repos/$OWNER/$NAME" --jq .parent.full_name)" = octocat/Hello-World
check "box running" is_state running
check "bridge up" bridge_up
check "protect-main ruleset applied" bash -c "gh api repos/$OWNER/$NAME/rulesets --jq '.[] | select(.name==\"protect-main\") | .id' | grep -q ."
d0="$(gh api "repos/$OWNER/$NAME/commits/$def" --jq .sha)"
check "box starts at the fork's default branch head" test "$(head_sha)" = "$d0"

c1="$(commit_push b1 one.txt)"; note "fork work" working
"$BOX" status "$NAME" >/dev/null
check "status logs the box HEAD (${c1:0:7})" bash -c "grep -q '$c1' '$CFG/status/$NAME.log'"

step "reset to the commit, then to the default branch head"
"$BOX" reset "$NAME" --to "$c1" || bad "reset c1"
check "HEAD is c1" test "$(head_sha)" = "$c1"
"$BOX" reset "$NAME" --to "$d0" || bad "reset d0"
check "HEAD is the default branch head" test "$(head_sha)" = "$d0"
check "repo is healthy (git fsck)" bx "cd ~/$REPO_NAME && git fsck --no-progress"
finish
