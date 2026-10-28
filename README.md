# agent-boxes

> **Day-to-day use and troubleshooting: see [PLAYBOOK.md](PLAYBOOK.md).**

One command gives a Claude Code agent its own disposable Linux machine, a GitHub repo and a Nix dev shell, walled off from my Mac. I watch and talk to every agent from one herdr window.

```sh
box new myapp --python 3.12
```

**Scope:** this repo builds the environment only: the repo, the dev shell, the isolated machine and the herdr connection. It deliberately sets no agent behavior. Workflow rules, the definition of done and any reviewer or judge agents belong to each project or to separate skills. It's built for Claude Code only.

## What `box new` does

1. **Repo.** It creates `github.com/<owner>/<name>` (public) with:
   - a Nix flake dev shell (`flake.nix`, `flake.lock`, `.envrc`) and a `.gitignore`
   - a minimal ruleset that blocks force-pushes and deletion of `main`, so history can't be erased; the repo admin can bypass it
   - a `tag` workflow that publishes every push to `main` as a GitHub Release named `merge-<n>`, titled with the PR, so known-good versions are easy to find
2. **Agent access.** It invites the agent's GitHub account as a write collaborator.
3. **Box.** It clones the prebuilt OrbStack machine `box-base` and sets up the clone:
   - isolates it, with CPU and memory limits
   - installs the firewall and checks isolation: the internet must work, while the host and home network must be blocked
   - injects the two tokens and removes `sudo`
4. **Inside the box.** It accepts the invite, matched by repo ID, confirms the agent can push, clones the repo, runs `direnv allow`, and pre-accepts Claude Code's folder-trust prompt.
5. **herdr.** It registers the box as a herdr machine and opens a Claude Code pane in the repo, optionally sending `--prompt "..."` as the first message.

If any step fails after the repo is created, `box new` rolls back: it removes the box, the herdr entry and the repo. Set `BOX_KEEP=1` to keep everything for debugging instead.

## Commands

| Command | What it does |
| --- | --- |
| `box new <name> [--python 3.12] [--node 22] [--packages "a b"] [--prompt "..."]` | new repo + box + herdr pane |
| `box reset <name> [--ref <commit-or-tag>]` | fresh box for an **existing** repo, optionally at a known-good version |
| `box rm <name>` | delete the box only |
| `box retire <name>` | project finished: delete the box and herdr entry, and revoke the agent's access. The repo stays |
| `box destroy <name>` | delete everything, **including the repo** (asks to confirm) |
| `box versions <name>` | list `merge-<n>` versions with titles and dates |
| `box ls` | list boxes |
| `box base` | rebuild `box-base` and apply the saved pstack config |
| `box save-pstack` | copy pstack's config from `box-base` into `box/pstack-config/` |
| `box --dry-run <command>` | print every step without running anything |

## Isolation model

| From inside a box | Allowed? | Enforced by |
| --- | --- | --- |
| Internet (IPv4) | yes | the box's own gateway and DNS |
| My Mac | no | OrbStack `--isolated`, plus the firewall |
| My home network | no | nftables firewall (root-owned, regenerated at boot) |
| Other boxes | no (best effort) | nftables rejects OrbStack's internal ranges |
| IPv6 | no | nftables |
| `sudo` / undoing the firewall | no | sudo grant removed at creation |
| My files, SSH keys, SSH agent | no | no mounts, `ForwardAgent no` |

**Credentials in a box: exactly two.**
- **The agent GitHub account's classic token,** scopes `public_repo` and `repo:invite`. It can push only to repos the account was invited to, can accept invites, and can't change CI.
- **A Claude Code token** from `claude setup-token`, which can make model requests and nothing else.

The base image holds no credentials. Commits are authored as me (so they count toward my contribution graph) and pushed by the agent account. Inside a box, the agent adds system tools by editing `flake.nix` and Python packages with `uv add`. Nix builds in its own sandbox, and the agent can't add untrusted binary caches.

## One-time setup

1. **Install the Mac side.** You need OrbStack (`brew install orbstack`; choose Linux), herdr and `gh`, logged in as the repo owner. Give `gh` the delete permission once with `gh auth refresh -s delete_repo`, so `destroy` and rollback work without extra logins.
2. **Create the agent account.** Make a separate GitHub account and give it a classic token with **`public_repo` and `repo:invite` only** and a 90-day expiry. Save it to `~/agent-boxes/.agent-token` (`chmod 600`).
3. **Create the Claude token.** Run `claude setup-token` and save the result to `~/agent-boxes/.claude-token` (`chmod 600`).
4. **Write the config file** at `~/.config/agent-boxes/config`. It's read as shell code, so quote values that contain spaces:
   ```sh
   OWNER="<github user>"
   GIT_NAME="<your name>"
   GIT_EMAIL="<id>+<user>@users.noreply.github.com"
   AGENT="<agent github user>"
   BOX_CPUS=4
   BOX_MEMORY_MIB=8192
   ```
5. **Add the SSH entry** to `~/.ssh/config`:
   ```
   Host orb
     HostName 127.0.0.1
     Port 32222
     User default
     IdentityFile ~/.orbstack/ssh/id_ed25519
     IdentitiesOnly yes
     ForwardAgent no
   ```
6. **Build the base:** `box base`. The first time, also run `ssh box-base@orb`, start `claude`, run `/pstack:setup-pstack`, exit, then `box save-pstack`, so future rebuilds apply your choices automatically.
7. **Put `box` on your PATH:** `ln -s ~/agent-boxes/bin/box ~/.local/bin/box`

## Layout

| Path | What |
| --- | --- |
| `bin/box` | Mac-side CLI: repo, invite, box lifecycle, herdr, versions |
| `box/sandbox` | box layer: `base`, `new`, `exec`, `rm`, `ls` |
| `box/setup.sh` | provisions `box-base`: Nix, direnv, herdr, Claude Code, pstack, firewall |
| `box/pstack-config/` | saved pstack settings applied by `box base` |

## Safety rules

- **Never set `ForwardAgent yes`** for `orb`.
- **Never run agent-written code on the Mac.** Don't run git hooks, `.envrc`, `npm install` or similar on the Mac from a repo an agent wrote. Use a box.
- **No agent works unattended in this repo.** It's the factory that builds every box.

## Credits

The isolation approach was inspired by [phasesoftware/sandbox](https://github.com/phasesoftware/sandbox). This code was written separately.
