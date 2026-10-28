#!/usr/bin/env bash
# setup.sh - provision a fresh Debian OrbStack machine as an agent box.
# Run as root with SETUP_USER set (the sandbox script does this). No secrets here:
# `sandbox new` injects the agent, Claude tokens and git identity per box.
set -euo pipefail
: "${SETUP_USER:?}"
home="/home/$SETUP_USER"
as_user() { runuser -u "$SETUP_USER" -- bash -lc "$1"; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    git curl ca-certificates jq ripgrep less procps unzip nftables sudo gh iproute2

# --- Determinate Nix: multi-user daemon, so the sandbox user needs no sudo ---
curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux --no-confirm

# --- direnv + nix-direnv, and the shell setup (PATH and token sourcing go above the interactive guard so non-interactive shells get them) ---
as_user 'nix profile install nixpkgs#direnv nixpkgs#nix-direnv'
install -d -o "$SETUP_USER" -g "$SETUP_USER" "$home/.config/direnv"
echo 'source "$HOME/.nix-profile/share/nix-direnv/direnvrc"' > "$home/.config/direnv/direnvrc"
touch "$home/.bashrc"
{
  echo 'export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:$PATH"'
  echo '[ -f ~/.claude-token-env ] && . ~/.claude-token-env'
  cat "$home/.bashrc"
  echo 'eval "$(direnv hook bash)"'
} > "$home/.bashrc.new"
mv "$home/.bashrc.new" "$home/.bashrc"
chown -R "$SETUP_USER:$SETUP_USER" "$home/.config" "$home/.bashrc"

# --- herdr ---
as_user 'curl -fsSL https://herdr.dev/install.sh | sh'

# --- Claude Code (native installer) + pstack plugin ---
as_user 'curl -fsSL https://claude.ai/install.sh | bash'
as_user 'claude plugin marketplace add cursor/plugins && claude plugin install pstack@cursor-plugins'

# Merge, not overwrite: the plugin/integration steps above already wrote settings.
install -d -o "$SETUP_USER" -g "$SETUP_USER" "$home/.claude"
s="$home/.claude/settings.json"; [ -s "$s" ] || echo '{}' > "$s"
jq '.permissions.defaultMode = "bypassPermissions" | .skipDangerousModePermissionPrompt = true' "$s" > "$s.tmp" && mv "$s.tmp" "$s"
[ -s "$home/.claude.json" ] || echo '{"hasCompletedOnboarding": true}' > "$home/.claude.json"
chown -R "$SETUP_USER:$SETUP_USER" "$home/.claude" "$home/.claude.json"

# Needs ~/.claude to exist, so it runs after the Claude Code install.
as_user 'herdr integration install claude'

# --- Egress firewall: allow internet, block LAN ---
# 192.168.138.0/23 and 198.18.0.0/15 are OrbStack's internal ranges. They are
# rejected here like any LAN; `sandbox new` adds back only each box's own
# gateway and DNS, so boxes cannot reach each other.
cat > /etc/nftables.conf << 'EOF2'
#!/usr/sbin/nft -f
flush ruleset
table inet sandbox {
  chain output {
    type filter hook output priority 0; policy accept;
    oifname "lo" accept
    ct state established,related accept
    meta l4proto ipv6-icmp accept
    ip daddr { 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 198.18.0.0/15,
               169.254.0.0/16, 100.64.0.0/10 } counter reject
    ip6 daddr { fc00::/7, fe80::/10 } counter reject
  }
}
EOF2
systemctl enable --now nftables

apt-get clean
echo "box provisioned"
