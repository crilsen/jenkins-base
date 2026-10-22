#!/bin/sh
# Compare this repository against a sibling checkout of the other one and report drift.
#
# The portfolio (jenkins-base) and the lab (cn-jenkins) are the same implementation with
# different identities: project name, ports, ADR numbering and secrets. Improvements must
# land in both, and the portfolio must never be behind. This script normalises those
# differences and diffs everything else.
#
# Usage:
#   scripts/sync-check.sh [path-to-sibling]      # default: ../cn-jenkins
#
# Files that are legitimately different are listed in DIFFERENCES below, with the reason.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SIBLING=${1:-$ROOT/../cn-jenkins}

[ -d "$SIBLING" ] || { echo "sibling checkout not found: $SIBLING" >&2; exit 2; }

python3 - "$ROOT" "$SIBLING" <<'PY'
import os, sys, difflib

this, other = sys.argv[1], sys.argv[2]
SKIP_DIRS = {'.git', 'data', 'backups', '.terraform'}

# Legitimately different: per-instance secrets, per-repository state, or sanitisation.
DIFFERENCES = {
    'casc/jenkins.yaml': 'live secrets differ per instance',
    '.ai/HANDOFF.md': 'session state is per repository',
    '.ai/TASKS.md': 'work state is per repository',
    '.ai/PROJECT.md': 'describes its own role (lab vs portfolio)',
    '.ai/LEARNINGS.md': 'the lab may mention local specifics',
    '.ai/DECISIONS.md': 'the lab keeps an extra ADR for the fork; the portfolio is sanitised',
    '.ai/TOOLS.md': 'the portfolio is sanitised (no other stacks on the machine)',
    'README.md': 'the portfolio carries the public scorecard, the lab its own notes',
    'scripts/sync-check.sh': 'this tool names both checkouts by design',
}

def files(root):
    out = set()
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            out.add(os.path.relpath(os.path.join(dirpath, name), root))
    return out

def normalize(text, forward):
    # forward: this repository is the lab, so map lab -> portfolio
    if forward:
        text = text.replace('cn-jenkins', 'jenkins-base')
        text = text.replace('8083', '8082').replace('50003', '50001').replace('8444', '8443')
        text = text.replace('ADR-011', 'ADR-@@').replace('ADR-010', 'ADR-009').replace('ADR-@@', 'ADR-010')
    else:
        text = text.replace('jenkins-base', 'cn-jenkins')
        text = text.replace('8082', '8083').replace('50001', '50003').replace('8443', '8444')
        text = text.replace('ADR-010', 'ADR-@@').replace('ADR-009', 'ADR-010').replace('ADR-@@', 'ADR-011')
    return text

mine, theirs = files(this), files(other)
only_mine = sorted(mine - theirs)
only_theirs = sorted(theirs - mine)

drift = []
for rel in sorted(mine & theirs):
    if rel in DIFFERENCES:
        continue
    a = open(os.path.join(this, rel)).read()
    # `forward` means "convert the sibling's lab text into portfolio text", which is the
    # case when this checkout is the portfolio.
    b = normalize(open(os.path.join(other, rel)).read(), forward=os.path.basename(this) != 'cn-jenkins')
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
