# Conventions

## Annotation language

- **Confirmed for this project:** English (code comments, `AGENTS.md`, `.ai/`, `README.md`).
  Recorded in `.ai/HANDOFF.md`. Re-confirm only if the user changes the preference.
- Existing files already follow this: the `Dockerfile`, `docker-compose.yml`, Groovy init
  script, and `README.md` all carry English comments.

## Observed conventions

### Docker and image

- Base image pinned by **digest** (`@sha256:…`), with the tag kept for readability.
- Tool versions that affect output are `ARG`-pinned in `Dockerfile` **and** verified
  against a SHA256 recorded in the same file (`echo "<hash>  <file>" | sha256sum -c -`).
  A changed upstream artifact must fail the build.
- The version lives only in the `Dockerfile`; `docker-compose.yml` no longer repeats
  `TERRAFORM_VERSION` (duplication was the previous drift risk).
- Debian packages are pinned as `name=version` in the `apt-get install` line.
  Superseded versions disappear from the pool, so a Debian point release requires
  bumping them — accepted trade for reproducibility.
- Jenkins plugins are pinned as a **fully resolved** set in `plugins.txt`; the
  regeneration command is in its header. Pinning only direct plugins leaves
  transitive dependencies floating.
- Python-based CLIs (`az`, `oci`) go into per-tool venvs under `/opt`, never into
  the system Python, with a symlink in `/usr/local/bin`.
- pip is **not** upgraded inside those venvs: `python3 -m venv` uses the pip from the
  pinned `python3-venv` package, which keeps the installer itself deterministic.
- `.dockerignore` excludes `casc/jenkins.yaml`, `.git`, `.ai`, and Terraform state,
  so the secret never reaches the build daemon.
- `USER root` only for the install block, then `USER jenkins`.
- `JAVA_OPTS` disables the setup wizard — the image is never configured by hand.

### Compose

- Image tagged with an explicit short version (`jenkins-base:1.0`).
- `container_name` matches the project name (`jenkins-base`), and the Compose
  project name is pinned with a top-level `name:` so it does not depend on the
  checkout directory.
- Host ports are interpolated with defaults (`${JENKINS_PORT:-8081}`) and always bound to
  `127.0.0.1`.
- Config and init directories are mounted `:ro`; only `jenkins_home` is writable state.
- Comments above a mount explain *why* it exists.

### Configuration as Code

- `casc/jenkins.yaml` is the live file and is git-ignored; `casc/jenkins.yaml.example` is
  the committed template. Never commit the real file, and never put a real password,
  account id, or ARN in the example — use placeholders like `<ACCOUNT_ID>`.
- Resources are named after their purpose (`waf-deploy-role-arn`, `terraform` label,
  `aws-waf-security` job) and job IDs mirror the git remote (`aws-waf-security-git`).
- **Split by top-level key:** `jenkins.yaml` owns `jenkins:` and `credentials:`;
  `jobs.yaml` owns `jobs:`. CasC files are supplementary and raise a conflict if two
  files define the same key, so never add a second `jobs:` or `credentials:` block.
- List the loaded files explicitly in `CASC_JENKINS_CONFIG` instead of pointing at the
  directory, so `jenkins.yaml.example` is never loaded.
- `systemMessage` states that the instance is a demo.

### Jobs and pipelines

- Jobs are declared in `casc/jobs.yaml`; pipeline bodies live in
  `casc/pipelines/<job>.groovy` and are loaded with `new File(pipelinesDir, …)`, where
  `pipelinesDir` comes from `CASC_PIPELINES_DIR` (default `/opt/casc/pipelines`). A
  missing file fails with an explicit message, not an opaque NPE.
- Example jobs are prefixed `example-`; the real pipeline job has no prefix.
- Pipelines set `agent { label 'terraform' }` and `options { timestamps() }`.
- Shell steps use `sh '''#!/bin/sh …'''` (single quotes, so `$` reaches the shell) with
  `set -eu`, `umask 077`, and `trap 'rm -f "$file"' EXIT` for anything holding a token.
- Fail fast on unconfigured inputs: `: "${VAR:?message}"` for required parameters, and an
  explicit `exit 78` when a credential still holds a placeholder.
- Never echo secrets: print an identity (`get-caller-identity`) or a small `jq` projection
  of the API response, never the token itself.
- On a failed token exchange, print the provider's `error_description` / `.error.message`
  instead of a bare status code.
- CasC resolves `${NAME}` inside `jobs: - script:` bodies as a secret/environment lookup, so
  the first boot logs `UnresolvedLookup` for any Groovy interpolation that is not an env
  var. Use `'a' + b` concatenation in those messages.
- `sh` steps run on dash, not bash: POSIX only, one name per `command -v`, no `[[ ]]`, no
  arrays.
- Never write three consecutive quotes inside a `sh '''…'''` body (a Python heredoc that
  mentions `'''` closes the Groovy string). Build the delimiter at runtime instead, and
  validate Jenkinsfiles by running them.
- The example jobs clone the image-baked repo `/opt/demo/repo.git`, which needs
  `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true` (demo-only) and means any edit to
  the Jenkinsfiles requires an image rebuild before a build sees it.

### Groovy init scripts

- Named `NN-description.groovy` (numeric prefix sets execution order).
- Each script starts with a comment explaining the decision and the production caveat.

### Documentation

- `README.md` is task-oriented: what it contains (table), prerequisites, run, run a build,
  security notes, clean up.
- Keep `AGENTS.md` short and route-oriented.
- Reference authoritative docs instead of copying them.
- Keep `TASKS.md` current-state only and `HANDOFF.md` operational, not a chat transcript.
- Treat `LEARNINGS.md` as a bounded, append-only buffer; promote durable learnings into
  `CONVENTIONS.md`, `DECISIONS.md`, `TOOLS.md`, or `VALIDATION.md`.
- Keep tool-specific files as thin adapters that only route to `AGENTS.md`; record their
  paths in `.ai/ADAPTERS.md`.
- Keep the Resume block in `HANDOFF.md` current as a rolling checkpoint and honor
  `.ai/LIMITS.md`.
- Only the primary agent writes `HANDOFF.md`, `TASKS.md`, and `LEARNINGS.md`.

## Recommended conventions (not yet adopted)

- Pin the base image by digest and verify downloaded archives with checksums.
- Add a `healthcheck` to the Compose service instead of relying on `restart`.
- Prefer a `docker-compose.override.yml` for machine-specific values (port, AWS profile).
- If this stops being a demo: attach a real agent (drop the controller label), replace
  `loggedInUsersCanDoAnything` with `matrix-auth` roles, and source the admin password
  from a secret store rather than CasC.
