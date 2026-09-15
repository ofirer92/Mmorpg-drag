#!/usr/bin/env bash
# Runs GUT headless. Skips with a warning if godot is missing unless STRICT_CLIENT=1 (CI). See ADR-011.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT_BIN:-godot}"
if ! command -v "$GODOT" >/dev/null 2>&1; then
  if [[ "${STRICT_CLIENT:-0}" == "1" ]]; then echo "❌ godot binary not found (STRICT_CLIENT=1)"; exit 1; fi
  echo "⚠️  godot not found — SKIPPING client tests (set STRICT_CLIENT=1 to fail instead)"; exit 0
fi
if [[ ! -f "$ROOT/client/addons/gut/gut_cmdln.gd" ]]; then
  if [[ "${STRICT_CLIENT:-0}" == "1" ]]; then echo "❌ GUT addon missing at client/addons/gut"; exit 1; fi
  echo "⚠️  GUT addon missing — SKIPPING client tests (run scripts/setup.sh)"; exit 0
fi
cd "$ROOT/client"
# First run imports resources so scripts compile; ignore its exit code.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
LOG="$(mktemp)"
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -glog=1 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}
# GUT silently skips a test script that fails to parse — treat that as a failure (a skipped file is a
# false green). Also require every tests/test_*.gd to appear in the run.
if grep -qE 'Failed to load script|Parse Error' "$LOG"; then echo "❌ a test script failed to load (see above)"; rm -f "$LOG"; exit 1; fi
# A runtime SCRIPT ERROR (a failed typed assignment, a nil call) does NOT fail a GUT assert — the
# suite can report green while the game is erroring every frame. T-1.7b hit exactly that: a ternary
# assigned an untyped Array to an Array[String] and only a screenshot run revealed it.
if grep -q 'SCRIPT ERROR' "$LOG"; then echo "❌ a runtime SCRIPT ERROR occurred during the tests (see above)"; rm -f "$LOG"; exit 1; fi
missing=0
for f in tests/test_*.gd; do grep -q "res://$f" "$LOG" || { echo "❌ test script not run: $f"; missing=1; }; done
rm -f "$LOG"
[[ $missing -eq 0 ]] || exit 1
exit "$status"
