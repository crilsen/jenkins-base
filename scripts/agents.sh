#!/bin/sh
# List the nodes and whether they are online. Reads the admin password from the live
# CasC file and passes it through a private netrc file.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=${JENKINS_PORT:-8082}
LIVE="$ROOT/casc/jenkins.yaml"

[ -f "$LIVE" ] || { echo "missing $LIVE; run 'make secrets' first" >&2; exit 1; }

umask 077
NETRC=$(mktemp)
trap 'rm -f "$NETRC"' EXIT

python3 -c "import yaml;print(yaml.safe_load(open('$LIVE'))['jenkins']['securityRealm']['local']['users'][0]['password'])" \
  | { printf 'machine 127.0.0.1 login admin password '; cat; } > "$NETRC"

# -g: the [name] in the tree parameter must not be treated as a glob.
curl -g -sS --netrc-file "$NETRC" \
  "http://127.0.0.1:$PORT/computer/api/json?tree=computer[displayName,offline,numExecutors,assignedLabels[name]]" \
  | python3 -c '
import json, sys

for node in json.load(sys.stdin)["computer"]:
    name = node["displayName"] or "(built-in)"
    labels = ",".join(label["name"] for label in node.get("assignedLabels", []))
    state = "OFFLINE" if node["offline"] else "online"
    print("%-20s %-8s executors=%s labels=%s" % (name, state, node["numExecutors"], labels))
'
