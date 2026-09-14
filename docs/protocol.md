# Client ↔ Server Protocol — source of truth

Version: **0** (skeleton; phase 2 defines v1 in T-2.1).
Transport: WebSocket (`ws`). Encoding: JSON until phase 4 (then MessagePack, ADR-003).
Every message is an object with a string field `t` (type) plus payload fields.
Direction: `C→S` = client sends an **intent**; `S→C` = server sends a **fact**. Never the other way.

Rules:
1. A message is added here **before** it is written in code.
2. The Zod schema for every message lives in `packages/shared-rules/src/protocol.ts` (`MESSAGE_TYPES` + schemas).
3. `scripts/gen_rules.py` emits `client/scripts/rules/protocol.gd` with the same type list.
4. `scripts/check_protocol_sync.sh` fails if the three disagree.
5. Server: Zod validate → rate limit → handler. Invalid = log + drop, never crash.

## Message table

| t | Direction | Fields | When sent | Server validation | On failure |
|---|---|---|---|---|---|
| `ping` | C→S | `ts: number` (client ms) | every 5 s | `ts` finite, ≥ 0 | drop |
| `pong` | S→C | `ts: number` (echo), `server_ts: number` | reply to ping | — | — |
| `error` | S→C | `code: string`, `msg_key: string` | any rejected intent | — | — |

`msg_key` is an i18n key from `docs/content/*.yaml`, never free text.

## Reserved for v1 (T-2.1) — not yet defined
`join`, `leave`, `input`, `state`, `attack`, `damage`, `loot`, `chat`.
