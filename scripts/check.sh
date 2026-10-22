#!/bin/sh
# The checks this repository must pass.
#
# Single definition, two callers: the self-check Jenkinsfile (runs it on the agent) and
# .github/workflows/check.yml (runs it on a GitHub runner), so CI and Jenkins cannot drift
# apart. Everything here is offline and read-only.
set -eu

ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

echo "== CasC: file split, credentials, controller shape"
python3 - <<'PY'
import yaml

jobs = yaml.safe_load(open('casc/jobs.yaml'))
assert set(jobs) == {'jobs'}, f"casc/jobs.yaml must only define jobs:, got {sorted(jobs)}"

example = yaml.safe_load(open('casc/jenkins.yaml.example'))
expected_keys = {'jenkins', 'credentials', 'unclassified'}
assert set(example) == expected_keys, (
    f"casc/jenkins.yaml.example must define {sorted(expected_keys)}, got {sorted(example)}")

ids = {c['string']['id'] for c in
       example['credentials']['system']['domainCredentials'][0]['credentials']}
required = {'waf-deploy-role-arn', 'aws-demo-role-arn',
            'azure-demo-oidc-token', 'gcp-demo-oidc-token'}
missing = required - ids
assert not missing, f"missing credentials in the example: {sorted(missing)}"

jenkins = example['jenkins']

# The controller schedules; it must not execute builds and must not carry labels.
assert jenkins['numExecutors'] == 0, 'the controller must have zero executors'
assert not jenkins.get('labelString'), 'the controller must not have labels of its own'

# Least privilege instead of "any logged-in user is an admin".
auth = jenkins['authorizationStrategy']
assert 'globalMatrix' in auth, f'expected globalMatrix authorization, got {sorted(auth)}'
assert 'loggedInUsersCanDoAnything' not in auth, 'loggedInUsersCanDoAnything is not acceptable'
permissions = ' '.join(auth['globalMatrix']['permissions'])
assert 'Overall/Administer:admin' in permissions, 'admin must hold Overall/Administer'
assert 'Overall/Administer:viewer' not in permissions, 'viewer must not be an admin'

# The agent node is declared in CasC and reachable by label.
nodes = jenkins.get('nodes') or []
labels = ' '.join(n['permanent']['labelString'] for n in nodes)
assert 'terraform' in labels, 'an agent with the terraform label must be declared'
assert any(n['permanent']['launcher'].get('inbound') for n in nodes), (
    'the agent must use the inbound launcher')

print('CasC OK:', len(ids), 'credentials,', len(nodes), 'node(s), authorization: matrix')
PY

echo "== pipelines: POSIX sh payloads and quoting"
python3 - <<'PY'
import glob, os, re, subprocess, tempfile

files = sorted(glob.glob('casc/pipelines/*.groovy'))
assert files, 'no pipeline bodies found in casc/pipelines/'

q3 = "'" * 3
pattern = 'sh ' + q3 + '(.*?)' + q3
failed = 0

for path in files:
    source = open(path).read()
    if source.count(q3) % 2:
        print(f'{path}: unbalanced triple quotes')
        failed += 1
    if 'buildDiscarder' not in source:
        print(f'{path}: missing buildDiscarder (retention policy)')
        failed += 1
    for block in re.findall(pattern, source, re.S):
        handle = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False)
        handle.write(block)
        handle.close()
        result = subprocess.run(['sh', '-n', handle.name], capture_output=True, text=True)
        os.unlink(handle.name)
        if result.returncode != 0:
            print(f'{path}: {result.stderr.strip()}')
            failed += 1

assert failed == 0, f'{failed} pipeline check(s) failed'
print(f'{len(files)} pipeline bodies OK')
PY

echo "== Jenkinsfiles: retention policy present"
python3 - <<'PY'
import glob

files = ['Jenkinsfile'] + sorted(glob.glob('examples/Jenkinsfile.*'))
missing = [f for f in files if 'buildDiscarder' not in open(f).read()]
assert not missing, f'missing buildDiscarder in: {missing}'
print(f'{len(files)} Jenkinsfiles declare retention')
PY

echo "== Compose: architecture, state, proxy, health"
python3 - <<'PY'
import yaml

compose = yaml.safe_load(open('docker-compose.yml'))
project = compose.get('name')
services = compose['services']
service = services['jenkins']

casc = service['environment']['CASC_JENKINS_CONFIG']
parts = [p.strip() for p in casc.split(',')]
assert parts == ['/opt/casc/jenkins.yaml', '/opt/casc/jobs.yaml'], (
    f'CASC_JENKINS_CONFIG must list both CasC files, got {casc!r}')
assert service['container_name'] == project, (
    f"container_name ({service['container_name']!r}) must match the Compose project name ({project!r})")

# The controller is the stock image: nothing to build.
assert 'build' not in service, 'the controller must not be built: use the official image'
assert service['image'].startswith('jenkins/jenkins:'), 'the controller must be the official image'
assert '@sha256:' in service['image'], 'the controller image must be pinned by digest'
assert 'healthcheck' in service, 'the controller needs a healthcheck'

# State must be a bind mount, never a named volume.
mounts = [v for v in service['volumes'] if v.endswith(':/var/jenkins_home')]
assert mounts, 'the state must be mounted at /var/jenkins_home'
assert not service.get('volumes', []).count('jenkins_home:/var/jenkins_home'), 'state must not be a named volume'

# The agent is the built part, and it is the only place with credentials.
assert 'agent' in services and services['agent'].get('build'), 'the agent image is the one that gets built'
assert 'healthcheck' in services['agent'], 'the agent needs a healthcheck'

# TLS terminates in a proxy in front of the controller.
assert 'proxy' in services, 'a reverse proxy must terminate TLS'
assert 'healthcheck' in services['proxy'], 'the proxy needs a healthcheck'
proxy_ports = services['proxy']['ports']
assert any(p.startswith('127.0.0.1:') for p in proxy_ports), 'the proxy must bind to loopback'

# Every published port stays on loopback.
for name, svc in services.items():
    for published in svc.get('ports', []):
        assert published.startswith('127.0.0.1:'), f'{name} publishes {published} beyond loopback'

print('Compose OK:', project, '|', ','.join(sorted(services)))
PY

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  echo "== docker compose config"
  docker compose config --quiet
  echo "compose config OK"
else
  echo "== docker compose config: skipped (no docker)"
fi

echo "check: OK"
