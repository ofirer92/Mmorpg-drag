import { WebSocket } from "ws";
import { GameServer, type GameServerOptions } from "../../src/net/server.js";

export async function startTestServer(
  opts: GameServerOptions = {},
): Promise<{ server: GameServer; url: string }> {
  const server = new GameServer({ logLevel: "silent", ...opts });
  const { port, host } = await server.listen();
  return { server, url: `ws://${host}:${port}` };
}

/** A fake client that records every message it receives. Two of these = the minimum for any handler test. */
export class FakeClient {
  readonly received: Array<Record<string, unknown>> = [];
  private closedCode: number | null = null;
  private constructor(readonly ws: WebSocket) {}

  static async join(url: string): Promise<FakeClient> {
    const ws = new WebSocket(url);
    const c = new FakeClient(ws);
    ws.on("message", (raw) => c.received.push(JSON.parse(String(raw)) as Record<string, unknown>));
    ws.on("close", (code) => (c.closedCode = code));
    await new Promise<void>((resolve, reject) => {
      ws.once("open", () => resolve());
      ws.once("error", reject);
    });
    return c;
  }
  sendRaw(raw: string): void {
    this.ws.send(raw);
  }
  send(msg: Record<string, unknown>): void {
    this.sendRaw(JSON.stringify(msg));
  }
  async next(
    pred: (m: Record<string, unknown>) => boolean = () => true,
    timeoutMs = 1000,
  ): Promise<Record<string, unknown>> {
    const start = Date.now();
    let seen = 0;
    for (;;) {
      for (; seen < this.received.length; seen++) {
        const m = this.received[seen];
        if (m !== undefined && pred(m)) return m;
      }
      if (Date.now() - start > timeoutMs) throw new Error("timeout waiting for message");
      await new Promise((r) => setTimeout(r, 5));
    }
  }
  async waitClosed(timeoutMs = 1000): Promise<number> {
    const start = Date.now();
    while (this.closedCode === null) {
      if (Date.now() - start > timeoutMs) throw new Error("timeout waiting for close");
      await new Promise((r) => setTimeout(r, 5));
    }
    return this.closedCode;
  }
  close(): void {
    this.ws.close();
  }
}
