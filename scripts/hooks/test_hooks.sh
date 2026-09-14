#!/usr/bin/env bash
# Simulates hook inputs (DoD for T-I.6): protected edits blocked, normal edits allowed, dangerous bash blocked.
set -uo pipefail
H="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0
expect() { # expect <exit_code> <hook> <json>
  local want=$1 hook=$2 json=$3
  echo "$json" | "$H/$hook" >/dev/null 2>&1; local got=$?
  if [[ $got -eq $want ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $hook expected $want got $got for $json"; fi
}
expect 2 guard_protected.sh '{"tool_input":{"file_path":"client/scripts/rules/xp.gd"}}'
expect 2 guard_protected.sh '{"tool_input":{"file_path":"/x/repo/.github/workflows/ci.yml"}}'
expect 2 guard_protected.sh '{"tool_input":{"file_path":"docker-compose.yml"}}'
expect 2 guard_protected.sh '{"tool_input":{"file_path":"server/drizzle/0001_init.sql"}}'
expect 2 guard_protected.sh '{"tool_input":{"file_path":"packages/shared-rules/src/_balance_data.ts"}}'
expect 0 guard_protected.sh '{"tool_input":{"file_path":"server/drizzle/README.md"}}'
expect 0 guard_protected.sh '{"tool_input":{"file_path":"client/scripts/player/player.gd"}}'
expect 0 guard_protected.sh '{"tool_input":{"file_path":"packages/shared-rules/src/xp.ts"}}'
expect 2 guard_bash.sh '{"tool_input":{"command":"rm -rf build"}}'
expect 2 guard_bash.sh '{"tool_input":{"command":"git push --force origin main"}}'
expect 2 guard_bash.sh '{"tool_input":{"command":"git push -f"}}'
expect 2 guard_bash.sh '{"tool_input":{"command":"scripts/deploy.sh prod"}}'
expect 2 guard_bash.sh '{"tool_input":{"command":"psql -c \"DROP TABLE users\""}}'
expect 0 guard_bash.sh '{"tool_input":{"command":"git push -u origin feature"}}'
expect 0 guard_bash.sh '{"tool_input":{"command":"scripts/deploy.sh staging"}}'
expect 0 guard_bash.sh '{"tool_input":{"command":"rm build/tmp.txt"}}'
expect 0 on_stop.sh '{"stop_hook_active":true}'
echo "hooks: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
