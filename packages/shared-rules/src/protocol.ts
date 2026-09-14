// Zod schemas for every network message. docs/protocol.md is the source of truth — update it FIRST.
// gen_rules.py extracts MESSAGE_TYPES into client/scripts/rules/protocol.gd; check_protocol_sync.sh enforces parity.
import { z } from "zod";

export const PROTOCOL_VERSION = 0;

export const MESSAGE_TYPES = ["ping", "pong", "error"] as const;
export type MessageType = (typeof MESSAGE_TYPES)[number];

const ms = z.number().finite().nonnegative();

export const PingSchema = z.object({ t: z.literal("ping"), ts: ms }).strict();
export const PongSchema = z.object({ t: z.literal("pong"), ts: ms, server_ts: ms }).strict();
export const ErrorSchema = z
  .object({ t: z.literal("error"), code: z.string().max(64), msg_key: z.string().max(128) })
  .strict();

/** Messages the server accepts from clients (intents). */
export const ClientMessageSchema = z.discriminatedUnion("t", [PingSchema]);
/** Messages the server sends to clients (facts). */
export const ServerMessageSchema = z.discriminatedUnion("t", [PongSchema, ErrorSchema]);

export type ClientMessage = z.infer<typeof ClientMessageSchema>;
export type ServerMessage = z.infer<typeof ServerMessageSchema>;

export const DIRECTION: Record<MessageType, "C2S" | "S2C"> = { ping: "C2S", pong: "S2C", error: "S2C" };

/** Parse raw JSON text from a client. Returns null on any failure (caller logs + drops). */
export function parseClientMessage(raw: string, maxBytes = 4096): ClientMessage | null {
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
