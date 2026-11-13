# Box tests

End-to-end tests for agent-boxes. They use real boxes and real GitHub repos, so they run by hand on your Mac (not in CI). Each test makes its own throwaway box and repo, named `boxtest-*`, and deletes them at the end. Cleanup refuses to touch any name that does not start with `boxtest-`.

## Run

```
tests/run.sh                          # everything (15 tests, about 16 minutes)
tests/run.sh chain2_panic_recover     # one test (name without .sh)
BOX_BIN=/path/to/bin/box tests/run.sh # test a different checkout of box
```

Needs OrbStack, herdr, `gh` logged in with the `delete_repo` scope, and the Keychain tokens from `box setup`. `box-base` must be built.

`box panic` stops every box. Tests that run it (`chain2`, `redflag5`) refuse to start if any other box is running. Set `BOX_TEST_ALLOW_PANIC=1` to override.

## What each test covers

| Test | Checks |
|---|---|
| `chain1_status_reset` | status history logs the right commit hashes; bad `reset --to` values fail and leave the box alone; reset to `status/1` and to a full commit land on the right HEAD |
| `chain2_panic_recover` | new, panic, then reset to the current commit brings the box back with jobs, bridge and isolation intact |
| `chain3_pr_reset_rm` | agent opens a PR; reset to `pr/N`; `rm` keeps the repo, PR and status history |
| `chain4a_repo` | `box new --repo`: ruleset applied, right commit logged, repo healthy after reset, `rm` keeps the repo |
| `chain4b_fork` | `box new --fork` (forks `octocat/Hello-World`): same reset checks |
| `chain5_failed_new` | a `box new` that fails after the repo exists rolls back repo, jobs, registry and box |
| `redflag1_token_leak` | real Claude and GitHub tokens never appear in the box (files, env, argv) after new or reset; includes a canary so the scan is proven to see a planted secret |
| `redflag2_isolation` | LAN, Mac, other ports, IPv6, sudo, host mounts and managed settings stay locked after new and after reset |
| `redflag3_proxy_blocks` | the proxy refuses other repos, GraphQL, merge, approve, contents write, ref delete, settings, repo delete, path traversal and wrong tokens |
| `redflag4_main_protected` | the agent cannot push, force-push, delete or merge into `main`, through the box or straight at GitHub with the bot token |
| `redflag6_no_nested_boxes` | a boxed agent cannot make boxes or repos (OrbStack's `orb`, `orbctl` and `mac` are installed but cannot reach the Mac; repo creation and forks get 403) yet can run subagent-style parallel git worktrees and pushes inside its own box. A real Claude subagent run is optional (`BOX_TEST_REAL_AGENT=1`, spends Pro usage) |
| `multibox1_isolation` | two boxes at once: neither reaches the other on any tested port, each proxy refuses the other box's token and repo, no tokens, logs or sockets shared |
| `multibox2_load` | 50 simultaneous requests per box, both at once: all succeed, answers never cross between boxes; one box holding 120 connections (cap is 64) does not affect the other, and recovers |
| `multibox3_containment` | killing A's bridge or proxy, resetting A, and removing A never interrupt B (B polled every second throughout) |
| `redflag5_no_leftovers` | nothing is left (machine, launchd jobs, sockets, processes, herdr machine) after `rm`, after panic, or after both |

## Known limits

- "Must fail" checks can pass for the wrong reason. Where it matters there is a positive control (box reachable, web works, own repo returns 200).
- Reset does not rewind the Mac's status history; `chain1` asserts that current behavior so a change shows up.
- The tests use the installed `box` unless `BOX_BIN` is set.

## Writing a test

Source `lib.sh`, call `mkbox` (or `mkbox --repo ...`), use `check "what" command...`, and end with `finish`. `lib.sh` has helpers for commits, PRs, status notes, proxy calls and cleanup.
