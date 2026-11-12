#!/usr/bin/env bash
# Run every test, or the ones named: tests/run.sh [chain2_panic_recover redflag1_token_leak ...]
# Real boxes and repos: needs OrbStack, herdr, gh (with delete_repo) and the Keychain tokens. Run by hand on the Mac.
cd "$(dirname "$0")" || exit 2
if [ $# -gt 0 ]; then tests=("${@/%/.sh}"); else tests=(*_*.sh); fi
failed=()
for t in "${tests[@]}"; do
  echo "##### $t"
  bash "$t" || failed+=("$t")
done
echo
if [ ${#failed[@]} -eq 0 ]; then echo "ALL PASSED"; else echo "FAILED: ${failed[*]}"; exit 1; fi
