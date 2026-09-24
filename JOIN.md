# Join the factory

Instructions for another Claude Code instance, or another SE, to set up against
the AutoFactory we already have running and take a turn at it. Written to be
handed over verbatim: read it top to bottom and follow it.

You are **joining an existing factory, not building one.** That distinction
matters: this repo's own [INSTALL-CLAUDE-CODE.md](INSTALL-CLAUDE-CODE.md) walks
you through `npm run init`, which *creates* projects. Running it here would be
the wrong verb.

## What already exists

| Thing | Where |
|---|---|
| LaunchDarkly instance | `https://ld-stg.launchdarkly.com` (**staging**, never production) |
| Factory project | `word-golf-factory`: 7 agent configs, 2 judges, the `gha-auto-factory` graph, 20 tools, 5 operational flags |
| App project | `word-golf`: where the agents create flags and metrics |
| This repo | the tool, the live UI (`factory-ui/`), and these instructions |
| App repo | `MadelinePreston-LaunchDarkly/WordGolfAutofactory`, branch `qbr-2026-workshop` |

**One factory, shared.** Everyone joining runs against the same
`word-golf-factory`. See "Shared, so coordinate" below for the one consequence.

## Setup

```bash
# 1. This repo (the tool AND the UI) plus the app repo, as siblings.
git clone https://github.com/MadelinePreston-LaunchDarkly/launchdarkly-auto-factory
git clone -b qbr-2026-workshop https://github.com/MadelinePreston-LaunchDarkly/WordGolfAutofactory

# 2. Point at the existing factory and prove the connection.
#    Needs an LD API token with write access, and an Anthropic API key.
cd launchdarkly-auto-factory/factory-ui
LD_API_KEY=api-... ANTHROPIC_API_KEY=sk-ant-... ./join.sh

# 3. Independent check of the same install.
cd .. && npm run doctor -- --skip-github

# 4. The live UI. Leave it running; it is how a round is watched.
cd factory-ui && node server.mjs        # then open http://localhost:3030
```

Ask Madeline for the two keys; they are handed over directly, never pasted into
a repo or a channel.

`join.sh --check` verifies and writes nothing, if you want to look first. It
fetches the factory's SDK key **by project** rather than trusting a pasted one,
writes `../.env`, backs up any existing one, and builds the CLI if `dist/` is
missing. If the factory does not exist, or exists but was never provisioned, it
says so and prints the `init` command instead of leaving you a broken `.env`.

Expect `doctor` to end with `✓ No problems.` If it does not, stop and report
what it said rather than working around it.

## Take a turn

A **round** is one pass of the six-agent chain over one change.

```bash
cd launchdarkly-auto-factory/factory-ui
./round.sh --fresh my-change      # branches lab/my-change, then stops
# ... make ONE small change in the app repo's word-golf/ directory, commit it
./round.sh                        # runs the chain, streaming to the UI
```

If your app checkout is not a sibling of this repo, point at it:
`AF_APP_ROOT=/path/to/WordGolfAutofactory ./round.sh`.

Watch at http://localhost:3030 with the source menu on **Live run (newest)**.
Each branch writes its own feed under `factory-ui/feeds/`, so concurrent rounds
do not overwrite each other, and the server follows whichever started last. Any
finished round stays selectable in that menu by branch name.

### Rules, and the reasons

1. **Do not add feature flags yourself.** The pipeline creates them. A change
   that arrives pre-flagged defeats the exercise. Write the feature as if flags
   did not exist.
2. **Do not run `npm run init`.** The factory exists. `init` is idempotent so it
   would not break anything, but it also would not tell you whether you are
   pointed at the right factory, which is what `join.sh` is for.
3. **One small change per round.** The chain reasons about a diff; a sprawling
   diff produces a sprawling flag.
4. **Never set `APPROVAL_MODE` or `RISK_THRESHOLD`.** They silently override the
   LaunchDarkly flags that are the entire point.
5. **Repeating a round needs a new change, not a re-run.** The chain diffs your
   branch against its base, so a re-run reprocesses the same diff and the agents
   correctly conclude there is nothing new. `round.sh` refuses this case.

### How long, and when to worry

Usually 10 to 15 minutes across six agents. It can exceed 45 minutes if a model
call times out and retries, and **nothing on the progress stream says it is
retrying**, so a healthy run can look hung on one step. Do not kill a slow run.
Check `factory-ui/feeds/<your-branch>.ndjson` for the last event if unsure.

### Exit codes

| Code | Meaning | What to do |
|---|---|---|
| 0 | approved, or a clean no-op | done; look at the flag it made |
| 1 | rejected, or the chain stalled | read the deciding agent's output, which the CLI prints |
| 2 | configuration problem | fix it; do not retry blindly |
| 3 | held at an approval gate | re-run adding `--approve <node>` for each approved step |
| 4 | an agent asked a question | answer in the manifest's `humanInput.answer`, re-run |

## Shared, so coordinate

One factory means the operational flags are shared. If you flip the approval
gate, **everyone's next round is gated**, not just yours. Say so before you do
it, and put it back:

```bash
./round.sh --gate --fresh gated-change   # gate ON, for everyone
./round.sh --no-gate                     # back to running straight through
```

Use `--gate` (which serves `always`) rather than the `risk-threshold` mode: the
threshold is 0.6 and these changes score around 0.25, so they would sail through
and the gate would look broken.

The gate is worth showing because it is LaunchDarkly holding an agent pipeline
rather than a config file doing it. With it on, the chain halts before the flag
implementer, creates nothing for that step or any later one, and prints the exact
`--approve` command. The UI shows step 3 amber and steps 4 to 6 greyed.

## Already fixed here: do not rediscover these

Three bugs stop a fresh **upstream** install. All three are fixed in this fork.
If you hit them, you cloned upstream by mistake.

| Symptom | Cause |
|---|---|
| `init` fails, then `graph gha-auto-factory [404]` | `isInverted` missing from the judge create body. Two judges fail, then the agents that attach them, then the graph. The 404 points nowhere near the cause |
| `ERR_MODULE_NOT_FOUND: @auto-factory/shared/dist/index.js` | no workspace package has a `prepare` hook, so `npm run build` is a required step the quick start omits |
| `401 (invalid SDK key) for streaming request` while every setup check passes | `LD_BASE_URL` only redirects the REST API; the server SDK needs its own endpoint overrides, or a staging key hits production |

One more if you change this repo's source: `dist/action.bundle.js` is
**committed** and the GitHub workflow runs it with no build step, so a source fix
reaches the CLI but not CI until someone runs `npm run bundle` and commits it.

Full write-ups in [docs/qbr2026/POSTMORTEM.md](docs/qbr2026/POSTMORTEM.md).

## What to report back

- the branch, and what the change was
- the verdict, plus the flag and metric keys the chain created
- judge scores, and anything the deterministic handoff checks flagged
- anything that surprised you, for the post-mortem

## If you are stuck

Run `npm run doctor -- --skip-github` first. It checks the local env, the factory
project, that the SDK key belongs to that project, that every committed config
exists in LaunchDarkly, and that the graph version matches this checkout.

It is REST-only, though, so it can pass on an install whose **SDK** cannot
connect. That looks like a clean bill of health followed by a 401 at run time,
and it is the third row in the table above.
