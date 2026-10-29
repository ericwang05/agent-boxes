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
box new myapp                                # a new repo and box
box new myapp --repo <owner>/<existing>      # a box on a repo you already have (the repo is not changed)
```
Open herdr, press `prefix+w`, pick `myapp`, then run `claude` in its workspace. The first instruction is yours. To start pstack, begin your message with `/pstack:poteto-mode`.

### Work in a box
- **herdr:** every box is in the sidebar, and `prefix+w` switches between them. The agent list shows who's working, idle or waiting on you.
- **A plain shell:** `ssh myapp@orb`.
- **One-off commands that need the project's tools:** `direnv exec . <cmd>` **(in the box, inside the repo)**.
- **Results:** the repo's commits and pull requests on GitHub.

### Add tools to a project
Tell the agent "add `<tool>` to `flake.nix`". For language packages, it uses that language's own tool, such as `uv`, `npm` or `cargo`. The shell reloads by itself.

### Review and merge what agents send
Agents open pull requests and never merge. You review each one on GitHub.
- **Approve and merge** it in the GitHub UI, as usual.
- **Merge one without approving it** (your own PR, or a throwaway): `gh pr merge <number> --admin --merge`. Tested on a throwaway repo: it merges as you with the review still "required". Without `--admin`, `gh` refuses. The web UI's bypass option for this is untested.

### Finish a project

| You want | Run |
| --- | --- |
| Keep the repo, stop giving the box tokens | `box retire myapp` |
| Delete everything, repo included | `box destroy myapp` (not for boxes made with `--repo`; retire those) |

`retire` stops the refresher minting for the box. Its last token still lives up to an hour; to cut off sooner, use `box panic`.

---

## When something goes wrong

### The agent is stuck
1. Talk to it in its herdr pane.
2. Still stuck? Get a fresh box with the same repo: `box reset myapp`.

### Bad code landed on main
- **Undo specific commits:** ask an agent to "revert commits `<sha>`…`<sha>` in one PR."
- **Jump back to a good commit.** Find it in the repo's commit history on GitHub, or with `git log`, then roll back with a revert PR (`main` can't be force-pushed):
  ```sh
  git clone https://github.com/<owner>/myapp /tmp/fix && cd /tmp/fix
  git switch -c rollback
  git read-tree -u --reset <good-commit> && git commit -m "Roll back to <good-commit>"
  git push -u origin rollback && gh pr create --fill
  ```
  Merge that PR yourself; the rules let you merge your own pull requests. If it can't be done as a PR, pause the ruleset instead: repo Settings → Rules → Rulesets → `main` → Enforcement: Disabled, fix `main`, then set it back to Active.
- **Fresh box from that commit:** `box reset myapp --ref <good-commit>`.

### You suspect a box was compromised
1. **Stop it:** `orb stop myapp`, or `box panic` to stop every box and the refresher.
2. **Cut off the tokens.** That's what stops anything it copied:
   - **GitHub (App):** a box token dies within an hour on its own. To cut it off now: github.com/settings/installations → eric-w-agent → Configure → Suspend (reversible) or Uninstall. If the private key may have leaked, delete it under the App's settings → Private keys, and make a new one for `app.pem`. Revoking a single token can lag on git, so don't rely on it.
   - **GitHub (legacy `--classic` boxes):** sign in as the agent account → Settings → Developer settings → Tokens (classic) → revoke. Create a new token (`public_repo` and `repo:invite`) and save it to `~/agent-boxes/.agent-token`.
   - **Claude:** revoke the old token in your Claude account settings, then run `claude setup-token` and save the new one to `~/agent-boxes/.claude-token`.
3. **Check what it touched:** recent commits and pull requests in this project, your other box projects, and the agent account's profile.
4. **Fix `main`** if needed (see above), then `box reset myapp --ref <good-commit>`.

### `box new` failed
It cleans up after itself, so just read the error and run it again. To keep a failed box for debugging, use `BOX_KEEP=1 box new myapp`.

### Stop everything
- **One box:** `orb stop <name>`
- **All boxes and the refresher:** `box panic`. It sets `~/.config/agent-boxes/state/panic`; to resume, delete that file, start the boxes and reload the launchd job. It does not suspend the GitHub App.
- **Everything, no questions:** quit OrbStack

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
| Every 90 days | Only if you still use `--classic` boxes: the agent token expires. Make a new one, save it to `.agent-token`, then `box reset` active projects |
| Before overnight runs | Keep the Mac plugged in and awake. Boxes pause when the Mac sleeps and tokens go stale, then the refresher catches up right after wake. To stay awake: `caffeinate -i -t 28800` (8 hours) |
| Every year | The Claude token from `claude setup-token` expires after about a year. Set a calendar reminder a month early, then run `claude setup-token`, save it to `~/agent-boxes/.claude-token` and `box reset` active projects |
| After a Mac restart | The launchd job should start the refresher when you log in (not yet tested). Check `~/Library/Logs/agent-boxes/refresh.log` for `ok` lines |
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
| `agent cannot push … 403` | Legacy `--classic` box: check the agent token has `repo:invite`, then `box destroy` and `box new` |
| `mint failed: HTTP 422 … does not exist or is not accessible` | The registry file for the box names a repo that doesn't exist or the App can't reach. Check `~/.config/agent-boxes/boxes/<name>.json` |
| `box: no App token in the box` or a box has no `/run/agent/gh-token` | The refresher restores it within a minute if it is running. If not, load the launchd job (README, setup step 7) or run `bin/box-refresh --once` |
| `panic flag set, not refreshing` in the refresher log | You ran `box panic`. Delete `~/.config/agent-boxes/state/panic` to resume |
| `mint failed: HTTP 401` | The App's key or ids in `~/.config/agent-boxes` are wrong, the key was deleted, or the App is suspended |
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

## Check a box's GitHub access by hand
Only for the throwaway repos `test`, `test2` and `test3` (it attempts forbidden writes on purpose). Open an unapproved pull request from the box first, then:
```sh
VERIFY_PR=<number> VERIFY_ALLOW_WRITE=1 bin/box-verify <box>
```
Every line should say `PASS`.

## Retiring the legacy agent account
Do this in order: a clean overnight run on App tokens, then a week of clean `refresh.log`, then remove the `--classic` path from the code (your call), then revoke the agent token, and delete the account last.
