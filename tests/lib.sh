#!/usr/bin/env bash
# Shared helpers for the box tests. They use real boxes and real GitHub repos, so run them by hand on the Mac.
# Every box and repo a test creates is named boxtest-*, and cleanup refuses to touch any other name.
# BOX_BIN picks the box CLI to test (default: the one on PATH).
set -uo pipefail

BOX="${BOX_BIN:-$(command -v box || true)}"
[ -x "$BOX" ] || { echo "box CLI not found; set BOX_BIN" >&2; exit 2; }
ROOT="$(cd "$(dirname "$(readlink -f "$BOX")")/.." && pwd)"
SANDBOX="$ROOT/box/sandbox"
CFG="${BOX_CONFIG_DIR:-$HOME/.config/agent-boxes}"
# shellcheck disable=SC1091
. "$CFG/config" # OWNER
LA="$HOME/Library/LaunchAgents"
NAME="boxtest-$(date +%m%d%H%M%S)-$$"
REPO_NAME="$NAME" # the repo's name; differs from the box name only with --repo
EXTRA_REPO=""     # a second repo (owner/name) the test made; cleanup deletes it if it is a boxtest- name
fails=0

ok() { echo "  ok   $*"; }
bad() { echo "  FAIL $*"; fails=$((fails + 1)); }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
step() { echo "== $*"; }
guard() { [[ "${1:-}" == boxtest-* ]] || { echo "refusing to touch '${1:-}': not a boxtest- name" >&2; exit 2; }; }

bx() { "$SANDBOX" exec "$NAME" "$@"; }
state() { "$SANDBOX" ls | awk -v n="$NAME" '$1 == n { print $2 }'; }
is_state() { [ "$(state)" = "$1" ]; }
has_jobs() { [ -e "$LA/dev.agent-boxes.$NAME-proxy.plist" ] && [ -e "$LA/dev.agent-boxes.$NAME-bridge.plist" ]; }
no_jobs() { ! ls "$LA"/dev.agent-boxes."$NAME"-* >/dev/null 2>&1 && [ ! -e "$CFG/run/$NAME.sock" ]; }
head_sha() { bx "cd ~/$REPO_NAME && git rev-parse HEAD" 2>/dev/null | tr -d '[:space:]'; }
# The proxy health endpoint answers 200 only if the whole box -> bridge -> proxy loop works.
bridge_up() { [ "$(bx 'curl -s -m 5 -o /dev/null -w %{http_code} http://localhost:8080/__health')" = 200 ]; }
# Boxes other than box-base and this test's own.
other_running() { "$SANDBOX" ls | awk -v n="$NAME" '$2 == "running" && $1 != "box-base" && $1 != n { print $1 }'; }

box_fails() { ! bx "$@" >/dev/null 2>&1; }
no_herdr_machine() { herdr machine list --json | jq -e --arg l "$NAME" '[.. | objects | select(.label? == $l)] | length == 0' >/dev/null; }
no_procs() { ! pgrep -f "proxy.py --box $NAME" >/dev/null && ! pgrep -f "agentbox-bridge mac-side -box $NAME" >/dev/null; }
require_no_other_boxes() { # box panic stops EVERY box, so refuse to run next to real work
  if [ -n "$(other_running)" ] && [ "${BOX_TEST_ALLOW_PANIC:-}" != 1 ]; then
    echo "refusing: panic would stop these running boxes: $(other_running | tr '\n' ' ')" >&2
    echo "stop them first, or set BOX_TEST_ALLOW_PANIC=1" >&2
    exit 2
  fi
}
# HTTP status of a request made from inside the box to its proxy, with the box's own fake token.
code() { # METHOD PATH [json-body]
  local body="${3-}"; [ -n "$body" ] || body='{}'
  bx ". ~/.box-env; curl -s -m 20 --path-as-is -o /dev/null -w '%{http_code}' -X $1 -H \"Authorization: token \$GH_TOKEN\" -H 'Content-Type: application/json' -d '$body' 'http://localhost:8080$2'"
}
commit_push() { # branch file -> full sha of the new commit, pushed to that branch
  bx "cd ~/$REPO_NAME && git checkout -q -B $1 && echo $2-\$RANDOM > $2 && git add $2 && git commit -qm 'test $2' && git push -q origin $1 2>&1 && git rev-parse HEAD" | tail -1 | tr -d '[:space:]'
}
note() { bx "cd ~/$REPO_NAME && box-note '$1' $2"; } # logs a status line at the box's current HEAD
open_pr() { # branch -> PR number
  bx ". ~/.box-env; curl -s -m 20 -X POST -H \"Authorization: token \$GH_TOKEN\" -d '{\"title\":\"t\",\"head\":\"$1\",\"base\":\"main\"}' http://localhost:8080/ghapi/repos/$OWNER/$REPO_NAME/pulls | jq -r .number"
}
mkbox() { step "new $NAME"; "$BOX" new "$NAME" "$@" || { bad "box new"; finish; }; }

cleanup() {
  guard "$NAME"
  step "cleanup $NAME"
  "$BOX" rm "$NAME" >/dev/null 2>&1
  gh repo delete "$OWNER/$NAME" --yes >/dev/null 2>&1
  if [ -n "$EXTRA_REPO" ]; then guard "${EXTRA_REPO#*/}"; gh repo delete "$EXTRA_REPO" --yes >/dev/null 2>&1; fi
  rm -f "$CFG/box-repos/$NAME.json" "$CFG/status/$NAME.log"
}
trap 'rc=$?; cleanup; exit $rc' EXIT

finish() {
  echo
  if [ "$fails" -eq 0 ]; then echo "PASS"; else echo "FAIL ($fails)"; fi
  exit $((fails > 0))
}
