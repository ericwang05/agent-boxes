# agent-boxes

`box new myapp` makes a locked GitHub repo and an isolated Linux box, and opens a herdr pane inside the box with Claude Code running. You type the task there. The agent works in bypass mode, opens a PR as the bot `eric-code-agent`, and you review and merge on GitHub. If something goes wrong, `box reset myapp --to <commit|pr/N|status/N>` rebuilds the box at that point.

Compared with plain herdr plus Claude Code it adds four things: an isolated box, real tokens that never enter the box, a locked `main`, and reset to a saved point.

```
MAC                                              BOX (one per project, OrbStack --isolated)
box CLI (plain bash, no AI)                      repo + Nix dev shell, Claude Code with FAKE tokens
proxy.py per box (real tokens from Keychain)     ANTHROPIC_BASE_URL=http://localhost:8080
   ^ unix socket per box                         git insteadOf (own repo only) -> localhost:8080
   +---- Go bridge (yamux over orb run) -------> localhost:8080 (bridge, box side)
herdr: one pane per box                          firewall: no Mac, no LAN, no IPv6; only ports 53, 80, 443 out
status log copy (append-only)  <-- orb run cat -- ~/.box/status.log (agent appends with box-note)
```

## Commands

| Command | Does |
|---|---|
| `box new NAME [--repo owner/name]` | Create (or attach) the repo, lock main, make the box, start its proxy and bridge, open the herdr pane |
| `box status [NAME] [--history]` | One row per box: state, last task, commit, PR link, time. `--history` numbers every entry (`status/N`) |
| `box reset NAME --to <commit\|pr/N\|status/N>` | Delete the box and rebuild it at that commit. Packages come back through `flake.lock` |
| `box rm NAME` | Delete the box, its proxy and bridge. The repo and status history stay |
| `box panic` | Stop every box, bridge and proxy now |
| `box base` | Rebuild `box-base`, the bridge binaries, and apply `box/claude` |
| `box ls` | List machines |

## One-time setup

1. `brew install go`, install OrbStack and herdr; `gh auth login` as the repo owner.
2. `~/.config/agent-boxes/config`: `OWNER=`, `AGENT=` (the bot's GitHub login), `GIT_NAME=`, `GIT_EMAIL=`.
3. Keychain (service names are fixed): `agentbox-claude` (from `claude setup-token`) and `agentbox-github` (the bot's classic token, scopes `repo`). Nothing else holds the real tokens.
4. `~/.ssh/config` entry `Host orb` (the error message from `box new` prints it).
5. `bin/box base`, then put `bin/box` on your PATH.

## What protects what

| Threat | Control |
|---|---|
| Real token leaks from a box | Boxes hold fake tokens; the per-box proxy swaps in the real one. Verified: no real token in a box, argv or log |
| Agent writes to another repo or merges | Proxy: own repo only; REST allow-list (read, open or edit a PR, comment); GraphQL refused. GitHub: `main` ruleset with no bypass and 1 required approval, so only you merge |
| Box reaches your Mac or home network | OrbStack `--isolated` plus a root-owned nftables file: LAN, private ranges, multicast, IPv6 rejected; only 53, 80, 443 out. No sudo |
| Agent edits Claude's settings | `/etc/claude-code/managed-settings.json` is root-owned |
| Secrets pushed to GitHub | GitHub secret scanning and push protection on every repo `box new` makes |
| Install scripts and brand-new packages | A request in the box `CLAUDE.md` (no install scripts, nothing newer than 7 days). Not enforced |

## Accepted gaps

- With 80/443 open the agent can still send repo code anywhere. The design protects **tokens, not data**. The repos are public anyway.
- An injected agent could misuse your home internet address over 80/443 (for example hammering a website).
- "If anything is unclear or blocked, stop and ask" and the 7-day package rule in the box `CLAUDE.md` are requests, not controls.
- Apple Silicon Macs only (the box bridge is built for arm64).
- A repo attached with `--repo` gets no ruleset or bot invite from `box new`; set up `protect-main` and the bot's write access by hand.
- Pro usage is the real cap on parallel boxes.
- With the Mac asleep or the proxy down, Claude shows its own error and stops after about 3 minutes.
- Claude shows "Remote managed settings failed to load (401)" in every pane: its policy call goes direct with a fake token. Harmless.

## Stretch goals (not built)

DNS tunnelling, narrowing the DHCP rule (`udp dport 67`) to the box gateway, a size cap on proxy request bodies, a marketplace allow-list for plugins, fine-grained GitHub tokens in an org, a `gh pr create` wrapper, hooks that write status lines, Mac notifications, rotating fake tokens.

## Layout

- `bin/box` the CLI. `box/sandbox` makes boxes; `box/setup.sh` builds the base; `box/firewall.nft`, `box/managed-settings.json`, `box/box-note` are installed into every box; `box/claude/` is the agent's `~/.claude` (CLAUDE.md, plugins).
- `proxy/proxy.py` the per-box proxy (Python stdlib, one file). `bridge/` the Go bridge (frozen; built into `build/` by `box base`).
- Mac state in `~/.config/agent-boxes/`: `config`, `box-repos/` (box to repo), `run/` (sockets, mode 700), `logs/` (JSON lines from the proxy; no header values), `status/` (append-only copies of each box's status log).
- launchd jobs `dev.agent-boxes.<box>-proxy` and `-bridge` in `~/Library/LaunchAgents`, written by `box new`, removed by `box rm` and `box panic`.
- `MVP-HANDOFF.md` records the design decisions. The earlier GitHub App flow is on branch `app-token`.

## Rules to keep

- Real tokens never enter a box, a log, argv or a file other than Keychain.
- No path from a box to the Mac except the bridge socket and the Mac-started `orb run`.
- Keep the proxy small and in one file; don't change the bridge unless a test fails.
