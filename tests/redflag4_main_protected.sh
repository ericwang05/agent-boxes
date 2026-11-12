#!/usr/bin/env bash
# Red flag 4: the agent must not be able to change main. Checked twice: through the box, and straight at GitHub with the
# bot's own token (so the GitHub ruleset is tested even if the proxy were wrong).
. "$(dirname "$0")/lib.sh"

mkbox
main0="$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)"
c1="$(commit_push b1 x.txt)"
check "agent can push a feature branch (control)" test "$(gh api "repos/$OWNER/$NAME/commits/b1" --jq .sha)" = "$c1"
n="$(open_pr b1)"
check "agent can open a PR (control, #$n)" bash -c "[[ '$n' =~ ^[0-9]+$ ]]"

step "from the box"
check "push to main refused" box_fails "cd ~/$NAME && git push origin HEAD:refs/heads/main"
check "force push to main refused" box_fails "cd ~/$NAME && git push --force origin HEAD:refs/heads/main"
check "delete main refused" box_fails "cd ~/$NAME && git push origin :refs/heads/main"
check "merge via API refused" test "$(code PUT "/ghapi/repos/$OWNER/$NAME/pulls/$n/merge")" = 403

step "straight at GitHub with the bot token (the ruleset itself)"
tok="$(security find-generic-password -s agentbox-github -w | tr -d '[:space:]')"
[[ ! "$tok" =~ ^([0-9a-f]{2})+$ ]] || tok="$(xxd -r -p <<<"$tok")"
check "bot cannot merge its own unapproved PR" bash -c "! GH_TOKEN='$tok' gh api -X PUT repos/$OWNER/$NAME/pulls/$n/merge"
check "bot cannot move main to its commit" bash -c "! GH_TOKEN='$tok' gh api -X PATCH repos/$OWNER/$NAME/git/refs/heads/main -f sha=$c1 -F force=true"
check "bot cannot delete main" bash -c "! GH_TOKEN='$tok' gh api -X DELETE repos/$OWNER/$NAME/git/refs/heads/main"
unset tok

step "the ruleset"
check "protect-main: active, no bypass, default branch, >=1 approval" bash -c "gh api repos/$OWNER/$NAME/rulesets --jq '.[]|select(.name==\"protect-main\")|.id' | xargs -I{} gh api repos/$OWNER/$NAME/rulesets/{} --jq '.enforcement==\"active\" and (.bypass_actors|length)==0 and (.conditions.ref_name.include|index(\"~DEFAULT_BRANCH\"))!=null and ([.rules[]|select(.type==\"pull_request\")|.parameters.required_approving_review_count]|max//0)>=1' | grep -qx true"
check "main is exactly where it started" test "$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)" = "$main0"
finish
