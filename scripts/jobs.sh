#!/bin/sh
# List the jobs through the API. The admin password is read from the live CasC file
# and passed through a private netrc file, never on the command line.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PORT=${JENKINS_PORT:-8082}
LIVE="$ROOT/casc/jenkins.yaml"

[ -f "$LIVE" ] || { echo "missing $LIVE; copy casc/jenkins.yaml.example first" >&2; exit 1; }

umask 077
NETRC=$(mktemp)
trap 'rm -f "$NETRC"' EXIT

python3 -c "import yaml;print(yaml.safe_load(open('$LIVE'))['jenkins']['securityRealm']['local']['users'][0]['password'])" \
  | { printf 'machine 127.0.0.1 login admin password '; cat; } > "$NETRC"

# -g: do not let curl interpret the [name] in the tree parameter as a glob.
curl -g -sS --netrc-file "$NETRC" "http://127.0.0.1:$PORT/api/json?tree=jobs[name]" \
  | python3 -c 'import json,sys; [print(j["name"]) for j in json.load(sys.stdin)["jobs"]]'
