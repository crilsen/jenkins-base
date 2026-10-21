# Tools

The rules behind these lists live in `.ai/GUARDRAILS.md`. Never store secrets here.

## Current availability (verified on this machine)

| Tool | Version | Notes |
| --- | --- | --- |
| Docker | 29.8.1 | usable by the current user without sudo (verified) |
| Docker Compose | v5.5.1 | `docker compose` subcommand |
| Terraform | 1.16.1 | host and image match |
| git | present | the working directory is **not** a git repository (no `.git`) |
| jq, python3, curl, unzip | present on host | also inside the image by design |

Inside the image (all pinned, see `Dockerfile` / `README.md`):

| Tool | How to call it | Use |
| --- | --- | --- |
| Terraform | `terraform` | IaC |
| AWS CLI v2 | `aws` | AWS, STS role assumption |
| kubectl | `kubectl` | Kubernetes (also `kubectl kustomize`) |
| helm | `helm` | chart lint/template/install |
| Google Cloud CLI | `gcloud` (on `PATH` via `/opt/google-cloud-sdk/bin`) | GCP, WIF |
| Azure CLI | `az` (venv `/opt/azure-cli`) | Azure, federated credentials |
| OCI CLI | `oci` (venv `/opt/oci-cli`) | Oracle Cloud |
| Python | `python3`, `python3 -m venv` | scripting; `yaml` available |

No MCP servers, credentials, or environment wrappers were found in the repository.
Authentication for AWS is the operator's `~/.aws`, mounted read-only into the container.

## Current runtime (verified 2026-10-21)

Three services: `jenkins-base` (stock image, 0 executors), `jenkins-base-agent` (built,
2 executors, labels `terraform,linux,cloud`) and `jenkins-base-git` (serves
`http://git:8080/repo.git`).

State is a bind mount at `data/jenkins_home` (or `$JENKINS_HOME_DIR`), not a Docker volume,
so `down -v` and `prune --volumes` cannot delete it. The Compose project name is pinned
(`name: jenkins-base`), so the container and network names do not depend on the checkout
directory.

## Allowed without additional authorization

- Read and search repository files.
- Make scoped, task-related edits to the Dockerfile, Compose file, `plugins.txt`, `casc/*`,
  `init/*`, `README.md`, and `.ai/`.
- `docker compose config`, `docker build`, syntax/YAML checks, `hadolint`/`shellcheck`
  when installed.
- Read-only inspection of a running instance: `docker compose ps|logs|exec … (version,
  curl api/json)`, `docker inspect`, `docker image ls`.
- Starting the stack locally for a smoke test and stopping it again with
  `docker compose down` (keeps the state directory), or `make up` / `make verify` /
  `make status`.
- Triggering a build of an `example-*` job **while its credential is still a placeholder**:
  it stops at the guard with `exit 78` before any network call, so it is a safe wiring test.
- Authenticated read calls (`api/json`, `crumbIssuer`) using the admin password read from
  `casc/jenkins.yaml` into a private temporary netrc file.
- Update this portable context.

## Requires explicit authorization

- `docker compose down -v` or any removal of the `jenkins_home` volume (irreversible: job
  history, credentials, builds).
- `docker system prune`, `docker rmi`, or deleting images/volumes.
- Triggering `Plan`/`Apply` in the Jenkins pipeline: it assumes a role and mutates real AWS
  resources (paid).
- `terraform apply` / `terraform destroy` anywhere.
- Editing, printing, or committing `casc/jenkins.yaml` (contains the admin password); it is
  git-ignored on purpose. Use `.example` for anything shareable.
- Changing the admin password, security realm, or authorization strategy.
- Exposing the controller beyond `127.0.0.1`, or adding a public port mapping.
- Removing files, including the `*:Zone.Identifier` sidecars (already done, with
  authorization) and unused template workflows.
- Running an `example-*` job with real credentials: it makes an external (read-only) call to
  AWS/Azure/GCP.

## MCP servers and external tools

None configured for this repository. If a harness adds one, record name, purpose, and the
read-only/mutating split here — never endpoints or tokens.

## Technology-specific guidance

| Technology | Usually safe | Restricted |
| --- | --- | --- |
| Docker / Compose | `config`, `build`, `up`, `ps`, `logs`, `exec` (read-only cmds), `down` | `down -v`, `prune`, `rm`, volume/image deletion |
| Jenkins | read `api/json`, read logs, `terraform version` in-container | config changes, job deletion, pipeline runs that touch AWS |
| Terraform (target repo) | `fmt`, `validate`, `plan` | `apply`, `destroy` |
| Shell / Groovy | `bash -n`, `shellcheck` | executing init scripts outside Jenkins |

## Notes

- The image downloads from `awscli.amazonaws.com` and `releases.hashicorp.com` at build
  time; builds therefore need network access and are not fully hermetic.
- `JENKINS_PORT` and `JENKINS_AGENT_PORT` are the only documented environment overrides.
