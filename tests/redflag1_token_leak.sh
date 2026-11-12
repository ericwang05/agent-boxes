#!/usr/bin/env bash
# Red flag 1: the real Claude and GitHub tokens must never appear in a box (files, env, argv),
# after new and after reset. We pull the box's data out and search it on the Mac, so the tokens never go into the box.
. "$(dirname "$0")/lib.sh"

umask 077
pats="$(mktemp)"; dump="$(mktemp)"
trap 'rc=$?; rm -f "$pats" "$dump"; cleanup; exit $rc' EXIT
for k in claude github; do
  t="$(security find-generic-password -s "agentbox-$k" -w 2>/dev/null | tr -d '[:space:]')"
  [ ${#t} -ge 30 ] || { echo "no usable Keychain token agentbox-$k" >&2; exit 2; }
  printf '%s\n%s\n' "$t" "${t:8:24}" >>"$pats" # the whole token and a slice, in case it is cut up
  # The Keychain prints a token containing a newline as hex; the proxy decodes it, so search for the decoded form too.
  if [[ "$t" =~ ^([0-9a-f]{2})+$ ]]; then
    d="$(xxd -r -p <<<"$t" | tr -d '[:space:]')"
    [ ${#d} -ge 30 ] && printf '%s\n%s\n' "$d" "${d:8:24}" >>"$pats" # never write an empty line: it would match everything
  fi
done

dump_box() { # fills $dump; an empty or failed dump would pass by accident
  bx 'tar -cf - -C / etc home root var/log opt srv tmp usr/local 2>/dev/null; cat /proc/[0-9]*/environ /proc/[0-9]*/cmdline 2>/dev/null' >"$dump"
  [ "$(wc -c <"$dump")" -gt 1000000 ]
}
scan() { # label
  dump_box || { bad "$1: dump too small to trust ($(wc -c <"$dump") bytes)"; return; }
  if grep -aqF -f "$pats" "$dump"; then bad "$1: a real token is inside the box"; else ok "$1: no real token in files, env or argv"; fi
}

step "new $NAME"
"$BOX" new "$NAME" || { bad "box new"; finish; }

# Canary: plant a fake secret in a file and in a process environment, and make sure the scan finds both.
step "canary: does the scan see a planted secret?"
canary="CANARY-$RANDOM$RANDOM$RANDOM-file"; envcanary="CANARY-$RANDOM$RANDOM$RANDOM-env"
bx "echo $canary > ~/canary.txt; (CANARYVAR=$envcanary nohup sleep 600 >/dev/null 2>&1 &)"
dump_box || bad "canary dump too small"
printf '%s\n' "$canary" >"$pats.c"; grep -aqF -f "$pats.c" "$dump" && ok "scan finds a planted file secret" || bad "scan MISSED a planted file secret"
printf '%s\n' "$envcanary" >"$pats.c"; grep -aqF -f "$pats.c" "$dump" && ok "scan finds a planted env secret" || bad "scan MISSED a planted env secret"
rm -f "$pats.c"; bx 'rm -f ~/canary.txt; pkill -f "sleep 600"' || true

scan "after new"

step "reset to current main"
sha="$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)"
"$BOX" reset "$NAME" --to "$sha" || { bad "box reset"; finish; }
scan "after reset"
finish
