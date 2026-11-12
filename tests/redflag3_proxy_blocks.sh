#!/usr/bin/env bash
# Red flag 3: from inside the box, the proxy must refuse other repos, merges, settings, deletes and GraphQL.
. "$(dirname "$0")/lib.sh"

mkbox
R="/ghapi/repos/$OWNER/$NAME"
main0="$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)"

step "positive control: the proxy does pass what is allowed"
check "GET own repo -> 200" test "$(code GET "$R")" = 200

step "must be refused (403)"
expect403() { check "$1 -> 403" test "$(code "$2" "$3" "${4-}")" = 403; }
expect403 "GET another repo (API)" GET /ghapi/repos/octocat/Hello-World
expect403 "GET another repo (git)" GET "/gh/octocat/Hello-World/info/refs?service=git-upload-pack"
expect403 "GraphQL" POST /ghapi/graphql '{"query":"{viewer{login}}"}'
expect403 "merge a PR" PUT "$R/pulls/1/merge"
expect403 "approve a PR" POST "$R/pulls/1/reviews" '{"event":"APPROVE"}'
expect403 "write a file via contents API" PUT "$R/contents/x.txt" '{"message":"m","content":"eA=="}'
expect403 "delete a branch ref" DELETE "$R/git/refs/heads/b1"
expect403 "change repo settings" PATCH "$R" '{"private":false}'
expect403 "delete the repo" DELETE "$R"
expect403 "path traversal to another repo" GET "$R/../../octocat/Hello-World"
expect403 "other API root (user)" GET /ghapi/user

step "a wrong token is refused"
check "made-up token -> 403" test "$(bx "curl -s -m 20 -o /dev/null -w '%{http_code}' -H 'Authorization: token not-the-fake-token' http://localhost:8080$R")" = 403

step "the proxy log names the rules"
for rule in not-own-repo rest-not-allowed gh-api-not-repos bad-token; do
  check "log has rule $rule" grep -q "\"rule\": *\"$rule\"" "$CFG/logs/$NAME.proxy.log"
done

step "nothing the refused calls aimed at happened"
check "repo still exists" gh repo view "$OWNER/$NAME"
check "main unchanged" test "$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)" = "$main0"
check "repo still private=false (settings untouched)" test "$(gh api "repos/$OWNER/$NAME" --jq .private)" = false
finish
