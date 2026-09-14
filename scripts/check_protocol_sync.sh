#!/usr/bin/env bash
# Verifies docs/protocol.md, packages/shared-rules/src/protocol.ts and client/scripts/rules/protocol.gd list the same message types.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
# Message rows are `| `name` | direction | ...`; prettier pads the cells, so allow spaces around the name.
md=$(grep -E '^\| *`[a-z_]+` *\|' docs/protocol.md | sed -E 's/^\| *`([a-z_]+)`.*/\1/' | sort -u)
ts=$(sed -n '/MESSAGE_TYPES = \[/,/\]/p' packages/shared-rules/src/protocol.ts | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u)
gd=$( [[ -f client/scripts/rules/protocol.gd ]] && sed -n '/MESSAGE_TYPES/,/\]/p' client/scripts/rules/protocol.gd | grep -oE '"[a-z_]+"' | tr -d '"' | sort -u )
ok=0
if [[ "$md" != "$ts" ]]; then echo "❌ protocol.md ≠ protocol.ts"; diff <(echo "$md") <(echo "$ts"); ok=1; fi
if [[ "$ts" != "$gd" ]]; then echo "❌ protocol.ts ≠ protocol.gd (run scripts/gen_rules.py)"; diff <(echo "$ts") <(echo "$gd"); ok=1; fi
[[ $ok -eq 0 ]] && echo "protocol in sync: $(echo $md | tr '\n' ' ')"
exit $ok
