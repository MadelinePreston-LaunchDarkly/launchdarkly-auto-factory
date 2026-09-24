# QBR 2026 SE Workshop: prep

Source: [SE Workshop - QBRS 2026](https://launchdarkly.atlassian.net/wiki/spaces/~779364305/pages/5190451215/SE+Workshop+-+QBRS+2026)
(owner Tom Totenberg). Two sessions: **AC Enablement Refresh** (1 hr, lead Kevin
Cochran) and **Factory Hands-on** (2 hrs).

Issues found along the way are collected in [POSTMORTEM.md](POSTMORTEM.md) for
Eric, Alex, Tom and Kevin. Prep is complete through **exercise step 6**, plus a
rehearsed lab: a working factory, both the CLI and the GitHub Action paths
proven end to end, and a live UI for showing it.

## The page's four prep items, all done

| Item | Status |
|---|---|
| Make sure Docker is installed | Docker Desktop 29.8.0, daemon verified, bundled Compose v5.5.1 |
| Try logging into Staging | Verified via API, `accountId 6a8f0c503153d70aa800afcf`, you are the sole member and owner |
| Check access to `EricDarkly/tabbit-demo` | Confirmed READ, cloned, image built, Anthropic path ran green |
| Anthropic keys | [Sheet](https://docs.google.com/spreadsheets/d/1JofFs0uHsRJ8BhOdDkg7MLA5quZ5FgSk5LxWLJaKPcE/edit) readable, 12 team keys, Team 11's marked INVALID. Claimed per team on the day, expire after the QBR |

Docker notes: do **not** `brew install docker`. The Homebrew formula lands in
`/opt/homebrew/bin` and shadows Desktop's CLI at `/usr/local/bin/docker`. Podman
6.1.1 and the PlatformLab VM are untouched, so both VMs running means two VMs'
worth of RAM. `~/.docker/config.json` has `credsStore: desktop` but no stored
auths, so confirm the Desktop UI shows you signed in. Docker's licensing requires
it and it needs the "Dockerhub" app in the
[Lumos App Store](https://app.lumosidentity.com/app_store?domainAppId=806909).
Public pulls worked anonymously, so it will not block you technically.

## Links to share with your group

Both forks are **public**, so the links alone are enough to read and clone. Add
groupmates as collaborators only so they can push to the shared branch.

| What | Link |
|---|---|
| AutoFactory fork (step 2) | https://github.com/MadelinePreston-LaunchDarkly/launchdarkly-auto-factory |
| Word Golf fork (step 3) | https://github.com/MadelinePreston-LaunchDarkly/WordGolfAutofactory |
| Shared working branch (step 4) | `qbr-2026-workshop` on the Word Golf fork |
| LD app project (step 5) | `word-golf` on `ld-stg.launchdarkly.com` |

Adding collaborators, once you know who is in your group:

```bash
for u in githubuser1 githubuser2; do
  gh api -X PUT repos/MadelinePreston-LaunchDarkly/WordGolfAutofactory/collaborators/$u -f permission=push
  gh api -X PUT repos/MadelinePreston-LaunchDarkly/launchdarkly-auto-factory/collaborators/$u -f permission=push
done
```

`push` is what they need to work on the shared branch. They each have to accept
the invite before they can clone.

### The private round trip left one permanent mark

Both repos were flipped to private and then back to public. Two notes from that:

1. **The GitHub fork link is gone for good.** Going private detached it, and
   going back to public did **not** restore it. Both repos now report
   `isFork: false` with no parent, so there is no "Sync fork" button and
   `gh repo sync` has nothing to sync from. Upstream is still reachable as a
   plain git remote in the local clone (`upstream` is
   `alawrenceld/WordGolfAutofactory`, `origin` is your copy), so this still
   works:

   ```bash
   git fetch upstream && git merge upstream/main
   ```

   Checked after the change: 0 behind upstream, 2 ahead.

2. **No PAT needed, and the workflow no longer asks for one.** While private, the
   tool checkout needed `token: ${{ secrets.TOOL_REPO_TOKEN }}`, because
   `GITHUB_TOKEN` is scoped to the repo running the workflow and cannot clone a
   different private repo. Now that the fork is public again that line is
   removed (commit `39eabf0`). It had to go: `TOOL_REPO_TOKEN` was never set, so
   leaving it would pass an empty string to `actions/checkout` and break a step
   that otherwise works. The reasoning is kept as a comment in the workflow in
   case you go private again.

Because the repos are public, Actions runners are free again rather than drawing
on the account quota.

Credentials and anything meant to be handed out by hand live in
**`handout.local.md`**, which `.gitignore` in this directory keeps out of git via
`*.local.md`. That file is the thing to share with groupmates, not this one.

## Exercise progress

Everything through step 6 is done. Steps 7 onward are the group's work.

1. ~~Cluster into groups of 3~~. On the day.
2. ~~Fork the AutoFactory Prototype and share the link~~. **Done**, public fork
   of `launchdarkly-labs/launchdarkly-auto-factory`, in sync at `13226182c7a3`.
   - **Run the bootstrap to create an AutoFactory project, verify the agent
     configs and graph landed. NOT done, this is the group's step.** Entry points:
     `npm run bootstrap` (`bootstrap/create.mjs`), `npm run init` for the guided
     config-bridge CLI, `npm run doctor -- --app-repo owner/name` to validate.
     Remember to set `LD_BASE_URL=https://ld-stg.launchdarkly.com` or it will
     build the factory in production.
3. ~~Each SE clones the Word Golf repo~~. **Done and then some.** Cloned at
   `WordGolfAutofactory/`, `npm install` warm, `npm run build` clean. Also forked,
   because step 4 needs push access (see POSTMORTEM item 5). The clone's remotes
   are rewired: `origin` is your fork, `upstream` is `alawrenceld/WordGolfAutofactory`.
4. ~~Someone creates and publishes a shared working branch~~. **Done**, branch
   `qbr-2026-workshop`, pushed and tracking. Groupmates get write access on your
   fork, or send PRs into that branch.
5. ~~Create a temporary LaunchDarkly project for Word Golf~~. **Done**, project
   `word-golf` ("Word Golf", tags `demo`, `qbr-2026`, `autofactory`, `temporary`)
   on **staging**, with default Test and Production environments.
6. ~~Point your branch's workflow at your AutoFactory fork~~. **Done**, commit
   `f8c163e` on `qbr-2026-workshop`. Two changes to `.github/workflows/auto-factory.yml`:
   the tool checkout now targets `MadelinePreston-LaunchDarkly/launchdarkly-auto-factory`,
   and `LD_BASE_URL: https://ld-stg.launchdarkly.com` is set explicitly.
7. Assign roles: frontend/mobile, backend/platform, infra/AI/prompt-control.
8. Build independently. **Do not add flags**, the pipeline does that.
9. Submit PRs, confirm AutoFactory runs, look at the flags it created.
10. Bonus: AutoFactory phase 2 in a deploy tool (Alex used Railway), test
    auto-release.

Narrative: you work for the New York Times Games team, asked to turn the beta
[Word Golf](https://wordgolffactory.launchdarklydemos.com/) into something more
compelling for NYT Games subscribers. New directions welcome, no bad ideas.

## Repo secrets: the state now

On the Word Golf fork, `MadelinePreston-LaunchDarkly/WordGolfAutofactory`. All
four the workflow needs are set, and the Action path is proven (see below).

| Name | Kind | State |
|---|---|---|
| `LD_APP_PROJECT_KEY` | variable | `word-golf`, the group's project, untouched |
| `ANTHROPIC_API_KEY` | secret | set from `LD/.env`; swap for your team key on the day |
| `LD_SDK_KEY` | secret | set to the **lab** factory project's key. Overwrite with the group's factory key once they bootstrap |
| `LD_API_KEY` | secret | the staging writer token |
| `CURSOR_API_KEY` | secret | not set, and not needed: the provider flag is pinned to `anthropic` |

The writer token is `QBR_2026_Workshop_Writer`, token id
`6ab2d1a8ef50830ac141afeb`, stored in `LD/.env` as
`LD_API_TOKEN_QBR_STAGING_WRITER`. It is also handed to the cohort **by hand**
via `handout.local.md`, not pasted anywhere public. Verified working:
authenticates, reads and writes the app project, and created every resource in
both proven paths.

Caveats on that token: the built-in Writer role is **account-wide** on this
staging account, so it can also reach `horizon-demo`, `react-qr-demo` and
`tabbit-demo`. A project-scoped custom role would be tighter but would block the
bootstrap, which has to create the factory project. **Expire it after the QBR:**
`DELETE /api/v2/tokens/6ab2d1a8ef50830ac141afeb` against the staging base URL.

## Reference: things worth knowing

- **Two projects, not one.** The AutoFactory needs a *factory* project (agent AI
  configs, the agent graph, the `auto-factory-*` operational flags, which it
  reads) and an *app* project (where it creates flags and metrics, which is
  `word-golf`). `npm run init` creates or confirms both and is idempotent, so it
  will reuse `word-golf` rather than duplicate it.
- Two details explaining the workflow's odd shape: the PR checks out at the
  workspace root, not a subdirectory, so `ld-find-code-refs` can find `.git`
  while scanning `SANDBOX_ROOT=word-golf`, and the factory checks out separately
  under `tool/` so agent git ops never sweep it into the PR.
- `word-golf/.release-flags/` already holds six manifests from PRs 12 to 25.
  Reading one is the fastest way to see what Phase 1 emits.
- Phase 1 has six front ends over one shared core, including a headless
  `autofactory` CLI with a drop-in Claude Code skill (`bootstrap/claude-code/`,
  see `INSTALL-CLAUDE-CODE.md`). Locally-driven runs set the created flag's
  maintainer from `git config user.email`.
- Node here is v26.7.0. AutoFactory wants 20+, the GitHub Action pins 24, the
  Cursor provider needs 22.13 or newer.
- `find-code-refs.yml` also consumes `vars.LD_APP_PROJECT_KEY`, so it picks up
  `word-golf` automatically.

## AC Enablement session: already provisioned

This went past prep into the session's own setup, kept deliberately. It is in
**your personal staging account only**, one member, you, so it cannot touch
another SE's cohort. Production `app.launchdarkly.com` was never touched.

- Staging project **`tabbit-demo`** ("Tabbit Demo", tags `demo`, `qbr-2026`,
  `agentcontrol`), created 2026-09-22, default Test and Production environments.
- All 11 Terraform resources applied: 5 tools (`add`, `subtract`, `divide`,
  `multiply`, `sum_amounts`), AI configs `receipt-itemizer` (completion),
  `claim-parser` (agent), `claim-accuracy-judge` (judge), one `default` variation
  each.
- Targeting came back `enabled: true` in both environments already, so the
  README's "turn targeting on if needed" step looks unnecessary. Note the field
  is `enabled`, not `on`.
- `claim-parser/default` attaches the judge at `sampling_rate = 1.0`, so every
  `turnkey_sdk.py` run costs an extra Sonnet call to score itself.
- `tabbit-demo/.env` holds the staging test-environment server SDK key, the
  staging API token, and `TF_VAR_project_key=tabbit-demo`. Gitignored, as is
  `terraform/terraform.tfstate`.
- Local fix applied: `is_inverted = false` on the judge resource in
  `terraform/main.tf` (POSTMORTEM item 1).
- **Not yet run:** `turnkey_sdk.py` end to end against these configs, and
  `optimization.py`.

## The sampleRunLab: a working factory, proven end to end

Built to rehearse the session solo, so the group's `word-golf` project and
`qbr-2026-workshop` branch stay pristine. Separate projects, separate branches,
nothing shared with the group artifacts.

| Piece | Where |
|---|---|
| Factory project | `samplerunlab-factory` on staging |
| App project | `samplerunlab-app` on staging |
| Tool clone | `LD/QBR2026/launchdarkly-auto-factory` |
| App worktree | `LD/QBR2026/wordgolf-lab`, branches `lab/sample-run` and `lab/gate-demo` |

Provisioned by `npm run init --yes --provider anthropic --base-url
https://ld-stg.launchdarkly.com --front-end none --no-pr`, deliberately using
the **writer** token rather than the admin one, so the credential the group will
use is proven to create projects, configs, judges, graphs, tools and metrics.

`samplerunlab-factory` holds 7 agent configs, 2 judges, the `gha-auto-factory`
graph, 20 tools and the 5 `auto-factory-*` operational flags. `npm run doctor`
reports `✓ No problems.`

### A complete Phase 1 run

I took the frontend lane, added a "To Par" stat to the scoreboard with **no
flags** (exercise step 8.1), committed it, and ran the chain headlessly:

```bash
SANDBOX_ROOT=word-golf node packages/phase1-cli/dist/cli.js run \
  --root ../wordgolf-lab --base qbr-2026-workshop
```

All six nodes ran: research-planner → manifest-steward → flag-implementer →
metrics-author → flag-testing → code-reviewer. **Verdict: APPROVED, risk low,
exit 0.** It took about 15 minutes, which is worth knowing when budgeting the
90-minute block.

What it produced, unprompted:

- Flag `show-live-par-score`, multivariate `control` | `v1`, marked temporary,
  maintainer resolved to your git email. **Targeting off in both environments,
  `offVariation` = `control`**, verified against the API rather than assumed
- Four metrics: `-error` (killswitch, puzzle abandoned), `-made-par` (pause,
  the primary hypothesis), `-completed` (pause), `-business` (monitoring,
  treatment-only engagement)
- It **rewrote my code** to sit behind the flag, with a fail-safe `control`
  default and a comment explaining both paths, then added a `useEffect` firing
  the business metric on the treatment path only, wrapped in try/catch so
  telemetry cannot break rendering
- Registered the flag and metrics in `config/flags.json`, `config/metrics.json`,
  `packages/ld/src/flags.ts` and `events.ts`
- Wrote flag-on/flag-off tests. `npm test` passes 86, fails 0, and
  `npm run build` is clean
- `.release-flags/pr-lab-sample-run.json`, whose notes even flag a CSS risk it
  noticed: the scoreboard goes from 3 to 4 stats on the treatment path, so the
  grid layout should be checked

Committed verbatim on `lab/sample-run` as a reference for what a finished run
looks like.

### The toggle demo, rehearsed

This is the "flip a flag, do not tear anything down" idea, and it works. The
gate is controlled by `auto-factory-approval-mode`: **off** serves `yolo` (no
gates), **on** serves `risk-threshold`, and variation 2 is `always`.

Set it to `always`, then re-ran on a second change. The chain stopped dead:

```
Approval policy: mode=always (source: LD flags) steps=[autofactory-flag-implementer]
▶ step 1: Research & plan      ■ done  risk_score: 0.25
▶ step 2: Release manifest     ■ done
⏸ approval gate: stopped before autofactory-flag-implementer
Skipped: flag-implementer, metrics-author, flag-testing, code-reviewer
⏸ Approval required. Nothing was created for this or later steps.
  autofactory run --graph gha-auto-factory --approve autofactory-flag-implementer
```

Verified afterwards: the app project still had exactly 1 flag and 6 metrics, and
the only file written was the step-2 manifest. The gate really does hold.

Two things this teaches that are worth saying out loud to the group: the policy
comes from LaunchDarkly (`source: LD flags`, not an env var), and a gated run is
**cheap**, halting in about 4 minutes instead of 15 because it stops before the
expensive coding nodes.

Use `always` for a guaranteed demo. `risk-threshold` (0.6 by default) would have
let both of my changes through, since they scored 0.25 and low.

The flag is back **off** (`yolo`), so the lab's baseline runs clean and flipping
it on is the demo.

## The live pipeline UI

`LD/QBR2026/factory-ui/` shows a run as it happens: the six steps, each agent's
output tags, and the flag and metrics appearing in LaunchDarkly. Built because a
scrolling terminal does not read on a projector. Zero dependencies, two files,
its own [README](factory-ui/README.md).

It needed a data source, so the CLI grew `--events <path>`: an NDJSON feed of
the run lifecycle, one JSON object per line. The UI server tails that file and
forwards lines over SSE. Committed to the fork as `a2bbe5e`.

```bash
# terminal 1
cd factory-ui && node server.mjs --events /tmp/af.ndjson     # localhost:3030

# terminal 2
cd launchdarkly-auto-factory
SANDBOX_ROOT=word-golf node packages/phase1-cli/dist/cli.js run \
  --root ../wordgolf-lab --base lab/sample-run --events /tmp/af.ndjson
```

Port 3030 keeps clear of HorizonDemo (3000/3001, v3 3020/3021), React_Demo
(3010) and PlatformLab (8080).

### Rehearse without spending a run

A real run is about 15 minutes and real tokens. Two captured fixtures replay
instead, both from real runs:

| URL | What it shows |
|---|---|
| `/?replay` | the full approved run, a step per second |
| `/?replay&instant` | same, jumped to the finished state |
| `/?replay&speed=4` | four times faster |
| `/?theme=light` | light mode, for a bright room |

`replay.ndjson` is the approved run. `replay-gate.ndjson` is the gate halt; swap
it in with `--replay replay-gate.ndjson`.

### What the runs proved

Two real runs through the UI, on the lab projects:

**Approved run** (`lab/ui-demo`, 12:30, all six nodes): flag
`show-clean-move-streak` plus four metrics, deterministic checks passing at
three separate handoffs, judges scoring 0.97 and 0.52, verdict APPROVED at
`risk_level medium`.

**Gate halt** (`lab/gate-fixture`, 4:37): stopped at step 3 marked awaiting
approval, steps 4 to 6 greyed as skipped, zero flags and zero metrics created,
and the exact `--approve` resume command on screen. This is the demo worth
showing: LaunchDarkly holding an agent pipeline, and the UI makes the halt
obvious in a way the terminal does not.

### Design notes worth keeping

- The planned chain is derived from the committed graph definition by following
  `edges` from `rootConfigKey`, not hardcoded. It is the plan, not the outcome,
  so a step the run skips shows as **skipped** rather than vanishing, and a node
  that runs but is not in the plan still gets a row.
- Created resources fill in **as the chain runs**, read from the agents' own
  routing tags (`flag_key`, `metric_keys`), not just from the final summary.
- Every state is an icon plus a word, and the word sits in an ink token rather
  than the status colour. Warning yellow is 1.79:1 on a light surface, so
  colouring the label with it would make the one state a human most needs to
  read the hardest to read.
- Animation is decoration only; `prefers-reduced-motion` turns all of it off.

## The GitHub Action path is proven

Exercise steps 8 and 9 run on PRs, not the CLI, so the Action path needed
proving separately. It works end to end.

PR [#1](https://github.com/MadelinePreston-LaunchDarkly/WordGolfAutofactory/pull/1)
on branch `lab/action-test`: one unflagged change, and the workflow completed
successfully. The agents pushed **five commits back onto the PR branch**:

```
bb4779cf Show moves remaining to par          <- mine
d82ac179 chore(auto-factory): create .release-flags/pr-1.json
13c25dd0 chore(auto-factory): update .release-flags/pr-1.json
e9490eb1 feat(auto-factory): wire show-moves-left behind feature flag
8fca3db4 chore(auto-factory): update .release-flags/pr-1.json
c4ad7553 test(auto-factory): flag-path tests for #1
```

and posted a verdict table as a PR comment: **code review APPROVED**, six agents
completed, judges 0.88 and 0.62, `risk_level=low`, flag `show-moves-left` plus
three metrics.

**It wrote to the lab, not to the group's project.** Verified after the run:
`samplerunlab-app` holds the three lab flags, and `word-golf` is still empty at
0 flags and 0 metrics. That is because the test branch pins
`LD_APP_PROJECT_KEY: samplerunlab-app` in **its own copy** of the workflow,
leaving the repo variable (`word-golf`) untouched for the group. Do not merge
that branch into `qbr-2026-workshop`.

### Repo config now set

| Name | Kind | Value |
|---|---|---|
| `LD_APP_PROJECT_KEY` | variable | `word-golf` (the group's, unchanged) |
| `ANTHROPIC_API_KEY` | secret | set |
| `LD_SDK_KEY` | secret | `samplerunlab-factory` server SDK key |
| `LD_API_KEY` | secret | the staging writer token |

`LD_SDK_KEY` currently points at the **lab** factory project, because the
group's factory project does not exist until they run the bootstrap. When they
do, overwrite this secret with their factory key. That is the one handoff step.

`CURSOR_API_KEY` is still unset and does not need to be: the provider flag is
pinned to `anthropic`.

### One trap this exposed

`dist/action.bundle.js` is committed and is what the workflow executes, with no
build step in CI. My staging SDK fix was in source only, so the CLI worked while
a CI run would still have died on `401 invalid SDK key`. Re-bundled and
committed as `4dce398`. Recorded as POSTMORTEM item 13, and worth knowing before
anyone patches this repo: **a source fix does not reach the Action until someone
runs `npm run bundle`.**

## Handing the factory to someone else

[JOIN.md](JOIN.md) is written to be passed verbatim to a second Claude Code
instance or another SE. It sets them up against the factory that already
exists rather than building a new one, which matters because the repo's own
`INSTALL-CLAUDE-CODE.md` walks you through `npm run init`, and `init` *creates*
projects.

Four commands, from `LD/QBR2026/`:

```bash
git clone https://github.com/MadelinePreston-LaunchDarkly/launchdarkly-auto-factory
cd factory-ui && ./join.sh
cd ../launchdarkly-auto-factory && npm run doctor -- --skip-github
cd ../factory-ui && node server.mjs --events live.ndjson
```

`join.sh` fetches the factory's SDK key by project rather than trusting a
pasted one, writes `.env` (backing up any existing file), builds the CLI if
`dist` is missing, and refuses to half-join: if the factory project does not
exist, or exists but was never provisioned, it says so and prints the `init`
command instead. `--check` verifies and writes nothing. Verified both ways
against the real factory (7 agents, 2 judges) and against a bogus project key.

`JOIN.md` also front-loads the three blockers already fixed in our fork, so a
joining instance does not spend its first twenty minutes rediscovering them.

### Claude Code can drive it directly

The drop-in skill and push gate are installed in the app repo:

| Path | What |
|---|---|
| `.claude/skills/autofactory/SKILL.md` | `/autofactory` runs the chain on the current change set |
| `.claude/hooks/autofactory-gate.mjs` | blocks a push or PR until AutoFactory has run on that branch |
| `.claude/settings.json` | wires the hook, **label-gated** |

Two deliberate choices there. The skill is patched to pass `--events`, which
the stock copy does not, so a run driven from Claude Code shows up in the live
UI like any other. And the gate is installed with
`AUTOFACTORY_REQUIRE_LABEL=true`, so it only fires on a PR labelled
`autofactory`: `settings.json` is committed, and full enforcement would block
groupmates' routine pushes on the shared branch. Drop that env var to gate
every push. Both behaviours were checked by invoking the hook directly.

### A round is 10 to 15 minutes, but can be much longer

Worth knowing before you plan the session around it. Three real runs:

| Run | Wall clock | Outcome |
|---|---|---|
| `lab/ui-demo` | 12:30 | approved |
| `lab/gate-fixture` | 4:37 | held at the gate |
| `lab/live-demo` | **56:40** | approved |

The 56 minutes was one node: `manifest-steward` hit two Anthropic API request
timeouts and retried with backoff, which is correct behaviour and it did
succeed. But nothing on the progress stream says "retrying", so a silent
45-minute node looks exactly like a hang.

**So do not put a live run on the critical path of a talk.** Start one early and
narrate it, or present from the captured samples, which show the identical UI
because they are real runs' feeds. POSTMORTEM item 14.

## Local layout

`LD/QBR2026/` is workshop scratch, not a demo. `tabbit-demo` is a plain clone.
`WordGolfAutofactory` is a plain clone rewired to your fork. Neither has
reinitialized history, because the workshop wants them forked and branched as a
group. Not currently referenced in the repo's `CLAUDE.md`.
