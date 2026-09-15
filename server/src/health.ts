import { PROTOCOL_VERSION, TICK_RATE_HZ } from "@hamirpaa/shared-rules";

export interface Health {
  status: "ok";
  version: string;
  protocol: number;
  tick_hz: number;
  uptime_s: number;
  players: number;
  /** p95 of recent GameServer.step() durations, ms — .claude/skills/server-architecture targets < 30 ms. */
  tick_p95_ms: number;
}

export interface HealthOpts {
  version?: string;
  tickP95Ms?: number;
}

const started = Date.now();

export function healthPayload(players: number, opts: HealthOpts = {}): Health {
  return {
    status: "ok",
    version: opts.version ?? "0.0.1",
    protocol: PROTOCOL_VERSION,
    tick_hz: TICK_RATE_HZ,
    uptime_s: Math.floor((Date.now() - started) / 1000),
    players,
    tick_p95_ms: opts.tickP95Ms ?? 0,
  };
}
