#!/usr/bin/env bash
# Chain 5: a box new that fails after the repo and jobs exist must roll everything back (README promise).
# We force the failure with a wrapper sandbox whose `new` always fails (BOX_SANDBOX), so no real box is built.
. "$(dirname "$0")/lib.sh"

w="$(mktemp -d)"
trap 'rc=$?; rm -rf "$w"; cleanup; exit $rc' EXIT
cat >"$w/sandbox" <<EOF
#!/usr/bin/env bash
[ "\$1" = new ] && { echo "forced failure" >&2; exit 1; }
exec "$SANDBOX" "\$@"
EOF
chmod +x "$w/sandbox"

step "new with a forced failure"
BOX_SANDBOX="$w/sandbox" "$BOX" new "$NAME"; rc=$?
check "box new exits non-zero" test "$rc" -ne 0
check "repo deleted" bash -c "! gh repo view '$OWNER/$NAME'"
check "no proxy or bridge jobs or socket" no_jobs
check "no proxy or bridge process" no_procs
check "no registry entry" test ! -e "$CFG/box-repos/$NAME.json"
check "no box" test -z "$(state)"
check "no herdr machine" no_herdr_machine
finish
