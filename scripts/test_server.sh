#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ ! -d node_modules ]]; then echo "node_modules missing — run scripts/setup.sh (pnpm install)"; exit 1; fi
pnpm -C packages/shared-rules exec tsc --noEmit
pnpm -C packages/shared-rules exec vitest run
pnpm -C server exec tsc --noEmit
pnpm -C server exec vitest run
