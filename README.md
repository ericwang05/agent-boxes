# agent-boxes

**One command gives Claude Code its own isolated Linux box, a GitHub repo and a Nix dev shell. I open it in herdr and start working.**

> 📘 **How do I...? → [PLAYBOOK.md](PLAYBOOK.md)** covers starting projects, fixing problems and changing the setup.

```sh
box new myapp      # repo + box + herdr workspace, ready in about a minute
```

## Commands

| Command | Use it when |
| --- | --- |
| `box new <name>` | starting a project |
| `box reset <name> [--ref <commit>]` | a box is broken or confused: fresh box, same repo (optionally from an older commit) |
| `box rm <name>` | you want the box gone, but the repo and access kept |
| `box retire <name>` | a project is finished: box gone, agent's access revoked, repo kept |
| `box destroy <name>` | throwing a project away entirely, repo included (asks first) |
| `box ls` | listing boxes |
| `box base` | rebuilding the base image (monthly, or after changing `box/claude/`) |
| `box --dry-run <command>` | previewing every step without doing anything |

## What you get

- **A public GitHub repo** with an empty Nix flake (`flake.nix`, `.envrc`, `flake.lock`). History is protected: nobody but you can force-push or delete `main`.
- **An isolated box:** an OrbStack Linux machine with Claude Code, herdr and Nix, plus your Claude settings and plugins from `box/claude/`.
- **A herdr workspace** already in the repo. Run `claude` there and you're working. Nothing starts on its own.

That's all. It sets up the environment only. How agents work and what "done" means are decided per project.

## Safety in one table

| From inside a box | Allowed? |
| --- | --- |
| The internet | ✅ |
| Your Mac, its files, SSH keys | ❌ |
| Your home network | ❌ |
| Other boxes | ❌ (best effort) |
| `sudo` / undoing these rules | ❌ |

These are checked automatically every time a box is created. If any check fails, the box isn't created.

**Credentials in a box: only two.**
- **The agent GitHub account's token,** scopes `public_repo` and `repo:invite`. It can push only to repos you've given it.
- **A Claude Code token** that can only make model requests.

The base image itself holds none. Commits are authored as you and pushed by the agent account.

## One-time setup

1. **Install:** OrbStack (`brew install orbstack`, then choose Linux), herdr and `gh`. Log `gh` in as yourself, then run `gh auth refresh -s delete_repo`.
2. **Agent account:** a separate GitHub account with a classic token scoped `public_repo` and `repo:invite`, with a 90-day expiry. Save it to `~/agent-boxes/.agent-token` and `chmod 600` it.
3. **Claude token:** run `claude setup-token`, save the result to `~/agent-boxes/.claude-token` and `chmod 600` it.
4. **Config file** `~/.config/agent-boxes/config`. Quote any value that contains a space:
   ```sh
   OWNER="<your github user>"
   GIT_NAME="<your name>"
   GIT_EMAIL="<id>+<user>@users.noreply.github.com"
   AGENT="<agent github user>"
   BOX_CPUS=4
   BOX_MEMORY_MIB=8192
   ```
5. **SSH entry** in `~/.ssh/config`:
   ```
   Host orb
     HostName 127.0.0.1
     Port 32222
     User default
     IdentityFile ~/.orbstack/ssh/id_ed25519
     IdentitiesOnly yes
     ForwardAgent no
   ```
6. **Build and link:** run `box base`, then `ln -s ~/agent-boxes/bin/box ~/.local/bin/box`.

## Customizing boxes

Everything Claude-related inside boxes comes from **`box/claude/`**, which is copied into the base by `box base`:

| File | What it controls |
| --- | --- |
| `box/claude/settings.json` | plugins (`enabledPlugins` plus their `extraKnownMarketplaces`), permission mode, other Claude settings |
| `box/claude/rules/` | rule files, for example pstack's model choices |
| `box/claude/CLAUDE.md` | optional instructions for every box agent |

Change a file, commit, run `box base`, and new boxes get it. **Never put tokens here:** this repo is public, and `box base` refuses to run if it finds anything that looks like one.

## Layout

| Path | What |
| --- | --- |
| `bin/box` | the `box` command |
| `box/sandbox` | creates, checks and deletes machines |
| `box/setup.sh` | what the base image installs |
| `box/claude/` | Claude settings and plugins for every box |

## Rules to keep

- **Never set `ForwardAgent yes`** for `orb`.
- **Never run agent-written code on your Mac.** That includes git hooks, `.envrc` and `npm install`. Use a box.
- **No agent works unattended in this repo.** It builds every box.

Inspired by [phasesoftware/sandbox](https://github.com/phasesoftware/sandbox). MIT licensed.
