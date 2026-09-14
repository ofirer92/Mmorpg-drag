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
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -glog=1
