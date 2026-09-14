import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { PROTOCOL_VERSION } from "@hamirpaa/shared-rules";
import { healthPayload } from "../src/health.js";
import { loadConfig } from "../src/config.js";
import { startTestServer, FakeClient } from "./helpers/fake_client.js";
import type { GameServer } from "../src/net/server.js";

describe("health", () => {
  it("payload has the required shape", () => {
    const h = healthPayload(3);
    expect(h.status).toBe("ok");
    expect(h.players).toBe(3);
    expect(h.protocol).toBe(PROTOCOL_VERSION);
    expect(h.tick_hz).toBe(20);
    expect(h.uptime_s).toBeGreaterThanOrEqual(0);
  });
  it("config rejects a bad port and applies defaults", () => {
    expect(() => loadConfig({ PORT: "99999" })).toThrow();
    expect(loadConfig({}).PORT).toBe(8080);
  });
});

describe("GET /health", () => {
  let server: GameServer;
  let url: string;
  beforeAll(async () => ({ server, url } = await startTestServer()));
  afterAll(async () => server.close());

  it("returns 200 with live player count", async () => {
    const httpUrl = url.replace("ws://", "http://");
    const a = await FakeClient.join(url);
    const b = await FakeClient.join(url);
    const res = await fetch(`${httpUrl}/health`);
    expect(res.status).toBe(200);
    const body = (await res.json()) as { status: string; players: number };
    expect(body.status).toBe("ok");
    expect(body.players).toBe(2);
    a.close();
    b.close();
  });
  it("404s anything else", async () => {
    const res = await fetch(`${url.replace("ws://", "http://")}/nope`);
    expect(res.status).toBe(404);
  });
});
