---
name: server-architecture
description: Real-time game server architecture for this project — 20Hz tick loop, light ECS, handler pattern (validate→authorize→apply→broadcast), interest management, two-fake-clients test template, Drizzle schema/repo pattern. Load before any work under server/.
---
# Server architecture (Hamirpaa)

## Layout
```
server/src/
  index.ts           # boot: config (Zod-validated env) → db → redis → ws → tick
  world/   tick.ts (20Hz loop), zone.ts, entities.ts (light ECS: Map<EntityId, Components>)
  combat/  handlers that call shared-rules reducers
  economy/ loot, shop, trade (escrow)
  net/     server.ts (ws), router.ts, ratelimit.ts, session.ts
  persistence/ schema.ts (Drizzle), repos/*.ts, write_queue.ts
  anticheat/ speed.ts, cooldown.ts, sanity.ts
```

## Tick loop
```ts
const TICK_MS = 50; // 20 Hz — comes from shared-rules constants, not a literal here
let last = performance.now();
setInterval(() => {
  const now = performance.now();
  const dt = (now - last) / 1000; last = now;
  for (const zone of zones.values()) zone.step(dt);      // pure: state' = reduce(state, intents, dt)
  broadcastDiffs();                                        // interest-managed
}, TICK_MS);
```
Rules: no `await` inside `step`; no DB calls in the tick; input intents are queued between ticks and drained inside `step`. Metrics: record tick duration, p95 target < 30 ms.

## Handler pattern
```ts
router.on("attack", {
  schema: AttackSchema,                       // from shared-rules/protocol.ts
  rate: { perSec: 10, burst: 20 },
  authorize: (s, msg) => s.player.alive && s.player.zone === msg.zone,
  apply: (s, msg, zone) => zone.queueIntent(s.playerId, msg),   // never mutates directly
});
```
Invalid schema → `log.warn({type, reason})` + drop + increment counter. 3 invalid in 10 s → disconnect.

## Interest management
Each player receives events only from entities within `INTEREST_RADIUS` (shared-rules constant). Zone keeps a spatial hash (cell = 256 px). `broadcastDiffs` iterates players → cells in radius → dedupe.

## Two-fake-clients test template
```ts
import { describe, it, expect } from "vitest";
import { startTestServer, FakeClient } from "./helpers/fake_client";
describe("attack", () => {
  it("both clients see the same hp after one hit", async () => {
    const srv = await startTestServer();
    const a = await FakeClient.join(srv, "A"), b = await FakeClient.join(srv, "B");
    a.send({ t: "attack", target: b.id });
    await srv.tick(2);
    expect(a.lastState().players[b.id].hp).toBe(b.lastState().players[b.id].hp);
    await srv.close();
  });
});
```

## Drizzle schema + repo
```ts
// persistence/schema.ts
export const characters = pgTable("characters", {
  id: uuid("id").primaryKey().defaultRandom(),
  userId: uuid("user_id").notNull().references(() => users.id),
  archetype: text("archetype").notNull(),
  level: integer("level").notNull().default(1),
  xp: integer("xp").notNull().default(0),
});
// persistence/repos/characters.ts — the only place that touches the table
export const CharacterRepo = { byUser: (db, userId) => db.select().from(characters).where(eq(characters.userId, userId)) };
```
Writes go through `write_queue.ts` (write-behind, flush every 5 s or 100 ops; crash test: ≤ 5 s loss). Migrations: `pnpm -C server drizzle-kit generate`; existing files in server/drizzle/ are protected.
