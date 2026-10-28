# Playbook

What to do, situation by situation. Commands run on the Mac unless they say "inside the box".

## Start a project

```sh
box new myapp --python 3.12
```

1. In herdr, press `prefix+w` and pick `myapp`. Claude is open in the repo.
2. Give it its first instruction. Start with `/pstack:poteto-mode` if you want pstack's playbooks, since they don't start on their own. Or pass the instruction up front:
   `box new myapp --python 3.12 --prompt "/pstack:poteto-mode <what to build>"`
3. Want to check the steps first? Run `box --dry-run new myapp --python 3.12`.

## Watch and talk to agents

- **herdr:** the sidebar lists every box. The agent list shows each agent as working, idle or waiting on you. `prefix+w` switches boxes.
- **GitHub:** the repo's Pull requests, Actions and Releases pages show what landed.
- **A shell inside a box:** `ssh myapp@orb`. Use `orb -m myapp` for quick admin commands.

## Add tools to a project

Tell the agent: "add `<tool>` to `flake.nix`", or for Python, "`uv add <package>`". The dev shell reloads automatically.

## Find a known-good version

```sh
box versions myapp
```

This lists `merge-<n>`, the PR title and the date, so you can see which version you want to go back to.

## The agent is stuck or confused

1. Switch to its pane and talk to it.
2. If that doesn't help, reset the box. The code stays on GitHub:
   ```sh
   box reset myapp
   ```

## Bad code landed on `main`

**Undo specific changes:** tell any agent, "revert commits `<sha>`…`<sha>` in one PR." History stays intact.

**Jump back to a known-good version:** you're the repo admin, so the ruleset lets you do this.
```sh
box versions myapp
git clone https://github.com/<owner>/myapp /tmp/fix && cd /tmp/fix
git push --force origin merge-12:main
```
Only `git push` in that clone. Don't run anything else from an agent-written repo on the Mac.

## You suspect a box or agent went rogue

1. **Stop it now:** `orb stop myapp`.
2. **Cut off copied tokens.** Revoke and replace both tokens:
   - **GitHub:** sign in as the agent account → Settings → Developer settings → Tokens (classic). Revoke the old token, create a new one with only `public_repo`, and write it to `~/agent-boxes/.agent-token`.
   - **Claude:** revoke the old token in your Claude account settings, run `claude setup-token`, and write the new one to `~/agent-boxes/.claude-token`.
3. **Check what it touched.** Look at recent commits and PRs in this repo, in your other box projects (the agent account can reach those too), and on the agent account's own profile.
4. **Restore `main`** if needed (see "Bad code landed on `main`").
5. **Start fresh from a safe version:** `box reset myapp --ref merge-12`.

The rogue box is destroyed by `reset`. Revoking the tokens stops anything it copied out.

## A project is finished

```sh
box retire myapp
```
This deletes the box, removes it from herdr, and revokes the agent's access to the repo. The repo stays on your account.

## Delete a project completely

```sh
box destroy myapp
```
After a y/N prompt this deletes the box, removes it from herdr, revokes the agent's access and deletes the repo. It adds the `delete_repo` scope to `gh` for the delete and removes it afterwards (you approve in the browser).

## Stop everything

- **One box:** `orb stop <name>`
- **All boxes:** quit OrbStack

## `box new` failed partway

Read the error, fix the cause and rerun `box new myapp`. A failed `new` already removed its box, herdr entry and repo. If the rollback itself failed it says so; then run `box destroy myapp`.

## Routine maintenance

| When | What |
| --- | --- |
| Every 90 days | **The agent token expires.** Make a new one, overwrite `.agent-token`, then `box reset` active projects |
| Monthly | **Rebuild the base** for updates: `box base` (applies the saved pstack config) |
| Overnight runs | **Keep the Mac plugged in and awake,** since boxes pause when it sleeps |
| Weekly | **Check Claude plan usage.** All boxes share it |
| When done | **`box retire` finished projects** to free disk space and access |

## Common errors

| Error | Fix |
| --- | --- |
| `dial: no such file or directory` | OrbStack isn't running: `open -a OrbStack`, wait, retry |
| `Could not resolve hostname orb` | Add the `Host orb` entry from the README to `~/.ssh/config` |
| `claude: command not found` in a box | Open a login shell (`ssh <name>@orb`), or rebuild the base |
| Paste looks like it did nothing | Token and login prompts hide input. Press Enter |
| `repo … already exists` | Use `box reset <name>` for an existing project, or `box destroy <name>` first |

## Check isolation by hand

Inside any box:
```sh
curl -sS -o /dev/null -w "internet: %{http_code}\n" https://github.com
curl -m 3 -s http://host.orb.internal >/dev/null && echo "mac: REACHABLE" || echo "mac: blocked"
curl -m 3 -s http://192.168.1.1 >/dev/null && echo "home: REACHABLE" || echo "home: blocked"
sudo -n true 2>/dev/null && echo "sudo: WORKS" || echo "sudo: blocked"
```
You want `200`, then `blocked` three times.
