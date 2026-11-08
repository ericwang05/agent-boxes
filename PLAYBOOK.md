# Playbook

## Everyday

- **Start:** `box new myapp` (or `--repo you/existing`). A herdr pane opens in the box with Claude running; type the task there.
- **Packages:** the agent adds them through the project's `flake.nix` dev shell. The 7-day and no-install-scripts rule is a request in the box `CLAUDE.md`, not enforced.
- **See what the agents did:** `box status`, `box status myapp --history`.
- **Review and merge:** open the PR on GitHub, approve, merge. The bot can't merge or approve; main needs 1 approval from you.
- **Roll back:** `box reset myapp --to <commit | pr/N | status/N>`.
- **Finish:** `box rm myapp`, then delete the repo on GitHub if you want it gone.

## When something goes wrong

- **Agent is stuck or asked something:** answer in its pane. "dangerous rm" questions in bypass mode are normal.
- **Suspect a box:** `box panic` (stops everything), then `box rm NAME`. To cut GitHub access, revoke the bot's classic token and re-save it in Keychain (`agentbox-github`).
- **`box new` failed:** it rolls back the box, jobs and a repo it created. `BOX_KEEP=1 box new ...` keeps them for debugging. Proxy and bridge logs: `~/.config/agent-boxes/logs/`.
- **Claude says it can't connect:** is the Mac awake and the bridge up? `BRIDGE_DIR=~/.config/agent-boxes/logs ~/agent-boxes/build/agentbox-bridge status`.
- **Proxy blocks:** one JSON line each in `logs/NAME.proxy.log` (`rule`: `not-own-repo`, `rest-not-allowed`, `bad-token`, `gh-api-not-repos`).

## Changing the setup

- **Plugins or Claude settings:** edit `box/claude/`, run `box base`; new boxes pick it up. Root-owned settings: edit `box/managed-settings.json`, then new boxes get it.
- **Firewall:** edit `box/firewall.nft`. If a real tool needs another port, add that port; don't remove the rule.
- **Rebuild the base:** `box base` and answer `y`.

## Check isolation by hand

```
orb -m NAME curl -m 3 http://192.168.1.1        # must fail
orb -m NAME curl -m 3 http://host.orb.internal  # must fail
orb -m NAME curl -m 5 https://github.com        # must work
orb -m NAME sudo -n true                        # must fail
```
