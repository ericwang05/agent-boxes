#!/usr/bin/env bash
# Chain 4a: box new --repo (attach an existing repo of yours), then reset. Right commit logged, repo state good.
. "$(dirname "$0")/lib.sh"

REPO_NAME="$NAME-att"; EXTRA_REPO="$OWNER/$REPO_NAME"
step "make the repo to attach: $EXTRA_REPO"
guard "$REPO_NAME"
gh repo create "$EXTRA_REPO" --public --add-readme >/dev/null || { bad "gh repo create"; finish; }
sleep 3
mkbox --repo "$EXTRA_REPO"
check "box running" is_state running
check "bridge up" bridge_up
check "protect-main ruleset applied (details are checked in redflag4)" bash -c "gh api repos/$EXTRA_REPO/rulesets --jq '.[] | select(.name==\"protect-main\") | .id' | grep -q ."
check "repo cloned into the box" bx "cd ~/$REPO_NAME && git rev-parse HEAD"

c1="$(commit_push b1 one.txt)"; note "attached work" working
"$BOX" status "$NAME" >/dev/null
check "status logs the box HEAD (${c1:0:7})" bash -c "grep -q '$c1' '$CFG/status/$NAME.log'"

step "reset to the commit"
"$BOX" reset "$NAME" --to "$c1" || bad "reset"
check "HEAD is c1" test "$(head_sha)" = "$c1"
check "repo is healthy (git fsck)" bx "cd ~/$REPO_NAME && git fsck --no-progress"
check "no tracked file modified or deleted" bx "cd ~/$REPO_NAME && test -z \"\$(git diff HEAD --name-only --diff-filter=MD)\""

step "rm keeps the attached repo"
"$BOX" rm "$NAME" || bad "rm"
check "attached repo still exists" gh repo view "$EXTRA_REPO"
finish
