# Validation

## Completion rule

Before completion, run all applicable validations that are available and safe. Report
each as **Validated**, **Partially validated**, or **Not validated**, with the reason for
anything not run. Never claim validation that did not occur.

## Pinned versions

Versions live in `Dockerfile` ARGs (and `plugins.txt`); `docker-compose.yml` does not
repeat them. Verify a change by rebuilding **without cache** and confirming the trace:

```bash
docker build --no-cache -t jenkins-base:1.0 .          # checksums must pass
docker image inspect jenkins-base:1.0 --format '{{.Size}}'
docker run --rm --entrypoint sh jenkins-base:1.0 -c '
  terraform version | head -1; aws --version; kubectl version --client -o yaml | head -3;
  helm version --short; gcloud --version | head -1; az version | head -4; oci --version;
  python3 --version'
```

If a checksum fails, either upstream republished the artifact (treat it as a review
event: confirm the new content, then update version **and** hash together) or the
version was bumped without its hash.

Note: apt pins fail after a Debian point release, because the previous package version
is removed from the pool. The fix is to bump the pinned versions, not to unpin.

## Checks for this repository

### 1. Static validation (safe, always allowed)

```bash
# Compose file resolves and is syntactically valid
docker compose config --quiet

# Dockerfile lints (if hadolint is installed)
hadolint Dockerfile

# Every CasC file parses, and the top-level keys stay split (no overlap)
python3 - <<'PY'
import yaml
files = ['casc/jenkins.yaml', 'casc/jenkins.yaml.example', 'casc/jobs.yaml']
keys = {f: set(yaml.safe_load(open(f))) for f in files}
print(keys)
assert keys['casc/jobs.yaml'] == {'jobs'}, 'jobs.yaml must only define jobs:'
assert 'jobs' not in keys['casc/jenkins.yaml'], 'jobs: must live in jobs.yaml'
PY

# Shell payloads inside the pipelines must be valid POSIX sh
python3 - <<'PY'
import glob, re, subprocess, tempfile, os
for f in glob.glob('casc/pipelines/*.groovy'):
    for block in re.findall(r"sh '''(.*?)'''", open(f).read(), re.S):
        t = tempfile.NamedTemporaryFile('w', suffix='.sh', delete=False)
        t.write(block); t.close()
        r = subprocess.run(['sh', '-n', t.name], capture_output=True, text=True)
        print(f, 'OK' if r.returncode == 0 else 'FAIL ' + r.stderr)
        os.unlink(t.name)
PY
```

Note: `docker compose config` does **not** require `casc/jenkins.yaml` to exist (the mount
source is only a string), so it passes before setup — verified 2026-10-21.

Also check, by reading rather than running: every job in `casc/jobs.yaml` has a matching
file in `casc/pipelines/`, and `CASC_JENKINS_CONFIG` lists both CasC files (Dockerfile and
`docker-compose.yml`).

### 2. Image build (allowed, but slow and network-dependent)

```bash
docker build --build-arg TERRAFORM_VERSION=1.16.1 -t jenkins-base:1.0 .
```

Validates `plugins.txt` (plugin resolution against the update center), the AWS CLI
install, and the Terraform download. Requires network access.

### 3. Runtime smoke test (allowed locally; creates a container)

```bash
cp -n casc/jenkins.yaml.example casc/jenkins.yaml   # only if missing; then edit values
docker compose up -d
docker compose logs --tail=50 jenkins       # expect: Jenkins is fully up and running
curl -sS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8081/login   # expect 200
docker compose exec jenkins terraform version
docker compose exec jenkins aws --version
docker compose exec jenkins sh -c 'curl -s -u admin:<pass> http://localhost:8080/api/json?tree=jobs[name]'
```

Confirm via the API that `aws-waf-security`, `example-aws-role`, `example-azure-role`, and
`example-gcp-role` all exist, which proves CasC loaded both files and job-dsl resolved the
pipeline bodies. Then `docker compose down` (keep the volume unless the test was meant to
reset state).

### 4. Agent health

```bash
make agents     # agent-1 must be "online", executors=2, labels include terraform
make verify     # waits for the agent and fails if it never comes online
```

A build that hangs waiting for an executor means no agent matches the label. If the agent
is offline, the controller log shows whether the secret was published
(`[init] published the agent secret for agent-1`) and `docker compose logs agent` shows the
connection attempt.

### 5. Example jobs (safe to start; they stop at the placeholder check)

Running `example-*` build now should fail fast with `exit 78` and a message naming the
credential to fill in — that is the expected result and proves the guard works. Running
them with real credentials contacts AWS/Azure/GCP; that is a read-only call but still an
external operation, so ask before doing it. `example-aws-role` additionally needs the
mounted `~/.aws` identity to be allowed to assume the role.

### 4. End-to-end pipeline run (requires authorization)

Triggering `Plan`/`Apply` against a real AWS account is an external, potentially costly
operation. Do not run it as part of validation without explicit user approval. It also
needs the `aws-waf-security` repository to be reachable and the deployment role to exist.

## Current status

No project-specific validation is automated (no tests, no CI for this repository). The
checks above are manual.

**Last full validation — 2026-10-21 (agent split):** the controller runs the stock image
with 0 executors and no labels; `agent-1` is online with 2 executors and labels
`terraform,linux,cloud`; the `git` service serves the demo repository and both the
controller and the agent can `git ls-remote` it; five builds (`example-single-branch`,
`example-basic`, `example-terraform`, `multibranch/main`, `multibranch/feature/demo`)
finished **SUCCESS** with `node: agent-1` in the console.

**Previous validation — 2026-10-21:** the pinned toolchain image built (checksums passed,
4.07 GB); every CLI reports the pinned version (`terraform 1.16.1`, `aws-cli 2.38.4`,
`kubectl v1.37.1`, `helm v4.3.1`, `gcloud 590.0.0`, `az 2.91.0`, `oci 3.95.1`,
`python 3.13.5`, 70 pinned plugins); CasC created all nine jobs; the multibranch job
indexed both branches; and `example-single-branch`, `example-basic`, `example-terraform`,
plus `multibranch/main` and `multibranch/feature/demo` all finished **SUCCESS**.

Not exercised: `example-azure-role` / `example-gcp-role` with real tokens,
`example-parameters-approval` (blocks on manual approval), and the WAF pipeline itself.

Practical note: because the demo repository is baked into the image at build time, editing
`Jenkinsfile` or `examples/*` changes nothing until the image is rebuilt — the SCM checkout
inside Jenkins reads `/opt/demo/repo.git`, not this working directory.

### Authenticated API calls (needed for any POST)

`curl --netrc-file` works for GET, but POST fails with `403 No valid crumb` unless the
crumb comes from the same session. Use a cookie jar:

```bash
CRUMB=$(curl -sS -c jar --netrc-file netrc "$JENKINS/crumbIssuer/api/json" \
        | python3 -c 'import json,sys;print(json.load(sys.stdin)["crumb"])')
curl -sS -b jar -c jar --netrc-file netrc -H "Jenkins-Crumb: $CRUMB" -X POST "$JENKINS/job/X/build"
```

Never put the admin password in a command line; read it from `casc/jenkins.yaml` into a
temporary `umask 077` file and delete it afterwards.
