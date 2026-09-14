import { PROTOCOL_VERSION, TICK_RATE_HZ } from "@hamirpaa/shared-rules";

export interface Health {
  status: "ok";
  version: string;
  protocol: number;
  tick_hz: number;
  uptime_s: number;
  players: number;
}

const started = Date.now();

export function healthPayload(players: number, version = "0.0.1"): Health {
  return {
    status: "ok",
    version,
    protocol: PROTOCOL_VERSION,
    tick_hz: TICK_RATE_HZ,
    uptime_s: Math.floor((Date.now() - started) / 1000),
    players,
  };
}
