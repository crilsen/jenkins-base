#!/bin/sh
# Compare this repository against a sibling checkout of the other one and report drift.
#
# The portfolio (jenkins-base) and the dev controller (jenkins-dev) are the same
# implementation with different identities: project name, ports, ADR numbering, secrets,
# and — by design — the jobs. Improvements must land in both; the portfolio must never be
# behind. This script normalises the identity differences and diffs everything else.
#
# Usage:
#   scripts/sync-check.sh [path-to-sibling]      # default: the other checkout next door
#
# Files that are legitimately different are listed in DIFFERENCES below, with the reason.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)

if [ -d "$ROOT/../jenkins-dev" ]; then
  SIBLING=${1:-$ROOT/../jenkins-dev}
else
  SIBLING=${1:-$ROOT/../jenkins-base}
fi

[ -d "$SIBLING" ] || { echo "sibling checkout not found: $SIBLING" >&2; exit 2; }

python3 - "$ROOT" "$SIBLING" <<'PY'
import os, sys, difflib

this, other = sys.argv[1], sys.argv[2]
SKIP_DIRS = {'.git', 'data', 'backups', '.terraform'}

# Legitimately different: per-instance secrets, per-repository state, sanitisation, or the
# jobs themselves — the portfolio ships the examples only, the dev controller also carries
# the operator's real pipelines.
DIFFERENCES = {
    'casc/jenkins.yaml': 'live secrets differ per instance',
    'casc/jobs.yaml': 'the dev controller also carries the real jobs; the portfolio ships examples only',
    'casc/jenkins.yaml.example': 'the portfolio example omits the real pipeline credentials',
    '.ai/HANDOFF.md': 'session state is per repository',
    '.ai/TASKS.md': 'work state is per repository',
    '.ai/PROJECT.md': 'describes its own role (portfolio vs dev controller)',
    '.ai/LEARNINGS.md': 'the dev checkout may mention local specifics',
    '.ai/DECISIONS.md': 'the dev checkout keeps an extra ADR for the fork; the portfolio is sanitised',
    '.ai/TOOLS.md': 'the portfolio is sanitised (no other stacks on the machine)',
    'README.md': 'the portfolio carries the public scorecard, the dev checkout its own notes',
    'scripts/sync-check.sh': 'this tool names both checkouts by design',
}

def files(root):
    out = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            out.add(os.path.relpath(os.path.join(dirpath, name), root))
    return out

def normalize(text, to_portfolio):
    # to_portfolio: convert the dev checkout's text into portfolio form.
    if to_portfolio:
        text = text.replace('jenkins-dev', 'jenkins-base')
        text = text.replace('8083', '8082').replace('50003', '50001').replace('8444', '8443')
        text = text.replace('ADR-011', 'ADR-@@').replace('ADR-010', 'ADR-009').replace('ADR-@@', 'ADR-010')
    else:
        text = text.replace('jenkins-base', 'jenkins-dev')
        text = text.replace('8082', '8083').replace('50001', '50003').replace('8443', '8444')
        text = text.replace('ADR-010', 'ADR-@@').replace('ADR-009', 'ADR-010').replace('ADR-@@', 'ADR-011')
    return text

mine, theirs = files(this), files(other)
only_mine = sorted(mine - theirs)
only_theirs = sorted(theirs - mine)

# When this checkout is the portfolio, the sibling is the dev controller, so its text is
# converted dev -> portfolio.
to_portfolio = os.path.basename(this) != 'jenkins-dev'

drift = []
for rel in sorted(mine & theirs):
    if rel in DIFFERENCES:
        continue
    a = open(os.path.join(this, rel)).read()
    b = normalize(open(os.path.join(other, rel)).read(), to_portfolio)
    if a != b:
        diff = list(difflib.unified_diff(a.splitlines(), b.splitlines(), lineterm='', n=0))
        drift.append((rel, diff))

if only_mine:
    print('only here :', ' '.join(only_mine))
if only_theirs:
    print('only there:', ' '.join(only_theirs))
for rel, diff in drift:
    print(f'\ndrift: {rel}')
    for line in diff[2:12]:
        print('   ', line)

if drift or only_mine or only_theirs:
    print(f'\nsync-check: DRIFT ({len(drift)} file(s))')
    sys.exit(1)

print('sync-check: OK — no drift beyond the documented differences')
PY
