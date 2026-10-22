# jenkins-base — a reproducible local Jenkins for multicloud Terraform

A Jenkins setup in Docker, configured entirely as code, meant to be a **template**:
clone it, run `make up`, and you have a controller that can run Terraform and cloud
pipelines against AWS, Azure, GCP, OCI, Kubernetes or on-prem targets — with every tool
version pinned and every job declared in YAML.

The controller is the **stock `jenkins/jenkins` image** (pinned by digest, no custom
build, zero executors); the toolchain lives in a separate **agent** image. That split is
the point of the repository: the part that schedules is boring and replaceable, and the
part that runs pipelines carries the tools.

It is deliberately generic, and honest about being a local baseline rather than a
production controller — see [Good practice: what this does, and what it deliberately does
not](#good-practice-what-this-does-and-what-it-deliberately-does-not).

## What it demonstrates

- **Configuration as code** for the whole controller: security realm, credentials,
  jobs and pipelines — no clicking in the UI.
- **A reproducible image**: base image pinned by digest, Debian packages by exact
  version, and every downloaded CLI verified with `sha256sum -c`.
- **Credential acquisition without static keys**, one example per cloud: AWS
  `sts:AssumeRole`, Azure Entra ID federated credential, GCP Workload Identity
  Federation with service account impersonation.
- **Both SCM wiring styles**: a plain pipeline job pinned to a branch, and a
  multibranch job that discovers branches.
- **Persistence that survives Docker**: state lives in a host directory, so
  `docker compose down -v` cannot delete it; backups and restores are plain `tar`.
- **A pipeline that checks the repository itself**: `Jenkinsfile` validates the CasC
  split, the shell payloads and the Compose wiring on every run.

## Quickstart

```bash
make up        # secrets + build the agent image + start everything
make verify    # wait for Jenkins, check the API, job count and agent health
make agents    # list nodes, executors and labels
make check     # the repository checks (same ones CI runs)
make ca        # export the proxy's local CA so https://localhost:8443 is trusted
make tools     # print the pinned tool versions inside the agent image
```

Console: <https://localhost:8443> (via the proxy, TLS) or <http://localhost:8082> directly.
Users: `admin` (administrator) and `viewer` (read-only); both passwords live in
`casc/jenkins.yaml`, created by `make secrets` and git-ignored. `make help` lists every
target.

Prerequisites: Docker with Compose, and an AWS identity able to `sts:AssumeRole` on
the deployment role if you want to run the WAF pipeline (`~/.aws` is mounted
read-only).

## Architecture

Three services. Only the agent image is built; the controller is stock, and the demo SCM
is generated from the mounted files.

```text
docker compose up -d
   |
   +-- controller  jenkins-base        stock jenkins/jenkins:lts-jdk17 (digest), 0 executors
   |     +-- data/jenkins_home         state: plugins resolved at first boot, jobs, builds
   |     +-- /opt/casc                 ./casc (read-only)
   |     +-- init.groovy.d             ./init (read-only)
   |     +-- data/agent-secret         hands the agent its JNLP secret
   |
   +-- agent  jenkins-base-agent       built from Dockerfile.agent
   |     labels: terraform, linux, cloud - 2 executors
   |     toolchain: terraform, aws, az, gcloud, oci, kubectl, helm, python3, jq, git
   |     ~/.aws read-only; workspace in a named volume
   |
   +-- git  jenkins-base-git           serves http://git:8080/repo.git
   |     built from the mounted Jenkinsfile/examples/casc files at startup
   |
   +-- proxy  jenkins-base-proxy       https://localhost:8443  (Caddy, TLS internal)
         the only service a browser talks to
```

Why this shape:

- **The controller carries no toolchain and no executors.** It schedules, serves the UI
  and applies CasC. There is no controller build to get wrong, and a controller restart
  cannot lose the ability to run pipelines.
- **The agent is the disposable part.** Its image is rebuilt from `Dockerfile.agent`, and
  jobs request it by label (`agent { label 'terraform' }`), so adding a second agent is a
  Compose service, not a pipeline change.
- **The agent secret is handed over, not typed in.** Jenkins generates a secret per node;
  `init/02-publish-agent-secret.groovy` publishes it to a shared directory and the agent's
  entrypoint reads it (never as a command-line argument), retrying across controller
  restarts.
- **The demo repository is a real remote** (HTTP, dumb git protocol) instead of a local
  path: the controller can read Jenkinsfiles for lightweight checkout and multibranch
  indexing without the toolchain, and nothing needs the `ALLOW_LOCAL_CHECKOUT`
  relaxation.
- **TLS terminates in the `proxy` service**, so the controller keeps speaking plain HTTP
  inside the network and Jenkins knows its public URL (`unclassified.location`).
- **Every service has a healthcheck**, and `depends_on: service_healthy` replaces blind
  retries when the agent and the demo SCM start.

## Persistence

| Layer | Contents | Where | `down` | `down -v` |
| --- | --- | --- | --- | --- |
| Config / code | `Dockerfile`, `plugins.txt`, `casc/jobs.yaml`, `casc/jenkins.yaml.example`, `init/`, `Jenkinsfile`, `examples/` | this repository | safe | safe |
| Secret | `casc/jenkins.yaml` | this repository, git-ignored | safe | safe |
| State | builds, workspaces, `credentials.xml`, `identity.key.enc`, installed plugins | `data/jenkins_home` | safe | **safe** |
| Artifact | toolchain, `/opt/demo` snapshot, plugins in `/usr/share/jenkins/ref` | the image | rebuilt | safe |

```bash
make backup                          # -> backups/jenkins-home-<timestamp>.tar.gz
make restore FILE=backups/xxx.tar.gz # destructive: replaces the state directory
make reset                           # destructive: deletes the state directory
```

`make backup` stops the container for a consistent snapshot and starts it again.

**Deploying to another server.** The state directory is per-machine: a fresh clone
starts an empty Jenkins (jobs come back from CasC, history does not). Keep the state
outside the checkout and seed it from a backup:

```bash
sudo mkdir -p /srv/jenkins/home && sudo chown -R 1000:1000 /srv/jenkins
echo 'JENKINS_HOME_DIR=/srv/jenkins/home' >> .env   # see .env.example
make up && make restore FILE=/path/to/backup.tar.gz
```

The directory must be writable by uid `1000` (the container's `jenkins` user), and
backups must be copied off the machine — a tarball on the same disk is not a backup.

## Toolchain (pinned)

| Tool | Version | How it is pinned |
| --- | --- | --- |
| Base image | `jenkins/jenkins:lts-jdk17` | by digest |
| Debian packages | Debian 13 | exact `name=version` |
| Terraform | 1.16.1 | version + SHA256 |
| AWS CLI v2 | 2.38.4 | versioned zip + SHA256 |
| kubectl | v1.37.1 | version + SHA256 |
| helm | v4.3.1 | version + SHA256 |
| Google Cloud CLI | 590.0.0 | versioned tarball + SHA256 |
| Azure CLI | 2.91.0 | pip in its own venv |
| OCI CLI | 3.95.1 | pip in its own venv |
| Jenkins plugins | 70 entries | fully resolved `name:version` list |

A changed upstream artifact fails the build on its checksum instead of silently changing
the image. `az` and `oci` live in isolated venvs under `/opt` so their Python dependencies
cannot break the system Python. All of it is in the **agent** image (~3.6 GB, dominated by
`az` and `gcloud`); the controller image is upstream's (~0.8 GB) and carries no tools.
Per-cloud derived agents (`FROM jenkins-base-agent:1.0`) are the escape hatch.

## Jobs

| Job | What it shows |
| --- | --- |
| `aws-waf-security` | Multibranch job for the `aws-waf-security` Terraform pipeline |
| `example-aws-role` | `sts:AssumeRole` → `get-caller-identity`, no static keys |
| `example-azure-role` | Entra ID federated credential: OIDC token → ARM token |
| `example-gcp-role` | Workload Identity Federation → service account impersonation |
| `example-single-branch` | One job pinned to `main`, no branch discovery |
| `example-multibranch` | One job per branch, created by the scan |
| `example-basic` | Smallest useful pipeline |
| `example-parameters-approval` | Parameters + manual approval + guarded apply |
| `example-terraform` | Real `terraform fmt/init/validate` on `examples/terraform` |

The three role examples use only `curl` and `jq` on purpose: they show the token
exchange itself rather than wrapping `az`/`gcloud`. They fail fast with a clear
message while their credential still holds a placeholder, and never echo a secret.

The example jobs clone `http://git:8080/repo.git`: a repository built at startup from the
mounted project files and served by the `git` service, with branches `main` and
`feature/demo`. It works offline, needs no GitHub account, and is a real remote — so no
`ALLOW_LOCAL_CHECKOUT` relaxation is involved. Point `remote(...)` in `casc/jobs.yaml` at a
real repository and nothing else changes.

## Repository layout

```
Dockerfile.agent       the agent image: pinned toolchain (the only build)
plugins.txt            fully resolved plugin set, installed at first boot
docker-compose.yml     controller + agent + demo SCM, ports, bind-mounted state
Makefile               build / up / verify / agents / plugins / backup / restore / reset
casc/                  CasC: jobs.yaml (tracked) + jenkins.yaml(.example)
casc/pipelines/        pipeline bodies for the role examples
init/                  init script that hands the agent its secret
examples/              example Jenkinsfiles + offline Terraform fixture
scripts/               agent entrypoint, demo-repo seeding, backup, verify, jobs
.ai/                   portable agent context: decisions, conventions, validation
```

## Good practice: what this does, and what it deliberately does not

This repository is a **demonstration**, not a production controller. Here is the honest
scorecard — where the practice is followed, and where it is not:

| Area | Here | A production setup would |
| --- | --- | --- |
| Job definition | ✅ in code (`casc/jobs.yaml`), reviewed in git | same, plus drift detection against the running controller |
| Pipeline definition | ✅ `Jenkinsfile` in the project repository, never in the job | same |
| Controller configuration | ✅ CasC for realm, credentials and jobs | same |
| Reproducible images | ✅ base digests, apt versions, every CLI with a checksum, plugins fully pinned | same, plus a rebuild pipeline and per-cloud derived images |
| Controller build | ✅ none: the stock official image, plugins resolved at first boot | same |
| State vs artifact | ✅ state in a host directory; backup and restore tested | same, plus scheduled off-box backups and restore drills |
| Cloud credentials | ✅ role assumption / workload identity, no static keys | same |
| Secrets at rest | ⚠️ live CasC file git-ignored, demo tokens as Jenkins credentials | a secret manager or JCasC secret sources; only platform-issued tokens |
| Health / startup order | ✅ Docker healthchecks on all four services; dependents wait for `service_healthy` | same, plus restart alerts |
| Authorization | ✅ `globalMatrix`: `admin` administers, `viewer` is read-only (verified: 403 on admin-only endpoints) | SSO/OIDC on top of the same permissions |
| Agents | ✅ controller with 0 executors; a separate agent image runs the builds | same, plus ephemeral agents (Kubernetes/EC2) for stronger isolation |
| SCM wiring | ✅ real remote (the `git` service over HTTP); no local-checkout relaxation | a hosted remote, webhooks, per-repository credentials |
| Transport | ✅ TLS via the `proxy` service (Caddy, local CA); everything stays on loopback | a real certificate and a managed proxy |
| Build retention | ✅ every pipeline declares `buildDiscarder` (verified in the job config) | same, plus per-repo policy |
| CI for this repository | ✅ GitHub Actions runs `scripts/check.sh` on push/PR — the same script the pipeline runs | same, plus image build and publish |
| Licence | ❌ none | an explicit licence |

Legend: ✅ follows the practice · ⚠️ partial, or a deliberate compromise · ❌ not done.

The ⚠️ and ❌ rows are deliberate for a loopback-only demo, and each one is recorded in
[`.ai/DECISIONS.md`](.ai/DECISIONS.md) with its reasoning. Adopting this repository means
deciding about each of them explicitly — which is the point of writing them down instead
of claiming the whole thing is best practice.

## Design decisions

The reasoning behind the choices above — including why the plugin set is pinned in
full, why the controller is the stock image while the toolchain lives in the agent, and
why the state is a bind mount — is recorded in [`.ai/DECISIONS.md`](.ai/DECISIONS.md). Conventions, guardrails
and validation steps live next to it, so an agent (or a new maintainer) can pick the
repository up without prior context. Start at [`AGENTS.md`](AGENTS.md).

## Security notes

- The container binds to `127.0.0.1` only.
- No AWS keys are stored in Jenkins: `~/.aws` is mounted read-only **into the agent** and
  the pipeline assumes a role through STS.
- `casc/jenkins.yaml` holds the admin password and is git-ignored; never commit it.
- `loggedInUsersCanDoAnything` is a deliberate demo simplification, and the agent secret
  is handed over through a shared directory rather than an agent configuration
  management tool. For anything shared: `matrix-auth` roles, TLS behind a reverse proxy,
  platform-injected tokens instead of pasted ones, and ephemeral agents.
