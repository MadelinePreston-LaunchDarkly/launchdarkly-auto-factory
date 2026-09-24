#!/usr/bin/env bash
# Join an EXISTING AutoFactory, rather than bootstrapping a new one.
#
# `npm run init` in the tooling repo CREATES projects. That is the wrong verb
# when a factory already exists: a second person running init against the same
# project keys does no harm (it is idempotent) but it also does not tell you
# whether you are actually pointed at the right factory. This writes the .env
# for an existing factory and then proves the connection.
#
#   ./join.sh                                   join the lab factory
#   ./join.sh --factory <key> --app <key>       join some other factory
#   ./join.sh --check                           verify only, write nothing
#
# You need: the tooling repo checked out, Node 20+, an LD API token with write
# access to the factory, and an Anthropic API key.
set -euo pipefail

# factory-ui lives INSIDE the tooling repo, so the tool root is our parent.
TOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UI="$TOOL/factory-ui"
FACTORY="word-golf-factory"
APP="word-golf"
BASE_URL="https://ld-stg.launchdarkly.com"
CHECK_ONLY=""

while [ $# -gt 0 ]; do
  case "$1" in
    --factory)  FACTORY="${2:?--factory needs a project key}"; shift 2 ;;
    --app)      APP="${2:?--app needs a project key}"; shift 2 ;;
    --base-url) BASE_URL="${2:?--base-url needs a URL}"; shift 2 ;;
    --check)    CHECK_ONLY=1; shift ;;
    -h|--help)  sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1"; exit 2 ;;
  esac
done

[ -f "$TOOL/package.json" ] || { echo "not inside the tooling repo (looked for $TOOL/package.json)"; exit 1; }

# Credentials: env first, then the workspace .env, so this works for someone
# who has their own token and for someone using the shared workshop one.
API_KEY="${LD_API_KEY:-}"
ANTHROPIC="${ANTHROPIC_API_KEY:-}"
# Fall back to an existing .env in the tool repo, so re-running join.sh after a
# first successful join needs no credentials re-supplied.
if [ -z "$API_KEY" ] && [ -f "$TOOL/.env" ]; then
  # shellcheck disable=SC1091
  set -a; . "$TOOL/.env"; set +a
  API_KEY="${LD_API_KEY:-}"
  ANTHROPIC="${ANTHROPIC_API_KEY:-$ANTHROPIC}"
fi
[ -n "$API_KEY" ] || {
  echo "no LaunchDarkly API token."
  echo "Set one and re-run:  LD_API_KEY=api-... ANTHROPIC_API_KEY=sk-ant-... ./join.sh"
  exit 1
}
[ -n "$ANTHROPIC" ] || { echo "no Anthropic key. Set ANTHROPIC_API_KEY and re-run."; exit 1; }

api() { curl -fsS -H "Authorization: $API_KEY" "$BASE_URL/api/v2/$1"; }

echo "Joining factory '$FACTORY' (app '$APP') on $BASE_URL"
echo

# 1. The token has to actually reach this instance.
api caller-identity >/dev/null || { echo "FAIL: token rejected by $BASE_URL"; exit 1; }
echo "  ok   token authenticates"

# 2. The factory must already exist. If it does not, the answer is `npm run
#    init`, not this script, so say that rather than half-joining.
if ! api "projects/$FACTORY" >/dev/null 2>&1; then
  echo "  FAIL factory project '$FACTORY' does not exist on this instance."
  echo "       Nothing to join. Create one instead:"
  echo "         cd $TOOL && npm run init -- --factory-project $FACTORY --app-project $APP --base-url $BASE_URL"
  exit 1
fi
echo "  ok   factory project '$FACTORY' exists"
api "projects/$APP" >/dev/null 2>&1 && echo "  ok   app project '$APP' exists" \
  || { echo "  FAIL app project '$APP' does not exist"; exit 1; }

# 3. A factory with no graph cannot run the chain; that is the failure mode the
#    judge bug produced, and it is worth catching here rather than mid-run.
GRAPHS=$(api "projects/$FACTORY/ai-configs?limit=100" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(sum(1 for c in d.get('items',[]) if c.get('mode')=='agent'), sum(1 for c in d.get('items',[]) if c.get('mode')=='judge'))" 2>/dev/null || echo "0 0")
echo "  ok   agent configs / judges: $GRAPHS"
if [ "${GRAPHS%% *}" = "0" ]; then
  echo "  FAIL no agent configs in '$FACTORY' it was never provisioned."
  echo "       cd $TOOL && npm run init -- --factory-project $FACTORY --app-project $APP --base-url $BASE_URL"
  exit 1
fi

# 4. The SDK key must be the FACTORY's, not the app's: the SDK reads agent
#    configs and the graph, which live in the factory project.
SDK_KEY=$(api "projects/$FACTORY/environments/production" | python3 -c "import json,sys; print(json.load(sys.stdin)['apiKey'])")
[ -n "$SDK_KEY" ] || { echo "  FAIL could not fetch the factory SDK key"; exit 1; }
echo "  ok   fetched factory SDK key (production)"

if [ -n "$CHECK_ONLY" ]; then
  echo
  echo "--check: verified, wrote nothing."
  exit 0
fi

# Preserve anything already in .env that we are not responsible for.
ENVF="$TOOL/.env"
if [ -f "$ENVF" ]; then
  cp "$ENVF" "$ENVF.bak"
  echo "  ok   backed up existing .env to .env.bak"
  # That backup holds live credentials. A .gitignore covering only `.env` does
  # not match `.env.bak`, and this repo is public, so refuse to leave a
  # committable copy of someone's keys lying around.
  if git -C "$TOOL" check-ignore -q .env.bak 2>/dev/null; then
    echo "  ok   .env.bak is gitignored"
  else
    echo "  WARN .env.bak is NOT gitignored and contains live credentials."
    echo "       Add '.env.*' to .gitignore, or delete it: rm $ENVF.bak"
  fi
fi
cat > "$ENVF" <<ENVEOF
# Written by factory-ui/join.sh: joined an EXISTING factory, not bootstrapped.
# factory project holds the agent configs, graph and operational flags.
# app project is where the agents create flags and metrics.
LD_SDK_KEY=$SDK_KEY
LD_API_KEY=$API_KEY
LD_PROJECT_KEY=$FACTORY
LD_APP_PROJECT_KEY=$APP
LD_BASE_URL=$BASE_URL
ANTHROPIC_API_KEY=$ANTHROPIC
ENVEOF
echo "  ok   wrote $ENVF"

# Build, because the committed tree ships no dist and the quick start omits it.
if [ ! -f "$TOOL/packages/phase1-cli/dist/cli.js" ]; then
  echo
  echo "building the tooling repo (the quick start omits this step)..."
  (cd "$TOOL" && npm install --silent && npm run build) || { echo "build failed"; exit 1; }
fi
echo "  ok   CLI built"

echo
echo "Joined. Verify and run:"
echo "  cd $TOOL && npm run doctor -- --skip-github"
echo "  cd $UI && node server.mjs                       # then open :3030"
echo "  cd $UI && ./round.sh --fresh my-change"
