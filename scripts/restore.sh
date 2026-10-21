#!/bin/sh
# Restore a backup made by scripts/backup.sh into the state directory.
#
# DESTRUCTIVE: the current state directory is emptied first. Requires the literal
# word "yes" to proceed.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
HOME_DIR=${JENKINS_HOME_DIR:-$ROOT/data/jenkins_home}
FILE=${1:-}

if [ -z "$FILE" ] || [ ! -f "$FILE" ]; then
  echo "usage: $0 backups/jenkins-home-YYYYmmdd-HHMMSS.tar.gz" >&2
  echo "available:" >&2
  ls -1 "$ROOT/backups" 2>/dev/null >&2 || true
  exit 2
fi

ARCHIVE=$(cd "$(dirname "$FILE")" && pwd)/$(basename "$FILE")

printf 'This REPLACES all current state in %s with %s\nType "yes" to continue: ' \
  "$HOME_DIR" "$(basename "$FILE")"
read -r answer
[ "$answer" = "yes" ] || { echo "aborted"; exit 1; }

cd "$ROOT"
docker compose down >/dev/null 2>&1 || true

mkdir -p "$HOME_DIR"
find "$HOME_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
tar xzf "$ARCHIVE" -C "$HOME_DIR"

echo "restored; start it with 'make start'"
