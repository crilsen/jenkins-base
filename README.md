# jenkins-base — a reproducible local Jenkins for multicloud Terraform

A Jenkins controller in Docker, configured entirely as code, meant to be a
**template**: clone it, run `make up`, and you have a controller that can run
Terraform and cloud pipelines against AWS, Azure, GCP, OCI, Kubernetes or on-prem
targets — with every tool version pinned and every job declared in YAML.

It is deliberately generic, and honest about being a local baseline rather than a
production controller.

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
make up        # secrets + build + start
make verify    # wait for Jenkins, check the API, count the jobs
make tools     # print the pinned tool versions inside the image
```

Console: <http://localhost:8082> — user `admin`, password in `casc/jenkins.yaml`
(created by `make secrets`, git-ignored). `make help` lists every target.

Prerequisites: Docker with Compose, and an AWS identity able to `sts:AssumeRole` on
the deployment role if you want to run the WAF pipeline (`~/.aws` is mounted
read-only).

## Architecture

```text
docker compose up -d
   │
   ├── image jenkins-base:1.0
   │     jenkins/jenkins:lts-jdk17 (digest) + Terraform + AWS/Azure/GCP/OCI CLIs
   │     + kubectl + helm + pinned plugin set
   │
   └── container jenkins-base   (127.0.0.1:8082 → 8080, 50001 → 50000)
         ├── data/jenkins_home           host directory, the state
         ├── data/jenkins_home/.aws      ~/.aws (read-only)
         ├── /opt/casc                   ./casc (read-only)
         └── /var/jenkins_home/init.groovy.d  ./init (read-only)
             │
             ├── CasC: casc/jenkins.yaml   jenkins: + credentials:
             └── CasC: casc/jobs.yaml      jobs:
```

The two CasC files must stay supplementary — each top-level key belongs to exactly
one file, otherwise CasC raises a conflict. `CASC_JENKINS_CONFIG` lists both files
explicitly so `jenkins.yaml.example` is never loaded.

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

A changed upstream artifact fails the build on its checksum instead of silently
changing the image. `az` and `oci` live in isolated venvs under `/opt` so their
Python dependencies cannot break the system Python Jenkins uses. The image is
~4.1 GB, dominated by `az` and `gcloud`; per-cloud derived images
(`FROM jenkins-base:1.0`) are the escape hatch.

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

The example jobs clone a snapshot of this repository's Jenkinsfiles baked into the
image at `/opt/demo/repo.git` (branches `main` and `feature/demo`), so the examples
work offline. That requires `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true`,
which is a demo-only trade — drop it and point the jobs at a real remote before
sharing this controller.

## Repository layout

```
Dockerfile             Jenkins + the pinned toolchain
plugins.txt            fully resolved plugin set
docker-compose.yml     container, ports, bind-mounted state
Makefile               build / up / verify / backup / restore / reset / tools
casc/                  CasC: jobs.yaml (tracked) + jenkins.yaml(.example)
casc/pipelines/        pipeline bodies for the role examples
init/                  Groovy init script (controller label)
examples/              example Jenkinsfiles + offline Terraform fixture
scripts/               backup, restore, reset, jobs, verify
.ai/                   portable agent context: decisions, conventions, validation
```

## Design decisions

The reasoning behind the choices above — including why the plugin set is pinned in
full, why the demo repository is baked into the image, and why the state is a bind
mount — is recorded in [`.ai/DECISIONS.md`](.ai/DECISIONS.md). Conventions, guardrails
and validation steps live next to it, so an agent (or a new maintainer) can pick the
repository up without prior context. Start at [`AGENTS.md`](AGENTS.md).

## Security notes

- The container binds to `127.0.0.1` only.
- No AWS keys are stored in Jenkins: `~/.aws` is mounted read-only and the pipeline
  assumes a role through STS.
- `casc/jenkins.yaml` holds the admin password and is git-ignored; never commit it.
- `loggedInUsersCanDoAnything` and building on the controller are deliberate demo
  simplifications. For anything shared: real agents, `matrix-auth` roles, TLS behind a
  reverse proxy, and platform-injected tokens instead of pasted ones.
