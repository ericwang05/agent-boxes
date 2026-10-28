# agent-boxes

> **Day-to-day use and troubleshooting: see [PLAYBOOK.md](PLAYBOOK.md).**

One command gives a Claude Code agent its own disposable Linux machine, a GitHub repo and a Nix dev shell, walled off from my Mac. I watch and talk to every agent from one herdr window.

```sh
box new myapp
```

**Scope:** this repo builds the environment only: the repo, an empty dev shell, the isolated machine and the herdr connection. It starts no agent and sets no agent behavior beyond the Claude Code config you put in `box/claude/`. Workflow rules, the definition of done and any reviewer or judge agents belong to each project or to separate skills. It's built for Claude Code only.

## What `box new` does

1. **Repo.** It creates `github.com/<owner>/<name>` (public) with:
   - an empty Nix flake dev shell for `aarch64-linux` and `x86_64-linux` (`flake.nix`, `flake.lock`, `.envrc`) and a `.gitignore`
   - a minimal ruleset that blocks force-pushes and deletion of `main`, so history can't be erased; the repo admin can bypass it
2. **Agent access.** It invites the agent's GitHub account as a write collaborator.
3. **Box.** It clones the prebuilt OrbStack machine `box-base` and sets up the clone:
   - isolates it, with CPU and memory limits
   - installs the firewall, removes `sudo`, then checks isolation (all checks are fatal): the internet must work; the host, the home network and `sudo` must be blocked; no host files may be mounted
   - injects the two tokens, only after the checks pass
4. **Inside the box.** It accepts the invite, matched by repo ID, confirms the agent can push, clones the repo, runs `direnv allow`, and pre-accepts Claude Code's folder-trust prompt.
5. **herdr.** It registers the box as a herdr machine and creates one workspace at `~/<name>`. No agent is started; open Claude Code in that workspace yourself.

If any step fails after the repo is created, `box new` rolls back: it removes the box, the herdr entry and the repo. Set `BOX_KEEP=1` to keep everything for debugging instead.

## Commands

| Command | What it does |
| --- | --- |
| `box new <name>` | new repo + box + herdr workspace |
| `box reset <name> [--ref <commit>]` | fresh box for an **existing** repo, optionally at a known-good commit |
| `box rm <name>` | delete the box only |
| `box retire <name>` | project finished: delete the box and herdr entry, and revoke the agent's access. The repo stays |
| `box destroy <name>` | delete everything, **including the repo** (asks to confirm) |
| `box ls` | list boxes |
| `box base` | rebuild `box-base` and apply `box/claude/` to it |
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
| My files, SSH keys, SSH agent | no | no mounts (checked at creation), `ForwardAgent no` |

**Credentials in a box: exactly two.**
- **The agent GitHub account's classic token,** scopes `public_repo` and `repo:invite`. It can push only to repos the account was invited to, can accept invites, and can't change CI.
- **A Claude Code token** from `claude setup-token`, which can make model requests and nothing else.

The base image holds no credentials. Commits are authored as me (so they count toward my contribution graph) and pushed by the agent account. Inside a box, the agent adds tools by editing the `packages` list in `flake.nix`. Nix builds in its own sandbox, and the agent can't add untrusted binary caches.

## Claude config

`box/claude/` is the Claude Code config every box starts with. `box base` copies it into the base's `~/.claude`:

| Path | What |
| --- | --- |
| `box/claude/settings.json` | merged into the base's `settings.json` with `jq`. Holds permission defaults, `enabledPlugins` and `extraKnownMarketplaces` |
| `box/claude/rules/` | copied to `~/.claude/rules/` |
| `box/claude/CLAUDE.md` | optional; copied to `~/.claude/CLAUDE.md` |

For every key in `enabledPlugins`, `box base` runs `claude plugin marketplace add` for its marketplace (looked up in `extraKnownMarketplaces`) and `claude plugin install <plugin>`. To add a plugin, edit `box/claude/settings.json`, then run `box base`. Never put tokens in `box/claude/`; `box base` refuses if it finds one.

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
6. **Build the base:** `box base`. It also applies `box/claude/`.
7. **Put `box` on your PATH:** `ln -s ~/agent-boxes/bin/box ~/.local/bin/box`

## Layout

| Path | What |
| --- | --- |
| `bin/box` | Mac-side CLI: repo, invite, box lifecycle, herdr, Claude config |
| `box/sandbox` | box layer: `base`, `new`, `exec`, `rm`, `ls` |
| `box/setup.sh` | provisions `box-base`: Nix, direnv, herdr, Claude Code, firewall |
| `box/claude/` | Claude Code config applied by `box base` |

## Safety rules

- **Never set `ForwardAgent yes`** for `orb`.
- **Never run agent-written code on the Mac.** Don't run git hooks, `.envrc`, `npm install` or similar on the Mac from a repo an agent wrote. Use a box.
- **No agent works unattended in this repo.** It's the factory that builds every box.

## Credits

The isolation approach was inspired by [phasesoftware/sandbox](https://github.com/phasesoftware/sandbox). This code was written separately.
