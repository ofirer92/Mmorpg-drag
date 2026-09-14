#!/usr/bin/env bash
# PostToolUse (Edit|Write): format + lint the touched file by extension. Missing tools are skipped, never fatal.
FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" || ! -f "$FILE" ]] && exit 0
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
has() { command -v "$1" >/dev/null 2>&1; }
case "$FILE" in
  *.gd)
    has gdformat && gdformat "$FILE" >/dev/null 2>&1
    has gdlint && gdlint "$FILE" ;;
  *.ts|*.tsx|*.js|*.json|*.md)
    has prettier && prettier --log-level warn --write "$FILE" >/dev/null 2>&1
    case "$FILE" in *.ts) [[ -x "$ROOT/node_modules/.bin/eslint" ]] && "$ROOT/node_modules/.bin/eslint" --no-warn-ignored "$FILE" ;; esac ;;
  *.yaml|*.yml)
    has yamllint && yamllint -d relaxed "$FILE"
    case "$FILE" in "$ROOT"/docs/balance/*|docs/balance/*) python3 "$ROOT/scripts/validate_balance.py" ;; esac ;;
  *.py)
    has ruff && ruff format --quiet "$FILE" && ruff check --quiet "$FILE" ;;
esac
exit 0
