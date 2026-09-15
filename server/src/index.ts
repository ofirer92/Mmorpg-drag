import { TICK_MS } from "@hamirpaa/shared-rules";
import { loadConfig } from "./config.js";
import { GameServer } from "./net/server.js";

const cfg = loadConfig();
const server = new GameServer({ host: cfg.HOST, port: cfg.PORT, logLevel: cfg.LOG_LEVEL });
await server.listen();

// 20 Hz tick loop (.claude/skills/server-architecture): fixed wall-clock interval, real elapsed dt
// passed into the step so a slow tick doesn't desync the simulation from real time. No `await`, no
// DB access inside — GameServer.step() only touches in-memory zone state.
let lastTick = performance.now();
const tickTimer = setInterval(() => {
  const now = performance.now();
  const dt = (now - lastTick) / 1000;
  lastTick = now;
  server.step(dt);
}, TICK_MS);

const shutdown = (): void => {
  clearInterval(tickTimer);
  void server.close().then(() => process.exit(0));
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
