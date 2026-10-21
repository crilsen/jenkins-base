#!/bin/sh
# Build the demo repository from the mounted project files and serve it over plain
# HTTP (the dumb git protocol), so the controller and the agent can both use it as a
# real remote.
#
# Two reasons it works this way instead of baking the repository into an image:
#   * editing Jenkinsfile / examples/* takes effect on the next `docker compose up`,
#     with no image rebuild;
#   * the controller can read the Jenkinsfile (lightweight checkout, multibranch
#     indexing) without carrying the toolchain or relaxing ALLOW_LOCAL_CHECKOUT.
#
# Only the files listed in the compose mounts are visible: casc/jenkins.yaml (the admin
# password and real ARNs) is deliberately absent.
set -eu

SEED=${SEED_DIR:-/seed}
SERVE=${SERVE_DIR:-/srv}
REPO="$SERVE/repo.git"
SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT

cp -a "$SEED"/. "$SRC"/

git -C "$SRC" init -q
git -C "$SRC" add -A
git -C "$SRC" -c user.name=jenkins -c user.email=jenkins@localhost \
  commit -qm "demo: initial branch"
git -C "$SRC" branch -M main

# A second branch so the multibranch example has something to discover.
git -C "$SRC" checkout -q -b feature/demo
git -C "$SRC" -c user.name=jenkins -c user.email=jenkins@localhost \
  commit -q --allow-empty -m "demo: second branch"
git -C "$SRC" checkout -q main

rm -rf "$REPO"
git clone -q --bare "$SRC" "$REPO"
# Required for the dumb HTTP protocol.
git --git-dir="$REPO" update-server-info

echo "serving $REPO on :8080 (branches: $(git --git-dir="$REPO" branch --format='%(refname:short)' | tr '\n' ' '))"
exec python3 -m http.server 8080 --bind 0.0.0.0 --directory "$SERVE"
