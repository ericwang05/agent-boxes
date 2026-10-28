# agent-boxes

One command gives a Claude Code agent its own disposable Linux machine, a GitHub repo and a Nix dev shell, walled off from my Mac. I watch and talk to every agent from one herdr window.

```sh
box new myapp --python 3.12
```

**Scope:** this repo only builds the environment: the repo, the dev shell, the isolated machine and the herdr connection. It deliberately sets no agent behavior. Workflow rules, the definition of done and any reviewer or judge agents belong to each project or to separate skills.

## What `box new` does

1. **Repo.** It creates `github.com/<owner>/<name>` with:
   - a Nix flake dev shell (`flake.nix`, `flake.lock`, `.envrc`) and a `.gitignore`
   - a minimal ruleset that blocks force-pushes and deletion of `main`, so history can't be erased
   - a `tag` workflow that publishes every merge to `main` as a named GitHub Release, for example `merge-12: add parser (#7)`, so known-good versions are easy to find
2. **Agent access.** It invites the agent's GitHub account as a write collaborator on that repo.
3. **Box.** It clones the prebuilt OrbStack machine `box-base`, then:
   - isolates it: no shared folders, no host access, no `sudo`, and CPU and memory limits
   - installs the firewall and checks it
   - injects two tokens
4. **Inside the box.** It clones the repo and approves its `.envrc`, so the dev shell's tools are on the PATH the moment a shell opens there. It also pre-accepts Claude Code's folder-trust prompt.
5. **herdr.** It registers the box as a herdr machine and opens a Claude Code pane in the repo, optionally sending a first message with `--prompt "..."`.

If any step fails after the repo is created, `box new` removes the box, the herdr entry and the repo, so the same name can be rerun.

## Commands

| Command | What it does |
| --- | --- |
| `box new <name> [--python 3.12] [--node 22] [--packages "a b"] [--prompt "..."]` | new repo + box + herdr pane |
| `box reset <name> [--ref <commit-or-tag>]` | fresh box for an **existing** repo, optionally starting from a known-good version |
| `box rm <name>` | delete the box only (repo and access untouched) |
| `box retire <name>` | project finished: delete the box, remove it from herdr, revoke the agent's access to the repo (repo stays) |
| `box destroy <name>` | after a y/N prompt: retire, then delete the repo. Handles the `delete_repo` scope itself |
| `box versions <name>` | list named versions (`merge-<n>`), with titles and dates |
| `box base` | build (or rebuild) `box-base`, then apply `box/pstack-config/` to its `~/.claude` |
| `box save-pstack` | copy the pstack config files from `box-base` into `box/pstack-config/`, to capture them once |
| `box ls` | list boxes |
| `box --dry-run <command>` | print every step without running anything |

## Isolation model

| From inside a box | Allowed? | Enforced by |
| --- | --- | --- |
| Internet (IPv4) | yes | the box's own gateway and DNS |
| My Mac | no | OrbStack `--isolated`, plus the firewall |
| My home network | no | nftables firewall (root-owned) |
| Other boxes | no (best effort) | nftables rejects OrbStack's internal ranges |
| IPv6 | no | nftables |
| `sudo` / undoing the firewall | no | sudo grant removed at creation |
| My files, SSH keys, SSH agent | no | no mounts, `ForwardAgent no` |

**Credentials in a box: exactly two.**
- **The agent GitHub account's classic token,** scope `public_repo` only, exported as `GH_TOKEN` from a 600 file sourced by `~/.bashrc`. It can push only to repos the account was invited to, and it can't change CI.
- **A Claude Code token** from `claude setup-token`, which can make model requests and nothing else.

The base image holds no credentials. Commits are authored as me, so they count toward my contribution graph, and they're pushed by the agent account.

**Inside the box the agent can:**
- add system tools by editing `flake.nix`
- add Python packages with `uv add`

Nix builds in its own sandbox, and the agent can't add untrusted binary caches.

## One-time setup

1. **Install the Mac side.** You need OrbStack (`brew install orbstack`; choose Linux), herdr and `gh`, with `gh` logged in as the repo owner.
2. **Create the agent account.** Make a separate GitHub account and give it a classic token with only `public_repo` and a 90-day expiry. Save the token to `~/agent-boxes/.agent-token` (`chmod 600`).
3. **Create the Claude token.** Run `claude setup-token` and save the result to `~/agent-boxes/.claude-token` (`chmod 600`).
4. **Write the config file** at `~/.config/agent-boxes/config`:
   ```
   OWNER=<github user>
   GIT_NAME=<name>
   GIT_EMAIL=<id>+<user>@users.noreply.github.com
   AGENT=<agent github user>
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
6. **Build the base:** `box base`. To capture your pstack settings once: `ssh box-base@orb`, run `/pstack:setup-pstack` in `claude`, exit, `orb stop box-base`, then `box save-pstack` and commit `box/pstack-config/`. Every later `box base` applies them.
7. **Put `box` on your PATH:** `ln -s ~/agent-boxes/bin/box ~/.local/bin/box`

See [PLAYBOOK.md](PLAYBOOK.md) for day-to-day use and what to do when something goes wrong.

## Layout

| Path | What |
| --- | --- |
| `bin/box` | Mac-side CLI: repo, invite, box, herdr, versions, base |
| `box/sandbox` | box layer: `base`, `new`, `exec`, `rm`, `ls` |
| `box/pstack-config/` | pstack settings copied into the base by `box base` |
| `box/setup.sh` | provisions `box-base`: Nix, direnv, herdr, Claude Code, pstack, firewall |

## Safety rules

- **Never set `ForwardAgent yes`** for `orb`.
- **Never run agent-written code on the Mac.** Don't run git hooks, `.envrc`, `npm install` or similar on the Mac from a repo an agent wrote. Use a box.
- **No agent works unattended in this repo.** It's the factory that builds every box.

## Credits

The isolation approach was inspired by [phasesoftware/sandbox](https://github.com/phasesoftware/sandbox). This code was written separately.
