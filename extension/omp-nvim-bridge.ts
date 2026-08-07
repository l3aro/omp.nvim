// omp.nvim bridge — runs inside every omp process (auto-discovered from
// ~/.omp/agent/extensions/). Opens a per-cwd Unix socket; the nvim plugin
// sends JSONL frames; prompts are injected into this process's live session
// via pi.sendUserMessage. Status frames flow back for :checktime refresh.
//
// Wire protocol (one JSON object per line):
//   in:  {"type":"ping"}
//   in:  {"type":"prompt","text":"..."}
//   out: {"type":"pong"}
//   out: {"type":"status","event":"ready"|"turn_started"|"turn_ended"}
import * as fs from "node:fs";
import * as net from "node:net";
import * as os from "node:os";
import * as path from "node:path";
import { createHash } from "node:crypto";

const DIR = path.join(os.homedir(), ".omp", "run", "omp-nvim");
const HASH_LEN = 16;
const SOCKET_MODE = 0o600;

interface Pi {
  sendUserMessage(content: string, options?: { deliverAs?: string }): void;
  on(event: string, handler: (event: unknown, ctx: unknown) => void): void;
}

interface PromptFrame {
  type: "prompt";
  text: string;
}

function isPromptFrame(value: unknown): value is PromptFrame {
  if (typeof value !== "object" || value === null) return false;
  if (!("type" in value) || !("text" in value)) return false;
  return value.type === "prompt" && typeof value.text === "string";
}

function socketPathFor(cwd: string): string {
  const hash = createHash("sha256").update(cwd).digest("hex").slice(0, HASH_LEN);
  return path.join(DIR, `omp-nvim-${hash}.sock`);
}

/** True if something is alive on the socket (another omp owns it). */
function isOccupied(socketPath: string): Promise<boolean> {
  return new Promise((resolve) => {
    const probe = net.createConnection(socketPath);
    probe.once("connect", () => {
      probe.destroy();
      resolve(true);
    });
    probe.once("error", () => resolve(false));
  });
}

export default async function ompNvimBridge(pi: Pi): Promise<void> {
  fs.mkdirSync(DIR, { recursive: true });
  const socketPath = socketPathFor(process.cwd());

  if (fs.existsSync(socketPath) && (await isOccupied(socketPath))) {
    console.error(
      `[omp-nvim] bridge disabled: another omp already owns ${socketPath} for ${process.cwd()}`,
    );
    return;
  }
  if (fs.existsSync(socketPath)) {
    fs.unlinkSync(socketPath); // stale socket from a dead omp
  }

  const clients = new Set<net.Socket>();
  const clientBufs = new WeakMap<net.Socket, string>();

  const broadcast = (frame: object): void => {
    const line = `${JSON.stringify(frame)}\n`;
    for (const client of clients) {
      client.write(line);
    }
  };

  const handleLine = (client: net.Socket, line: string): void => {
    if (!line.trim()) return;
    let frame: unknown;
    try {
      frame = JSON.parse(line);
    } catch {
      return;
    }
    if (isPromptFrame(frame)) {
      pi.sendUserMessage(frame.text);
      client.write(`${JSON.stringify({ type: "status", event: "prompt_accepted" })}\n`);
    } else if (typeof frame === "object" && frame !== null && "type" in frame && frame.type === "ping") {
      client.write(`${JSON.stringify({ type: "pong" })}\n`);
    }
  };

  let server: ReturnType<typeof Bun.listen>;
  try {
    server = Bun.listen({
      unix: socketPath,
      socket: {
        open(client) {
          clients.add(client);
          clientBufs.set(client, "");
          client.write(`${JSON.stringify({ type: "status", event: "ready" })}\n`);
        },
        data(client, buffer) {
          const combined = (clientBufs.get(client) ?? "") + buffer.toString();
          const lines = combined.split("\n");
          clientBufs.set(client, lines.pop() ?? "");
          for (const line of lines) {
            handleLine(client, line);
          }
        },
        close(client) {
          clients.delete(client);
          clientBufs.delete(client);
        },
        error(client, error) {
          clients.delete(client);
          console.error(`[omp-nvim] socket error: ${String(error)}`);
        },
      },
    });
  } catch (error) {
    console.error(`[omp-nvim] bridge disabled: cannot bind ${socketPath}: ${String(error)}`);
    return;
  }
  try {
    fs.chmodSync(socketPath, SOCKET_MODE);
  } catch {
    // non-fatal; dir is user-private anyway
  }

  pi.on("agent_start", () => broadcast({ type: "status", event: "turn_started" }));
  pi.on("agent_end", () => broadcast({ type: "status", event: "turn_ended" }));

  process.on("exit", () => {
    try {
      server.close();
      fs.unlinkSync(socketPath);
    } catch {
      // best effort
    }
  });

  console.error(`[omp-nvim] bridge listening on ${socketPath}`);
}
