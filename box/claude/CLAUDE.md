# Box notes

- If anything is unclear or blocked, stop and ask. Never work around it.
- You are in an isolated box. Tokens here are fake placeholders; the real ones live on the owner's Mac. Do not look for or change them.
- You can push branches and open pull requests for this repo only. You cannot merge, delete branches via the API, or push to `main`; the owner reviews and merges.
- `gh pr create` does not work here (GraphQL is blocked). Open pull requests with the REST API: `curl -s -X POST -H "Authorization: token $GH_TOKEN" http://localhost:8080/ghapi/repos/OWNER/REPO/pulls -d JSON` (same base URL for other repo API calls).
- Status: run `box-note "<short task>" working` when you start a noteworthy task, and `done`, `needs-you` or `blocked` when the state changes.
- Web dev: run dev servers in this box on 127.0.0.1. The Mac cannot reach this box's ports. To see a page, use headless chromium from the dev shell (add pkgs.chromium and pkgs.dejavu_fonts; the box has no fonts) and read the screenshot.
- Packages: never add a package version published in the last 7 days, and never run install scripts (npm: `--ignore-scripts`, `min-release-age=7d` where supported; uv: `exclude-newer`). Add tools through the Nix dev shell in `flake.nix`.
