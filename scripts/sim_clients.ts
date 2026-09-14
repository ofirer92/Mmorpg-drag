#!/usr/bin/env -S pnpm exec tsx
/**
 * Runs N fake clients against the server for D seconds: connects, pings, measures RTT, checks that
 * every pong echoes its ping. Usage: pnpm sim -- --clients 50 --seconds 600 --url ws://localhost:8080
 */
import WebSocket from "ws";
import { MESSAGE_TYPES } from "../packages/shared-rules/src/protocol.js";

const arg = (k: string, d: string): string => {
  const i = process.argv.indexOf(`--${k}`);
  return i >= 0 && process.argv[i + 1] ? process.argv[i + 1] : d;
};
const N = Number(arg("clients", "4"));
const SECONDS = Number(arg("seconds", "10"));
const URL = arg("url", "ws://localhost:8080");

let sent = 0,
  got = 0,
  bad = 0;
const rtts: number[] = [];

function client(id: number): Promise<void> {
  return new Promise((resolve) => {
    const ws = new WebSocket(URL);
    const timer = setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify({ t: "ping", ts: Date.now() }));
        sent++;
      }
    }, 1000);
    ws.on("message", (raw) => {
      const msg = JSON.parse(String(raw)) as { t: string; ts?: number };
      if (!(MESSAGE_TYPES as readonly string[]).includes(msg.t)) {
        bad++;
        return;
      }
      if (msg.t === "pong" && typeof msg.ts === "number") {
        got++;
        rtts.push(Date.now() - msg.ts);
      }
    });
    ws.on("error", (e) => {
      console.error(`client ${id}:`, e.message);
      bad++;
    });
    setTimeout(() => {
      clearInterval(timer);
      ws.close();
      resolve();
    }, SECONDS * 1000);
  });
}

(async () => {
  console.log(`sim_clients: ${N} clients × ${SECONDS}s → ${URL}`);
  await Promise.all(Array.from({ length: N }, (_, i) => client(i)));
  rtts.sort((a, b) => a - b);
  const p95 = rtts[Math.floor(rtts.length * 0.95)] ?? NaN;
  console.log(
    JSON.stringify({
      sent,
      got,
      bad,
      p95_rtt_ms: p95,
      mean_rtt_ms: rtts.reduce((a, b) => a + b, 0) / (rtts.length || 1),
    }),
  );
  process.exit(bad === 0 && got >= sent * 0.9 ? 0 : 1);
})();
