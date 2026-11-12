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
  check "$1: github port 22 blocked" box_fails 'timeout 4 bash -c "echo > /dev/tcp/github.com/22"'
  check "$1: github port 8443 blocked" box_fails 'timeout 4 bash -c "echo > /dev/tcp/github.com/8443"'
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
