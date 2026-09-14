import { describe, expect, it } from "vitest";
import {
  ClientMessageSchema,
  DIRECTION,
  MAX_CLIENT_MESSAGE_BYTES,
  MESSAGE_TYPES,
  PROTOCOL_VERSION,
  ServerMessageSchema,
  SnapshotSchema,
  parseClientMessage,
  parseServerMessage,
  type MessageType,
} from "../src/protocol.js";

// ---------- fixture builders ----------
const vec = { x: 120.5, y: -40.25 };
const zero = { x: 0, y: 0 };

function player(i: number) {
  return {
    id: `p_${i}`,
    name: `Intern ${i}`,
    pos: vec,
    vel: zero,
    hp: 50,
    max_hp: 100,
    level: 3,
    xp: 120,
    facing: 1,
    anim: "idle",
    alive: true,
  };
}
function monster(i: number) {
  return {
    id: `m_${i}`,
    kind: "queue_clerk",
    pos: vec,
    vel: zero,
    hp: 20,
    max_hp: 20,
    level: 2,
    facing: -1,
    anim: "walk",
    alive: true,
  };
}
function drop(i: number) {
  return { id: `d_${i}`, pos: vec, item_id: "intern_coat", money: 0, expires_tick: 92_500 };
}
function snapshot(players = 1, monsters = 1, drops = 1) {
  return {
    tick: 91_235,
    last_seq: Object.fromEntries(Array.from({ length: players }, (_, i) => [`p_${i}`, 412 + i])),
    players: Array.from({ length: players }, (_, i) => player(i)),
    monsters: Array.from({ length: monsters }, (_, i) => monster(i)),
    drops: Array.from({ length: drops }, (_, i) => drop(i)),
  };
}

/** One valid payload per message type (TS enforces that all 16 are present). */
const VALID: Record<MessageType, unknown> = {
  ping: { t: "ping", ts: 1_757_800_000_123 },
  join: { t: "join", protocol: PROTOCOL_VERSION, token: "tok_abc", character_id: "char_7" },
  leave: { t: "leave" },
  input: { t: "input", seq: 412, tick: 91_234, dir: -1, jump: true, attack: false },
  loot_pickup: { t: "loot_pickup", drop_id: "d_88" },
  chat: { t: "chat", text: "מישהו ראה את הרוקח?", channel: "zone" },
  pong: { t: "pong", ts: 1, server_ts: 2 },
  error: { t: "error", code: "zone_full", msg_key: "error.zone_full" },
  joined: {
    t: "joined",
    player_id: "p_7",
    zone_id: "clinic_lobby",
    tick: 91_235,
    tick_ms: 50,
    state: snapshot(),
  },
  left: { t: "left", player_id: "p_7" },
  state: { t: "state", ...snapshot() },
  attack: { t: "attack", attacker_id: "p_7", skill_id: "stim_double_dose", target_ids: ["m_12"] },
  damage: { t: "damage", target_id: "m_12", attacker_id: "p_7", amount: 37, new_hp: 0, crit: true },
  died: {
    t: "died",
    id: "m_12",
    killer_id: "p_7",
    xp: 25,
    drop_id: "d_88",
    item_id: "intern_coat",
    money: 0,
  },
  loot: { t: "loot", player_id: "p_7", drop_id: "d_88", item_id: "intern_coat", money: 0, added: true },
  chat_msg: { t: "chat_msg", player_id: "p_7", channel: "party", text: "hello", ts: 1_757_800_000_123 },
};

/** One out-of-bounds payload per message type — each one violates exactly one limit. */
const INVALID: Record<MessageType, unknown> = {
  ping: { t: "ping", ts: -1 }, // negative clock
  join: { t: "join", protocol: 1, token: "x".repeat(513), character_id: "c" }, // token > 512
  leave: { t: "leave", zone_id: "clinic_lobby" }, // strict: no extra fields
  input: { t: "input", seq: 1, tick: 1, dir: 2, jump: false, attack: false }, // dir not -1|0|1
  loot_pickup: { t: "loot_pickup", drop_id: "" }, // empty id
  chat: { t: "chat", text: "x".repeat(201), channel: "zone" }, // 201 chars
  pong: { t: "pong", ts: Number.NaN, server_ts: 2 }, // not finite
  error: { t: "error", code: "x".repeat(65), msg_key: "k" }, // code > 64
  joined: {
    t: "joined",
    player_id: "p_7",
    zone_id: "clinic_lobby",
    tick: 1,
    tick_ms: 0, // tick_ms must be >= 1
    state: snapshot(),
  },
  left: { t: "left", player_id: "x".repeat(65) }, // id > 64
  state: { t: "state", ...snapshot(65) }, // 65 players > cap of 64
  attack: {
    t: "attack",
    attacker_id: "p_7",
    skill_id: null,
    target_ids: Array.from({ length: 17 }, (_, i) => `m_${i}`), // > 16 targets
  },
  damage: { t: "damage", target_id: "m_1", attacker_id: null, amount: -1, new_hp: 0, crit: false },
  died: { t: "died", id: "m_1", killer_id: null, xp: 1.5, drop_id: null, item_id: null, money: 0 }, // xp not int
  loot: { t: "loot", player_id: "p_7", drop_id: "d_1", item_id: null, money: 0, added: "yes" },
  chat_msg: { t: "chat_msg", player_id: "p_7", channel: "zone", text: "", ts: 1 }, // empty text
};

const schemaFor = (t: MessageType) => (DIRECTION[t] === "C2S" ? ClientMessageSchema : ServerMessageSchema);
const otherSchemaFor = (t: MessageType) =>
  DIRECTION[t] === "C2S" ? ServerMessageSchema : ClientMessageSchema;

describe("protocol: message table", () => {
  it("is version 1 and every type has a direction", () => {
    expect(PROTOCOL_VERSION).toBe(1);
    expect(new Set(MESSAGE_TYPES).size).toBe(MESSAGE_TYPES.length); // no duplicates
    for (const t of MESSAGE_TYPES) expect(DIRECTION[t]).toMatch(/^(C2S|S2C)$/);
    expect(Object.keys(DIRECTION).sort()).toEqual([...MESSAGE_TYPES].sort());
  });

  it("covers every message type with a valid and an invalid fixture", () => {
    expect(Object.keys(VALID).sort()).toEqual([...MESSAGE_TYPES].sort());
    expect(Object.keys(INVALID).sort()).toEqual([...MESSAGE_TYPES].sort());
  });

  for (const t of MESSAGE_TYPES) {
    it(`${t}: valid payload parses in the ${DIRECTION[t]} union`, () => {
      const res = schemaFor(t).safeParse(VALID[t]);
      expect(res.success, JSON.stringify(res.success ? {} : res.error.issues)).toBe(true);
    });
    it(`${t}: out-of-bounds payload is rejected`, () => {
      expect(schemaFor(t).safeParse(INVALID[t]).success).toBe(false);
    });
    it(`${t}: is not accepted by the opposite direction`, () => {
      expect(otherSchemaFor(t).safeParse(VALID[t]).success).toBe(false);
    });
  }
});

describe("protocol: intents vs facts", () => {
  it("a client cannot send a fact", () => {
    for (const t of MESSAGE_TYPES.filter((m) => DIRECTION[m] === "S2C")) {
      expect(parseClientMessage(JSON.stringify(VALID[t]))).toBeNull();
    }
  });
  it("a fact stream cannot carry an intent", () => {
    for (const t of MESSAGE_TYPES.filter((m) => DIRECTION[m] === "C2S")) {
      expect(parseServerMessage(JSON.stringify(VALID[t]))).toBeNull();
    }
  });
});

describe("protocol: parseClientMessage", () => {
  it("accepts a valid ping and a valid input", () => {
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: 123 }))).toEqual({ t: "ping", ts: 123 });
    expect(parseClientMessage(JSON.stringify(VALID.input))).toEqual(VALID.input);
  });
  it("drops invalid pings: negative, NaN, extra fields, unknown type, garbage, oversized", () => {
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: -1 }))).toBeNull();
    expect(parseClientMessage('{"t":"ping","ts":"NaN"}')).toBeNull();
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: 1, hp: 9999 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ t: "pong", ts: 1, server_ts: 2 }))).toBeNull(); // S2C only
    expect(parseClientMessage("not json")).toBeNull();
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: 1 }), 5)).toBeNull();
  });
  it("refuses a frame larger than the cap before parsing it", () => {
    const huge = JSON.stringify({ t: "chat", text: "x".repeat(MAX_CLIENT_MESSAGE_BYTES), channel: "zone" });
    expect(huge.length).toBeGreaterThan(MAX_CLIENT_MESSAGE_BYTES);
    expect(parseClientMessage(huge)).toBeNull();
  });
});

describe("protocol: parseServerMessage", () => {
  it("accepts a state snapshot and rejects garbage / oversized frames", () => {
    expect(parseServerMessage(JSON.stringify(VALID.state))).toEqual(VALID.state);
    expect(parseServerMessage("not json")).toBeNull();
    expect(parseServerMessage(JSON.stringify(VALID.state), 10)).toBeNull();
    expect(parseServerMessage(JSON.stringify({ t: "teleport", x: 0 }))).toBeNull();
  });
});

describe("protocol: input bounds (anticheat)", () => {
  it("rejects dir 2, negative seq, fractional seq and unknown fields", () => {
    const base = { t: "input", seq: 1, tick: 1, dir: 0, jump: false, attack: false };
    expect(ClientMessageSchema.safeParse({ ...base, dir: 2 }).success).toBe(false);
    expect(ClientMessageSchema.safeParse({ ...base, dir: -1 }).success).toBe(true);
    expect(ClientMessageSchema.safeParse({ ...base, seq: -1 }).success).toBe(false);
    expect(ClientMessageSchema.safeParse({ ...base, seq: 1.5 }).success).toBe(false);
    expect(ClientMessageSchema.safeParse({ ...base, tick: 2_147_483_648 }).success).toBe(false);
    expect(ClientMessageSchema.safeParse({ ...base, hp: 9999 }).success).toBe(false);
  });
  it("accepts an optional skill_id but not an oversized one", () => {
    const base = { t: "input", seq: 1, tick: 1, dir: 0, jump: false, attack: true };
    expect(ClientMessageSchema.safeParse({ ...base, skill_id: "stim_rush_order" }).success).toBe(true);
    expect(ClientMessageSchema.safeParse({ ...base, skill_id: "x".repeat(33) }).success).toBe(false);
  });
});

describe("protocol: chat bounds", () => {
  const chat = (text: string) => ClientMessageSchema.safeParse({ t: "chat", text, channel: "zone" }).success;
  it("accepts 1..200 chars and rejects 0, 201, blank and control characters", () => {
    expect(chat("x")).toBe(true);
    expect(chat("x".repeat(200))).toBe(true);
    expect(chat("")).toBe(false);
    expect(chat("x".repeat(201))).toBe(false);
    expect(chat("   ")).toBe(false);
    expect(chat("line\nbreak")).toBe(false);
  });
  it("only knows the zone and party channels", () => {
    expect(ClientMessageSchema.safeParse({ t: "chat", text: "hi", channel: "global" }).success).toBe(false);
  });
});

describe("protocol: state snapshot bounds", () => {
  it("parses a full 64-player snapshot and rejects a 65-player one", () => {
    expect(SnapshotSchema.safeParse(snapshot(64, 256, 256)).success).toBe(true);
    expect(SnapshotSchema.safeParse(snapshot(65, 1, 1)).success).toBe(false);
    expect(SnapshotSchema.safeParse(snapshot(1, 257, 1)).success).toBe(false);
    expect(SnapshotSchema.safeParse(snapshot(1, 1, 257)).success).toBe(false);
  });
  it("rejects forged positions (NaN / Infinity / out of world)", () => {
    const bad = (pos: unknown) => {
      const snap = snapshot();
      return SnapshotSchema.safeParse({ ...snap, players: [{ ...player(0), pos }] }).success;
    };
    expect(bad({ x: Number.NaN, y: 0 })).toBe(false);
    expect(bad({ x: Number.POSITIVE_INFINITY, y: 0 })).toBe(false);
    expect(bad({ x: 1_000_001, y: 0 })).toBe(false);
    expect(bad({ x: 0, y: 0 })).toBe(true);
  });
  it("caps last_seq at one entry per allowed player", () => {
    const tooMany = {
      ...snapshot(),
      last_seq: Object.fromEntries(Array.from({ length: 65 }, (_, i) => [`p_${i}`, i])),
    };
    expect(SnapshotSchema.safeParse(tooMany).success).toBe(false);
  });
});

describe("protocol: join version negotiation", () => {
  // Documented in docs/protocol.md § Join: a wrong version must reach the handler so the client gets a
  // readable protocol_mismatch error instead of an anonymous invalid_message drop.
  it("accepts a join with the wrong protocol version — the handler rejects it, not the schema", () => {
    const old = { t: "join", protocol: 0, token: "tok", character_id: "char_7" };
    expect(parseClientMessage(JSON.stringify(old))).toEqual(old);
    expect(PROTOCOL_VERSION).not.toBe(0);
  });
  it("still rejects a protocol field that is not a small non-negative int", () => {
    const bad = (protocol: unknown) =>
      ClientMessageSchema.safeParse({ t: "join", protocol, token: "tok", character_id: "c" }).success;
    expect(bad(-1)).toBe(false);
    expect(bad(1.5)).toBe(false);
    expect(bad(65_536)).toBe(false);
    expect(bad("1")).toBe(false);
  });
});
