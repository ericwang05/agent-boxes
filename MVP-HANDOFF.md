# Agent box MVP: technical handoff for Claude Code

Written 2026-11-08. This replaces `PLAN.md` as the plan. It does not replace the POC reports, which hold the evidence.

**Before you write any code:** read this file, then `POC-ROUND4-REPORT.md`, `POC-HANDOFF.md`, `POC-ROUND3-REPORT.md`, `POC-STATUS.md` and `POC-BRIDGE.md` in the repo root, then `bin/box`, `box/sandbox` and `box/setup.sh`. Section 9's questions are already answered (checked 2026-11-08), so don't re-ask them. Ask Eric only about anything new you find, one batch of 5 or fewer, each with your suggested answer. Eric prefers very plain language, short answers, and being asked rather than having you assume. Explain every test as the plain question it answers. Build only after he answers.

## 1. What we are building

Eric runs `box new myapp`. A locked GitHub repo and an isolated Linux box are created, and a herdr pane opens inside the box with Claude Code running. Eric types the task there. The agent works in bypass mode. When it's unsure, it stops and asks, and Eric hears Claude Code's ding in herdr. It opens a PR as the bot `eric-code-agent`. Eric reviews and merges it on GitHub. If something goes wrong, `box reset myapp --to <commit|PR>` rebuilds the box at that point.

Compared with plain herdr plus Claude Code, it adds four things: an isolated box, real tokens that never enter the box, a locked main, and reset to a saved point. Nothing else.

```
MAC                                              BOX (one per project, OrbStack --isolated)
box CLI (no AI)  ── orb run ──────────────────▶  repo + Nix dev shell
status history (Mac copy)  ◀── orb run cat ───   status.log (agent appends)
proxy (real tokens from Keychain)                Claude Code, FAKE tokens
   ▲ unix socket per box                         ANTHROPIC_BASE_URL=http://localhost:8080
   └──── Go bridge (yamux over orb run) ───────▶ localhost:8080 (bridge box side)
herdr: one pane per box                          firewall: no Mac, no LAN, internet on 80/443 only
                                                 everything else goes DIRECT (no proxy)
```

## 2. Decisions already made (do not re-ask)

- **One box per project by default.** There's no hard cap. Boxes never talk to each other. Any coordination goes through git branches.
- **The proxy only hides tokens.** Only Claude and GitHub token traffic goes through the proxy, using base URLs (the round 1 style: `ANTHROPIC_BASE_URL`, `git url.<proxy>/gh/.insteadOf https://github.com/`, `/ghapi/` for REST). All other traffic goes **direct**. There's **no CA, no decrypting, and no `HTTPS_PROXY`.**
- **GitHub uses the bot's classic token** (Eric's final pick, 2026-11-08, option 1). The bot `eric-code-agent` is invited to each project repo, and the proxy's own-repo filter blocks everything else. It passed POC test 4 and round 4. Fine-grained tokens (needs a GitHub org) are a later option, not the MVP. The GitHub App path (`box-mint`, `box-refresh`, `box/app-token.sh`, App default in `bin/box`) is no longer used. Keep the code behind a flag and don't delete it.
- **Proxy:** start from round 4's `~/agent-boxes-poc/round4/proxy.py` (Python stdlib, 182 lines, no CONNECT, no CA). Keep it in Python. Its rules, carried over from round 3:
  - Exact-host token swap.
  - Writes only to the box's own repo.
  - REST allow-list. Allowed: reads, `POST /pulls`, `PATCH /pulls/N`, `POST /issues/N/comments`, `POST /pulls/N/comments`. Refused: merge, ref delete, settings, contents write.
  - GraphQL refused. The box CLAUDE.md gets the REST hint (round 4 test 4: Claude used it alone). No `gh-pr` wrapper.
  - Answer `GET`/`HEAD /api/hello` locally.
  - Quiet 403s for tokenless Claude calls (`/mcp-registry/v0/servers`, `/api/directory/plugins`, `/api/event_logging/v2/batch`).
  - Strip whitespace from the Keychain token and decode it if it's hex.
  - Never log or echo header values.
- **Bridge:** the round 3 Go bridge (`~/agent-boxes-poc/round3/src/main.go`) is frozen. Settings: one Unix socket per box (folder mode 700), launchd KeepAlive, 64 streams, 100 new/s, 2-minute idle, no lifetime limit.
- **Firewall:** a box created by `box new` blocks the Mac, the home LAN, private ranges, IPv6 and multicast. **Outbound internet is TCP 80 and 443 only**, plus DNS (port 53). Everything else is dropped (this closes round 4 finding 3, `github.com:22` reachable). Eric's rule (2026-11-08): every request carrying a token goes through the proxy; the port rule is an extra layer that is in the MVP because it is a few lines. If a real tool needs another port, add that port; don't remove the rule. There's no sudo. Make it one fixed file with no boot script, and remove the old copy in `setup.sh`.
- **Main is locked:** a ruleset with no bypass and 1 required approval, so only Eric merges. Turn GitHub push protection on. `bin/box` already sets this up.
- **Packages:** install scripts off, and skip packages less than 7 days old (npm `min-release-age` if the box's npm has it, else pnpm's `minimumReleaseAge`; uv `exclude-newer`; check the versions). Each project has a Nix flake dev shell that the agent edits. Copy the `nix-daemon` drop-in and `AWS_EC2_METADATA_DISABLED=true` from round 3, minus the proxy variables, since Nix now goes direct.
- **Claude Code:** `bypassPermissions`. Settings get locked in a root-owned `/etc/claude-code/managed-settings.json`. The agent has no sudo, so it can't change them. Eric changes them from the Mac with `orb run` as root.
- **Box CLAUDE.md rule:** "If anything is unclear or blocked, stop and ask. Never work around it." This is a request, not a security control. Don't count it as a control anywhere.
- **No AI on the Mac.** The CLI is plain code. No chat front door.
- **Notifications:** none from the Mac in the MVP. Eric relies on Claude Code's ding inside herdr. Log proxy blocks quietly as structured lines, one JSON per line: time, box, rule, method, host, path with no query, and bytes. They're the raw data for the later red-team table.
- **Memory** is the repo plus the status log (section 4). Chat history is not saved.
- **No extra hooks** (Eric, 2026-11-08). Keep herdr's own `herdr integration install claude` from `setup.sh`. Status lines come from the agent only.
- **Fixes from round 4 that `box new` must include:**
  - Don't set `http.proactiveAuth basic` globally. The proxy answers a credential-less `/gh/` request with `401` + `WWW-Authenticate: Basic`, and git uses a credential helper for `http://localhost:8080` only.
  - Don't set `credential.https://github.com.helper = !gh auth git-credential` (it breaks public clones).
  - Pre-answer Claude's two first-run prompts (folder trust, "make auto mode default").
  - Claude's "dangerous rm" question in bypass mode is a normal "needs you" case, not an error.

## 3. Commands

| Command | Does |
|---|---|
| `box new <proj> [--repo owner/name]` | Creates or attaches the repo, locks main, adds the bot as a collaborator, creates the box with fake tokens and the bridge, then opens the herdr pane with `claude` running. Eric types the first task there. |
| `box status [proj] [--history]` | Pulls new status lines from each box and shows one row per box: state, last task, commit, PR link, time. `--history` shows the full Mac-side timeline. |
| `box reset <proj> --to <commit\|PR\|status#>` | Deletes the box, rebuilds it at that commit (packages come back through `flake.lock`), and prints the matching status entry in the new pane. This builds on the existing `reset --ref`. |
| `box rm <proj>` | Deletes the box and its bridge and fake tokens. Keeps the repo and the Mac status history. |
| `box panic` | Stops every box, every bridge and the proxy right away. |
| `box base` | Rebuilds the base image. |
| `box ls` | Keep it if it's free. |

Cut: `retire`, `destroy`. `--classic` becomes the only path.

## 4. Status log (Eric's design)

- Inside the box there's a tiny helper, `box-note "<task>" <working|done|needs-you|blocked>`. It appends one line to `~/.box/status.log` with the time, the task (capped at 200 chars) and the current commit SHA. The box CLAUDE.md tells the agent to call it when it starts a noteworthy task and when the state changes. No hooks call it (Eric's choice). If `box status` drifts in real use, hooks can be added later.
- The Mac pulls with `orb run -m <box> cat ~/.box/status.log`. It parses strictly (fixed fields, length caps, a safe character set, and a commit that matches `[0-9a-f]{7,40}`), drops anything malformed, and appends new lines to `~/.config/agent-boxes/status/<proj>.log`. The box never sends anything to the Mac. The Mac copy is append-only, so the box can't change history it has already handed over.
- An injected agent can write a false status line. That's accepted. Eric decides where to roll back to, and the commit is checked against git.

## 5. What changes from today's repo and `PLAN.md`

| Area | Today | MVP |
|---|---|---|
| Claude token | Real token in the box (`~/.claude-token-env`) | Fake token in the box; proxy swaps in the real one |
| GitHub token | App tokens by default, refreshed every 30 min | The bot's classic token, held by the proxy only |
| Proxy | None in the repo (POC code only) | Round 4's base-URL proxy (`round4/proxy.py`), no CA, no CONNECT |
| Bridge | None in the repo | Round 3 Go bridge, frozen |
| Firewall | `box/sandbox` plus a copy in `setup.sh`, any port open | One fixed file, 80/443 + DNS only |
| Settings | `~/.claude/settings.json`, writable by the agent | Root-owned managed settings |
| Commands | `new`, `reset --ref`, `rm`, `retire`, `destroy`, `panic`, `ls`, `base` | `new` (opens pane), `status`, `reset --to`, `rm`, `panic`, `base` |
| Memory | None | Status log, with the Mac copy kept |

**Kept as is:** OrbStack `--isolated` boxes, `check_isolation` at create time, Nix plus direnv dev shells, the herdr workspace, the ruleset setup in `bin/box`, the plugins in `box/claude/settings.json`, and the base image flow.

**Dropped from earlier plans:** the decrypting CA, the all-traffic proxy, the AI log judge, rate caps, 48-hour logs, Mac pop-ups, an extra secret scan, plugin pinning, the GUI, overnight runs, cloud keys and fake-token rotation.

## 6. Accepted gaps (write these down in the README)

- With direct internet on 80/443 the agent can still send repo code anywhere. The design protects **tokens, not data**. The repos are public anyway.
- Pro usage is the real cap on parallel boxes.
- An injected agent could still misuse Eric's home internet address over 80/443 (for example hammering a website). Accepted for the MVP.
- The STOP-and-ask rule is a request to the agent, not a control.
- With the Mac asleep or the proxy down, Claude shows its own error and stops after about 3 minutes.

## 7. Build order (each step ends with a check you show Eric)

1. ~~Pipe check~~ **Done:** round 4 passed (`POC-ROUND4-REPORT.md`). Fake key, Go bridge, base-URL proxy and direct internet work together.
2. Managed-settings lock. Check that the agent can't edit the settings or get around them.
3. Firewall as one file. Rerun round 2's LAN checks, confirm 443 works (npm, Nix, a public `git clone`) and that port 22 to `github.com` is refused.
4. `box new` with the proxy, bridge (launchd), fake tokens and herdr pane.
5. `box-note` plus `box status`.
6. `box reset --to`. Run it once on a real older commit and check that the packages come back.
7. `box rm`, `box panic`. Check that no bridge or launchd agents are left behind.
8. Check the herdr ding (5 minutes).
9. Eric uses it on one real task to a PR. After that, add no features for 2 weeks. Eric notes friction in `FRICTION.md`.

## 8. Hard rules

- Real tokens never enter a box, a log, argv or a file other than Keychain.
- Never add a path from a box to the Mac other than the bridge socket and the Mac-initiated `orb run`.
- Keep the proxy small and in one file. Eric must be able to read it.
- Don't change the bridge unless a test fails.
- Commit design docs and POC reports, but not the throwaway POC code.

## 9. Questions already answered (do not re-ask)

1. **GitHub token:** the bot's classic token (option 1). Fine-grained + org is later.
2. **Proxy language:** keep round 4's Python proxy.
3. **7-day package rule:** npm `min-release-age` (else pnpm), uv `exclude-newer`. Check the versions.
4. **`gh` CLI:** the REST hint. It worked in round 4. No wrapper.
5. **Status hooks:** none. Agent-written lines only; keep herdr's integration.
6. **Round 3 boxes and the old refresh launchd agent:** already removed in round 4. Box `r4a` stays until Eric says delete.

Still open, not blocking: what the Google IP `35.190.46.17` seen in round 4 is.
