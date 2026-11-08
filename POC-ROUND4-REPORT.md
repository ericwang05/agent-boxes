# Round 4 report: the MVP pipe

Run on 2026-11-07. Throwaway code in `~/agent-boxes-poc/round4/` (`proxy.py`, `sandbox`, `launchd/`, `proxy.log`). Box `r4a`, repo `ericwang05/test`, the bot's classic token. Nothing in `bin/` or `box/` was changed.

**Answer: yes, the pipe works end to end.** A fake token in the box, the Go bridge, a base-URL proxy that swaps in the real token, and everything else going direct. Two things need fixing in the real build (git auth and the port-22 hole), listed below.

## Results

| # | Plain question | Result | Notes |
|---|---|---|---|
| 1 | Can Claude work with only a fake key? | **Pass** | Interactive `claude` answered `pong` and did a 2-step task. The log shows `HEAD /api/hello` answered locally and every `/v1/messages` swapped. The first turn got one 429 from Anthropic and then worked (not from our proxy). |
| 2 | Which Claude features break without the CA? | **Pass** | Two calls skip the base URL and go straight to Anthropic with the worthless fake token: `GET /api/claude_cli/bootstrap` and an OAuth profile check. Both get 401. Claude logs the errors and carries on. Effect: no bootstrap data (server-side flags and settings) and no account or usage info. Auto-update (about 120 MB) also goes direct. One Google IP (`35.190.46.17`) was also connected, purpose not checked. |
| 3 | Can the agent push its own branch? | **Pass** | `git push origin poc4-a` went through `/gh/`. |
| 4 | Can it open a PR as the bot? | **Pass** | Claude followed the REST hint on its own. PR #6 was opened by `eric-code-agent`. **The REST hint works, so no `gh-pr` wrapper is needed.** |
| 5 | Is everything else refused? | **Pass** | 403 plus a log line for each: other repo over git (`test2`), other repo over REST, merge, ref delete, contents write, GraphQL, wrong GitHub token, wrong Anthropic token. Own-repo read still 200. |
| 6 | Does normal internet work without the proxy? | **Pass after two fixes** | Nix shell (nodejs, python3, 48 paths) plus `npm install next react` took 19 s. `git clone cursor/plugins`, `marketplace add` and `/plugin install pstack@cursor-plugins` (a real download) all work. None of it is in the proxy log. See findings 1 and 2 for the fixes. |
| 7 | Is the home network still blocked? | **Partial** | Blocked: the Mac's LAN IP, the router, `169.254.169.254`, `10.0.0.1`, `[::1]`, `host.orb.internal`, port 8443, and sudo is off. No host mounts. **`github.com:22` was reachable.** The repo's `box/sandbox` firewall has `policy accept`, so any port to a public host is open. See finding 3. |
| 8 | Is the real token anywhere in the box? | **Pass** | No `ghp_`, `github_pat_` or `sk-ant-` in the box's env, `/home`, `/root`, `/tmp`, `/etc`, `/usr/local`, `/var/tmp` or the process list. I skipped plugin source folders (docs could contain the prefix as text). Nothing in the proxy log or the Mac process list either. |
| 9 | Does a bridge crash heal itself? | **Pass** | 3 x `kill -9` of the Mac-side bridge, 12 s apart, mid-task. launchd restarted it in about 1 s each time. Claude finished the 6-file task. After 60 s: 1 Mac bridge, 1 `orb run`, 1 box-side pair, nothing stale. |
| 10 | Does a long turn survive? | **Pass** | One turn with 2 subagents ran 29 minutes (more than needed). 0 rejected. Peak 24 streams open (limit 64). All 232 streams closed normally. I stopped it myself. |

## Findings for the real build

1. **`http.proactiveAuth basic` must not be global.** It made plain `git clone https://github.com/cursor/plugins` ask for a username and abort. Fix used: the proxy answers a credential-less `/gh/` request with `401` and `WWW-Authenticate: Basic`, and git then uses the credential helper for `http://localhost:8080` only. With this, public clones, own-repo clone and push all work, and the global git setting is gone. Round 3 had no such problem only because everything went through the proxy.
2. **Drop the `credential.https://github.com.helper = !gh auth git-credential` line** (it comes from `inject_token`). It hands the fake `GH_TOKEN` to github.com directly, so GitHub rejects public clones with "Invalid username or token". The new `box new` must not set it.
3. **The firewall needs a port rule.** Today it only rejects private ranges. Add "accept tcp 80 and 443 (and the DHCP/DNS bits), reject the rest" or SSH, SMTP and everything else stay open. This is MVP step 3.
4. **The OrbStack gateway/DNS allow rule is still empty** in the generated ruleset (as in rounds 2 and 3). DNS works anyway, and it is not a problem today.
5. **Fresh box needs two Claude prompts answered by hand** (folder trust, "make auto mode default"). `box new` should pre-set them, like it already does for folder trust in `~/.claude.json`.
6. **Claude still asks about "dangerous rm" in bypass mode** when it can't resolve the target (`cd dir && rm -f *`). That is a "needs you" case for the herdr ding, not an error.
7. **Boxes carry a fake `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN` in env.** That's by design. The REST hint uses `$GH_TOKEN` against `http://localhost:8080/ghapi/...`.
8. **No-token requests all get a quiet 403** with the same structured line (`rule: quiet-tokenless`), but I didn't see any in this run's log (Claude sent none through the base URL).
9. Proxy is 182 lines (round 3 had 379).

## State now

- Stopped: proxy, bridge (launchd job unloaded), tmux. No bridge, proxy or `orb run` processes left.
- GitHub: PR #6 closed, `poc4-a` and `poc4-b` deleted. No open PRs on `ericwang05/test`.
- Boxes: `r4a` kept (until Eric says delete), plus `box-base`.
- Old stuff cleaned up before the run: `r3a`, `r3b`, `e2e` deleted, `dev.agent-boxes.refresh` unloaded and its plist moved to `~/agent-boxes-poc/refresh.plist.bak`. The never-loaded `br1`/`br2` plists in `~/Library/LaunchAgents` were left alone.
- Not committed: this report and the round 4 folder. Keychain untouched.
