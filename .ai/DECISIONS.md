# Decision Records

Durable, meaningful choices. Two types:

- **ADR** — architecture decision: how the system is structured.
- **TDR** — technology decision: stack, library, provider, protocol, or tooling.

Status lifecycle: `Proposed → Accepted → Superseded | Deprecated`. ADR and TDR use separate ID sequences.

## Modes

**Chosen for this project: simple** — entries live inline in this file. Revisit at
roughly 15–20 active records and migrate to `docs/decisions/` (one file per record,
`ADR-NNN-<slug>.md` / `TDR-NNN-<slug>.md`, this file becomes the index only).

## Entry format

```text
## ADR-NNN / TDR-NNN — Title
Type: ADR | TDR
Status: Proposed | Accepted | Superseded | Deprecated
Date: YYYY-MM-DD
Owners: <who>
Supersedes: <ID or none>

Context:
...

Decision:
...

Reasoning:
...

Consequences:
...
```

## Index

| ID | Type | Title | Status | Date | File |
| --- | --- | --- | --- | --- | --- |
| ADR-001 | ADR | Local single-container Jenkins, controller builds on itself | Accepted (observed) | unknown | inline |
| ADR-002 | ADR | Configuration as code with a committed example and a git-ignored real file | Accepted (observed) | unknown | inline |
| ADR-003 | ADR | No static AWS credentials in Jenkins; mount `~/.aws` read-only and assume a role | Accepted (observed) | unknown | inline |
| TDR-001 | TDR | Terraform pinned to 1.16.1 in the image | Accepted (observed) | unknown | inline |
| ADR-004 | ADR | Portable agent context lives in `.ai/`, kept up to date automatically | Accepted | 2026-10-21 | inline |
| ADR-005 | ADR | Split CasC by top-level key; add one role-assumption example job per cloud | Accepted | 2026-10-21 | inline |
| ADR-006 | ADR | Rename the project to `jenkins-base`; pin the Compose project name | Accepted | 2026-10-21 | inline |
| ADR-007 | ADR | Reproducible image: pin base digest, packages, every CLI and all plugins | Accepted | 2026-10-21 | inline |
| ADR-008 | ADR | Jenkins state in a host bind mount instead of a Docker volume | Accepted | 2026-10-21 | inline |
| ADR-009 | ADR | Stock controller image, toolchain only in the agent, demo SCM served over HTTP | Accepted | 2026-10-21 | inline |

## Records

### ADR-001 — Local single-container Jenkins, controller builds on itself

Type: ADR | Status: Accepted (observed) | Date: unknown (pre-dates this context) | Owners: repository author

**Context:** the pipeline needs a Jenkins controller able to run Terraform and AWS CLI,
reachable at `localhost`, with no infrastructure to manage.

**Decision:** one container built from `jenkins/jenkins:lts-jdk17`, with the controller
labelled `terraform` (`init/01-terraform-label.groovy`) so jobs targeting
`agent { label 'terraform' }` execute on it. Two executors.

**Reasoning:** for a demo, an agent fleet adds nothing; a label keeps the pipeline file
agnostic so a real agent can be attached later without editing the Jenkinsfile.

**Consequences:** builds share the controller's JVM and workspace volume; a hung build can
take the controller down. Explicitly not a production topology — `README.md` and the init
script both say so.

### ADR-002 — Configuration as code with a committed example and a git-ignored real file

Type: ADR | Status: Accepted (observed) | Date: unknown | Owners: repository author

**Context:** the controller must be reproducible, but its CasC file holds an admin password
and an AWS account-specific role ARN.

**Decision:** `casc/jenkins.yaml.example` is the committed, secret-free template;
`casc/jenkins.yaml` is the live file and is listed in `.gitignore`. The example is copied
and edited during setup.

**Reasoning:** CasC gives a reproducible controller without a setup wizard; splitting real
from example keeps secrets out of version control.

**Consequences:** a fresh clone cannot start until the copy step is done; the two files can
drift silently. Anyone with the file has admin access.

### ADR-003 — No static AWS credentials in Jenkins; mount `~/.aws` read-only and assume a role

Type: ADR | Status: Accepted (observed) | Date: unknown | Owners: repository author

**Context:** the pipeline deploys with Terraform into a real AWS account.

**Decision:** the operator's `~/.aws` is mounted read-only at `JENKINS_HOME/.aws`; the only
Jenkins credential is the string `waf-deploy-role-arn`, holding the deployment role ARN. The
pipeline assumes that role through STS and uses the temporary credentials.

**Reasoning:** no long-lived keys are stored in Jenkins, and the blast radius is limited to
what the role allows, not to the operator's full identity.

**Consequences:** the container inherits the host's AWS identity; credential rotation is the
operator's responsibility (`aws login`, SSO, or instance profile preferred over static keys).
Contributors need their own identity allowed to assume the role.

### TDR-001 — Terraform pinned to 1.16.1 in the image

Type: TDR | Status: Accepted (observed) | Date: unknown | Owners: repository author

**Context:** plans must be reproducible across machines and across time.

**Decision:** `ARG TERRAFORM_VERSION=1.16.1` in the `Dockerfile`, overridden with the same
value from `docker-compose.yml` `build.args`; the binary is downloaded from
`releases.hashicorp.com` at build time.

**Reasoning:** a floating "latest" Terraform changes plan output and state behaviour without
notice. Downloading (instead of a package) keeps the pinned version available.

**Consequences:** the version is duplicated in two files and must be bumped together; builds
require network access; no checksum verification (TLS only). The host also has 1.16.1,
matching the image.

### ADR-004 — Portable agent context lives in `.ai/`, kept up to date automatically

Type: ADR | Status: Accepted | Date: 2026-10-21 | Owners: repository operator

**Context:** work on this repository is done by different agents, models, and harnesses, and
chat history does not travel with the repository.

**Decision:** `AGENTS.md` + `.ai/` are the single source of truth. The agent maintains them
as work happens (automatic mode, chosen by the user), including the rolling Resume block in
`.ai/HANDOFF.md`. Annotations are in English (user choice, standing preference).

**Reasoning:** the repository must be resumable without chat history; automatic maintenance
keeps the context from rotting, which is the failure mode of manual docs.

**Consequences:** every task ends with `TASKS.md`, `HANDOFF.md`, and (when relevant)
`LEARNINGS.md` updated. Optional infrastructure workflows that do not apply here
(`terraform-change`, `kubernetes-change`, `cloud-port`) are ignored rather than used.

### ADR-005 — Split CasC by top-level key; add one role-assumption example job per cloud

Type: ADR | Status: Accepted | Date: 2026-10-21 | Owners: repository operator

**Context:** job definitions were mixed into `casc/jenkins.yaml`, the git-ignored file that
holds the admin password and the real role ARN. Job definitions are the part most worth
reviewing in version control, and the demo needed a worked example of obtaining cloud
credentials without static keys.

**Decision:** move `jobs:` into a tracked `casc/jobs.yaml`, keep `jenkins:` and
`credentials:` in `jenkins.yaml`, and load both explicitly via `CASC_JENKINS_CONFIG`
(a comma-separated list, not the directory). Pipeline bodies live in
`casc/pipelines/*.groovy` and are read from the mounted read-only `/opt/casc`.
Add three example jobs, each using its cloud's short-lived mechanism: AWS
`sts:AssumeRole`; Azure Entra ID federated credential (OIDC → ARM token); GCP Workload
Identity Federation + service account impersonation. Credentials: `aws-demo-role-arn`,
`azure-demo-oidc-token`, `gcp-demo-oidc-token`.

**Reasoning:** CasC files must be supplementary — two files defining `jobs:` (or
`credentials:`) raise a `ConfiguratorException` — so one top-level key per file is the only
clean split. Pointing at the directory would also load `jenkins.yaml.example`, which
duplicates both keys. Keeping pipeline bodies in `.groovy` files avoids triple-nested
quoting inside YAML and keeps the shell readable. The per-cloud jobs use only `aws`,
`curl`, and `jq`, all already in the image, so no plugins or CLIs were added and the image
does not grow.

**Consequences:** editing a pipeline file requires a CasC reload (the job definition is set
at apply time); `CASC_PIPELINES_DIR` must be set if the compose mount changes. The example
jobs fail with `exit 78` until placeholders are replaced. The OIDC tokens sit in
secret-text credentials, which is a demo convenience — a production deployment should
inject a platform-issued token as a file instead. `casc/jenkins.yaml` gained three
credential entries; the previous layout is backed up outside the repository.

### ADR-006 — Rename the project to `jenkins-base`; pin the Compose project name

Type: ADR | Status: Accepted | Date: 2026-10-21 | Owners: repository operator

**Context:** the repository was called `jenkins-ci`, which is redundant (Jenkins is a CI
server), says nothing about scope, and disagreed with the container actually run
(an earlier container name). The intent is that this is the **default** Jenkins, used
for multicloud (AWS/Azure/GCP) and on-prem/local pipelines — not a single-project demo.

**Decision:** name it `jenkins-base` (image `jenkins-base:1.0`, container `jenkins-base`),
and pin `name: jenkins-base` at the top of `docker-compose.yml` so the Compose project — and
therefore the `jenkins-base_jenkins_home` volume — no longer depends on the checkout
directory. The scope (multicloud + on-prem, currently wired to `aws-waf-security`) is
documented in `README.md` and `.ai/PROJECT.md` instead of encoded in the name.

**Reasoning:** the name must survive the repository being copied per project. A
scope-neutral base name plus an explicit scope statement stays accurate as more pipelines
are added; a target-specific name would have to be renamed again.

**Consequences:** renaming the Compose project creates a new volume, so the previous
`jenkins-ci_jenkins_home` state is not reused (jobs and the admin user come from CasC, so
only build history is lost). The directory is still `jenkins-ci` on disk — the operator
decides whether to rename it; `name:` keeps the runtime identity independent of that.

### ADR-007 — Reproducible image: pin base digest, packages, every CLI and all plugins

Type: ADR | Status: Accepted | Date: 2026-10-21 | Owners: repository operator

**Context:** the image combined a floating `lts-jdk17` tag, `apt-get install` without
versions, an unversioned AWS CLI zip, plugin names without versions, and a
`TERRAFORM_VERSION` duplicated between `Dockerfile` and Compose. Two builds of the same
commit could produce different images, and nothing failed loudly when that happened.
At the same time the controller had to gain the CLIs for its real job: Kubernetes,
OCI, Google, Azure, plus Python tooling.

**Decision:** pin everything that has a stable identity, and fail the build when an
artifact changes:

- base image by digest;
- Debian packages by `name=version`;
- Terraform, AWS CLI, kubectl, helm, Google Cloud CLI by version **plus** SHA256,
  verified with `sha256sum -c` (the gcloud hash was computed once because Google
  publishes none);
- Azure CLI and OCI CLI by exact pip version, each in its own venv under `/opt`;
- all Jenkins plugins, including transitive dependencies, as `name:version` in
  `plugins.txt`;
- remove the duplicated `TERRAFORM_VERSION` from Compose so the `Dockerfile` ARG is the
  single source;
- `.dockerignore` excludes `casc/jenkins.yaml` so the secret never enters the build
  context.

**Reasoning:** reproducibility is a property of the artifact, not of discipline. A hash
turns "silently changed" into "build failed", which is the only reliable prompt to
review. Fully pinning plugins is the part usually skipped, yet it is where drift comes
from: `jenkins-plugin-cli` resolves transitive dependencies to the newest matching
version, so a direct-only pin still floats.

**Consequences:** bumping anything is a deliberate, reviewable edit; a Debian point
release breaks the apt pins until they are updated (documented, intentional); the image
is multi-GB because of `az`/`gcloud`, with per-cloud derived images as the escape hatch;
`az`/`oci` venvs add two more Python environments to keep in mind.

### ADR-008 — Jenkins state in a host bind mount instead of a Docker volume

Type: ADR | Status: Accepted | Date: 2026-10-21 | Owners: repository maintainer

**Context:** `$JENKINS_HOME` was in a named Compose volume. That volume is deleted by
`docker compose down -v`, and also by `docker system prune --volumes` while the
container is stopped. The requirement is that the state — build history, credentials,
the instance identity key — survives Docker operations and can be moved to another
server.

**Decision:** bind-mount a host directory:
`${JENKINS_HOME_DIR:-./data/jenkins_home}:/var/jenkins_home`. Locally that is
`./data/jenkins_home` (git-ignored); on a server `JENKINS_HOME_DIR` points outside the
checkout (`/srv/jenkins/home`, see `.env.example`). `make backup` / `make restore` /
`make reset` operate on that directory with plain `tar` and `rm`, behind confirmation
prompts.

**Reasoning:** a bind mount is the standard Docker answer when the operator must own
and inspect the files. It survives `down -v`, `prune --volumes`, Docker upgrades and
reinstalls; it is backed up by copying a directory; and it makes the deployment path
explicit, so a redeploy of the checkout cannot touch the state.

**Consequences:** the directory must be writable by uid `1000` (the container's
`jenkins` user), so a fresh server needs `chown -R 1000:1000`. `data/` and `.env` must
never be committed. Persistence stays per-machine: a new host starts empty and is
seeded with `make restore`, and backups must be copied off the machine. Verified by
running `docker compose down -v` and restarting: 9 jobs and the previous builds
survived.

Do not backfill invented history. Record decisions that are observed, expressly documented,
or approved during future work.

### ADR-009 — Stock controller image, toolchain only in the agent, demo SCM served over HTTP

Type: ADR | Status: Accepted | Date: 2026-10-21 | Owners: repository maintainer

**Context:** one image did everything: it carried the cloud toolchain, the plugin set and
the demo repository, and the controller built on itself. The controller was therefore the
hardest thing to rebuild, and "the machine that schedules" was coupled to "the machine that
runs pipelines".

**Decision:** three services.

- `jenkins` — the **stock** `jenkins/jenkins:lts-jdk17` image pinned by digest, with
  `numExecutors: 0` and no labels. Plugins are resolved at first boot from `plugins.txt`
  into the state directory (a marker file makes later boots skip it; `make plugins`
  refreshes). There is no controller `Dockerfile`.
- `agent` — built from `Dockerfile.agent` (`jenkins/inbound-agent`, same Debian release)
  with the toolchain, labels `terraform,linux,cloud`, connected over WebSocket. The node is
  declared in CasC (`jenkins.nodes`); `init/02-publish-agent-secret.groovy` publishes the
  generated JNLP secret to `data/agent-secret` and the agent entrypoint reads it (never as
  a command-line argument, so it stays out of `ps`).
- `git` — builds the demo repository at startup from the mounted project files and serves
  it over HTTP (dumb git protocol).

**Reasoning:** the controller should be the boring, replaceable part, and the toolchain
belongs where the builds happen. Serving the demo repo over HTTP removes the
`ALLOW_LOCAL_CHECKOUT` relaxation and removes the need for the controller to hold the
repository: lightweight checkout and multibranch indexing read the Jenkinsfile over HTTP.
Generating the repository at startup means editing a Jenkinsfile costs a `restart`, not an
image rebuild.

**Consequences:** the agent secret must be handed over, which is why the init script and
the entrypoint's retry loop exist — a controller restart rotates it and the agent
reconnects. Plugin installation moved from build time to first boot, so the pinned set
materialises in the state directory. The agent image is the only build, and the controller
image is upstream's. Verified: five example builds run with `node: agent-1`.

Do not backfill invented history. Record decisions that are observed, expressly documented,
or approved during future work.
