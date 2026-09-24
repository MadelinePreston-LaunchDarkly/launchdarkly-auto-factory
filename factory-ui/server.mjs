#!/usr/bin/env node
/**
 * Live AutoFactory pipeline UI: a tiny static server plus an SSE endpoint that
 * tails the CLI's NDJSON event feed.
 *
 * The CLI writes one JSON object per line when run with `--events <path>` (see
 * packages/phase1-cli/src/eventLog.ts). This process owns no pipeline logic at
 * all: it forwards lines to the browser, and index.html decides what to draw.
 * That split is deliberate, so the UI can be reloaded or opened late without
 * disturbing a run in flight.
 *
 *   node server.mjs [--events <path>] [--port 3030]
 *
 * Port 3030 stays clear of the other demos in this workspace: HorizonDemo owns
 * 3000/3001 (and v3 3020/3021), React_Demo 3010, PlatformLab 8080.
 */

import { createServer } from "node:http";
import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const HERE = dirname(fileURLToPath(import.meta.url));

function arg(name, fallback) {
  const i = process.argv.indexOf(`--${name}`);
  return i !== -1 && process.argv[i + 1] && !process.argv[i + 1].startsWith("--") ? process.argv[i + 1] : fallback;
}

// Two modes. `--events <path>` PINS one file, which is what a single-presenter
// demo wants. Without it, follow whichever per-branch feed in feeds/ was
// written most recently: several cohorts share one factory and round.sh gives
// each branch its own file, so "the live run" means "the one happening now".
const PINNED = arg("events", null);
const FEEDDIR = join(HERE, "feeds");
let EVENTS = PINNED ?? newestFeed() ?? join(FEEDDIR, "(waiting)");

/** Most recently modified feeds/*.ndjson, or null when there are none yet. */
function newestFeed() {
  try {
    const entries = readdirSync(FEEDDIR)
      .filter((f) => f.endsWith(".ndjson"))
      .map((f) => {
        const full = join(FEEDDIR, f);
        return { full, mtime: statSync(full).mtimeMs };
      })
      .sort((a, b) => b.mtime - a.mtime);
    return entries[0]?.full ?? null;
  } catch {
    return null;
  }
}
const PORT = Number(arg("port", "3030"));
/** How often to check the feed for growth. Fast enough to feel live, cheap enough to ignore. */
const POLL_MS = 250;

/**
 * Captured runs the page can offer as sample demos. Each is a real run's feed,
 * not a hand-written script, so what the UI draws in sample mode is exactly
 * what it drew live.
 */
const FIXTURES = [
  { id: "approved", file: "replay.ndjson", label: "Sample: full run approved" },
  { id: "gate", file: "replay-gate.ndjson", label: "Sample: held at approval gate" },
];

/** Parsed events, newest last. The whole history is replayed to each new client. */
const history = [];
/** Byte offset consumed so far, and the size we last saw, to detect truncation. */
let offset = 0;
let lastSize = -1;
/** Open SSE responses. */
const clients = new Set();

function broadcast(payload) {
  const frame = `data: ${JSON.stringify(payload)}\n\n`;
  for (const res of clients) {
    try {
      res.write(frame);
    } catch {
      clients.delete(res);
    }
  }
}

/**
 * Read whatever is new in the feed and push it out.
 *
 * A file smaller than last time means the CLI truncated it for a fresh run, so
 * the history is dropped and clients are told to reset rather than splicing two
 * runs into one timeline.
 */
function poll() {
  // Unpinned: if another branch's round started more recently, follow it. The
  // switch resets clients rather than splicing two runs into one timeline.
  if (!PINNED) {
    const newest = newestFeed();
    if (newest && newest !== EVENTS) {
      EVENTS = newest;
      history.length = 0;
      offset = 0;
      lastSize = -1;
      broadcast({ type: "_reset" });
      broadcast({ type: "_ready", feed: EVENTS });
    }
  }
  if (!existsSync(EVENTS)) return;
  let size;
  try {
    size = statSync(EVENTS).size;
  } catch {
    return;
  }
  if (size === lastSize) return;
  if (size < lastSize || (size > 0 && lastSize === -1 && offset > 0)) {
    history.length = 0;
    offset = 0;
    broadcast({ type: "_reset" });
  }
  lastSize = size;
  if (size <= offset) return;

  let chunk;
  try {
    const buf = readFileSync(EVENTS);
    chunk = buf.subarray(offset).toString("utf8");
  } catch {
    return;
  }
  // Keep a trailing partial line in the buffer: the CLI appends whole lines,
  // but a read can still land mid-write.
  const lastNewline = chunk.lastIndexOf("\n");
  if (lastNewline === -1) return;
  const complete = chunk.slice(0, lastNewline);
  offset += Buffer.byteLength(complete, "utf8") + 1;

  for (const line of complete.split("\n")) {
    if (!line.trim()) continue;
    let event;
    try {
      event = JSON.parse(line);
    } catch {
      continue; // a malformed line is skipped, never fatal
    }
    history.push(event);
    broadcast(event);
  }
}

setInterval(poll, POLL_MS).unref?.();

const server = createServer((req, res) => {
  const url = new URL(req.url, "http://localhost");

  if (url.pathname === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache, no-transform",
      Connection: "keep-alive",
    });
    // Replay so a browser opened mid-run (or reloaded) renders full state.
    for (const event of history) res.write(`data: ${JSON.stringify(event)}\n\n`);
    res.write(`data: ${JSON.stringify({ type: "_ready", feed: EVENTS })}\n\n`);
    clients.add(res);
    // Comment keepalive: proxies and some browsers drop an idle stream, and the
    // gaps between agent steps are minutes long.
    const keepalive = setInterval(() => {
      try {
        res.write(": keepalive\n\n");
      } catch {
        /* cleaned up on close */
      }
    }, 20000);
    req.on("close", () => {
      clearInterval(keepalive);
      clients.delete(res);
    });
    return;
  }

  // Captured feeds, for rehearsing the visuals (and screenshotting the page)
  // without spending a real run. `/fixtures` lets the page build its own menu
  // from whatever is actually on disk, so adding a capture needs no code change.
  // Per-branch feeds on disk, so one cohort can look at another's round.
  if (url.pathname === "/feeds") {
    let feeds = [];
    try {
      feeds = readdirSync(FEEDDIR)
        .filter((f) => f.endsWith(".ndjson"))
        .map((f) => ({ id: `feed:${f}`, file: `feeds/${f}`, label: `Run: ${f.replace(/\.ndjson$/, "")}`, mtime: statSync(join(FEEDDIR, f)).mtimeMs }))
        .sort((a, b) => b.mtime - a.mtime)
        .map(({ mtime, ...rest }) => rest);
    } catch { /* no feeds yet */ }
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    res.end(JSON.stringify(feeds));
    return;
  }

  if (url.pathname === "/fixtures") {
    const found = FIXTURES.filter((f) => existsSync(join(HERE, f.file)));
    res.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
    res.end(JSON.stringify(found));
    return;
  }

  if (url.pathname.startsWith("/fixture/")) {
    const name = decodeURIComponent(url.pathname.slice("/fixture/".length));
    let file = null;
    if (name.startsWith("feed:")) {
      // basename only: never let a feed id walk out of feeds/.
      const bare = name.slice("feed:".length).replace(/[^A-Za-z0-9._-]/g, "");
      if (bare.endsWith(".ndjson")) file = join(FEEDDIR, bare);
    } else {
      const entry = FIXTURES.find((f) => f.id === name);
      file = entry ? join(HERE, entry.file) : null;
    }
    if (!file || !existsSync(file)) {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("no such fixture: capture one with `autofactory run --events <file>`");
      return;
    }
    res.writeHead(200, { "Content-Type": "application/x-ndjson", "Cache-Control": "no-store" });
    res.end(readFileSync(file));
    return;
  }

  // Kept for the earlier ?replay URLs.
  if (url.pathname === "/replay.ndjson") {
    const file = arg("replay", join(HERE, "replay.ndjson"));
    if (!existsSync(file)) {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("no replay fixture: capture one with `autofactory run --events replay.ndjson`");
      return;
    }
    res.writeHead(200, { "Content-Type": "application/x-ndjson", "Cache-Control": "no-store" });
    res.end(readFileSync(file));
    return;
  }

  if (url.pathname === "/" || url.pathname === "/index.html") {
    const file = join(HERE, "index.html");
    if (!existsSync(file)) {
      res.writeHead(500, { "Content-Type": "text/plain" });
      res.end("index.html is missing next to server.mjs");
      return;
    }
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "no-store" });
    res.end(readFileSync(file));
    return;
  }

  res.writeHead(404, { "Content-Type": "text/plain" });
  res.end("not found");
});

server.listen(PORT, () => {
  console.log(`AutoFactory pipeline UI  →  http://localhost:${PORT}`);
  console.log(`tailing feed             ->  ${EVENTS}${PINNED ? " (pinned)" : " (newest in feeds/)"}`);
  console.log(`\nRun the chain with:  --events ${EVENTS}`);
  if (!existsSync(EVENTS)) console.log("\n(feed does not exist yet; the UI will come alive when the run starts)");
});
