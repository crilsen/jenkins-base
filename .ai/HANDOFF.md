# Session Handoff

## Resume block (read first)

- Repo state: git repository; see `git log -1` for the current commit.
- Source of truth: `AGENTS.md` → `.ai/`
- Budget / usage observed: `unknown` (not exposed to the agent)
- Checkpoint updated: `2026-10-21`
- Last goal: bring the repository to a shareable baseline — pinned toolchain, CasC
  split, example jobs, host bind mount for state, and a Makefile.
- Annotation language: `English` (standing preference: yes)
- Exact next action: none pending; pick work from `.ai/TASKS.md`.
- Blocked by: `None.`
- Resume prompt: `Read AGENTS.md and .ai/HANDOFF.md. Continue from the Resume block. Do not rediscover context.`

## Goal

A template Jenkins controller that is reproducible from text, demonstrates credential
acquisition per cloud without static keys, and keeps its state independent of Docker's
volume lifecycle.

## Current State

- Image `jenkins-base:1.0` (4.07 GB), fully pinned (ADR-007): base digest, Debian
  packages, Terraform 1.16.1, AWS CLI 2.38.4, kubectl v1.37.1, helm v4.3.1,
  gcloud 590.0.0, az 2.91.0, oci 3.95.1, 70 plugins.
- CasC split: `casc/jenkins.yaml` (git-ignored; `jenkins:` + `credentials:`) and
  `casc/jobs.yaml` (tracked; `jobs:`).
- Nine jobs, including three cloud role examples and five SCM/pipeline-style examples.
- State is a host directory (`data/jenkins_home`, or `$JENKINS_HOME_DIR`), with
  `make backup` / `make restore` / `make reset`.
- Makefile targets: `help`, `secrets`, `build`, `up`, `start`, `down`, `restart`,
  `logs`, `shell`, `status`, `verify`, `tools`, `jobs`, `backup`, `restore`, `reset`.

## What Was Done

- Adopted the `.ai/` context and replaced every placeholder with observed facts.
- Split CasC by top-level key; added the AWS/Azure/GCP role examples and the
  single-branch/multibranch/basic/parameters/terraform examples.
- Pinned the whole toolchain and added the Kubernetes, OCI, Google and Azure CLIs.
- Moved state to a bind mount and proved `docker compose down -v` no longer loses it.
- Added `Makefile`, `scripts/`, `.env.example`, `.dockerignore`.

## Files Changed

See `git log`. Nothing is left uncommitted.

## Decisions Made

ADR-001 … ADR-008 in `.ai/DECISIONS.md`: single-container controller, CasC split with a
committed example, no static AWS credentials, pinned Terraform, portable agent context,
per-cloud role examples, reproducible image, and the bind-mounted state.

## Problems / Risks

- `ALLOW_LOCAL_CHECKOUT=true` is required by the offline example repository and lets any
  job clone a local path — acceptable only for a loopback-only demo.
- The example Jenkinsfiles are snapshotted into the image, so editing one requires a
  rebuild before a build sees it.
- Pinned plugins only take effect on a volume/directory that does not already contain
  them; an upgraded plugin needs the state directory recreated or that plugin removed.
- apt pins go stale after a Debian point release (intentional, documented).
- The Azure and GCP role examples are unproven with real tokens; the WAF pipeline itself
  is not run here.

## Validation Performed

- Image build with checksum verification; every CLI at its pinned version. **Validated.**
- CasC creates all nine jobs; `make verify` → `jobs: 9`. **Validated.**
- Builds `example-single-branch`, `example-basic`, `example-terraform`,
  `multibranch/main`, `multibranch/feature/demo` → **SUCCESS**. **Validated.**
- `make backup` (338 MB) and `make restore` rehearsal. **Validated.**
- `docker compose down -v` → state, jobs and build history survived. **Validated.**
- Not run: role examples with real cloud tokens, `example-parameters-approval`, the WAF
  pipeline, and a deploy on a second machine.

## Next Actions

- Add an OCI counterpart to the role examples (`example-oci-role`).
- Run `example-parameters-approval` once to exercise the manual approval path.
- Optional: per-cloud derived images if the 4.1 GB base becomes a problem.
