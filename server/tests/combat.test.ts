// T-2.4: combat through the server. Two fake clients (server-architecture skill's template) for the
// DoD ("2 clients see the same hp"); the rest use a single client against a monster spawned right
// next to the player (server/tests/helpers/combat_map.ts) so combat resolves from tick 1 without
// walking clinic_lobby's real distances.
import { afterEach, describe, expect, it } from "vitest";
import { PROTOCOL_VERSION, balance, damage, damage_taken } from "@hamirpaa/shared-rules";
import { startTestServer, FakeClient } from "./helpers/fake_client.js";
import { combatMap } from "./helpers/combat_map.js";
import { Zone } from "../src/world/zone.js";
import { MONSTER_ATTACK_POWER } from "../src/world/monster_sim.js";
import type { GameServer } from "../src/net/server.js";

async function join(url: string, characterId: string): Promise<{ client: FakeClient; playerId: string }> {
  const client = await FakeClient.join(url);
  client.send({ t: "join", protocol: PROTOCOL_VERSION, token: "sim", character_id: characterId });
  const joined = await client.next((m) => m["t"] === "joined");
  return { client, playerId: joined["player_id"] as string };
}

type Msg = Record<string, unknown>;
type Monsters = Array<{ id: string; hp: number; alive: boolean }>;
type Players = Array<{ id: string; alive: boolean; hp: number }>;

describe("combat: attack → damage → death (T-2.4)", () => {
  let server: GameServer;
  let url: string;

  afterEach(async () => {
    await server.close();
  });

  /** Advances the server clock N ticks, yielding to the event loop after each one so FakeClient has
   * actually received everything before the test inspects it (WS delivery is async even on loopback —
   * see room.test.ts). Also returns the tick count so callers can build a valid `input.tick`. */
  async function stepN(n: number, tick: number): Promise<number> {
    let t = tick;
    for (let i = 0; i < n; i++) {
      // Wait for any just-sent WS message to actually arrive (async even on loopback, see
      // room.test.ts) BEFORE stepping, so a queued input is applied on the tick the test expects.
      await new Promise((r) => setTimeout(r, 5));
      server.step(0.05);
      t += 1;
    }
    // ...and wait once more so the LAST step's broadcast (attack/damage/died/state) has actually
    // arrived before a caller inspects FakeClient.received synchronously (tests that instead use
    // client.next(), which polls, don't strictly need this — but it's cheap and makes every caller safe).
    await new Promise((r) => setTimeout(r, 5));
    return t;
  }

  it("both clients see the identical monster hp in their next state after A attacks (DoD)", async () => {
    const zone = new Zone("combat_test", combatMap("side_effect_slime"), { seed: 1 });
    ({ server, url } = await startTestServer({ zone }));
    const a = await join(url, "char_a");
    const b = await join(url, "char_b");

    a.client.send({ t: "input", seq: 1, tick: 0, dir: 0, jump: false, attack: true });
    await stepN(1, 0);

    const stateA = await a.client.next((m) => m["t"] === "state" && (m["monsters"] as Monsters).length === 1);
    const stateB = await b.client.next((m) => m["t"] === "state" && (m["monsters"] as Monsters).length === 1);
    const monA = (stateA["monsters"] as Monsters)[0];
    const monB = (stateB["monsters"] as Monsters)[0];
    expect(monA).toBeDefined();
    expect(monA).toEqual(monB);
    expect(monA?.hp).toBeLessThan(60); // side_effect_slime's hp (docs/balance/monsters.yaml)
    a.client.close();
    b.client.close();
  });

  it("an out-of-range attack does nothing (no damage, monster hp unchanged)", async () => {
    const zone = new Zone("combat_test", combatMap("side_effect_slime", { cellsAway: 10 }), { seed: 1 });
    ({ server, url } = await startTestServer({ zone }));
    const a = await join(url, "char_a");

    a.client.send({ t: "input", seq: 1, tick: 0, dir: 0, jump: false, attack: true });
    await stepN(1, 0);

    const state = await a.client.next((m) => m["t"] === "state");
    const mon = (state["monsters"] as Monsters)[0];
    expect(mon?.hp).toBe(60);
    expect(a.client.received.filter((m) => m["t"] === "damage")).toHaveLength(0);
    a.client.close();
  });

  it("an attack from a dead player is ignored", async () => {
    const zone = new Zone("combat_test", combatMap("side_effect_slime"), { seed: 2 });
    ({ server, url } = await startTestServer({ zone }));
    const a = await join(url, "char_a");
    server.debugSetPlayerHp(a.playerId, 1);
    const t = await stepN(6, 0); // point-blank monster kills the 1-hp player within a few ticks
    expect(a.client.received.some((m) => m["t"] === "died" && m["id"] === a.playerId)).toBe(true);

    const before = a.client.received.filter(
      (m) => m["t"] === "attack" && m["attacker_id"] === a.playerId,
    ).length;
    expect(before).toBe(0); // the player never got an attack off before dying
    a.client.send({ t: "input", seq: 1, tick: t, dir: 0, jump: false, attack: true });
    await stepN(1, t);
    const after = a.client.received.filter(
      (m) => m["t"] === "attack" && m["attacker_id"] === a.playerId,
    ).length;
    expect(after).toBe(0); // still 0 — a dead player's attack intent never resolves
    a.client.close();
  });

  it("cooldown is enforced on the server clock (second use rejected, allowed after the cooldown)", async () => {
    const zone = new Zone("combat_test", combatMap("side_effect_slime"), { seed: 3 });
    ({ server, url } = await startTestServer({ zone }));
    const a = await join(url, "char_a");
    server.debugSetPlayerLevel(a.playerId, 3); // unlocks stim_double_dose (docs/balance/classes.yaml: cooldown 4s)

    a.client.send({
      t: "input",
      seq: 1,
      tick: 0,
      dir: 0,
      jump: false,
      attack: true,
      skill_id: "stim_double_dose",
    });
    let t = await stepN(1, 0);
    console.log("DEBUG received:", JSON.stringify(a.client.received));
    expect(a.client.received.some((m) => m["t"] === "attack" && m["skill_id"] === "stim_double_dose")).toBe(
      true,
    );

    a.client.send({
      t: "input",
      seq: 2,
      tick: t,
      dir: 0,
      jump: false,
      attack: true,
      skill_id: "stim_double_dose",
    });
    t = await stepN(1, t);
    const acceptedSoFar = a.client.received.filter(
      (m) => m["t"] === "attack" && m["skill_id"] === "stim_double_dose",
    );
    expect(acceptedSoFar).toHaveLength(1); // second use, still on cooldown → no new `attack` fact

    t = await stepN(80, t); // 80 × 50ms = 4s, past the cooldown
    a.client.send({
      t: "input",
      seq: 3,
      tick: t,
      dir: 0,
      jump: false,
      attack: true,
      skill_id: "stim_double_dose",
    });
    await stepN(1, t);
    const acceptedAfterCooldown = a.client.received.filter(
      (m) => m["t"] === "attack" && m["skill_id"] === "stim_double_dose",
    );
    expect(acceptedAfterCooldown).toHaveLength(2);
    a.client.close();
  });

  it("crash after 4 consecutive landed hits doubles the damage the attacker takes", async () => {
    const zone = new Zone("combat_test", combatMap("side_effect_slime"), { seed: 4 });
    ({ server, url } = await startTestServer({ zone }));
    const a = await join(url, "char_a");

    // The monster swings every 1/attack_speed s (1.25 s = 25 ticks at 20 Hz), so a 4-tick combo is far
    // too short for it to answer inside. Take a BASELINE hit first (no crash), then land the combo,
    // then let it swing again while the 2 s crash is still running.
    let t = 0;
    t = await stepN(40, t); // ≥ 1 monster swing at 25-tick intervals — the pre-crash baseline
    for (let seq = 1; seq <= 4; seq++) {
      a.client.send({ t: "input", seq, tick: t, dir: 0, jump: false, attack: true }); // basic skill (stim_jab, cooldown 0)
      t = await stepN(1, t);
    }
    // Crash lasts 2 s (40 ticks) from the 4th landed hit; 30 more ticks covers the monster's next
    // swing while it is still active. The monster is still alive at ~16/60 hp, so it keeps swinging.
    await stepN(30, t);

    const monsterDef = balance.MONSTERS.monsters.side_effect_slime;
    if (monsterDef === undefined)
      throw new Error("test fixture: side_effect_slime missing from balance.MONSTERS");
    const playerBase = balance.CLASSES.archetypes.stim;
    const attackerView = {
      attack: monsterDef.attack,
      defense: monsterDef.defense,
      level: monsterDef.level,
      hp: 0,
    };
    const defenderView = {
      attack: playerBase.base_attack,
      defense: playerBase.base_defense,
      level: 1,
      hp: 0,
    };
    // damage()'s magnitude only depends on whether `roll < CRIT_CHANCE`, never on the roll's exact
    // value past that boundary (see packages/shared-rules/src/combat.ts) — so replaying the observed
    // `crit` flag through the same formula reproduces the exact base damage deterministically,
    // without needing to predict the server's internal rng call sequence.
    const expectedBase = (crit: boolean): number =>
      damage(attackerView, defenderView, MONSTER_ATTACK_POWER, crit ? 0 : 1);

    const events = a.client.received;
    const playerHits = events.filter((m) => m["t"] === "damage" && m["attacker_id"] === a.playerId);
    expect(playerHits.length).toBeGreaterThanOrEqual(4);
    const fourthHitIndex = events.indexOf(playerHits[3] as Msg);
    const monsterHits = events.filter((m) => m["t"] === "damage" && m["target_id"] === a.playerId);
    expect(monsterHits.length).toBeGreaterThanOrEqual(2);
    const beforeCrash = monsterHits.find((m) => events.indexOf(m) < fourthHitIndex);
    const afterCrash = monsterHits.find((m) => events.indexOf(m) > fourthHitIndex);
    expect(beforeCrash).toBeDefined();
    expect(afterCrash).toBeDefined();
    expect(beforeCrash?.["amount"]).toBe(expectedBase(beforeCrash?.["crit"] as boolean));
    expect(afterCrash?.["amount"]).toBe(damage_taken(expectedBase(afterCrash?.["crit"] as boolean), true));
    a.client.close();
  });

  it("a monster kills a player: hp reaches 0, `died` is emitted, and the player respawns after the documented delay", async () => {
    const zone = new Zone("combat_test", combatMap("side_effect_slime"), { seed: 5 });
    ({ server, url } = await startTestServer({ zone }));
    const a = await join(url, "char_a");
    server.debugSetPlayerHp(a.playerId, 1);

    await stepN(6, 0);
    const died = a.client.received.find((m) => m["t"] === "died" && m["id"] === a.playerId);
    expect(died).toBeDefined();
    expect(died?.["killer_id"]).toBe("m_1");
    const stateAfterDeath = a.client.received.filter((m) => m["t"] === "state").at(-1) as Msg;
    const meAfterDeath = (stateAfterDeath["players"] as Players).find((p) => p.id === a.playerId);
    expect(meAfterDeath?.alive).toBe(false);

    // Documented respawn behaviour (world/zone.ts's PLAYER_RESPAWN_DELAY_S, mirroring
    // clinic_lobby.gd's RESPAWN_DELAY_S): 2s (40 ticks) after dying the player is alive again, full
    // hp, back at the map's spawn — entirely server-driven, there is no client "respawn" intent in
    // protocol v1 (docs/protocol.md § "Sent while dead").
    await stepN(45, 6);
    const latest = a.client.received.filter((m) => m["t"] === "state").at(-1) as Msg;
    const meNow = (latest["players"] as Players).find((p) => p.id === a.playerId);
    expect(meNow?.alive).toBe(true);
    expect(meNow?.hp).toBeGreaterThan(0);
    a.client.close();
  });
});
