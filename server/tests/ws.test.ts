import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { startTestServer, FakeClient } from "./helpers/fake_client.js";
import type { GameServer } from "../src/net/server.js";

describe("websocket: validate → rate limit → handler", () => {
  let server: GameServer;
  let url: string;
  beforeAll(
    async () => ({ server, url } = await startTestServer({ rate: { perSec: 5, burst: 5 }, maxInvalid: 3 })),
  );
  afterAll(async () => server.close());

  it("two clients each get their own pong, echoing their own ts", async () => {
    const a = await FakeClient.join(url);
    const b = await FakeClient.join(url);
    a.send({ t: "ping", ts: 111 });
    b.send({ t: "ping", ts: 222 });
    const pa = await a.next((m) => m["t"] === "pong");
    const pb = await b.next((m) => m["t"] === "pong");
    expect(pa["ts"]).toBe(111);
    expect(pb["ts"]).toBe(222);
    expect(typeof pa["server_ts"]).toBe("number");
    expect(a.received.filter((m) => m["t"] === "pong")).toHaveLength(1);
    a.close();
    b.close();
  });

  it("invalid messages are dropped with an error and never crash; 3 in a row disconnects", async () => {
    const c = await FakeClient.join(url);
    c.sendRaw("garbage");
    const e1 = await c.next((m) => m["t"] === "error");
    expect(e1["msg_key"]).toBe("error.invalid_message");
    c.send({ t: "ping", ts: -1 });
    c.send({ t: "teleport", x: 0 });
    expect(await c.waitClosed()).toBe(1008);
  });

  it("flooding beyond the bucket gets rate_limited errors", async () => {
    const c = await FakeClient.join(url);
    for (let i = 0; i < 10; i++) c.send({ t: "ping", ts: i });
    const err = await c.next((m) => m["t"] === "error");
    expect(err["code"]).toBe("rate_limited");
    expect(c.received.filter((m) => m["t"] === "pong").length).toBeLessThanOrEqual(5);
    c.close();
  });
});
