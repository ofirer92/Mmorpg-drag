import { describe, expect, it } from "vitest";
import { balance, GRAVITY_PX, JUMP_VELOCITY_PX, MOVE_SPEED_PX, TICK_MS } from "@hamirpaa/shared-rules";
import { isSolid, moveAndCollide, type MapDef } from "../src/world/tilemap.js";
import { createPlayerState, stepPlayer, PLAYER_HEIGHT_PX, PLAYER_WIDTH_PX } from "../src/world/player_sim.js";
import { createDefaultZone, DEFAULT_ZONE_ID } from "../src/world/zone.js";

const map = balance.MAPS[DEFAULT_ZONE_ID];
if (map === undefined) throw new Error("test fixture: clinic_lobby map missing from balance.MAPS");
const DT = TICK_MS / 1000;

function floorInput(dir: -1 | 0 | 1 = 0, jump = false) {
  return { seq: 1, dir, jump, attack: false };
}

// A small isolated flat-floor map so tilemap/player_sim tests don't depend on clinic_lobby's exact
// platform layout — one row of ground at the bottom, walls left/right, air everywhere else.
function flatMap(): MapDef {
  const cols = 20;
  const rows = 10;
  const rowsArr: string[] = [];
  for (let r = 0; r < rows; r++) {
    if (r === rows - 1) {
      rowsArr.push("#".repeat(cols));
    } else {
      rowsArr.push("W" + ".".repeat(cols - 2) + "W");
    }
  }
  return {
    id: "flat_test",
    tile_size: 32,
    cols,
    rows,
    spawn: { x: 160, y: 32 * (rows - 1) - 16 - 1 },
    solid_chars: ["#", "W"],
    layout: rowsArr,
  };
}

describe("tilemap.isSolid", () => {
  const m = flatMap();
  it("ground row is solid everywhere", () => {
    for (let c = 0; c < m.cols; c++) expect(isSolid(m, c, m.rows - 1)).toBe(true);
  });
  it("air cells are not solid", () => {
    expect(isSolid(m, 5, 3)).toBe(false);
  });
  it("side walls are solid", () => {
    expect(isSolid(m, 0, 2)).toBe(true);
    expect(isSolid(m, m.cols - 1, 2)).toBe(true);
  });
  it("out-of-bounds cells are not solid (moveAndCollide clamps separately)", () => {
    expect(isSolid(m, -1, 0)).toBe(false);
    expect(isSolid(m, m.cols, 0)).toBe(false);
    expect(isSolid(m, 0, -1)).toBe(false);
    expect(isSolid(m, 0, m.rows)).toBe(false);
  });
});

describe("tilemap.moveAndCollide", () => {
  const m = flatMap();
  it("a falling body lands on the ground and reports onFloor", () => {
    let aabb = { x: 160, y: 0, w: PLAYER_WIDTH_PX, h: PLAYER_HEIGHT_PX };
    let vel = { x: 0, y: 0 };
    let onFloor = false;
    for (let i = 0; i < 200 && !onFloor; i++) {
      vel = { x: 0, y: Math.min(900, vel.y + GRAVITY_PX * DT) };
      const r = moveAndCollide(m, aabb, vel, DT);
      aabb = { ...aabb, x: r.pos.x, y: r.pos.y };
      vel = r.vel;
      onFloor = r.onFloor;
    }
    expect(onFloor).toBe(true);
    // bottom of the box rests on (or a sub-pixel above, from the 1px-step sweep) the ground row —
    // never below it.
    const groundY = (m.rows - 1) * m.tile_size;
    expect(aabb.y + aabb.h).toBeLessThanOrEqual(groundY + 0.001);
    expect(aabb.y + aabb.h).toBeGreaterThan(groundY - 1);
  });

  it("a body resting on the ground cannot be pushed through it by a huge downward velocity", () => {
    const groundY = (m.rows - 1) * m.tile_size;
    const aabb = { x: 160, y: groundY - PLAYER_HEIGHT_PX, w: PLAYER_WIDTH_PX, h: PLAYER_HEIGHT_PX };
    const r = moveAndCollide(m, aabb, { x: 0, y: 100_000 }, DT);
    expect(r.pos.y + PLAYER_HEIGHT_PX).not.toBeGreaterThan(groundY + 0.001);
    expect(r.onFloor).toBe(true);
  });

  it("a wall stops horizontal movement", () => {
    const aabb = { x: 32, y: 32, w: PLAYER_WIDTH_PX, h: PLAYER_HEIGHT_PX };
    const r = moveAndCollide(m, aabb, { x: -10_000, y: 0 }, DT);
    expect(r.vel.x).toBe(0);
    expect(r.pos.x).toBeGreaterThanOrEqual(m.tile_size - 0.001);
  });

  it("clamps to map pixel bounds", () => {
    const aabb = { x: 5, y: 5, w: PLAYER_WIDTH_PX, h: PLAYER_HEIGHT_PX };
    const r = moveAndCollide(m, aabb, { x: -10_000, y: -10_000 }, DT);
    expect(r.pos.x).toBeGreaterThanOrEqual(0);
    expect(r.pos.y).toBeGreaterThanOrEqual(0);
  });
});

describe("player_sim.stepPlayer", () => {
  const m = flatMap();

  it("walking reaches exactly MOVE_SPEED_PX after enough ticks", () => {
    // ACCEL_PX/dt reaches MOVE_SPEED_PX in ~3 ticks; keep the walk short so the flat map's walls
    // (20 tiles wide) never come into play — this test is about step_horizontal, not collision.
    let state = createPlayerState(m.spawn);
    for (let i = 0; i < 15; i++) state = stepPlayer(state, floorInput(1), DT, m);
    expect(state.vel.x).toBe(MOVE_SPEED_PX);
  });

  it("lands and stays on the floor, never falling through it", () => {
    let state = createPlayerState({ x: 160, y: 0 });
    for (let i = 0; i < 300; i++) state = stepPlayer(state, floorInput(0), DT, m);
    expect(state.onFloor).toBe(true);
    const groundY = (m.rows - 1) * m.tile_size;
    const feetY = state.pos.y + PLAYER_HEIGHT_PX / 2;
    expect(feetY).toBeLessThanOrEqual(groundY + 0.001);
    expect(feetY).toBeGreaterThan(groundY - 1);
  });

  it("a wall stops horizontal walking", () => {
    let state = createPlayerState({ x: 60, y: (m.rows - 1) * m.tile_size - PLAYER_HEIGHT_PX / 2 - 1 });
    for (let i = 0; i < 200; i++) state = stepPlayer(state, floorInput(-1), DT, m);
    expect(state.vel.x).toBe(0);
    expect(state.pos.x - PLAYER_WIDTH_PX / 2).toBeGreaterThanOrEqual(m.tile_size - 0.5);
  });

  it("jump apex height is close to v²/2g (grounded jump, no horizontal input)", () => {
    let state = createPlayerState({ x: 160, y: (m.rows - 1) * m.tile_size - PLAYER_HEIGHT_PX / 2 });
    // one tick to register onFloor at the resting spawn point
    state = stepPlayer(state, floorInput(0), DT, m);
    expect(state.onFloor).toBe(true);
    const startY = state.pos.y;
    state = stepPlayer(state, floorInput(0, true), DT, m);
    let minY = state.pos.y;
    for (let i = 0; i < 200 && state.vel.y <= 0; i++) {
      state = stepPlayer(state, floorInput(0, true), DT, m);
      minY = Math.min(minY, state.pos.y);
    }
    const apexHeight = startY - minY;
    const expected = (JUMP_VELOCITY_PX * JUMP_VELOCITY_PX) / (2 * GRAVITY_PX);
    expect(apexHeight).toBeGreaterThan(expected * 0.5);
    expect(apexHeight).toBeLessThan(expected * 1.5);
  });

  it("is deterministic: same state+input+dt+map always produce the same result", () => {
    const s0 = createPlayerState({ x: 160, y: 160 });
    const input = floorInput(1, true);
    const a = stepPlayer(s0, input, DT, m);
    const b = stepPlayer(s0, input, DT, m);
    expect(a).toEqual(b);
  });
});

describe("Zone", () => {
  it("starts empty, at tick 0, snapshot has no players", () => {
    const zone = createDefaultZone();
    expect(zone.playerCount).toBe(0);
    expect(zone.tick).toBe(0);
    expect(zone.snapshot().players).toHaveLength(0);
  });

  it("spawns a joining player at the map's spawn point", () => {
    const zone = createDefaultZone();
    zone.addPlayer("p1", "P1");
    const snap = zone.snapshot();
    expect(snap.players).toHaveLength(1);
    expect(snap.players[0]?.pos.x).toBe(map.spawn.x);
    expect(snap.players[0]?.pos.y).toBe(map.spawn.y);
  });

  it("applies the latest queued input per tick and advances last_seq", () => {
    const zone = createDefaultZone();
    zone.addPlayer("p1", "P1");
    zone.queueInput("p1", { seq: 1, dir: 1, jump: false, attack: false });
    zone.step(DT);
    expect(zone.lastSeqOf("p1")).toBe(1);
    const snap1 = zone.snapshot();
    expect(snap1.tick).toBe(1);
    expect(snap1.last_seq["p1"]).toBe(1);
    expect(snap1.players[0]?.vel.x).toBeGreaterThan(0);
  });

  it("drops a duplicate/out-of-order seq silently (no throw, last_seq unchanged)", () => {
    const zone = createDefaultZone();
    zone.addPlayer("p1", "P1");
    zone.queueInput("p1", { seq: 5, dir: 1, jump: false, attack: false });
    zone.step(DT);
    expect(zone.lastSeqOf("p1")).toBe(5);
    zone.queueInput("p1", { seq: 5, dir: -1, jump: false, attack: false });
    zone.queueInput("p1", { seq: 3, dir: -1, jump: false, attack: false });
    zone.step(DT);
    expect(zone.lastSeqOf("p1")).toBe(5);
  });

  it("input from one player is silently ignored if the player isn't in the zone", () => {
    const zone = createDefaultZone();
    expect(() => zone.queueInput("ghost", { seq: 1, dir: 1, jump: false, attack: false })).not.toThrow();
    zone.step(DT);
    expect(zone.snapshot().players).toHaveLength(0);
  });

  it("enforces MAX_PLAYERS_PER_ZONE via isFull()", () => {
    const zone = createDefaultZone();
    zone.addPlayer("p1", "A");
    zone.addPlayer("p2", "B");
    zone.addPlayer("p3", "C");
    zone.addPlayer("p4", "D");
    expect(zone.isFull()).toBe(true);
  });

  it("two players walking the same input reach the same position (determinism across players)", () => {
    const zone = createDefaultZone();
    zone.addPlayer("a", "A");
    zone.addPlayer("b", "B");
    for (let seq = 1; seq <= 20; seq++) {
      zone.queueInput("a", { seq, dir: 1, jump: false, attack: false });
      zone.queueInput("b", { seq, dir: 1, jump: false, attack: false });
      zone.step(DT);
    }
    const snap = zone.snapshot();
    const a = snap.players.find((p) => p.id === "a");
    const b = snap.players.find((p) => p.id === "b");
    expect(a?.pos).toEqual(b?.pos);
    expect(a?.vel).toEqual(b?.vel);
  });
});
