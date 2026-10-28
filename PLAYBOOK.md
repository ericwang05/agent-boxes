# Playbook

What to do, situation by situation. Commands run on the Mac unless they say "inside the box". Setup and design are in the [README](README.md).

## Start a project

```sh
box new myapp --python 3.12
```

1. In herdr, press `prefix+w` and pick `myapp`. Claude is open in the repo.
2. Give it its first instruction. pstack doesn't start on its own, so begin with `/pstack:poteto-mode` if you want its playbooks. Or pass the instruction up front:
   `box new myapp --python 3.12 --prompt "/pstack:poteto-mode <what to build>"`
3. Want to check the steps first? Run `box --dry-run new myapp --python 3.12`.

## Watch and talk to agents

- **herdr:** the sidebar lists every box. The agent list shows each agent as working, idle or waiting. `prefix+w` switches boxes.
- **GitHub:** the repo's Pull requests, Actions and Releases pages.
- **A shell inside a box:** `ssh myapp@orb`, or `orb -m myapp` for quick admin commands. The dev shell loads in interactive shells. For one-off commands, use `direnv exec . <cmd>` inside the repo.

## Add tools to a project

Tell the agent: "add `<tool>` to `flake.nix`", or for Python, "`uv add <package>`". direnv reloads the shell automatically.

## Find a known-good version

```sh
box versions myapp
```

## The agent is stuck or confused

1. Talk to it in its pane.
2. If that doesn't help, reset the box. The code stays on GitHub: `box reset myapp`.

## Bad code landed on `main`

**Undo specific changes:** tell any agent, "revert commits `<sha>`…`<sha>` in one PR."

**Jump back to a known-good version:** you're the repo admin, so the ruleset lets you do this.
```sh
box versions myapp
git clone https://github.com/<owner>/myapp /tmp/fix && cd /tmp/fix
git push --force origin merge-12:main
```
Only `git push` in that clone. Don't run anything else from an agent-written repo on the Mac.

## You suspect a box or agent went rogue

1. **Stop it now:** `orb stop myapp`.
2. **Revoke and replace both tokens.** That's what stops anything it copied out:
   - **GitHub:** sign in as the agent account → Settings → Developer settings → Tokens (classic). Revoke the old token, then create a new one with `public_repo` and `repo:invite`, and save it to `~/agent-boxes/.agent-token`.
   - **Claude:** revoke the old token in your Claude account settings, then run `claude setup-token` and save the new one to `~/agent-boxes/.claude-token`.
3. **Check what it touched:** recent commits and PRs here, in your other box projects (the agent account can reach those too), and on the agent account's own profile.
4. **Restore `main`** if needed (see above).
5. **Start fresh from a safe version:** `box reset myapp --ref merge-12`.

## A project is finished

- **`box retire myapp`:** keeps the repo and revokes the agent's access.
- **`box destroy myapp`:** deletes everything, including the repo.

## Stop everything

- **One box:** `orb stop <name>`
- **All boxes:** quit OrbStack

## Routine maintenance

| When | What |
| --- | --- |
| Every 90 days | **The agent token expires.** Make a new one (`public_repo` + `repo:invite`), save it to `.agent-token`, and `box reset` active projects |
| Monthly | **Rebuild the base** for updates: `box base` |
| After changing pstack settings | Run `/pstack:setup-pstack` inside `ssh box-base@orb`, then `box save-pstack` |
| Overnight runs | **Keep the Mac plugged in and awake,** since boxes pause when it sleeps |
| Weekly | **Check Claude plan usage.** All boxes share it |

## Common errors

| Error | Fix |
| --- | --- |
| `dial: no such file or directory` | OrbStack isn't running: `open -a OrbStack`, wait, retry |
| `Could not resolve hostname orb` | Add the `Host orb` entry from the README to `~/.ssh/config` |
| SSH works but the box looks empty or `sudo` works | You hit a box name that doesn't exist, and OrbStack fell back to its default machine. Check `orb list` |
| `box new` fails partway | It rolls back by itself. Read the error and rerun. Use `BOX_KEEP=1 box new …` to keep the box for debugging |
| `repo … already exists` | Use `box reset <name>` for an existing project, or `box destroy <name>` first |
| `agent cannot push … 403` | The agent's invite wasn't accepted. `box new` matches invites by repo ID and clears stale ones, so this is rare. Check the token has `repo:invite` |
| Config error like `line 2: Wang: command not found` | Quote values with spaces in `~/.config/agent-boxes/config` |
| `gh` asks "Authenticate Git with your GitHub credentials?" | Answer yes. It only affects git on your Mac |
| `claude: command not found` in a box | Use a login shell (`ssh <name>@orb`), or rebuild with `box base` |
| Paste looks like it did nothing | Token and login prompts hide input. Press Enter |

## Check isolation by hand

Inside any box:
```sh
curl -sS -o /dev/null -w "internet: %{http_code}\n" https://github.com
curl -m 3 -s http://host.orb.internal >/dev/null && echo "mac: REACHABLE" || echo "mac: blocked"
curl -m 3 -s http://192.168.1.1 >/dev/null && echo "home: REACHABLE" || echo "home: blocked"
sudo -n true 2>/dev/null && echo "sudo: WORKS" || echo "sudo: blocked"
```
You want `200`, then `blocked` three times.
