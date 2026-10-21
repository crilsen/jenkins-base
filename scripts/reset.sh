#!/bin/sh
# Delete the Jenkins state directory. Irreversible: build history, credentials created
# in the UI, the instance identity key and installed plugins all go with it.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOME_DIR=${JENKINS_HOME_DIR:-$ROOT/data/jenkins_home}

printf 'This DELETES %s (all Jenkins state). Type "yes" to continue: ' "$HOME_DIR"
read -r answer
[ "$answer" = "yes" ] || { echo "aborted"; exit 1; }

cd "$ROOT"
docker compose down
rm -rf "$HOME_DIR"

echo "state removed; 'make up' recreates an empty one from casc/"
