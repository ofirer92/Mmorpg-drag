#!/usr/bin/env bash
# Usage: scripts/deploy.sh <staging|prod>   — build Docker image → push → migrate → restart.
# prod requires CONFIRM=yes and is for humans only (CLAUDE.md "אסור").
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_NAME="${1:?staging|prod}"
case "$ENV_NAME" in
  staging) APP="${FLY_APP_STAGING:-hamirpaa-staging}" ;;
  prod)
    [[ "${CONFIRM:-}" == "yes" ]] || { echo "prod deploy requires CONFIRM=yes (human only)"; exit 2; }
    APP="${FLY_APP_PROD:-hamirpaa}" ;;
  *) echo "unknown env $ENV_NAME"; exit 1 ;;
esac
echo "== check.sh must be green before deploy"
"$ROOT/scripts/check.sh"
TAG="$(git -C "$ROOT" rev-parse --short HEAD)"
echo "== building server image $APP:$TAG"
docker build -t "$APP:$TAG" -f "$ROOT/server/Dockerfile" "$ROOT"
if command -v flyctl >/dev/null; then
  flyctl deploy --app "$APP" --image "$APP:$TAG" --config "$ROOT/server/fly.toml" --remote-only=false
  flyctl ssh console --app "$APP" -C "node server/dist/migrate.js"
else
  echo "flyctl not installed — image built locally as $APP:$TAG; push/migrate manually."
fi
echo "== deployed $ENV_NAME ($TAG)"
