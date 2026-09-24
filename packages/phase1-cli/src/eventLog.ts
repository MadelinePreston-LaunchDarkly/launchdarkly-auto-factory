/**
 * Optional NDJSON event feed for the run (`--events <path>`).
 *
 * The CLI already streams human-readable progress to stdout. This writes the
 * same lifecycle as one JSON object per line so another process can follow a
 * run without scraping console text: the live pipeline UI tails this file and
 * pushes each line to the browser over SSE.
 *
 * Deliberately additive and best-effort. Without `--events` nothing is written,
 * and a write failure never interrupts the chain — telemetry must not be able
 * to break the thing it is observing.
 */

import { appendFileSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname } from "node:path";

/** A line in the feed: the event payload plus when it happened. */
export interface FeedEvent {
  type: string;
  at: string;
  [key: string]: unknown;
}

export interface EventLog {
  emit(event: Record<string, unknown> & { type: string }): void;
}

/** A sink that discards everything, so callers need no null checks. */
const NOOP: EventLog = { emit() {} };

/**
 * Open an append-only NDJSON sink at `path`, truncating any previous run so the
 * UI never shows two runs spliced together. Returns a no-op sink when `path` is
 * undefined or the file cannot be opened.
 */
export function openEventLog(path: string | undefined): EventLog {
  if (!path) return NOOP;
  try {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, "");
  } catch (e) {
    console.warn(`[events] cannot open ${path} (${e instanceof Error ? e.message : e}); continuing without the feed.`);
    return NOOP;
  }
  return {
    emit(event) {
      try {
        const line: FeedEvent = { ...event, at: new Date().toISOString() };
        appendFileSync(path, `${JSON.stringify(line)}\n`);
      } catch {
        /* best-effort: a broken feed must not stop the run */
      }
    },
  };
}
