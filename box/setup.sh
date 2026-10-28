#!/usr/bin/env bash
# setup.sh - provision a fresh Debian OrbStack machine as an agent box.
# Run as root with SETUP_USER and AGENT_TOKEN set (the sandbox script does this).
set -euo pipefail
: "${SETUP_USER:?}" "${AGENT_TOKEN:?}"
home="/home/$SETUP_USER"
as_user() { runuser -u "$SETUP_USER" -- bash -lc "$1"; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    git curl ca-certificates jq ripgrep less procps unzip nftables sudo

# --- Determinate Nix: multi-user daemon, so the sandbox user needs no sudo ---
curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux --no-confirm
cat > /etc/profile.d/nix-path.sh << 'EOP'
export PATH="$PATH:/nix/var/nix/profiles/default/bin:$HOME/.local/bin"
EOP

# --- herdr (user install) + Claude integration ---
as_user 'curl -fsSL https://herdr.dev/install.sh | sh'
as_user 'herdr integration install claude'

# --- Claude Code (native installer) + pstack plugin ---
as_user 'curl -fsSL https://claude.ai/install.sh | bash'
as_user 'claude plugin marketplace add cursor/plugins && claude plugin install pstack@cursor-plugins'

# Merge, not overwrite: the plugin/integration steps above already wrote settings.
install -d -o "$SETUP_USER" -g "$SETUP_USER" "$home/.claude"
s="$home/.claude/settings.json"; [ -s "$s" ] || echo '{}' > "$s"
jq '.permissions.defaultMode = "bypassPermissions" | .skipDangerousModePermissionPrompt = true' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
[ -s "$home/.claude.json" ] || echo '{"hasCompletedOnboarding": true}' > "$home/.claude.json"
chown -R "$SETUP_USER:$SETUP_USER" "$home/.claude" "$home/.claude.json"

# --- Git identity + credentials (agent account's classic token) ---
git config --system user.name  "Eric Wang"
git config --system user.email "45795682+ericwang05@users.noreply.github.com"
git config --system credential.helper store
printf 'https://x-access-token:%s@github.com\n' "$AGENT_TOKEN" > "$home/.git-credentials"
chown "$SETUP_USER:$SETUP_USER" "$home/.git-credentials"; chmod 600 "$home/.git-credentials"

# --- Egress firewall: allow internet, block LAN ---
# 192.168.138.0/23 and 198.18.0.0/15 are OrbStack's internal ranges (Settings >
# Network); other machines/host there are blocked by --isolate-network.
cat > /etc/nftables.conf << 'EOF2'
#!/usr/sbin/nft -f
flush ruleset
table inet sandbox {
  chain output {
    type filter hook output priority 0; policy accept;
    oifname "lo" accept
    ct state established,related accept
    meta l4proto ipv6-icmp accept
    ip daddr { 192.168.138.0/23, 198.18.0.0/15 } accept comment "orbstack internal"
    ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16,
               169.254.0.0/16, 100.64.0.0/10 } counter reject
    ip6 daddr { fc00::/7, fe80::/10 } counter reject
  }
}
EOF2
systemctl enable --now nftables

apt-get clean
echo "box provisioned"
