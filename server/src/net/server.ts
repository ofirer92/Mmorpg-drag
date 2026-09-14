import { createServer, type IncomingMessage, type Server, type ServerResponse } from "node:http";
import type { AddressInfo } from "node:net";
import { WebSocketServer, WebSocket } from "ws";
import pino from "pino";
import { parseClientMessage, type ClientMessage, type ServerMessage } from "@hamirpaa/shared-rules";
import { healthPayload } from "../health.js";
import { newBucket, take, type Bucket } from "./ratelimit.js";

export interface GameServerOptions {
  host?: string;
  port?: number; // 0 = random (tests)
  logLevel?: string;
  rate?: { perSec: number; burst: number };
  maxInvalid?: number;
}

interface Session {
  ws: WebSocket;
  bucket: Bucket;
  invalid: number;
  invalidSince: number;
}

/** Minimal authoritative server: HTTP /health + WebSocket with validate → rate-limit → handler. */
export class GameServer {
  private readonly http: Server;
  private readonly wss: WebSocketServer;
  private readonly sessions = new Set<Session>();
  private readonly log: pino.Logger;
  private readonly rate: { perSec: number; burst: number };
  private readonly maxInvalid: number;
  private readonly opts: GameServerOptions;

  constructor(opts: GameServerOptions = {}) {
    this.opts = opts;
    this.log = pino({ level: opts.logLevel ?? "info" });
    this.rate = opts.rate ?? { perSec: 20, burst: 40 };
    this.maxInvalid = opts.maxInvalid ?? 3;
    this.http = createServer((req, res) => this.onHttp(req, res));
    this.wss = new WebSocketServer({ server: this.http });
    this.wss.on("connection", (ws) => this.onConnection(ws));
  }

  get players(): number {
    return this.sessions.size;
  }

  listen(): Promise<{ port: number; host: string }> {
    return new Promise((resolve) => {
      const host = this.opts.host ?? "127.0.0.1";
      this.http.listen(this.opts.port ?? 0, host, () => {
        const addr = this.http.address() as AddressInfo;
        this.log.info({ port: addr.port, host }, "listening");
        resolve({ port: addr.port, host });
      });
    });
  }

  close(): Promise<void> {
    for (const s of this.sessions) s.ws.terminate();
    return new Promise((resolve) => this.wss.close(() => this.http.close(() => resolve())));
  }

  private onHttp(req: IncomingMessage, res: ServerResponse): void {
    if (req.url === "/health") {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify(healthPayload(this.players)));
      return;
    }
    res.writeHead(404);
    res.end();
  }

  private onConnection(ws: WebSocket): void {
    const session: Session = {
      ws,
      bucket: newBucket(this.rate.burst, Date.now()),
      invalid: 0,
      invalidSince: Date.now(),
    };
    this.sessions.add(session);
    ws.on("message", (raw) => this.onMessage(session, String(raw)));
    ws.on("close", () => this.sessions.delete(session));
    ws.on("error", (err) => this.log.warn({ err }, "ws error"));
  }

  private onMessage(session: Session, raw: string): void {
    const now = Date.now();
    if (!take(session.bucket, this.rate.perSec, this.rate.burst, now)) {
      this.send(session, { t: "error", code: "rate_limited", msg_key: "error.rate_limited" });
      return;
    }
    const msg = parseClientMessage(raw);
    if (msg === null) {
      if (now - session.invalidSince > 10_000) {
        session.invalid = 0;
        session.invalidSince = now;
      }
      session.invalid += 1;
      this.log.warn({ len: raw.length, invalid: session.invalid }, "invalid message dropped");
      this.send(session, { t: "error", code: "invalid_message", msg_key: "error.invalid_message" });
      if (session.invalid >= this.maxInvalid) session.ws.close(1008, "too many invalid messages");
      return;
    }
    this.handle(session, msg, now);
  }

  private handle(session: Session, msg: ClientMessage, now: number): void {
    switch (msg.t) {
      case "ping":
        this.send(session, { t: "pong", ts: msg.ts, server_ts: now });
        return;
    }
  }

  private send(session: Session, msg: ServerMessage): void {
    if (session.ws.readyState === WebSocket.OPEN) session.ws.send(JSON.stringify(msg));
  }
}
