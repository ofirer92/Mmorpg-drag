---
name: release-checklist
description: Pre-build/release checklist — version bump, changelog, migrations, smoke test, Android keystore/permissions, iOS privacy manifest, Web CORS/WSS/size. Load before export_builds.sh or deploy.sh.
---
# Release checklist

## Before every build
- [ ] `scripts/check.sh` green on the release commit (CI link in PR).
- [ ] Version bump in `client/project.godot` (`config/version`), `server/package.json`, `CHANGELOG.md` entry dated today.
- [ ] DB: `pnpm -C server drizzle-kit generate` produced nothing new (or the migration is in this release and `migrate up/down` was tested on an empty DB).
- [ ] Protocol version constant bumped if docs/protocol.md changed; old clients get a `error` with `msg_key: error.client_outdated`.
- [ ] `scripts/export_builds.sh` succeeded for all target presets.
- [ ] Smoke test: `scripts/sim_clients.ts` 50 clients × 10 min against staging, 0 crashes, p95 tick < 30 ms.
- [ ] Human: manual smoke on a real phone + desktop (WORKPLAN §8.5 step 5).

## Android
- Keystore from env `ANDROID_KEYSTORE` / `ANDROID_KEYSTORE_PASS`, never committed.
- Permissions: `INTERNET` only. No location, no contacts, no storage.
- Build < 60 MB. `targetSdk` current per Play policy.

## iOS
- Privacy manifest (`PrivacyInfo.xcprivacy`) with no tracking domains.
- App Transport Security: WSS only.

## Web
- Served over HTTPS; WebSocket is WSS; CORS on the gateway allows only the game origin.
- Build < 30 MB; threads disabled unless COOP/COEP headers are set.

## Deploy
- `scripts/deploy.sh staging` (agent-allowed after green). `scripts/deploy.sh prod` requires `CONFIRM=yes` and a human at the keyboard.
- Post-deploy: watch metrics 15 min; rollback = redeploy previous image tag.
