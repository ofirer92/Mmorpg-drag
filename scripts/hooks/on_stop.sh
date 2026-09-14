#!/usr/bin/env bash
# Stop hook: block ending the session while check.sh is red or PROGRESS.md is untouched.
INPUT=$(cat)
# Avoid infinite loop: if we're already continuing because of this hook, let it stop.
if echo "$INPUT" | jq -e '.stop_hook_active == true' >/dev/null 2>&1; then exit 0; fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
if ! scripts/check.sh > /tmp/check.log 2>&1; then
  echo "Tests failing — fix before ending session:" >&2
  tail -30 /tmp/check.log >&2
  exit 2
fi
# PROGRESS.md must have changed this session: uncommitted diff OR committed within the last 12 hours.
recent=$(git log -1 --format=%ct -- PROGRESS.md 2>/dev/null || echo 0)
now=$(date +%s)
if git diff --quiet HEAD -- PROGRESS.md 2>/dev/null && (( now - recent > 43200 )); then
  echo "PROGRESS.md was not updated this session. Update it (3-5 lines: done / next / broken)." >&2
  exit 2
fi
exit 0
