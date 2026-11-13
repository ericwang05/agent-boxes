#!/usr/bin/env bash
# Chain 1: new, two commits with status notes, status --history, bad resets, reset to status/1, then to the later commit.
. "$(dirname "$0")/lib.sh"

mkbox
c1="$(commit_push b1 one.txt)"; note "step one" working
c2="$(commit_push b1 two.txt)"; note "step two" done
check "two distinct commits made" test -n "$c1" -a -n "$c2" -a "$c1" != "$c2"

step "status"
hist="$("$BOX" status "$NAME" --history 2>&1)"; echo "$hist"
check "history has 2 entries" test "$(grep -cE '^ *[0-9]+ ' <<<"$hist")" = 2
check "entry 1 logs commit ${c1:0:7}" grep -qE "^ *1 .*working +${c1:0:7} " <<<"$hist"
check "entry 2 logs commit ${c2:0:7}" grep -qE "^ *2 .*done +${c2:0:7} " <<<"$hist"
check "plain status shows the latest (done, ${c2:0:7})" bash -c "'$BOX' status '$NAME' | grep -q 'done.*${c2:0:7}'"

step "bad resets must not touch the box"
check "reset --to status/99 fails" bash -c "! '$BOX' reset '$NAME' --to status/99"
check "reset --to deadbeef fails" bash -c "! '$BOX' reset '$NAME' --to deadbeef"
check "reset --to nonsense fails" bash -c "! '$BOX' reset '$NAME' --to banana"
check "box still running, same HEAD" bash -c "[ \"\$($SANDBOX ls | awk -v n=$NAME '\$1==n{print \$2}')\" = running ]"
check "HEAD is still ${c2:0:7}" test "$(head_sha)" = "$c2"

step "reset --to status/1"
"$BOX" reset "$NAME" --to status/1 || bad "reset status/1"
check "HEAD is c1" test "$(head_sha)" = "$c1"
check "one.txt present, two.txt gone" bx "cd ~/$NAME && test -e one.txt && test ! -e two.txt"
check "no tracked file modified or deleted" bx "cd ~/$NAME && test -z \"\$(git diff HEAD --name-only --diff-filter=MD)\""
check "bridge up" bridge_up
# The entry for the reset commit stays. Entries after it are dropped by newer boxes (reset prunes them) and kept by older ones.
check "Mac status log still has the entry for ${c1:0:7}" grep -q "${c1:0:7}" "$CFG/status/$NAME.log"

step "reset --to full commit c2"
"$BOX" reset "$NAME" --to "$c2" || bad "reset c2"
check "HEAD is c2" test "$(head_sha)" = "$c2"
check "two.txt present again" bx "cd ~/$NAME && test -e two.txt"
finish
