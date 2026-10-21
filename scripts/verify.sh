#!/bin/sh
# Wait for Jenkins to answer, then prove the API works and count the jobs.
# Fails loudly instead of making the caller guess.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=${JENKINS_PORT:-8082}
TRIES=${TRIES:-60}

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
echo "verify: OK"
