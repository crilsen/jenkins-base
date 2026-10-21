# Current Work

## Active

- None.

## Planned

- Add an OCI counterpart to the role examples (`example-oci-role`, instance/principal
  federation) now that the `oci` CLI is in the image.
- Run `example-parameters-approval` once to exercise the manual approval path.
- Fill the cloud role placeholders when they are actually tested:
  `aws-demo-role-arn`, `azure-demo-oidc-token`, `gcp-demo-oidc-token`.
- Optional: per-cloud derived images (`FROM jenkins-base:1.0`) if the 4.1 GB base
  becomes a problem.
- Optional hardening for anything shared: real agents instead of building on the
  controller, `matrix-auth` roles instead of `loggedInUsersCanDoAnything`, and dropping
  `ALLOW_LOCAL_CHECKOUT` in favour of real remotes.

## Blocked

- None.

## Completed

- 2026-10-21 — Split controller and agent (ADR-009): stock controller image with 0
  executors, toolchain in `Dockerfile.agent`, node declared in CasC with its secret
  published by an init script, demo repository built and served over HTTP by the `git`
  service (which removed the `ALLOW_LOCAL_CHECKOUT` relaxation). Five builds verified green
  on `agent-1`. Added `make agents` / `make plugins`; `make verify` now waits for the agent.

- 2026-10-21 — Context adopted; every `.ai/` placeholder replaced with observed facts.
- 2026-10-21 — CasC split by top-level key; three per-cloud role examples added.
- 2026-10-21 — Renamed to `jenkins-base` with the Compose project name pinned.
- 2026-10-21 — Example Jenkinsfiles added (`Jenkinsfile`, `examples/Jenkinsfile.*`,
  `examples/terraform/`) plus the single-branch, multibranch, basic,
  parameters/approval and terraform jobs.
- 2026-10-21 — Whole toolchain pinned (base digest, Debian packages, Terraform, AWS CLI,
  kubectl, helm, gcloud, az, oci, 70 plugins) with checksum verification.
- 2026-10-21 — State moved to a host bind mount; `make backup` / `restore` / `reset` and
  the `make secrets` / `verify` / `status` helpers added.
