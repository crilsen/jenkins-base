// Self-check pipeline for this repository.
//
// It is what the single-branch and multibranch example jobs run: it validates the
// files a change to this project touches, without needing credentials or network.
// Keep it runnable on the controller label `terraform`.

pipeline {
  agent { label 'terraform' }
  options { timestamps() }

  environment {
    TF_IN_AUTOMATION = '1'
  }

  stages {
    stage('Context') {
      steps {
        sh '''#!/bin/sh
set -eu

echo "branch:    ${BRANCH_NAME:-<none: single-branch job has no BRANCH_NAME>}"
echo "build:     ${BUILD_NUMBER:-?}"
echo "node:      ${NODE_NAME:-?}"
echo "workspace: ${WORKSPACE:-?}"
echo "commit:    $(git rev-parse --short HEAD 2>/dev/null || echo '<unknown>')"
echo
terraform version | head -1
aws --version
'''
      }
    }

    stage('Validate CasC') {
      steps {
        sh '''#!/bin/sh
set -eu

python3 - <<'PY'
import sys, yaml

jobs = yaml.safe_load(open('casc/jobs.yaml'))
assert set(jobs) == {'jobs'}, f"casc/jobs.yaml must only define jobs:, got {sorted(jobs)}"

example = yaml.safe_load(open('casc/jenkins.yaml.example'))
assert set(example) == {'jenkins', 'credentials'}, (
    f"casc/jenkins.yaml.example must only define jenkins:/credentials:, got {sorted(example)}")

ids = [c['string']['id'] for c in
       example['credentials']['system']['domainCredentials'][0]['credentials']]
required = {'waf-deploy-role-arn', 'aws-demo-role-arn',
            'azure-demo-oidc-token', 'gcp-demo-oidc-token'}
missing = required - set(ids)
assert not missing, f"missing credentials in the example: {sorted(missing)}"

print('CasC keys OK;', len(ids), 'credentials declared')
PY
'''
      }
    }

    stage('Validate pipelines') {
      steps {
        sh '''#!/bin/sh
set -eu

python3 - <<'PY'
import glob, os, re, subprocess, tempfile

files = sorted(glob.glob('casc/pipelines/*.groovy'))
assert files, 'no pipeline bodies found in casc/pipelines/'

# Build the delimiter instead of writing it: a literal three-quote sequence
# inside this heredoc would close the surrounding Groovy string.
q3 = "'" * 3
pattern = 'sh ' + q3 + '(.*?)' + q3

failed = 0
for path in files:
    source = open(path).read()
    if source.count(q3) % 2:
        print(f'{path}: unbalanced triple quotes')
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
print(f'{len(files)} pipeline bodies have valid POSIX sh')
PY
'''
      }
    }

    stage('Validate Compose') {
      steps {
        sh '''#!/bin/sh
set -eu

python3 - <<'PY'
import yaml

compose = yaml.safe_load(open('docker-compose.yml'))
service = compose['services']['jenkins']
casc = service['environment']['CASC_JENKINS_CONFIG']
parts = [p.strip() for p in casc.split(',')]
assert parts == ['/opt/casc/jenkins.yaml', '/opt/casc/jobs.yaml'], (
    f'CASC_JENKINS_CONFIG must list both CasC files, got {casc!r}')
assert service['container_name'] == 'jenkins-base'
print('Compose OK:', service['container_name'], '|', ','.join(parts))
PY
'''
      }
    }
  }

  post {
    always {
      echo "Self-check finished: ${currentBuild.currentResult}"
    }
  }
}
