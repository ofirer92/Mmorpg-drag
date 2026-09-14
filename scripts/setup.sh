#!/usr/bin/env bash
# One-time developer setup (human runs once). Installs toolchain, brings up compose, migrates, creates .env.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
GODOT_VERSION="${GODOT_VERSION:-4.3-stable}"
GUT_VERSION="${GUT_VERSION:-v9.3.0}"

echo "== Node / pnpm"
command -v node >/dev/null || { echo "install Node 22 first (https://nodejs.org)"; exit 1; }
command -v pnpm >/dev/null || npm i -g pnpm
pnpm install

echo "== Python deps"
python3 -m pip install --quiet --user pyyaml pillow ruff 2>/dev/null || python3 -m pip install --quiet pyyaml pillow ruff

echo "== Godot $GODOT_VERSION"
if ! command -v godot >/dev/null; then
  case "$(uname -s)" in
    Linux)
      url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/Godot_v${GODOT_VERSION}_linux.x86_64.zip"
      mkdir -p "$HOME/.local/bin" && curl -fsSL "$url" -o /tmp/godot.zip && unzip -o -q /tmp/godot.zip -d /tmp/godot \
        && mv /tmp/godot/Godot_v${GODOT_VERSION}_linux.x86_64 "$HOME/.local/bin/godot" && chmod +x "$HOME/.local/bin/godot"
      echo "godot installed to ~/.local/bin/godot (add to PATH)";;
    *) echo "install Godot $GODOT_VERSION manually and put 'godot' on PATH";;
  esac
fi

echo "== GUT addon $GUT_VERSION"
if [[ ! -f client/addons/gut/gut_cmdln.gd ]]; then
  tmp=$(mktemp -d); git clone --quiet --depth 1 --branch "$GUT_VERSION" https://github.com/bitwes/Gut.git "$tmp/gut"
  mkdir -p client/addons && rm -rf client/addons/gut && cp -r "$tmp/gut/addons/gut" client/addons/gut && rm -rf "$tmp"
fi

echo "== .env"
[[ -f server/.env ]] || cp server/.env.example server/.env

echo "== docker compose (postgres, redis)"
if command -v docker >/dev/null; then
  docker compose up -d
  echo "waiting for postgres..."; for i in $(seq 1 30); do docker compose exec -T postgres pg_isready -U hamirpaa >/dev/null 2>&1 && break; sleep 1; done
  pnpm -C server migrate || echo "(migrate skipped/failed — fine until T-3.1)"
  docker compose ps
else
  echo "docker not found — skipping compose"
fi

echo "== generated rules"
python3 scripts/gen_rules.py
chmod +x scripts/*.sh scripts/hooks/*.sh
echo "== done. run scripts/check.sh"
