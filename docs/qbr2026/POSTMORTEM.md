# QBR 2026 SE Workshop: post-mortem notes

Things to raise with the workshop owners. Running list, added to as they get hit.

Owners: **Eric** (`EricDarkly/tabbit-demo`), **Alex Lawrence**
(`alawrenceld/WordGolfAutofactory`, `launchdarkly-auto-factory`),
**Tom Totenberg** (the Confluence page), **Kevin Cochran** (AC Enablement lead).

Source page: [SE Workshop - QBRS 2026](https://launchdarkly.atlassian.net/wiki/spaces/~779364305/pages/5190451215/SE+Workshop+-+QBRS+2026)

Severity key: **blocker** stops you following the instructions, **friction** costs
time but has an obvious workaround, **doc** means the instructions and the code
disagree.

---

## 1. `terraform apply` cannot create the judge (blocker)

**Repo:** `EricDarkly/tabbit-demo` · **Session:** AC Enablement Refresh
**Found:** 2026-09-22, during prep

The README's setup step fails partway through:

```
docker compose run --rm terraform apply

Error: failed to create AgentControl config with key "claim-accuracy-judge"
  on main.tf line 176, in resource "launchdarkly_ai_config" "claim_accuracy_judge"

400 Bad Request: {"code":"invalid_request","message":"isInverted is required
for a custom judge: offline evaluations derive pass/fail from it, and a judge
with no success direction cannot be scored"}
```

The staging API tightened custom-judge creation after this Terraform was written.
This will hit **every SE** who follows the README, and it fails *mid-apply*: 8 of
11 resources get created first, so people land in a partial state and may not
realize the judge and `claim-parser/default` are both missing. The judge is the
"LLM as a judge metrics" agenda item, so the session's headline topic is the part
that breaks.

**Fix.** Provider v3.1.2 already exposes the argument, so it is one line in
`terraform/main.tf`:

```hcl
resource "launchdarkly_ai_config" "claim_accuracy_judge" {
  ...
  is_inverted = false   # false means a higher score is better, matching the 0.0..1.0 rubric
}
```

Verified: re-applying after this created the remaining 3 resources cleanly,
`3 added, 0 changed, 0 destroyed`.

**Ask:** commit this upstream before the session, so nobody has to debug a 400
live.

---

## 2. `direct_api.py` looks for an image that is not in the repo (friction)

**Repo:** `EricDarkly/tabbit-demo` · **Session:** AC Enablement Refresh

The README says:

```
docker compose run --rm app python src/direct_api.py
```

`src/direct_api.py:243` defaults `IMAGE_PATH` to `receipt.jpg`. The repo ships
only `test.jpg`, and `turnkey_sdk.py:153` hardcodes `test.jpg`. So the documented
command fails on a missing file while the other script works, which reads like a
broken environment rather than a bad default.

**Fix:** change the default to `test.jpg`, or add `IMAGE_PATH=test.jpg` to
`.env.example`.

---

## 3. README describes a `tabbit` agent graph that does not exist yet (doc)

**Repo:** `EricDarkly/tabbit-demo` · **Session:** AC Enablement Refresh

The README says Terraform "Creates math tools, AI configs, the judge, and the
`tabbit` agent graph." There is no graph resource anywhere in
`terraform/main.tf`, and the graph call in `turnkey_sdk.py:143-167` is commented
out:

```python
# async def invoke_graph(image_path: str, claim: str) -> None:
#     return await graph(
#         "tabbit",
```

Not a blocker, but an SE who reads the README and then goes looking for the graph
in the UI will conclude their apply failed.

**Ask:** either land the graph resource or soften the README line.

---

## 4. Word Golf's workflow hardcodes someone else's AutoFactory fork (friction)

**Repo:** `alawrenceld/WordGolfAutofactory` · **Session:** Factory Hands-on

Exercise step 6 says to make sure your branch's workflow points at *your* fork of
the AutoFactory, and links `auto-factory.yml` as the example. That file hardcodes:

```yaml
- name: Check out the AutoFactory tool
  uses: actions/checkout@v4
  with:
    repository: alawrenceld/launchdarkly-auto-factory
```

Note it points at `alawrenceld/launchdarkly-auto-factory`, while the page tells
groups to fork `launchdarkly-labs/launchdarkly-auto-factory`. Two different
upstreams for the same tool is confusing when you are trying to work out which
line to change.

**Ask:** make the tool repo a workflow input, or an `env` var at the top with a
comment saying "change this to your fork", and reconcile which upstream is
canonical.

---

## 5. The page says clone Word Golf, but step 4 requires push access (friction)

**Repo:** `alawrenceld/WordGolfAutofactory` · **Session:** Factory Hands-on

Step 3 says "have each SE **clone** the Word Golf repo." Step 4 says "someone
create a working branch for their group to share. **Publish it**, so everyone in
that group can work on the same branch."

SEs have READ on `alawrenceld/WordGolfAutofactory`, so publishing a branch there
is impossible. A group has to fork Word Golf too, not just clone it. The page
only mentions forking the AutoFactory. Groups will discover this when their first
`git push` is rejected.

**Ask:** add "fork Word Golf" to step 3, or grant write access, or say explicitly
that the shared branch lives on a group member's fork.

---

## 6. Which LaunchDarkly instance does the Factory session use? (doc)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on

The prep list puts "try logging into Staging" under **AC Enablement**, and the
Factory instructions never name an instance. Meanwhile
`packages/shared/src/env.ts:72` defaults `LD_BASE_URL` to
`https://app.launchdarkly.com`, so an SE who follows the steps without thinking
about it will have the factory create real flags and metrics in **production**.
`tabbit-demo`'s Terraform, by contrast, hardcodes
`api_host = "https://ld-stg.launchdarkly.com/"`, so the two halves of the day
default to different instances.

**Ask:** state the intended instance in step 5, and if it is staging, say that
`LD_BASE_URL` has to be set explicitly in the workflow because the default is
production.

---

## 7. The workflow needs a Cursor key most SEs will not have (friction)

**Repo:** `alawrenceld/WordGolfAutofactory` · **Session:** Factory Hands-on

`auto-factory.yml` passes `CURSOR_API_KEY`, and per ADR 0018 the bootstrap
default is a 50/50 anthropic/cursor split per run. An SE with only an Anthropic
key (which is all the prep list provides, via the team key sheet) would expect
roughly half their runs to fail on a missing Cursor credential.

**Verified 2026-09-23, and it is milder than it first looked.** Running
`init --provider anthropic` pins `auto-factory-ai-provider` to serve
`anthropic` at 100% (targeting on, fallthrough variation 0), and runs then
report `[provider: anthropic]` with no Cursor involvement. So this bites only
someone who accepts the interactive default.

**Ask:** make the instructions say to pass `--provider anthropic`, or have the
bootstrap detect a missing `CURSOR_API_KEY` and pin the flag automatically.

---

## 8. Step 5 overlaps with what the bootstrap already does (doc)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on

Step 5 says "create a temporary LaunchDarkly project for your Word Golf instance."
Step 2.1 says to run the bootstrap, and per the AutoFactory README `npm run init`
"creates (or confirms) the **factory** project ... and the **app** project."
So the app project in step 5 is the same thing `init` makes, and the ordering
implies otherwise. It is idempotent, so no harm results, but a group will not know
whether to make the project by hand or let the tool do it.

**Ask:** say explicitly that step 5 is the app project and that `init` will create
it if you let it, or drop step 5.

---

## 9. The same judge bug kills the AutoFactory bootstrap, and it cascades (blocker, most important item here)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on
**Found:** 2026-09-23, first `npm run init` against staging

This is item 1's root cause in a second repo, and here the blast radius is the
whole session. A clean `init` produces:

```
✓ provisioned: 5 config(s), 0 graph(s), 5 flag(s), 20 tool(s), 2 app metric(s)
✗ ai-config autofactory-judge-implementation-quality [400]: isInverted is required for a custom judge
✗ ai-config autofactory-judge-metrics-quality        [400]: isInverted is required for a custom judge
✗ ai-config autofactory-flag-implementer             [400]: judge configs not found for the following keys: autofactory-judge-implementation-quality
✗ ai-config autofactory-metrics-author               [400]: judge configs not found for the following keys: autofactory-judge-metrics-quality
✗ graph gha-auto-factory                             [404]: AI config not found
5 provisioning failure(s)
```

Two judges fail, which fails the two agents that attach them, which fails the
**agent graph**. No graph means the six-agent chain cannot resolve, so Phase 1
does nothing at all. Worse for a room full of people debugging: the symptom that
gets noticed is a **404 on the graph**, which points nowhere near the actual
cause.

**Root cause.** `packages/config-bridge/src/provision.ts` builds the AI config
create body from an explicit field whitelist. It carries `evaluationMetricKey`
for judge mode but not `isInverted`, which the API now also requires.

**Fix** (verified, one place, covers all judges without touching any of the nine
JSON definitions). In `AiConfigFile` add:

```ts
isInverted?: boolean;
```

and in the create body next to the `evaluationMetricKey` spread:

```ts
...(cfg.mode === "judge" ? { isInverted: cfg.isInverted ?? false } : {}),
```

Defaulting to `false` (higher score is better) is correct for all of them: every
judge here scores 0.0 to 1.0 with 1.0 as best. After the fix, re-running `init`
resumed and completed: `4 config(s), 1 graph(s) created (32 already existed)`,
zero failures, and `npm run doctor` reports `✓ No problems.`

**Ask:** land this before the session. It is the difference between the exercise
working and not working.

---

## 10. The README's quick start cannot work as written (blocker)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on

README says:

```bash
npm install
npm run init
```

`init` then dies immediately:

```
Error [ERR_MODULE_NOT_FOUND]: Cannot find module
'.../node_modules/@auto-factory/shared/dist/index.js'
imported from .../packages/config-bridge/src/cli.ts
```

No workspace package has a `prepare`, `postinstall` or `prepublishOnly` script
(checked all of `packages/*/package.json`), so nothing builds the workspace on
install. **`npm run build` is a required third step the quick start omits.**
Every SE will hit this as their first command of the session.

**Ask:** add `npm run build` to the quick start, or add a root `prepare` script.

---

## 11. `npx autofactory` does not resolve (friction)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on

`packages/phase1-cli/README.md` offers:

```bash
npx autofactory run --root <app-repo>
```

From the repo root that goes to the public registry and fails:

```
npm error 404 Not Found - GET https://registry.npmjs.org/autofactory
```

The bin is not linked into the workspace root's `node_modules/.bin`. The
documented alternative on the next line does work:

```bash
node packages/phase1-cli/dist/cli.js run --root <app-repo>
```

**Ask:** either link the bin in the root `package.json`, add an `npm run
autofactory` script, or drop the `npx` form so people do not start with the
failing one.

---

## 12. `--base-url` does not redirect the SDK, so staging runs die 401 (blocker)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on
**Found:** 2026-09-23, first chain run against staging

`init --base-url https://ld-stg.launchdarkly.com` succeeds completely: token
validated, projects created, configs and graph provisioned, `doctor` reports
`✓ No problems.` Then the first actual run dies:

```
error: [LaunchDarkly] Authentication failed. Double check your SDK key.
error: [LaunchDarkly] Received error 401 (invalid SDK key) for streaming request - giving up permanently
```

The SDK key is correct. `LD_BASE_URL` only redirects the **REST API**. The
server SDK talks to LaunchDarkly's *SDK* endpoints, which are different hosts,
and `packages/shared/src/ldSdk.ts` calls `init(sdkKey, { plugins })` with no URI
overrides, so those always resolve to production. A staging key against
production endpoints is an invalid key.

Confirmed with the same staging SDK key:

| Endpoint | Result |
|---|---|
| `stream-stg.launchdarkly.com/all` | **200** |
| `sdk-stg.launchdarkly.com/sdk/latest-all` | **200** |
| `stream.launchdarkly.com/all` (the default) | **401** |

This is nastier than it looks because every setup step passes. `doctor` is
REST-only, so it gives a clean bill of health on an install that cannot run.

**Fix** (verified). In `ldSdk.ts`, derive the three SDK URIs when `LD_BASE_URL`
points at staging, and pass them to `init`. Note this SDK version takes the
older flat option names, not `serviceEndpoints`:

```ts
function resolveSdkEndpoints(): Pick<LDOptions, "streamUri" | "baseUri" | "eventsUri"> | undefined {
  const staging = (process.env.LD_BASE_URL ?? "").includes("ld-stg.launchdarkly.com");
  const streamUri = process.env.LD_STREAM_URI ?? (staging ? "https://stream-stg.launchdarkly.com" : undefined);
  const baseUri = process.env.LD_SDK_BASE_URI ?? (staging ? "https://sdk-stg.launchdarkly.com" : undefined);
  const eventsUri = process.env.LD_EVENTS_URI ?? (staging ? "https://events-stg.launchdarkly.com" : undefined);
  if (!streamUri || !baseUri || !eventsUri) return undefined;
  return { streamUri, baseUri, eventsUri };
}
```

then `init(sdkKey, { plugins: await observabilityPlugins(), ...(endpoints ?? {}) })`.

**Ask:** land this, and consider having `doctor` open an actual SDK connection
so a broken-but-green install is not possible. Related to item 6: if the Factory
session is meant to run on staging at all, this is required.

---

## 13. A source fix does not reach the Action until someone re-bundles (blocker-adjacent)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on
**Found:** 2026-09-24, setting up the Action path

`dist/action.bundle.js` is **committed**, and the workflow executes that file
directly:

```yaml
run: node "$GITHUB_WORKSPACE/tool/packages/phase1-resource-factory/dist/action.bundle.js"
```

There is no build step in the workflow, so the bundle is whatever was last
committed. A fix to `packages/shared/src/` therefore works in the CLI (which runs
from source via tsx) and silently does nothing in CI until someone runs
`npm run bundle` and commits the result.

This bit us concretely: the staging SDK endpoint fix (item 12) landed in source,
`doctor` was green, the CLI ran fine, and a CI run would still have died on
`401 invalid SDK key`. Fixed by re-bundling and committing.

**Ask:** either build the bundle in the workflow instead of committing it, or add
a CI check that fails when the committed bundle differs from a fresh build of
the source. A committed artifact that can silently disagree with its source is a
trap for anyone who patches this repo, which at a workshop is everyone.

---

## 14. A round's wall-clock is not predictable: plan the demo around it (friction)

**Repo:** `launchdarkly-labs/launchdarkly-auto-factory` · **Session:** Factory Hands-on
**Found:** 2026-09-24, third live run

Two runs of the same six-node chain over comparably small frontend changes:

| Run | Wall clock |
|---|---|
| `lab/ui-demo` | **12:30** |
| `lab/live-demo` | **56:40** |

The difference is one node. Per-event timing from the feed shows every node
taking 40 to 165 seconds except `autofactory-manifest-steward`, which took
**2761 seconds**. The log says why:

```
[node] autofactory-manifest-steward transient API error (Request timed out.) - retry 1/3 in 5s
[node] autofactory-manifest-steward transient API error (Request timed out.) - retry 2/3 in 15s
```

Two Anthropic API timeouts, retried with backoff, then success. The retry
handling is correct and the run completed APPROVED. The problem is only that
nothing on the surface says "this node is retrying": the console sits silent and
a watcher cannot tell a slow agent from a hung one.

**Why it matters for the session.** The build block is 90 minutes and the
instructions have each SE open a PR. One unlucky timeout eats half the block,
and an SE watching a silent terminal will reasonably conclude it has hung and
kill it.

**Asks:**
1. Surface retries on the progress stream, not just in a log line, so a front
   end can show "retrying 1/3" instead of nothing.
2. Say in the instructions that a round is usually 10 to 15 minutes but can
   exceed 45 if a model call times out, so nobody kills a healthy run.
3. Consider a shorter per-request timeout with more retries, so a stall costs
   minutes rather than tens of minutes.

---

## 15. Our own tooling: three guards added after two near-misses (internal)

**Repo:** this one, `factory-ui/round.sh` · **Found:** 2026-09-24

Not a finding about the AutoFactory. Recorded because two of these are easy to
repeat in any wrapper around the CLI, and one of them nearly wrote agent edits
into the branch a whole group shares.

**A git worktree's `.git` is a file, not a directory.** The app-repo autodetect
used `[ -d "$c/.git" ]`, which silently skipped the lab worktree and fell
through to the next candidate: the group's shared checkout. A run started
against `qbr-2026-workshop` before it was killed. The test has to be
`git -C "$c" rev-parse --git-dir`, which is true for both a clone and a
worktree.

**A bare flag flip should not start work.** `./round.sh --no-gate` reads as
"turn the gate off", but it flipped the flag and then ran a whole round. Flipping
with no other action flag now flips and stops; `--gate --run` makes
flip-then-run explicit.

**Refuse to run the chain on a shared branch.** The chain writes edits into the
working tree, so doing that on `qbr-2026-workshop`, `main` or `master` is never
intended. It now exits 2 with the `--fresh` command instead.

Worth generalising: any front end that edits a working tree should know which
branch it is on and refuse the shared ones, because the failure is silent until
someone else pulls.

---

## Template for new entries

```
## N. One-line symptom (blocker | friction | doc)

**Repo:** · **Session:**

What happened, with the exact command and error.
Why it matters for the room.

**Fix / Ask:**
```
