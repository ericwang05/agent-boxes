#!/usr/bin/env bash
# setup.sh - provision a fresh Debian OrbStack machine as an agent box.
# Run as root with SETUP_USER set (the sandbox script does this). No secrets here:
# `sandbox new` adds the firewall, fake tokens, bridge and git identity per box.
set -euo pipefail
: "${SETUP_USER:?}"
home="/home/$SETUP_USER"
as_user() { runuser -u "$SETUP_USER" -- bash -lc "$1"; }

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
    git curl ca-certificates jq ripgrep less procps unzip nftables sudo gh iproute2
# nodejs is for Claude plugins: several (e.g. ponytail, i-have-adhd) run node in their hooks, and the Claude install is a standalone binary with no node.
apt-get install -y --no-install-recommends nodejs

# --- Determinate Nix: multi-user daemon, so the sandbox user needs no sudo ---
curl -fsSL https://install.determinate.systems/nix | sh -s -- install linux --no-confirm

# --- direnv + nix-direnv, and the shell setup (PATH and token sourcing go above the interactive guard so non-interactive shells get them) ---
as_user 'nix profile install nixpkgs#direnv nixpkgs#nix-direnv'
install -d -o "$SETUP_USER" -g "$SETUP_USER" "$home/.config/direnv"
echo 'source "$HOME/.nix-profile/share/nix-direnv/direnvrc"' > "$home/.config/direnv/direnvrc"
touch "$home/.bashrc"
{
  echo 'export PATH="$HOME/.nix-profile/bin:/nix/var/nix/profiles/default/bin:$HOME/.local/bin:$PATH"'
  echo '[ -f ~/.box-env ] && . ~/.box-env'
  cat "$home/.bashrc"
  echo 'eval "$(direnv hook bash)"'
} > "$home/.bashrc.new"
mv "$home/.bashrc.new" "$home/.bashrc"
chown -R "$SETUP_USER:$SETUP_USER" "$home/.config" "$home/.bashrc"

# --- herdr ---
as_user 'curl -fsSL https://herdr.dev/install.sh | sh'

# --- Claude Code (native installer); settings and plugins come from box/claude via `box base` ---
as_user 'curl -fsSL https://claude.ai/install.sh | bash'

install -d -o "$SETUP_USER" -g "$SETUP_USER" "$home/.claude"
[ -s "$home/.claude.json" ] || echo '{"hasCompletedOnboarding": true}' > "$home/.claude.json"
chown -R "$SETUP_USER:$SETUP_USER" "$home/.claude" "$home/.claude.json"

# Needs ~/.claude to exist, so it runs after the Claude Code install.
as_user 'herdr integration install claude'

# The egress firewall is box/firewall.nft, installed per box by `sandbox new` (nftables is installed above).

apt-get clean
echo "box provisioned"
