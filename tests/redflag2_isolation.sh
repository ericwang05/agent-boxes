#!/usr/bin/env bash
# Red flag 2: the box cannot reach the Mac, LAN, other ports, IPv6 or root, after new AND after reset.
. "$(dirname "$0")/lib.sh"

iso() { # label
  step "isolation $1"
  check "$1: box reachable (else every block below is meaningless)" bx true
  check "$1: web (443) works" bx 'curl -s -m 8 -o /dev/null https://github.com'
  check "$1: 192.168.1.1 blocked" box_fails 'curl -s -m 3 -o /dev/null http://192.168.1.1'
  check "$1: 10.0.0.1 blocked" box_fails 'curl -s -m 3 -o /dev/null http://10.0.0.1'
  check "$1: 172.16.0.1 blocked" box_fails 'curl -s -m 3 -o /dev/null http://172.16.0.1'
  check "$1: the Mac (host.orb.internal) blocked" box_fails 'curl -s -m 3 -o /dev/null http://host.orb.internal'
  # Only ports that are open on the internet prove the firewall is what blocks them, so check from the Mac first.
  for hp in github.com:22 smtp.gmail.com:587; do
    h="${hp%:*}"; p="${hp#*:}"
    if to 6 bash -c "echo > /dev/tcp/$h/$p" 2>/dev/null; then check "$1: $hp (open from the Mac) blocked" box_fails "timeout 4 bash -c 'echo > /dev/tcp/$h/$p'"
    else skip "$1: $hp is not reachable from the Mac either"; fi
  done
  check "$1: IPv6 blocked" box_fails 'curl -6 -s -m 4 -o /dev/null https://ipv6.google.com'
  check "$1: sudo blocked" box_fails 'sudo -n true'
  check "$1: no host mounts" box_fails 'mount | grep -qE "/Users|mnt/mac|virtiofs"'
  check "$1: managed settings root-owned" bx 'test "$(stat -c %U /etc/claude-code/managed-settings.json)" = root'
  check "$1: agent cannot edit managed settings" box_fails 'echo {} >> /etc/claude-code/managed-settings.json'
}

mkbox
iso "after new"
step "reset"
"$BOX" reset "$NAME" --to "$(gh api "repos/$OWNER/$NAME/commits/main" --jq .sha)" || bad "reset"
iso "after reset"
finish
