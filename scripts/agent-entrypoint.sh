#!/bin/sh
# Connect this agent to the controller.
#
# The controller generates a per-node secret and publishes it to a shared
# directory (init/02-publish-agent-secret.groovy), because CasC owns the node and
# init scripts run before CasC applies. So: wait for the file, read it, connect.
# The whole thing loops, so the agent also recovers when the controller restarts
# and rewrites the secret.
set -eu

NAME=${AGENT_NAME:-agent-1}
URL=${JENKINS_URL:-http://jenkins:8080}
SECRET_FILE=${AGENT_SECRET_FILE:-/opt/agent-secret/$NAME.secret}
WORKDIR=${AGENT_WORKDIR:-/home/jenkins/agent}
TRIES=${AGENT_SECRET_TRIES:-150}

export JENKINS_URL="$URL"
export JENKINS_NAME="$NAME"
export JENKINS_WEB_SOCKET=true
export JENKINS_AGENT_WORKDIR="$WORKDIR"

while true; do
  i=0
  while [ ! -s "$SECRET_FILE" ]; do
    i=$((i + 1))
    if [ "$i" -ge "$TRIES" ]; then
      echo "timed out after $((i * 2))s waiting for $SECRET_FILE" >&2
      echo "is the controller up and the node '$NAME' declared in casc/jenkins.yaml?" >&2
      exit 1
    fi
    sleep 2
  done

  # Exported, never an argument: the secret must not show up in `ps`. The wrapper
  # script reads every option from the environment, so no CLI flags are passed.
  JENKINS_SECRET=$(cat "$SECRET_FILE")
  export JENKINS_SECRET

  echo "connecting to $URL as $NAME"
  /usr/local/bin/jenkins-agent || true

  echo "connection ended; retrying in 5s (the secret may have been rotated)"
  sleep 5
done
