#!/bin/sh
# Back up ./data/jenkins_home (the bind-mounted state) into backups/.
#
# The container is stopped first so the snapshot is consistent. The state is a plain
# directory, so this is a normal tar — no Docker volume API involved.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOME_DIR=${JENKINS_HOME_DIR:-$ROOT/data/jenkins_home}
STAMP=$(date +%Y%m%d-%H%M%S)
NAME="jenkins-home-$STAMP.tar.gz"

if [ ! -d "$HOME_DIR" ]; then
  echo "state directory $HOME_DIR not found; run 'make up' once first" >&2
  exit 1
fi

mkdir -p "$ROOT/backups"

RUNNING=$(docker ps -q --filter "name=jenkins-base")
if [ -n "$RUNNING" ]; then
  echo "stopping jenkins-base for a consistent snapshot"
  docker stop jenkins-base >/dev/null
fi

tar czf "$ROOT/backups/$NAME" -C "$HOME_DIR" .

if [ -n "$RUNNING" ]; then
  docker start jenkins-base >/dev/null
  echo "jenkins-base restarted"
fi

ls -lh "$ROOT/backups/$NAME"
echo "backup written to backups/$NAME"
