# Architecture

## Overview

A single, cloud-agnostic Jenkins controller, built as a Docker image and run by Compose.
It is the project's default local/on-prem baseline: the image carries Jenkins, Terraform,
and the AWS CLI, while credentials and jobs come from CasC, so the same controller can run
pipelines against AWS, Azure, GCP, or on-prem targets. Today it executes the
`aws-waf-security` Terraform pipeline plus three per-cloud role examples. It is a local
baseline: the controller builds on itself and there are no remote agents.

```text
docker compose up -d
        |
        +-- controller  jenkins-base   (127.0.0.1:8082 -> 8080, 50001 -> 50000)
        |     stock jenkins/jenkins:lts-jdk17@sha256:... , numExecutors: 0
        |     +-- data/jenkins_home          bind mount, the state
        |     +-- /opt/casc                  ./casc (read-only)
        |     +-- init.groovy.d              ./init (read-only)
        |     +-- data/agent-secret          JNLP secret hand-off
        |
        +-- agent  jenkins-base-agent   built from Dockerfile.agent
        |     labels: terraform, linux, cloud ; 2 executors
        |     toolchain + /home/jenkins/.aws (read-only) + workspace volume
        |
        +-- git  jenkins-base-git   http://git:8080/repo.git
        |     repository built at startup from the mounted project files
        |
        +-- proxy  jenkins-base-proxy   https://localhost:8443 (Caddy, tls internal)
              the only service a browser talks to
```

Only the agent image is built. The controller is the official image pinned by digest and
resolves its plugins at first boot from `plugins.txt` into the state directory; the demo
repository is generated from mounted files instead of being baked into an image, so
editing a Jenkinsfile needs `docker compose restart git`, not a rebuild.

## Components

| Component | File | Responsibility |
| --- | --- | --- |
| Controller image | (none) | The stock `jenkins/jenkins:lts-jdk17` image, pinned by digest; plugins resolve at first boot |
| Agent image | `Dockerfile.agent` | The toolchain, built from `jenkins/inbound-agent` pinned by digest |
| Agent entrypoint | `scripts/agent-entrypoint.sh` | Waits for the JNLP secret, connects over WebSocket, retries |
| Secret hand-off | `init/02-publish-agent-secret.groovy` | Publishes the node secret to `data/agent-secret` |
| Demo SCM | `scripts/seed-repo.sh` | Builds and serves the demo repository over HTTP |
| TLS proxy | `proxy/Caddyfile` | Terminates TLS for the browser; Jenkins stays HTTP internally |
| Repository checks | `scripts/check.sh` | One definition of the checks, run by CI and by the pipeline |
| CI | `.github/workflows/check.yml` | Runs `scripts/check.sh` on push/PR |
| Plugins | `plugins.txt` | Fully resolved, pinned plugin set installed by `jenkins-plugin-cli` |
| Runtime | `docker-compose.yml` | Port mapping (loopback only), volumes, `TZ`, `restart: unless-stopped` |
| Configuration as Code | `casc/jenkins.yaml` | Security realm, authorization, credentials |
| CasC template | `casc/jenkins.yaml.example` | Committed, secret-free template |
| Job definitions | `casc/jobs.yaml` | All jobs; versioned, no secrets; loads pipeline bodies from disk |
| Pipelines | `casc/pipelines/*.groovy` | One inline pipeline per example job (AWS, Azure, GCP role assumption) |
| Init script | `init/01-terraform-label.groovy` | Labels controller `terraform`, sets 2 executors |
| Docs | `README.md` | Prerequisites, run/build instructions, parameters, examples, security notes |

## Pinned toolchain

The image is reproducible: the base is pinned by digest, every downloaded artifact
by version **and** SHA256 (`sha256sum -c` runs before install), Debian packages by
exact `name=version`, and Jenkins plugins by a fully resolved `name:version` list.

| Tool | Version | Placement |
| --- | --- | --- |
| Terraform | 1.16.1 | `/usr/local/bin/terraform` |
| AWS CLI v2 | 2.38.4 | `/usr/local/aws-cli` (symlinked in `/usr/local/bin`) |
| kubectl | v1.37.1 | `/usr/local/bin/kubectl` |
| helm | v4.3.1 | `/usr/local/bin/helm` |
| Google Cloud CLI | 590.0.0 | `/opt/google-cloud-sdk/bin` (on `PATH`) |
| Azure CLI | 2.91.0 | venv `/opt/azure-cli`, symlink `/usr/local/bin/az` |
| OCI CLI | 3.95.1 | venv `/opt/oci-cli`, symlink `/usr/local/bin/oci` |
| Python | 3.13.5 | Debian package (system) |

Notes:

- `az` and `oci` are Python applications, so each lives in its own venv: their
  dependency trees cannot break the system Python that Jenkins itself uses.
- pip is not upgraded inside those venvs; it comes from the pinned
  `python3-venv` package, so the installer itself does not float.
- The image is deliberately large (multi-GB). Splitting per-cloud derived images
  is the documented escape hatch, not a requirement.

## Identity, secrets, and access

- **Observed:** no AWS access keys stored in Jenkins. The operator's `~/.aws` is mounted
  read-only into `JENKINS_HOME`, and the pipeline assumes the deployment role through
  STS (credential `waf-deploy-role-arn` holds the ARN string).
- **Observed (offline SCM):** the example jobs clone `/opt/demo/repo.git`, a snapshot of
  this project's Jenkinsfiles baked into the image with branches `main` and `feature/demo`.
  Cloning a local path needs `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true`, which
  is a demo-only trade: it lets any job clone any local path. Multibranch children are
  stored under `$JENKINS_HOME/jobs/<job>/branches/`, not `jobs/`.
- **Observed:** the admin password lives in `casc/jenkins.yaml`, which is git-ignored and
  replaced from `.example` at setup.
- **Observed (example jobs):** each cloud uses a different short-lived mechanism —
  AWS `sts:AssumeRole`, Azure Entra ID federated credential (OIDC → ARM token), GCP
  Workload Identity Federation (OIDC → federated token → service account impersonation).
  Tokens are supplied through secret-text credentials (`azure-demo-oidc-token`,
  `gcp-demo-oidc-token`) because this local controller has no workload-identity platform
  to inject them; the SECRETS are never echoed, and the exchanged credentials live only
  inside a single `sh` step. Note: a secret-text credential exposes the token to anyone
  with job configure rights — acceptable for a demo, not a production pattern.
- **Observed:** ports bind to `127.0.0.1`; the controller is not reachable from the LAN.
- **Observed:** authorization is `globalMatrix`: `Overall/Administer` for `admin`, and
  read-only (`Overall/Read`, `Job/Read`) for `viewer`. Verified: `viewer` gets 200 on
  `/api/json` and 403 on CasC reload and on triggering a build. Anonymous access is off.
- **Observed:** TLS terminates in the `proxy` service (Caddy with an internal CA);
  `unclassified.location.url` is set to the https URL so Jenkins builds correct links.
- **Observed:** every service has a Docker healthcheck; `docker compose ps` reports health
  and dependents wait for `service_healthy`.
- **Inferred:** the remaining production gaps are ephemeral agents, a real certificate
  authority, and secrets coming from a secret manager instead of the CasC file.

## Environments and deployment

- One environment: the operator's machine. No staging, no production, no IaC for the
  host, no CI/CD for this repository itself.
- Volume state lives in the named volume `<project>_jenkins_home` (`jenkins-base_jenkins_home`
  with the pinned Compose `name:`); `docker compose down -v` destroys it.
- The Terraform state the *pipeline* uses lives in the target repository's remote
  backend (`TF_STATE_BUCKET`), not here.

## External dependencies

- `github.com/crilsen/aws-waf-security` — the pipeline source, parameters, and
  IAM requirements (`docs/iam/`).
- Public downloads at image build: `awscli.amazonaws.com` and
  `releases.hashicorp.com` (Terraform archive is pinned by version).
- AWS account: the deployment role must pre-exist and be assumable by the local identity.

## Context-layer layout

```text
Tool-specific adapter (optional)
            ↓
        AGENTS.md
            ↓
          .ai/
  project · architecture · conventions · decisions
  tasks · handoff · tools · validation · workflows · prompts
```

`.ai/` is the portable source of truth. Tool-specific adapters must only route agents to it.
