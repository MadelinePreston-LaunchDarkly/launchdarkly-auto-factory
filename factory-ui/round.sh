#!/usr/bin/env bash
# Run one factory round against the lab, feeding the live UI.
#
# A "round" is one pass of the six-agent chain over one change. Repeating a
# round means a fresh branch with a fresh change, because the chain diffs the
# branch against a base: re-running on an unchanged branch just reprocesses the
# same diff and the agents will say there is nothing new to flag.
#
#   ./round.sh                      run the lab worktree's current branch
#   ./round.sh --fresh streak-v2    branch from the base first, then stop so you
#                                   can make and commit a change
#   ./round.sh --base <ref>         diff against something other than the default
#   ./round.sh --gate               hold at the approval gate this round
#   ./round.sh --no-gate            run straight through (the default state)
#
# The UI picks it up automatically: it tails the same feed file.
set -euo pipefail

# factory-ui lives INSIDE the tooling repo, so the tool root is our parent.
TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$TOOL/factory-ui"
# The app repo is a separate checkout. AF_APP_ROOT wins; otherwise take the
# first sibling of the tool repo that looks like the Word Golf app.
LAB="${AF_APP_ROOT:-}"
if [ -z "$LAB" ]; then
  for c in "$TOOL/../wordgolf-lab" "$TOOL/../WordGolfAutofactory"; do
    [ -d "$c/.git" ] && LAB="$(cd "$c" && pwd)" && break
  done
fi
# One feed file per branch. Several cohorts share one factory, and the UI treats
# a shrinking feed as a new round, so two people writing one file would reset
# each other's view. Derived from the branch name, overridable with AF_FEED.
FEEDDIR="$UI/feeds"
BASE="lab/sample-run"
FRESH=""
GATE=""

while [ $# -gt 0 ]; do
  case "$1" in
    --fresh) FRESH="${2:-}"; [ -n "$FRESH" ] || { echo "--fresh needs a name"; exit 2; }; shift 2 ;;
    --base)  BASE="${2:-}";  [ -n "$BASE" ]  || { echo "--base needs a ref";  exit 2; }; shift 2 ;;
    --gate)    GATE="always"; shift ;;
    --no-gate) GATE="off";    shift ;;
    -h|--help) sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

[ -n "$LAB" ] && [ -d "$LAB" ] || {
  echo "app repo not found. Set AF_APP_ROOT to your Word Golf checkout, e.g.:"
  echo "  AF_APP_ROOT=/path/to/WordGolfAutofactory ./round.sh"
  exit 1
}

# The approval gate is a LaunchDarkly flag, so flipping it is a REST call, not a
# code change. Needs the staging writer token from the workspace .env.
if [ -n "$GATE" ]; then
  # The gate is a LaunchDarkly flag, so flipping it needs a write token. Prefer
  # the tool repo's own .env (what join.sh writes); fall back to the env.
  TOKEN="${LD_API_KEY:-}"
  if [ -z "$TOKEN" ] && [ -f "$TOOL/.env" ]; then
    # shellcheck disable=SC1091
    set -a; . "$TOOL/.env"; set +a
    TOKEN="${LD_API_KEY:-}"
  fi
  [ -n "$TOKEN" ] || { echo "no LD API token: set LD_API_KEY or run factory-ui/join.sh first"; exit 1; }
  FACTORY_PROJECT="${LD_PROJECT_KEY:-word-golf-factory}"
  API="${LD_BASE_URL:-https://ld-stg.launchdarkly.com}/api/v2/flags/$FACTORY_PROJECT/auto-factory-approval-mode"
  if [ "$GATE" = "always" ]; then
    VID=$(curl -fsS -H "Authorization: $TOKEN" "$API" |
      python3 -c "import json,sys; print([v['_id'] for v in json.load(sys.stdin)['variations'] if v.get('value')=='always'][0])")
    curl -fsS -o /dev/null -X PATCH -H "Authorization: $TOKEN" \
      -H "Content-Type: application/json; domain-model=launchdarkly.semanticpatch" \
      -d "{\"environmentKey\":\"production\",\"instructions\":[{\"kind\":\"turnFlagOn\"},{\"kind\":\"updateFallthroughVariationOrRollout\",\"variationId\":\"$VID\"}]}" "$API"
    echo "approval gate: ON (serving 'always')"
  else
    curl -fsS -o /dev/null -X PATCH -H "Authorization: $TOKEN" \
      -H "Content-Type: application/json; domain-model=launchdarkly.semanticpatch" \
      -d '{"environmentKey":"production","instructions":[{"kind":"turnFlagOff"}]}' "$API"
    echo "approval gate: OFF (serving 'yolo')"
  fi
fi

if [ -n "$FRESH" ]; then
  # --porcelain, not `git diff`: the factory leaves UNTRACKED files (the release
  # manifest), and those are invisible to git diff but still ride along across a
  # checkout, which is how a previous round's output ended up inside a later
  # round's diff.
  if [ -n "$(git -C "$LAB" status --porcelain)" ]; then
    echo "the lab worktree is not clean; commit or discard first:"
    git -C "$LAB" status --short | sed 's/^/  /'
    exit 1
  fi
  git -C "$LAB" checkout -q "$BASE"
  git -C "$LAB" checkout -q -b "lab/$FRESH"
  echo "on branch lab/$FRESH, based on $BASE"
  echo "make a change in $LAB (no flags; the pipeline adds those), commit it, then: ./round.sh"
  exit 0
fi

BRANCH=$(git -C "$LAB" rev-parse --abbrev-ref HEAD)
# lab/my-change -> feeds/lab-my-change.ndjson
mkdir -p "$FEEDDIR"
FEED="${AF_FEED:-$FEEDDIR/$(printf '%s' "$BRANCH" | tr '/' '-').ndjson}"
AHEAD=$(git -C "$LAB" rev-list --count "$BASE..$BRANCH" 2>/dev/null || echo 0)
if [ "$BRANCH" = "$BASE" ] || [ "$AHEAD" = "0" ]; then
  echo "branch '$BRANCH' has no commits beyond '$BASE': the chain would have nothing to process."
  echo "start a round with: ./round.sh --fresh <name>"
  exit 2
fi

# Truncating the feed is what tells the UI a new round started; it resets rather
# than splicing this round onto the last one.
: > "$FEED"
echo "round: $BRANCH vs $BASE  ($AHEAD commit(s))"
echo "feed:  $FEED"
echo "UI:    http://localhost:3030   (node factory-ui/server.mjs, no args, follows the newest feed)"
echo

cd "$TOOL"
SANDBOX_ROOT=word-golf node packages/phase1-cli/dist/cli.js run \
  --root "$LAB" --base "$BASE" --events "$FEED" "$@"
