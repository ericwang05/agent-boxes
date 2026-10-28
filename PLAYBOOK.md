# Playbook

Find what you're trying to do, then run what it says. Commands run on your Mac unless marked **(in the box)**. Setup and design are in the [README](README.md).

**Jump to:**
- [Everyday](#everyday): [start a project](#start-a-project) · [work in a box](#work-in-a-box) · [add tools](#add-tools-to-a-project) · [finish a project](#finish-a-project)
- [When something goes wrong](#when-something-goes-wrong): [agent stuck](#the-agent-is-stuck) · [bad code on main](#bad-code-landed-on-main) · [suspected compromise](#you-suspect-a-box-was-compromised) · [`box new` failed](#box-new-failed) · [stop everything](#stop-everything)
- [Changing the setup](#changing-the-setup): [add a plugin](#add-or-change-a-claude-plugin-or-setting) · [rebuild the base](#rebuild-the-base)
- [Maintenance calendar](#maintenance-calendar) · [Error lookup](#error-lookup) · [Check isolation by hand](#check-isolation-by-hand)

---

## Everyday

### Start a project
```sh
box new myapp
```
Open herdr, press `prefix+w`, pick `myapp`, then run `claude` in its workspace. The first instruction is yours. To start pstack, begin your message with `/pstack:poteto-mode`.

### Work in a box
- **herdr:** every box is in the sidebar, and `prefix+w` switches between them. The agent list shows who's working, idle or waiting on you.
- **A plain shell:** `ssh myapp@orb`.
- **One-off commands that need the project's tools:** `direnv exec . <cmd>` **(in the box, inside the repo)**.
- **Results:** the repo's commits and pull requests on GitHub.

### Add tools to a project
Tell the agent "add `<tool>` to `flake.nix`". For language packages, it uses that language's own tool, such as `uv`, `npm` or `cargo`. The shell reloads by itself.

### Finish a project

| You want | Run |
| --- | --- |
| Keep the repo, revoke the agent | `box retire myapp` |
| Delete everything, repo included | `box destroy myapp` |

---

## When something goes wrong

### The agent is stuck
1. Talk to it in its herdr pane.
2. Still stuck? Get a fresh box with the same repo: `box reset myapp`.

### Bad code landed on main
- **Undo specific commits:** ask an agent to "revert commits `<sha>`…`<sha>` in one PR."
- **Jump back to a good commit.** Find it in the repo's commit history on GitHub, or with `git log`, then:
  ```sh
  git clone https://github.com/<owner>/myapp /tmp/fix && cd /tmp/fix
  git push --force origin <good-commit>:main
  ```
  You're the only one the rules allow to do this. In that clone, run `git push` and nothing else.
- **Fresh box from that commit:** `box reset myapp --ref <good-commit>`.

### You suspect a box was compromised
1. **Stop it:** `orb stop myapp`.
2. **Revoke and replace both tokens.** That's what cuts off anything it copied:
   - **GitHub:** sign in as the agent account → Settings → Developer settings → Tokens (classic) → revoke. Create a new token (`public_repo` and `repo:invite`) and save it to `~/agent-boxes/.agent-token`.
   - **Claude:** revoke the old token in your Claude account settings, then run `claude setup-token` and save the new one to `~/agent-boxes/.claude-token`.
3. **Check what it touched:** recent commits and pull requests in this project, your other box projects, and the agent account's profile.
4. **Fix `main`** if needed (see above), then `box reset myapp --ref <good-commit>`.

### `box new` failed
It cleans up after itself, so just read the error and run it again. To keep a failed box for debugging, use `BOX_KEEP=1 box new myapp`.

### Stop everything
- **One box:** `orb stop <name>`
- **All boxes:** quit OrbStack

---

## Changing the setup

### Add or change a Claude plugin or setting
1. Edit `box/claude/settings.json`: add the plugin under `enabledPlugins` and its marketplace under `extraKnownMarketplaces`. Put rule files in `box/claude/rules/`.
2. Commit, then run `box base`.
3. New boxes have it. For an existing box, run `box reset <name>`.

Plugin settings that differ per project (such as pstack's models) belong in that project, not in `box/claude/`.

### Rebuild the base
```sh
box base
```
This picks up updates to Nix, herdr, Claude Code and your `box/claude/`. Existing boxes keep their old copy until you `box reset` them.

---

## Maintenance calendar

| When | Do |
| --- | --- |
| Monthly | `box base` |
| Every 90 days | The agent token expires. Make a new one, save it to `.agent-token`, then `box reset` active projects |
| Before overnight runs | Keep the Mac plugged in and awake |
| Weekly | Check your Claude plan usage, which all boxes share |
| When a project ends | `box retire` or `box destroy` |

---

## Error lookup

| You see | Fix |
| --- | --- |
| `dial: no such file or directory` | OrbStack isn't running: `open -a OrbStack`, then retry |
| `Could not resolve hostname orb` | Add the `Host orb` entry from the README to `~/.ssh/config` |
| A box looks empty, or `sudo` works | You typed a box name that doesn't exist, and OrbStack connected you to its default machine instead. Check `orb list` |
| `repo … already exists` | Existing project: `box reset <name>`. Starting over: `box destroy <name>` |
| `agent cannot push … 403` | Check the agent token has `repo:invite`, then `box destroy` and `box new` |
| `line 2: Wang: command not found` | Quote values with spaces in `~/.config/agent-boxes/config` |
| `claude: command not found` in a box | Open a login shell with `ssh <name>@orb`, or run `box base` |
| A paste seems to do nothing | Token prompts hide what you type. Press Enter |
| `gh` asks "Authenticate Git with your GitHub credentials?" | Answer yes. It only affects git on your Mac |

---

## Check isolation by hand
**(in the box)**
```sh
curl -sS -o /dev/null -w "internet: %{http_code}\n" https://github.com
curl -m 3 -s http://host.orb.internal >/dev/null && echo "mac: REACHABLE" || echo "mac: blocked"
curl -m 3 -s http://192.168.1.1 >/dev/null && echo "home: REACHABLE" || echo "home: blocked"
sudo -n true 2>/dev/null && echo "sudo: WORKS" || echo "sudo: blocked"
```
You want `200`, then `blocked` three times.
