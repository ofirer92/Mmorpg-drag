import { afterEach, describe, expect, it } from "vitest";
import { PROTOCOL_VERSION } from "@hamirpaa/shared-rules";
import { startTestServer, FakeClient } from "./helpers/fake_client.js";
import type { GameServer } from "../src/net/server.js";

/** join() + wait for the `joined` reply, in one call — every room test does this at least twice. */
async function join(url: string, characterId: string): Promise<{ client: FakeClient; playerId: string }> {
  const client = await FakeClient.join(url);
  client.send({ t: "join", protocol: PROTOCOL_VERSION, token: "sim", character_id: characterId });
  const joined = await client.next((m) => m["t"] === "joined");
  return { client, playerId: joined["player_id"] as string };
}

describe("room: join/leave/input/chat over the zone", () => {
  let server: GameServer;
  let url: string;

  afterEach(async () => {
    await server.close();
  });

  it("two clients join, both get `joined` and a `state` with 2 players", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    const b = await join(url, "char_b");

    expect(a.playerId).not.toBe(b.playerId);
    const aJoined = a.client.received.find((m) => m["t"] === "joined");
    expect((aJoined?.["state"] as { players: unknown[] }).players).toHaveLength(1); // A was alone at the moment it joined

    server.step(0.05);
    const stateA = await a.client.next((m) => m["t"] === "state" && (m["players"] as unknown[]).length === 2);
    const stateB = await b.client.next((m) => m["t"] === "state" && (m["players"] as unknown[]).length === 2);
    expect(stateA["players"]).toHaveLength(2);
    expect(stateB["players"]).toHaveLength(2);
    a.client.close();
    b.client.close();
  });

  it("a 5th client is rejected with zone_full and the socket closes", async () => {
    ({ server, url } = await startTestServer());
    const clients = [];
    for (let i = 0; i < 4; i++) clients.push((await join(url, `char_${i}`)).client);

    const fifth = await FakeClient.join(url);
    fifth.send({ t: "join", protocol: PROTOCOL_VERSION, token: "sim", character_id: "char_5" });
    const err = await fifth.next((m) => m["t"] === "error");
    expect(err["code"]).toBe("zone_full");
    expect(await fifth.waitClosed()).toBe(1008);
    for (const c of clients) c.close();
  });

  it("wrong protocol version gets protocol_mismatch and the socket closes", async () => {
    ({ server, url } = await startTestServer());
    const c = await FakeClient.join(url);
    c.send({ t: "join", protocol: PROTOCOL_VERSION + 1, token: "sim", character_id: "char_x" });
    const err = await c.next((m) => m["t"] === "error");
    expect(err["code"]).toBe("protocol_mismatch");
    expect(await c.waitClosed()).toBe(1008);
  });

  it("a second `join` on the same socket is rejected as invalid_message", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    a.client.send({ t: "join", protocol: PROTOCOL_VERSION, token: "sim", character_id: "char_a2" });
    const err = await a.client.next((m) => m["t"] === "error" && m["code"] === "invalid_message");
    expect(err["code"]).toBe("invalid_message");
    a.client.close();
  });

  it("input from A moves A, and B sees the exact same position for A in its own state", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    const b = await join(url, "char_b");

    for (let seq = 1; seq <= 5; seq++) {
      a.client.send({ t: "input", seq, tick: 0, dir: 1, jump: false, attack: false });
      // Let each input actually arrive (WS delivery is async, even on loopback) before the next
      // server.step() — queueInput() keeps only the latest input per tick, so stepping ahead of
      // delivery would silently skip seqs rather than fail loudly.
      await new Promise((r) => setTimeout(r, 10));
      server.step(0.05);
    }
    const stateA = await a.client.next(
      (m) => m["t"] === "state" && (m["last_seq"] as Record<string, number>)[a.playerId] === 5,
    );
    const stateB = await b.client.next(
      (m) => m["t"] === "state" && (m["last_seq"] as Record<string, number>)[a.playerId] === 5,
    );
    type Players = Array<{ id: string; pos: { x: number; y: number } }>;
    const aInA = (stateA["players"] as Players).find((p) => p.id === a.playerId);
    const aInB = (stateB["players"] as Players).find((p) => p.id === a.playerId);
    expect(aInA).toBeDefined();
    expect(aInB).toEqual(aInA);
    expect(aInA?.pos.x).toBeGreaterThan(0);
    a.client.close();
    b.client.close();
  });

  it("leave removes the player and broadcasts `left` to the remaining client", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    const b = await join(url, "char_b");
    a.client.send({ t: "leave" });
    const left = await b.client.next((m) => m["t"] === "left");
    expect(left["player_id"]).toBe(a.playerId);
    server.step(0.05);
    const stateB = await b.client.next((m) => m["t"] === "state" && (m["players"] as unknown[]).length === 1);
    expect(stateB["players"]).toHaveLength(1);
    a.client.close();
    b.client.close();
  });

  it("a socket closing without `leave` still removes the player and broadcasts `left`", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    const b = await join(url, "char_b");
    a.client.close();
    const left = await b.client.next((m) => m["t"] === "left");
    expect(left["player_id"]).toBe(a.playerId);
    b.client.close();
  });

  it("chat is broadcast to both clients (including the sender)", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    const b = await join(url, "char_b");
    a.client.send({ t: "chat", text: "שלום מהמרפאה", channel: "zone" });
    const msgA = await a.client.next((m) => m["t"] === "chat_msg");
    const msgB = await b.client.next((m) => m["t"] === "chat_msg");
    expect(msgA["player_id"]).toBe(a.playerId);
    expect(msgB["text"]).toBe("שלום מהמרפאה");
    a.client.close();
    b.client.close();
  });

  it("input flood beyond the per-type rate limit is dropped without crashing the server", async () => {
    ({ server, url } = await startTestServer());
    const a = await join(url, "char_a");
    for (let seq = 1; seq <= 200; seq++) {
      a.client.send({ t: "input", seq, tick: 0, dir: 1, jump: false, attack: false });
    }
    const errs = await a.client.next((m) => m["t"] === "error" && m["code"] === "rate_limited");
    expect(errs["code"]).toBe("rate_limited");
    server.step(0.05); // server is still alive and ticking after the flood
    expect(server.players).toBe(1);
    a.client.close();
  });
});
