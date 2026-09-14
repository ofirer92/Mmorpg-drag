import { loadConfig } from "./config.js";
import { GameServer } from "./net/server.js";

const cfg = loadConfig();
const server = new GameServer({ host: cfg.HOST, port: cfg.PORT, logLevel: cfg.LOG_LEVEL });
await server.listen();

const shutdown = (): void => {
  void server.close().then(() => process.exit(0));
};
process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
