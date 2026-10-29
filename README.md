# agent-boxes

**One command gives Claude Code its own isolated Linux box, a GitHub repo and a Nix dev shell. I open it in herdr and start working.**

> 📘 **How do I...? → [PLAYBOOK.md](PLAYBOOK.md)** covers starting projects, fixing problems and changing the setup.

```sh
box new myapp      # repo + box + herdr workspace, ready in about a minute
```

## Commands

| Command | Use it when |
| --- | --- |
| `box new <name>` | starting a project: new repo, box, short-lived GitHub token |
| `box new <name> --repo <owner/name>` | putting a box on a repo that already exists (the repo is not changed) |
| `box new <name> --repos <owner/name>,...` | a new project whose box also needs tokens for those other repos |
| `box new <name> --classic` | the legacy agent-account token instead of GitHub App tokens |
| `box reset <name> [--ref <commit>]` | a box is broken or confused: fresh box, same repo (optionally from an older commit) |
| `box rm <name>` | you want the box gone, but the repo and access kept |
| `box retire <name>` | a project is finished: box gone, no more tokens for it, repo kept |
| `box destroy <name>` | throwing a project away entirely, repo included (asks first; refuses boxes attached to an existing repo) |
| `box panic` | something looks wrong: stops the token refresher and every box |
| `box ls` | listing boxes |
| `box base` | rebuilding the base image (monthly, or after changing `box/claude/`) |
| `box --dry-run <command>` | previewing every step without doing anything |

## What you get

- **A public GitHub repo** with an empty Nix flake (`flake.nix`, `.envrc`, `flake.lock`). `main` only changes through a pull request that needs one approval (you can merge your own), and nobody can push to it directly, force-push it or delete it. Agents open pull requests; you review and merge.
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
- **A GitHub App token** that lasts 1 hour, can only reach that box's own repo (Contents and Pull requests write; no workflows, no admin), and is replaced by the Mac every 30 minutes. The box never calls the Mac, and the App's private key never leaves the Mac. The token sits in `/run/agent/gh-token`, which the agent can read but not change.
- **A Claude Code token** that can only make model requests. It lasts about a year.

The base image itself holds none. Commits are authored by the App's bot identity.

Because the App is installed on all of your repositories, **the per-box registry in `~/.config/agent-boxes/box-repos/` is what limits a box to its own repo.** Only the Mac writes it. Boxes cannot read or change it.

## One-time setup

1. **Install:** OrbStack (`brew install orbstack`, then choose Linux), herdr and `gh`. Log `gh` in as yourself, then run `gh auth refresh -s delete_repo`.
2. **GitHub App:** create one on your account with repository permissions **Contents: read and write**, **Pull requests: read and write**, **Metadata: read** and nothing else (no Workflows, no Administration). Install it on **All repositories** (only if all of them are fine for an agent token to reach) and generate a private key. Then save:
   - `~/.config/agent-boxes/app.conf` with `APP_ID=`, `CLIENT_ID=` and `INSTALLATION_ID=`
   - the key as `~/.config/agent-boxes/app.pem`, then `chmod 600` both. Keep this folder out of iCloud, Dropbox and any cloud backup.
3. **Claude token:** run `claude setup-token`, save the result to `~/agent-boxes/.claude-token` and `chmod 600` it. It expires after about a year, so set a calendar reminder.
4. **Config file** `~/.config/agent-boxes/config`. Quote any value that contains a space:
   ```sh
   OWNER="<your github user>"
   GIT_NAME="<your name>"
   GIT_EMAIL="<id>+<user>@users.noreply.github.com"
   AGENT="<agent github user>"
   BOX_CPUS=4
   BOX_MEMORY_MIB=8192
   ```
   `AGENT` and `GIT_*` are only used by the legacy `--classic` path (see below), but the file must still set them.
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
7. **Token refresher (launchd):** without it, tokens expire after an hour.
   ```sh
   mkdir -p ~/Library/Logs/agent-boxes ~/Library/LaunchAgents
   ~/agent-boxes/bin/box-refresh --print-plist > ~/Library/LaunchAgents/dev.agent-boxes.refresh.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/dev.agent-boxes.refresh.plist
   ```
   It logs only box names, repos and expiry to `~/Library/Logs/agent-boxes/refresh.log`. To remove it: `launchctl bootout gui/$(id -u)/dev.agent-boxes.refresh`.

### Legacy: the agent account (`--classic`)

`box new <name> --classic` still uses a separate GitHub account with a classic token scoped `public_repo` and `repo:invite` (90-day expiry, saved to `~/agent-boxes/.agent-token`) that is invited to each repo as a collaborator. It stays until the App path has run a few clean overnight sessions; then it can go.

## Customizing boxes

Everything Claude-related inside boxes comes from **`box/claude/`**, which is copied into the base by `box base`:

| File | What it controls |
| --- | --- |
| `box/claude/settings.json` | plugins (`enabledPlugins` plus their `extraKnownMarketplaces`), permission mode, other Claude settings |
| `box/claude/rules/` | optional rule files copied into every box |
| `box/claude/CLAUDE.md` | optional instructions for every box agent |

Change a file, commit, run `box base`, and new boxes get it. **Never put tokens here:** this repo is public, and `box base` refuses to run if it finds anything that looks like one.

The base also installs `nodejs` (see `box/setup.sh`) because several plugins run node in their hooks and Claude Code itself ships without it.

## Layout

| Path | What |
| --- | --- |
| `bin/box` | the `box` command |
| `bin/box-mint` | mints a 1-hour GitHub App token for the repos in a box's registry file |
| `bin/box-refresh` | the refresher: pushes fresh tokens into running boxes (run by launchd) |
| `bin/box-verify` | security check of a box's GitHub access; only runs against the throwaway repos `test`, `test2`, `test3` |
| `box/sandbox` | creates, checks and deletes machines |
| `box/setup.sh` | what the base image installs |
| `box/app-token.sh` | installs the token tools in a new box (`install-token`, git credential helper, `gh` wrapper) |
| `box/claude/` | Claude settings and plugins for every box |

## Rules to keep

- **Never set `ForwardAgent yes`** for `orb`.
- **Never run agent-written code on your Mac.** That includes git hooks, `.envrc` and `npm install`. Use a box.
- **Never print, paste or commit** a token, the App's private key or `app.conf`.
- **No agent works unattended in this repo.** It builds every box.

Inspired by [phasesoftware/sandbox](https://github.com/phasesoftware/sandbox). MIT licensed.
