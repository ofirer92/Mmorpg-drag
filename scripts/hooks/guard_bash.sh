#!/usr/bin/env bash
# PreToolUse (Bash): block destructive / production commands. Exit 2 = block with reason.
CMD=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$CMD" ]] && exit 0
PATTERNS=(
  'rm -rf'
  'rm -fr'
  'git push[^|;&]*(--force|-f\b)'
  'deploy\.sh[[:space:]]+prod'
  'DROP TABLE'
  'DROP DATABASE'
  'git reset --hard'
  'git clean -f'
  'docker compose down[^|;&]*-v'
  'docker volume rm'
)
for p in "${PATTERNS[@]}"; do
  if echo "$CMD" | grep -Eiq -- "$p"; then
    echo "BLOCKED by guard_bash.sh: command matches '$p'. Ask a human." >&2
    exit 2
  fi
done
exit 0
