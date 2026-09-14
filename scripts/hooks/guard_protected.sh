#!/usr/bin/env bash
# PreToolUse (Edit|Write): block edits to generated / protected paths. Exit 2 = block with reason.
FILE=$(jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$FILE" ]] && exit 0
PROTECTED=("client/scripts/rules/" "packages/shared-rules/src/_balance_data.ts" ".github/" "docker-compose.yml" "server/drizzle/[0-9]")
for p in "${PROTECTED[@]}"; do
  if [[ "$FILE" =~ $p ]]; then
    echo "BLOCKED: $FILE is protected. Write to DECISIONS.md first or use gen_rules.py." >&2
    exit 2
  fi
done
exit 0
