# AutoFactory pipeline UI

A live view of a Phase 1 run: the six agent steps, what each one produced, and
the flag and metrics that appear in LaunchDarkly as it goes. Built for showing
the factory on a projector, where a scrolling terminal does not read.

Zero dependencies. Two files: a ~170-line Node server and one HTML page.

## How it works

The CLI grew a `--events <path>` flag that appends one JSON object per line for
every lifecycle event (`packages/phase1-cli/src/eventLog.ts`). This server
tails that file and forwards each line to the browser over SSE. The page owns
all the rendering.

```
autofactory run --events live.ndjson          →  live.ndjson
                                                     │  (tail, 250ms)
                                              server.mjs
                                                     │  (SSE /events)
                                              index.html
```

Nothing in the UI holds pipeline logic, so you can reload the page, or open it
late, without touching a run in flight: the server replays the events it has
seen to every new client.

## Run it

```bash
# terminal 1: no arguments needed. Follows whichever per-branch feed in
# factory-ui/feeds/ was written most recently, so it picks up any round.
node server.mjs                                # http://localhost:3030

# terminal 2
./round.sh --fresh my-change   # branch, then stop so you can edit
./round.sh                     # run the chain
```

Start the server first if you want to watch from the beginning, though it does
not matter much: the feed is a file, so the UI catches up on whatever it missed.

`--events <path>` pins the server to one file instead, which is what a single
presenter wants. Without it the server follows the newest feed and switches if
another branch's round starts, resetting rather than splicing two runs together.

Port 3030 is deliberate, clear of the other demos in this workspace
(HorizonDemo 3000/3001 and v3 3020/3021, React_Demo 3010, PlatformLab 8080).

| Flag | Default | What |
|---|---|---|
| `--events <path>` | newest in `feeds/` | pin the feed to tail |
| `--port <n>` | `3030` | HTTP port |
| `--replay <path>` | `./replay.ndjson` | captured feed served at `/replay.ndjson` |

Joining an existing factory rather than building one: see [`join.sh`](join.sh)
and [../JOIN.md](../JOIN.md).

### Several people, one factory

Each branch gets its own feed (`feeds/lab-<branch>.ndjson`), so concurrent
rounds never overwrite each other, and every finished round stays selectable in
the source menu by branch name. The operational flags are shared though, so
flipping the approval gate gates everyone's next round.

## Switching source, and repeating a round

Two controls in the header, so nothing needs a URL or a restart mid-demo:

- **Source menu**: `Live run`, or any captured sample. The menu is built from
  `/fixtures`, which lists whatever fixture files are actually on disk, so
  capturing a new one needs no code change. Switching always resets first, so
  two runs can never splice into one timeline.
- **↻ Repeat**: re-runs the selected source. For a sample that is a fresh
  replay from the top. For live it reconnects and replays the feed the server
  already has, which is how you show a round again without re-running it.

Shipped samples, both captured from real runs rather than hand-written, so
sample mode draws exactly what live mode drew:

| Sample | What it shows |
|---|---|
| `replay.ndjson` | the full run, all six steps, verdict approved |
| `replay-gate.ndjson` | held at the approval gate, nothing created |

There is also a **Run another round** panel at the bottom of the page: the
commands to start a round, the rule that repeating one needs a new change, and
the gate demo. Shut by default so it never covers the run; `?runbook` opens it
on load for a walkthrough where the commands are the point. In Live mode it
also names the feed path this server is tailing, so the commands match the
instance you are looking at rather than a documented default.

URL overrides still work, and are what to use for screenshots:
`?replay=gate`, `?replay&instant`, `?replay&speed=4`, `?theme=light`,
`?runbook`.

## Running an actual round

`./round.sh` drives one round against the lab and points the feed at this UI.

```bash
./round.sh --fresh streak-v2   # branch from the base, then stop so you can edit
# ...make a change, commit it (no flags; the pipeline adds those)
./round.sh                     # run the chain on that branch
```

| Flag | What |
|---|---|
| `--fresh <name>` | branch `lab/<name>` from the base and stop |
| `--base <ref>` | diff against something other than `lab/sample-run` |
| `--gate` | hold at the approval gate this round |
| `--no-gate` | run straight through (the default state) |

**Repeating a round needs a new change, not a re-run.** The chain diffs a branch
against a base, so running twice on an unchanged branch just reprocesses the
same diff and the agents correctly conclude there is nothing new to flag.
`round.sh` refuses that case rather than letting you watch a confusing no-op.

`--gate` / `--no-gate` flip `auto-factory-approval-mode` in the factory project
over the REST API, because the gate is a LaunchDarkly flag rather than a code
setting. That is the point worth making out loud in the demo.

Two guards, both learned the hard way: `--fresh` refuses a dirty worktree using
`git status --porcelain` rather than `git diff`, because the factory leaves
*untracked* files (the release manifest) that git diff cannot see but that still
ride along across a checkout; and truncating the feed is what signals a new
round, so the UI resets instead of appending to the last one.

## What it shows

**Stat tiles** for elapsed, steps done over steps planned, flags created,
metrics created, and the resolved provider. Elapsed ticks locally between
events, so the page never looks frozen during the minutes-long agent steps.

**A rail** with one segment per planned step: filled for done, sweeping for the
one running, amber for a step held at an approval gate.

**A card per step** carrying the agent's own output tags. These are the
interesting part, because they are what the graph routes on: `risk_score`,
`flag_worthy`, `flag_action`, `review_approved`, `risk_level`. Deterministic
handoff checks appear underneath when they run.

**Created in LaunchDarkly**, with the flag linking straight into the app
project, and **Judge scores** kept in a separate section, because a judge is a
sampled evaluation rather than a created resource, and it is explicitly not a
gate.

The planned chain is read from the committed graph definition
(`config/agentcontrol/graphs/auto-factory.json`), by following `edges` from
`rootConfigKey`. It is the plan, not the outcome: routing tags can skip a step,
so anything that never started is shown as **skipped** rather than quietly
dropped. A node that runs but is not in the plan still gets a row, so a custom
graph is never invisible.

## States

Each state is an icon plus a word, never a colour on its own, and the words sit
in an ink token rather than the status colour. Warning yellow is only 1.79:1 on
a light surface, so colouring the label with it would make the one state a human
most needs to read the hardest to read.

| | State | When |
|---|---|---|
| ○ | pending | planned, not started |
| ⟳ | running | in flight |
| ✓ | completed | finished |
| ✕ | failed | the agent failed |
| ⏸ | awaiting approval | an approval gate held before this step |
| – | skipped | never ran, and the run is over |

Animation is decoration only: every state is in the text as well, and
`prefers-reduced-motion` turns all of it off.

## Demoing the approval gate

The gate is the best thing to show, because it is LaunchDarkly controlling an
agent pipeline rather than a config file. In the **factory** project, set
`auto-factory-approval-mode` to serve `always`, then start a run. The UI stops
at step 3, marks it awaiting approval, greys the rest as skipped, and prints the
exact `--approve` command to resume.

Use `always` rather than `risk-threshold`: the threshold defaults to 0.6 and
these changes score around 0.25, so they would sail through. Turn the flag back
off afterwards so the baseline runs clean.

## Known limits

- **Phase 1 only.** Phase 2 (Beacon, guarded releases after deploy) has its own
  lifecycle and is not on this feed.
- **CLI runs only.** A GitHub Action run writes its feed inside the CI runner,
  so this shows local runs. For a presented demo that is the better path anyway:
  no CI latency, and you control when it starts.
- **One run at a time.** A shrinking feed is treated as a new run and resets the
  page, so two runs must not share a feed path.
