#!/usr/bin/env bash
# app-token.sh - install the GitHub App token path in a box. Run as root with SETUP_USER set:
#   orb -m BOX -u root env SETUP_USER=... bash -s < box/app-token.sh
# No secrets here: the token itself arrives later via install-token.
set -euo pipefail
: "${SETUP_USER:?}"
home="/home/$SETUP_USER"
APP_SLUG=agent-token-minter
# TODO(parent): fill from `gh api /users/agent-token-minter%5Bbot%5D --jq .id`; must be numeric
BOT_USER_ID=
[[ "$BOT_USER_ID" =~ ^[0-9]+$ ]] || { echo "error: set BOT_USER_ID in app-token.sh" >&2; exit 1; }

# Root-owned installer: the agent user cannot write /run/agent, so it cannot swap the token.
cat > /usr/local/sbin/install-token <<'EOT'
#!/usr/bin/env bash
# Read ONE installation token from stdin, validate it, publish it atomically. Never echoes the token.
set -euo pipefail
umask 077
dir="${TOKEN_DIR:-/run/agent}"  # TOKEN_DIR is for tests only
data=$(cat; echo x); data=${data%x}
data=${data%$'\n'}  # strip exactly one trailing newline
[[ "$data" != *$'\n'* && "$data" != *$'\r'* ]] || { echo "error: expected exactly one line" >&2; exit 1; }
# length checked apart from the regex: ERE repeat counts are capped (255) on some libcs
[[ "$data" =~ ^ghs_[A-Za-z0-9_]+$ && ${#data} -ge 24 && ${#data} -le 1028 ]] \
  || { echo "error: input is not a ghs_ installation token" >&2; exit 1; }
if [ "$(id -u)" = 0 ]; then install -d -o root -g root -m 755 "$dir"; else mkdir -p "$dir"; fi
tmp=$(mktemp "$dir/.gh-token.XXXXXX")
trap 'rm -f "$tmp"' EXIT
printf '%s\n' "$data" > "$tmp"
if [ "$(id -u)" = 0 ]; then chown root:root "$tmp"; fi
chmod 644 "$tmp"  # agent user must read it
mv -f "$tmp" "$dir/gh-token"
EOT
chown root:root /usr/local/sbin/install-token
chmod 755 /usr/local/sbin/install-token

cat > /usr/local/bin/box-git-credential <<'EOT'
#!/usr/bin/env bash
# git credential helper: serve the current App token (read per call, tokens expire hourly).
set -euo pipefail
[ "${1:-}" = get ] || exit 0
host=
while IFS='=' read -r k v; do if [ "$k" = host ]; then host=$v; fi; done
[ "$host" = github.com ] || exit 0
f="${TOKEN_FILE:-/run/agent/gh-token}"  # override is for tests only
[ -r "$f" ] || { echo "box-git-credential: no token at $f; run seed_token from the host" >&2; exit 1; }
printf 'username=x-access-token\npassword=%s\n' "$(cat "$f")"
EOT
chmod 755 /usr/local/bin/box-git-credential
# System-wide; the agent can still override it in its own git config, which is acceptable.
git config --system credential.https://github.com.helper /usr/local/bin/box-git-credential

# Debian's default PATH lists /usr/local/bin before /usr/bin, so this wrapper wins over apt's gh.
# Verify in the box with `command -v gh` (expect /usr/local/bin/gh).
cat > /usr/local/bin/gh <<'EOT'
#!/usr/bin/env bash
set -euo pipefail
f="${TOKEN_FILE:-/run/agent/gh-token}"  # override is for tests only
[ -r "$f" ] || { echo "gh: no token at $f; run seed_token from the host" >&2; exit 1; }
GH_TOKEN="$(cat "$f")" exec /usr/bin/gh "$@"
EOT
chmod 755 /usr/local/bin/gh

git config --system user.name "${APP_SLUG}[bot]"
git config --system user.email "${BOT_USER_ID}+${APP_SLUG}[bot]@users.noreply.github.com"

# Drop the classic path: token env file, its sourcing line, and the global git settings from
# inject_token that would shadow the system-wide helper and bot identity.
rm -f "$home/.gh-token-env"
if [ -f "$home/.bashrc" ]; then
  grep -v 'gh-token-env' "$home/.bashrc" > "$home/.bashrc.new" || true
  cat "$home/.bashrc.new" > "$home/.bashrc"; rm -f "$home/.bashrc.new"
fi
for k in credential.https://github.com.helper user.name user.email; do
  runuser -u "$SETUP_USER" -- git config --global --unset-all "$k" || true
done
