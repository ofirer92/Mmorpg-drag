// Zod schemas for every network message. docs/protocol.md is the source of truth — update it FIRST.
// gen_rules.py extracts MESSAGE_TYPES into client/scripts/rules/protocol.gd; check_protocol_sync.sh enforces parity.
//
// Principle (CLAUDE.md): C→S messages are *intents*, S→C messages are *facts*. Never the other way.
// Every object is .strict(), every number .finite(), every counter .int(), every string/array bounded —
// the bounds are the anticheat layer that runs before any handler. See "Bounds rationale" in docs/protocol.md.
import { z } from "zod";

export const PROTOCOL_VERSION = 1;

export const MESSAGE_TYPES = [
  // C→S (intents)
  "ping",
  "join",
  "leave",
  "input",
  "loot_pickup",
  "chat",
  // S→C (facts)
  "pong",
  "error",
  "joined",
  "left",
  "state",
  "attack",
  "damage",
  "died",
  "loot",
  "chat_msg",
] as const;
export type MessageType = (typeof MESSAGE_TYPES)[number];

// ---------- transport limits ----------
/** Longest frame parseClientMessage will even JSON.parse. Worst intent (`chat`) is ~830 B. */
export const MAX_CLIENT_MESSAGE_BYTES = 4096;
/** Longest frame parseServerMessage will JSON.parse. A full `state` is ~90 KB (64+256+256 entities). */
export const MAX_SERVER_MESSAGE_BYTES = 262_144;
export const MAX_PLAYERS_IN_STATE = 64;
export const MAX_MONSTERS_IN_STATE = 256;
export const MAX_DROPS_IN_STATE = 256;
export const MAX_TARGETS_PER_ATTACK = 16;
export const MAX_CHAT_CHARS = 200;

const INT32_MAX = 2_147_483_647;
const COORD_MAX = 1_000_000;
const HP_MAX = 1_000_000;
const BIG_INT_MAX = 1_000_000_000;
/** Sanity ceiling only — the real cap is XP_CURVE.max_level in docs/balance/xp_curve.yaml (docs/protocol.md). */
const LEVEL_MAX = 1000;
// Chat may not carry C0/C1 control characters: they break line-oriented logs and rich-text rendering.
// Written as a scan, not a regex: a control-character class trips eslint's no-control-regex
// (and literal escapes get mangled by the markdown/TS formatter).
function has_control_char(s: string): boolean {
  for (const ch of s) {
    const c = ch.codePointAt(0) ?? 0;
    if (c < 0x20 || (c >= 0x7f && c <= 0x9f)) return true;
  }
  return false;
}

// ---------- field primitives ----------
const ms = z.number().finite().nonnegative();
const entityId = z.string().min(1).max(64);
const tickNo = z.number().int().nonnegative().max(INT32_MAX);
const seqNo = z.number().int().nonnegative().max(INT32_MAX);
const coord = z.number().finite().min(-COORD_MAX).max(COORD_MAX);
const hp = z.number().int().min(0).max(HP_MAX);
const bigCount = z.number().int().min(0).max(BIG_INT_MAX);
const levelNo = z.number().int().min(1).max(LEVEL_MAX);
const animName = z.string().max(32);
const skillId = z.string().min(1).max(32);
const axis = z.union([z.literal(-1), z.literal(0), z.literal(1)]);
const facing = z.union([z.literal(-1), z.literal(1)]);
const channel = z.enum(["zone", "party"]);
const chatText = z
  .string()
  .min(1)
  .max(MAX_CHAT_CHARS)
  .refine((s) => !has_control_char(s), { message: "control characters" })
  .refine((s) => s.trim().length > 0, { message: "blank" });

// ---------- shared sub-schemas ----------
export const Vec2Schema = z.object({ x: coord, y: coord }).strict();

export const PlayerStateSchema = z
  .object({
    id: entityId,
    name: z.string().max(24),
    pos: Vec2Schema,
    vel: Vec2Schema,
    hp,
    max_hp: z.number().int().min(1).max(HP_MAX),
    level: levelNo,
    xp: bigCount,
    facing,
    anim: animName,
    alive: z.boolean(),
  })
  .strict();

export const MonsterStateSchema = z
  .object({
    id: entityId,
    kind: z.string().min(1).max(32),
    pos: Vec2Schema,
    vel: Vec2Schema,
    hp,
    max_hp: z.number().int().min(1).max(HP_MAX),
    level: levelNo,
    facing,
    anim: animName,
    alive: z.boolean(),
  })
  .strict();

export const DropStateSchema = z
  .object({
    id: entityId,
    pos: Vec2Schema,
    item_id: entityId.nullable(),
    money: bigCount,
    expires_tick: tickNo,
  })
  .strict();

/** One tick of authoritative world state for one client (already interest-filtered). */
export const SnapshotSchema = z
  .object({
    tick: tickNo,
    // Highest input.seq applied per player — the client replays everything after it (reconciliation).
    last_seq: z
      .record(entityId, seqNo)
      .refine((r) => Object.keys(r).length <= MAX_PLAYERS_IN_STATE, { message: "too many players" }),
    players: z.array(PlayerStateSchema).max(MAX_PLAYERS_IN_STATE),
    monsters: z.array(MonsterStateSchema).max(MAX_MONSTERS_IN_STATE),
    drops: z.array(DropStateSchema).max(MAX_DROPS_IN_STATE),
  })
  .strict();

// ---------- C→S: intents ----------
export const PingSchema = z.object({ t: z.literal("ping"), ts: ms }).strict();

/**
 * `protocol` is only range-checked here: a wrong version must reach the handler so the client gets a
 * readable `protocol_mismatch` error instead of an anonymous schema drop. See docs/protocol.md § Join.
 */
export const JoinSchema = z
  .object({
    t: z.literal("join"),
    protocol: z.number().int().min(0).max(65_535),
    token: z.string().min(1).max(512),
    character_id: z.string().min(1).max(64),
  })
  .strict();

export const LeaveSchema = z.object({ t: z.literal("leave") }).strict();

export const InputSchema = z
  .object({
    t: z.literal("input"),
    seq: seqNo,
    tick: tickNo,
    dir: axis,
    jump: z.boolean(),
    attack: z.boolean(),
    skill_id: skillId.optional(),
  })
  .strict();

export const LootPickupSchema = z.object({ t: z.literal("loot_pickup"), drop_id: entityId }).strict();

export const ChatSchema = z.object({ t: z.literal("chat"), text: chatText, channel }).strict();

// ---------- S→C: facts ----------
export const PongSchema = z.object({ t: z.literal("pong"), ts: ms, server_ts: ms }).strict();

export const ErrorSchema = z
  .object({ t: z.literal("error"), code: z.string().max(64), msg_key: z.string().max(128) })
  .strict();

export const JoinedSchema = z
  .object({
    t: z.literal("joined"),
    player_id: entityId,
    zone_id: z.string().min(1).max(64),
    tick: tickNo, // == state.tick; seeds the client tick clock
    tick_ms: z.number().int().min(1).max(1000),
    state: SnapshotSchema,
  })
  .strict();

export const LeftSchema = z.object({ t: z.literal("left"), player_id: entityId }).strict();

export const StateSchema = SnapshotSchema.extend({ t: z.literal("state") }).strict();

/** Fact: the server accepted an attack. Animation cue only — damage arrives in `damage`. */
export const AttackSchema = z
  .object({
    t: z.literal("attack"),
    attacker_id: entityId,
    skill_id: skillId.nullable(), // null = basic attack
    target_ids: z.array(entityId).max(MAX_TARGETS_PER_ATTACK),
  })
  .strict();

export const DamageSchema = z
  .object({
    t: z.literal("damage"),
    target_id: entityId,
    attacker_id: entityId.nullable(), // null = environment/status damage
    amount: hp,
    new_hp: hp,
    crit: z.boolean(),
  })
  .strict();

export const DiedSchema = z
  .object({
    t: z.literal("died"),
    id: entityId,
    killer_id: entityId.nullable(), // who the xp belongs to
    xp: bigCount,
    drop_id: entityId.nullable(),
    item_id: entityId.nullable(),
    money: bigCount,
  })
  .strict();

export const LootSchema = z
  .object({
    t: z.literal("loot"),
    player_id: entityId,
    drop_id: entityId,
    item_id: entityId.nullable(),
    money: bigCount,
    added: z.boolean(), // false = bag full / out of range / already taken (sent to the requester only)
  })
  .strict();

export const ChatMsgSchema = z
  .object({
    t: z.literal("chat_msg"),
    player_id: entityId,
    channel,
    text: z.string().min(1).max(MAX_CHAT_CHARS),
    ts: ms,
  })
  .strict();

/** Messages the server accepts from clients (intents). */
export const ClientMessageSchema = z.discriminatedUnion("t", [
  PingSchema,
  JoinSchema,
  LeaveSchema,
  InputSchema,
  LootPickupSchema,
  ChatSchema,
]);
/** Messages the server sends to clients (facts). */
export const ServerMessageSchema = z.discriminatedUnion("t", [
  PongSchema,
  ErrorSchema,
  JoinedSchema,
  LeftSchema,
  StateSchema,
  AttackSchema,
  DamageSchema,
  DiedSchema,
  LootSchema,
  ChatMsgSchema,
]);

export type Vec2 = z.infer<typeof Vec2Schema>;
export type PlayerState = z.infer<typeof PlayerStateSchema>;
export type MonsterState = z.infer<typeof MonsterStateSchema>;
export type DropState = z.infer<typeof DropStateSchema>;
export type Snapshot = z.infer<typeof SnapshotSchema>;
export type PingMessage = z.infer<typeof PingSchema>;
export type JoinMessage = z.infer<typeof JoinSchema>;
export type LeaveMessage = z.infer<typeof LeaveSchema>;
export type InputMessage = z.infer<typeof InputSchema>;
export type LootPickupMessage = z.infer<typeof LootPickupSchema>;
export type ChatMessage = z.infer<typeof ChatSchema>;
export type PongMessage = z.infer<typeof PongSchema>;
export type ErrorMessage = z.infer<typeof ErrorSchema>;
export type JoinedMessage = z.infer<typeof JoinedSchema>;
export type LeftMessage = z.infer<typeof LeftSchema>;
export type StateMessage = z.infer<typeof StateSchema>;
export type AttackMessage = z.infer<typeof AttackSchema>;
export type DamageMessage = z.infer<typeof DamageSchema>;
export type DiedMessage = z.infer<typeof DiedSchema>;
export type LootMessage = z.infer<typeof LootSchema>;
export type ChatMsgMessage = z.infer<typeof ChatMsgSchema>;
export type ClientMessage = z.infer<typeof ClientMessageSchema>;
export type ServerMessage = z.infer<typeof ServerMessageSchema>;

export const DIRECTION: Record<MessageType, "C2S" | "S2C"> = {
  ping: "C2S",
  join: "C2S",
  leave: "C2S",
  input: "C2S",
  loot_pickup: "C2S",
  chat: "C2S",
  pong: "S2C",
  error: "S2C",
  joined: "S2C",
  left: "S2C",
  state: "S2C",
  attack: "S2C",
  damage: "S2C",
  died: "S2C",
  loot: "S2C",
  chat_msg: "S2C",
};

/**
 * Parse raw JSON text from a client. Returns null on any failure (caller logs + drops).
 * The length check runs before JSON.parse — it is the only cheap defence against a JSON bomb.
 * Per-type worst cases well inside the cap: join ~620 B, chat ~830 B, input ~120 B, loot_pickup ~90 B.
 */
export function parseClientMessage(raw: string, maxBytes = MAX_CLIENT_MESSAGE_BYTES): ClientMessage | null {
  if (raw.length > maxBytes) return null;
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return null;
  }
  const res = ClientMessageSchema.safeParse(json);
  return res.success ? res.data : null;
}

/**
 * Parse raw JSON text from the server (client side / sim clients). Returns null on any failure.
 * The cap is far larger than the client one because a full `state` snapshot is ~90 KB; it exists to
 * protect a client from a wedged or hostile server, not to police the protocol.
 */
export function parseServerMessage(raw: string, maxBytes = MAX_SERVER_MESSAGE_BYTES): ServerMessage | null {
  if (raw.length > maxBytes) return null;
  let json: unknown;
  try {
    json = JSON.parse(raw);
  } catch {
    return null;
  }
  const res = ServerMessageSchema.safeParse(json);
  return res.success ? res.data : null;
}
