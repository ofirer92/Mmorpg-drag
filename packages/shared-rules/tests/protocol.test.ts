import { describe, expect, it } from "vitest";
import { DIRECTION, MESSAGE_TYPES, ServerMessageSchema, parseClientMessage } from "../src/protocol.js";

describe("protocol", () => {
  it("every message type has a direction", () => {
    for (const t of MESSAGE_TYPES) expect(DIRECTION[t]).toMatch(/^(C2S|S2C)$/);
  });
  it("accepts a valid ping", () => {
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: 123 }))).toEqual({ t: "ping", ts: 123 });
  });
  it("drops invalid pings: negative, NaN, extra fields, unknown type, garbage, oversized", () => {
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: -1 }))).toBeNull();
    expect(parseClientMessage('{"t":"ping","ts":"NaN"}')).toBeNull();
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: 1, hp: 9999 }))).toBeNull();
    expect(parseClientMessage(JSON.stringify({ t: "pong", ts: 1, server_ts: 2 }))).toBeNull(); // S2C only
    expect(parseClientMessage("not json")).toBeNull();
    expect(parseClientMessage(JSON.stringify({ t: "ping", ts: 1 }), 5)).toBeNull();
  });
  it("server messages validate", () => {
    expect(ServerMessageSchema.safeParse({ t: "pong", ts: 1, server_ts: 2 }).success).toBe(true);
    expect(
      ServerMessageSchema.safeParse({ t: "error", code: "bad", msg_key: "error.invalid_message" }).success,
    ).toBe(true);
    expect(ServerMessageSchema.safeParse({ t: "error", code: "x".repeat(65), msg_key: "k" }).success).toBe(
      false,
    );
  });
});
