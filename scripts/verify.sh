#!/bin/sh
# Wait for Jenkins to answer, then prove the API works, count the jobs and check that
# the build agent is online. Fails loudly instead of making the caller guess.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=${JENKINS_PORT:-8082}
TRIES=${TRIES:-90}

i=0
until curl -fsS -o /dev/null "http://127.0.0.1:$PORT/login"; do
  i=$((i + 1))
  if [ "$i" -ge "$TRIES" ]; then
    echo "timed out after $((i * 2))s waiting for Jenkins on port $PORT" >&2
    echo "check 'make logs'" >&2
    exit 1
  fi
  sleep 2
done
echo "jenkins: up on $PORT"

jobs=$("$ROOT/scripts/jobs.sh")
count=$(printf '%s\n' "$jobs" | grep -c . || true)
echo "$jobs"
echo "jobs: $count"
[ "$count" -gt 0 ] || { echo "no jobs found: CasC probably failed, see 'make logs'" >&2; exit 1; }

echo "--- agents"
# The agent connects a few seconds after the controller is up, so wait for it instead
# of failing on a race.
tries=0
while :; do
  agents=$("$ROOT/scripts/agents.sh")
  printf '%s\n' "$agents" | grep -q '^agent-1 *online' && break
  tries=$((tries + 1))
  if [ "$tries" -ge "$TRIES" ]; then
    echo "$agents"
    echo "agent-1 is still offline after $((tries * 2))s; check 'docker compose logs agent'" >&2
    exit 1
  fi
  sleep 2
done
echo "$agents"

echo "verify: OK"
