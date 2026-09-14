#!/usr/bin/env bash
# The ONLY command that defines "green". Hooks, CI and agents all call this.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail=0
step() { echo; echo "=== $1 ==="; }

step "gen_rules (drift check)"
python3 scripts/gen_rules.py --check || fail=1

step "validate_balance"
python3 scripts/validate_balance.py || fail=1

step "check_protocol_sync"
scripts/check_protocol_sync.sh || fail=1

step "test_server (server + shared-rules)"
scripts/test_server.sh || fail=1

step "test_client (GUT)"
scripts/test_client.sh || fail=1

echo
if [[ $fail -ne 0 ]]; then echo "❌ check.sh: RED"; exit 1; fi
echo "✅ check.sh: GREEN"
