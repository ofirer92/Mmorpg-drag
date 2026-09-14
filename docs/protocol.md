# Client ↔ Server Protocol — source of truth

Version: **1** (`PROTOCOL_VERSION = 1` in `packages/shared-rules/src/protocol.ts`).
Transport: WebSocket (`ws`). Encoding: JSON until phase 4 (then MessagePack, ADR-003).
Every message is an object with a string field `t` (type) plus payload fields.
Direction: `C→S` = client sends an **intent**; `S→C` = server sends a **fact**. Never the other way.

Rules:

1. A message is added here **before** it is written in code.
2. The Zod schema for every message lives in `packages/shared-rules/src/protocol.ts` (`MESSAGE_TYPES` + schemas).
3. `scripts/gen_rules.py` emits `client/scripts/rules/protocol.gd` with the same type list.
4. `scripts/check_protocol_sync.sh` fails if the three disagree.
5. Server: Zod validate → rate limit → authorize → apply → broadcast. Invalid = log + drop, never crash.
6. Every object schema is `.strict()`: one unknown field rejects the whole message. This makes protocol
   drift loud instead of silent, and stops a client from smuggling extra fields past a handler.
7. **A type has exactly one direction.** `DIRECTION` is `Record<MessageType, "C2S" | "S2C">`, so an intent and
   a fact that carry different payloads get different names (`chat` C→S vs `chat_msg` S→C,
   `loot_pickup` C→S vs `loot` S→C).
8. **Facts never omit a field.** S→C payloads always carry every key; "nothing here" is `null`
   (`died.drop_id: null`). Intents (C→S) may omit optional keys (`input.skill_id`). GDScript reads a missing
   key as an error and a `null` as a value, so this rule keeps the client parser branch-free.

## Message table

| t             | Direction | Fields                                                                                                                                                        | When sent                                                                                                      | Server validation                                                                                                                                                                         | On failure                                                                                                                 |
| ------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| `ping`        | C→S       | `ts: number` (client ms, finite ≥ 0)                                                                                                                          | every 5 s                                                                                                      | `ts` finite, ≥ 0; rate 1/s burst 4                                                                                                                                                        | drop + `error` `invalid_message`                                                                                           |
| `pong`        | S→C       | `ts: number` (echo), `server_ts: number`                                                                                                                      | reply to `ping`                                                                                                | —                                                                                                                                                                                         | —                                                                                                                          |
| `error`       | S→C       | `code: string ≤64`, `msg_key: string ≤128`                                                                                                                    | any rejected intent                                                                                            | —                                                                                                                                                                                         | —                                                                                                                          |
| `join`        | C→S       | `protocol: int 0..65535`, `token: string 1..512`, `character_id: string 1..64`                                                                                | once, first message after the socket opens                                                                     | schema; `protocol == PROTOCOL_VERSION`; token resolves to a session; character belongs to that account; character not already in a zone; zone has < 64 players; socket not already joined | `error` + close: `protocol_mismatch` / `invalid_token` / `zone_full`; second `join` on the same socket → `invalid_message` |
| `joined`      | S→C       | `player_id: string`, `zone_id: string ≤64`, `tick: int`, `tick_ms: int 1..1000`, `state: Snapshot`                                                            | reply to an accepted `join`, to that client only                                                               | —                                                                                                                                                                                         | —                                                                                                                          |
| `leave`       | C→S       | _(none)_                                                                                                                                                      | player clicks "log out" / changes zone                                                                         | must be joined; rate 1/s burst 2                                                                                                                                                          | drop (the socket closing has the same effect)                                                                              |
| `left`        | S→C       | `player_id: string`                                                                                                                                           | broadcast to the zone when a player leaves, disconnects or times out                                           | —                                                                                                                                                                                         | —                                                                                                                          |
| `input`       | C→S       | `seq: int 0..2^31-1`, `tick: int 0..2^31-1`, `dir: -1 \| 0 \| 1`, `jump: bool`, `attack: bool`, `skill_id?: string ≤32`                                       | every tick (20 Hz) while joined, even when idle                                                                | must be joined and alive; `seq > last_seq[player]` (monotonic, no dupes); `tick` within ±40 ticks of the server tick; rate 25/s burst 50                                                  | drop silently (no `error`: see "Amplification"); > 50/s → token bucket drops + `rate_limited`                              |
| `state`       | S→C       | `Snapshot` inlined: `tick: int`, `last_seq: Record<player_id, int>`, `players: PlayerState[] ≤64`, `monsters: MonsterState[] ≤256`, `drops: DropState[] ≤256` | every tick (20 Hz) to every joined client, interest-managed                                                    | —                                                                                                                                                                                         | —                                                                                                                          |
| `attack`      | S→C       | `attacker_id: string`, `skill_id: string ≤32 \| null`, `target_ids: string[] ≤16`                                                                             | the server **accepted** an attack intent, before the resulting `damage`; broadcast to the zone (animation cue) | —                                                                                                                                                                                         | —                                                                                                                          |
| `damage`      | S→C       | `target_id: string`, `attacker_id: string \| null`, `amount: int 0..1e6`, `new_hp: int 0..1e6`, `crit: bool`                                                  | after `RulesCombat.damage` resolves a hit                                                                      | —                                                                                                                                                                                         | —                                                                                                                          |
| `died`        | S→C       | `id: string`, `killer_id: string \| null`, `xp: int 0..1e9`, `drop_id: string \| null`, `item_id: string \| null`, `money: int 0..1e9`                        | when an entity's hp reaches 0, after the last `damage`                                                         | —                                                                                                                                                                                         | —                                                                                                                          |
| `loot_pickup` | C→S       | `drop_id: string 1..64`                                                                                                                                       | player overlaps a drop and presses pick-up                                                                     | must be joined and alive; drop exists, unclaimed, within `PICKUP_RADIUS_PX` of the player; inventory has room; rate 5/s burst 10                                                          | `error` `not_alive`; other cases → `loot` with `added: false` to the requester only                                        |
| `loot`        | S→C       | `player_id: string`, `drop_id: string`, `item_id: string \| null`, `money: int 0..1e9`, `added: bool`                                                         | after a `loot_pickup` is resolved — `added: true` broadcast to the zone, `added: false` to the requester only  | —                                                                                                                                                                                         | —                                                                                                                          |
| `chat`        | C→S       | `text: string 1..200` (no control chars, not blank), `channel: "zone" \| "party"`                                                                             | player presses Enter in the chat box                                                                           | must be joined (dead players may chat); text length/charset; `party` requires party membership; rate 1/s burst 3                                                                          | `error` `invalid_message`; over rate → `rate_limited`                                                                      |
| `chat_msg`    | S→C       | `player_id: string`, `channel: "zone" \| "party"`, `text: string ≤200`, `ts: number` (server ms)                                                              | after an accepted `chat`, to the zone or to the party                                                          | —                                                                                                                                                                                         | —                                                                                                                          |

`msg_key` is an i18n key from `docs/content/*.yaml`, never free text.

## Payload sub-schemas

Shared shapes, all `.strict()` (see `packages/shared-rules/src/protocol.ts`):

- **Vec2** — `x, y: number`, finite, `|v| ≤ 1e6` px.
- **PlayerState** — `id: string ≤64`, `name: string ≤24`, `pos: Vec2`, `vel: Vec2`, `hp: int 0..1e6`,
  `max_hp: int 1..1e6`, `level: int 1..1000`, `xp: int 0..1e9`, `facing: -1 | 1`, `anim: string ≤32`,
  `alive: bool`.
- **MonsterState** — `id`, `kind: string ≤32` (balance key, picks the sprite), `pos`, `vel`, `hp`, `max_hp`,
  `level`, `facing`, `anim`, `alive`.
- **DropState** — `id: string ≤64`, `pos: Vec2`, `item_id: string ≤64 | null`, `money: int 0..1e9`,
  `expires_tick: int`.
- **Snapshot** — `tick`, `last_seq: Record<player_id, seq>` (≤ 64 entries), `players ≤64`,
  `monsters ≤256`, `drops ≤256`.

`anim` is an opaque animation name; a client that does not know it falls back to `idle` rather than
failing to parse — animation names are content, not protocol.

`level`'s ceiling of 1000 is a **sanity bound, not a balance number**: the authoritative cap is
`XP_CURVE.max_level` in `docs/balance/xp_curve.yaml`. Wiring the wire schema to a balance file would mean a
balance tweak silently invalidates older clients, so the two are deliberately decoupled (CLAUDE.md bans
hardcoded _balance_ numbers in client/server code; these are transport limits and they live in one place).

## Sequences

### 1. Join handshake

```
C: (opens WebSocket)
C→S  join        {protocol: 1, token: "...", character_id: "char_7"}
        server: schema → protocol == 1 → token → character → zone capacity
S→C  joined      {player_id: "p_7", zone_id: "clinic_lobby", tick: 91234, tick_ms: 50, state: {...}}
S→C  state       ... every tick from here on
        peers are NOT sent a "joined": the new player simply appears in their next `state`.
```

Rejection (any of the checks above):

```
C→S  join        {protocol: 0, ...}
S→C  error       {code: "protocol_mismatch", msg_key: "error.protocol_mismatch"}
     (server closes the socket; the client shows the msg_key and offers "update")
```

`join` with the wrong `protocol` value is a **schema-valid message** — the field is just `int 0..65535`.
Version negotiation is a _handler_ concern, on purpose: a schema rejection is an anonymous
`invalid_message` drop, while an old client must get a readable `protocol_mismatch` before the socket
closes. If the schema policed the version, every outdated client would see "invalid form" instead of
"please update".

### 2. Per-tick input / state loop (20 Hz, `TICK_MS`)

```
tick N     C→S  input {seq: 412, tick: 91234, dir: 1, jump: false, attack: false}
                  client predicts locally and keeps input 412 in its replay buffer
           server: queue intent; drain inside zone.step(dt); apply RulesMovement
tick N+1   S→C  state {tick: 91235, last_seq: {"p_7": 412}, players: [...], ...}
                  client: if predicted_pos(412) != state.pos(p_7) → snap + replay 413.. from the buffer
```

`last_seq` is what makes reconciliation possible: it is the highest `input.seq` the server has _applied_
for that player. Inputs with `seq <= last_seq` are duplicates/replays and are dropped without a reply.
The client sends an `input` every tick even when nothing is pressed, so a gap in `seq` means packet loss,
not idleness.

### 3. Attack → damage → death

```
C→S  input  {seq: 500, tick: 91300, dir: 0, jump: false, attack: true, skill_id: "stim_double_dose"}
       server: alive? cooldown ready? skill unlocked? targets in range? (all via shared-rules)
S→C  attack {attacker_id: "p_7", skill_id: "stim_double_dose", target_ids: ["m_12"]}   ← animation cue
S→C  damage {target_id: "m_12", attacker_id: "p_7", amount: 37, new_hp: 0, crit: true}
S→C  died   {id: "m_12", killer_id: "p_7", xp: 25, drop_id: "d_88", item_id: "intern_coat", money: 0}
S→C  state  {tick: 91301, ...}   ← monster gone / marked dead, drop d_88 present
```

A rejected attack produces **no** `attack` and **no** `error` (the intent rode inside a 20 Hz `input`;
see "Amplification"). The client's local animation is cosmetic and is cancelled when no `attack` fact
arrives; hp on screen only ever changes because of `damage` / `state`. The client never computes damage
(CLAUDE.md; ADR-013 — the phase-0 `LocalServer` node emits exactly these facts, so T-2.3 swaps the node
for the socket without touching the player/monster scenes).

`killer_id` exists so the client can tell whose `xp` this is; without it `died.xp` is unattributable.
There is no `xp_gained` / `level_up` message in v1: `PlayerState.xp` and `.level` in the next `state`
carry that, and the client fires the level-up VFX when the level it sees goes up.

### 4. Loot

```
S→C  state       {..., drops: [{id: "d_88", pos: {...}, item_id: "intern_coat", money: 0, expires_tick: 92500}]}
C→S  loot_pickup {drop_id: "d_88"}
       server: alive? drop exists & unclaimed? within PICKUP_RADIUS_PX? bag has room?
S→C  loot        {player_id: "p_7", drop_id: "d_88", item_id: "intern_coat", money: 0, added: true}
S→C  state       {..., drops: []}
```

`PICKUP_RADIUS_PX` is a shared-rules constant that T-2.2 adds next to `INTEREST_RADIUS_PX`; it is a
server-side range check, never a client claim.

Bag full / out of range / already taken → `loot {..., added: false}` **to the requester only**, so the
client can un-highlight the drop and show `ui.shop.full`-style feedback. Dead players get
`error {code: "not_alive", msg_key: "error.not_alive"}`; pick-up is rare enough that a reply is not an
amplification risk. The drop is removed from the world only by the server; `added: true` is the single
authoritative "it is yours now".

### 5. Chat

```
C→S  chat     {text: "מישהו ראה את הרוקח?", channel: "zone"}
       server: joined? length 1..200? no control chars? party membership for "party"? ≤ 1/s
S→C  chat_msg {player_id: "p_7", channel: "zone", text: "מישהו ראה את הרוקח?", ts: 1757800000123}
```

The server echoes the message back to the sender too (via the same broadcast), so the sender's chat log
is ordered by the server, not by local optimism. Dead players may chat.

## Bounds rationale (anticheat review)

Every bound below is in the Zod schema, not in a handler, so it holds for the server _and_ for the
generated fixtures and sim clients.

**Forged values.** The union is `.strict()` and discriminated on `t`, so a client cannot send a fact:
`state`, `damage`, `died`, `loot` and `chat_msg` are not in `ClientMessageSchema` at all. A client that
posts `{t: "damage", new_hp: 9999}` is dropped at parse time and counted as an invalid message (3 in 10 s
→ disconnect, see `server/src/net/server.ts`). Numbers are `.finite()` so `Infinity`/`NaN` (which JSON
carries as `1e999` / `null`) can never reach a rule function and poison a position or an hp; indices and
counters are `.int()` so `seq: 1.5` cannot sit between two integers and replay forever.

**Huge values.** Every string has `.max()` (token 512, chat 200, ids 64, anim/skill 32, name 24) and every
array has `.max()` (targets 16, players 64, monsters 256, drops 256, `last_seq` 64 keys). Without these, a
single 10 MB `chat.text` or a 1e6-entry `target_ids` is an allocation DoS _before_ any handler runs.
`parseClientMessage` also refuses any frame longer than `MAX_CLIENT_MESSAGE_BYTES` (4096) **before**
`JSON.parse`, which is the only cheap defence against a deeply nested JSON bomb. Per-type worst cases fit
well inside it: `join` ≈ 620 B, `chat` ≈ 830 B (200 chars × 4 B UTF-8 worst case), `input` ≈ 120 B,
`loot_pickup` ≈ 90 B, `leave`/`ping` ≈ 40 B. Note that the check is on JS string _length_ (UTF-16 units),
which under-counts bytes by up to 3× for Hebrew/emoji — 4096 units is still a hard ceiling on work done.
`parseServerMessage` uses a much larger cap (`MAX_SERVER_MESSAGE_BYTES`, 256 KiB) because a full
`state` with 64 players + 256 monsters + 256 drops is ≈ 90 KB of JSON; the client uses it to protect
itself from a wedged/compromised server rather than to police the protocol.

**Sent 1000×/s.** Bounds cannot stop a flood, so the rate column above is part of the contract: the token
bucket in `server/src/net/ratelimit.ts` runs _before_ the handler, and `input` (25/s) is the only
high-frequency type. `state` is emitted by the tick loop, never by a client request, so no intent can make
the server fan out more work than one tick's worth.

**Amplification.** High-frequency intents (`input`) are dropped **silently** when they fail authorization.
Replying with an `error` to every 20 Hz input would let a dead or desynced client pull 20 responses/s out
of the server per socket, and would turn one bad client into a broadcast storm. Low-frequency intents
(`join`, `leave`, `loot_pickup`, `chat`) do get an `error`, because a human-paced action that fails
silently is a bug report.

**Sent while dead.** `alive` is a server fact in `PlayerState`, never a client claim. `input` from a dead
player parses fine but is dropped in `authorize` (movement/attack are ignored until respawn);
`loot_pickup` returns `error.not_alive`; `chat` and `leave` are allowed while dead. There is no "respawn"
intent in v1 — respawn is server-driven and shows up as `alive: true` with a new `pos` in `state`.

**Replay / ordering.** `input.seq` must strictly increase per player, so a captured packet replayed later
is dropped; `input.tick` is clamped to ±40 ticks (±2 s) of the server tick so a client cannot claim to be
acting far in the past or future. WebSocket is ordered and reliable, so no other sequencing is needed.

## Error codes

| msg_key                   | code                | Meaning                                                          |
| ------------------------- | ------------------- | ---------------------------------------------------------------- |
| `error.invalid_message`   | `invalid_message`   | schema/JSON/size rejection, or an intent sent in the wrong state |
| `error.rate_limited`      | `rate_limited`      | token bucket empty                                               |
| `error.protocol_mismatch` | `protocol_mismatch` | `join.protocol != PROTOCOL_VERSION`; socket closes after         |
| `error.invalid_token`     | `invalid_token`     | token unknown/expired, or character not owned by the account     |
| `error.zone_full`         | `zone_full`         | the zone already holds 64 players                                |
| `error.not_alive`         | `not_alive`         | the intent requires a living player (`loot_pickup`)              |

## Changelog

- **v1 (T-2.1)** — join/leave/input/state/attack/damage/died/loot/chat added; `PROTOCOL_VERSION = 1`.
  Not yet implemented by any handler: T-2.2 (server) and T-2.3 (client) do that.
- **v0** — `ping`/`pong`/`error` skeleton.
