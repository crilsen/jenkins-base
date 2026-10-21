# Project

## Identity

- **Name:** `jenkins-base`
- **Objective:** be the default local/on-prem Jenkins controller used to run Terraform
  pipelines against AWS, Azure, GCP, or on-prem targets, all driven from code.
- **Repository purpose:** a reusable Jenkins base — image, plugin set, CasC, and job
  catalogue — that a project inherits instead of rebuilding a controller per project.
  The one pipeline wired in today is `aws-waf-security`; the controller itself is
  cloud-agnostic. It is a local **baseline/demo**, not a production controller.
- **Status:** working local baseline; no automated tests and no CI pipeline of its own.

## Observed

- Single-container Jenkins: `Dockerfile` (Jenkins LTS JDK17 + pinned Terraform +
  AWS CLI v2) built and run by `docker-compose.yml`.
- One Multibranch Pipeline job (`aws-waf-security`, branch `main`, `scriptPath('Jenkinsfile')`)
  defined in `casc/jenkins.yaml`; the real file is git-ignored and
  `casc/jenkins.yaml.example` is the committed template.
- One credential: `waf-deploy-role-arn` (a role ARN string, not access keys).
- Three example jobs (`example-aws-role`, `example-azure-role`, `example-gcp-role`)
  demonstrate role assumption / workload identity federation per cloud, using only `aws`,
  `curl`, and `jq` — no extra plugins or CLIs. Their OIDC tokens are placeholders until an
  operator fills them in.
- `init/01-terraform-label.groovy` labels the controller `terraform` with 2 executors.
- Toolchain present on this machine: Docker 29.8.1, Compose v5.5.1, Terraform 1.16.1.
- The working directory is **not** a git repository (no `.git`), although `.gitignore`
  is present.
- Windows metadata sidecars (`*:Zone.Identifier`) exist next to most files; they are
  artifacts of copying from Windows and carry no project meaning.

## Not determined from repository

- Target users, expected lifetime of the demo, and whether it is a training aid or a
  pre-production rehearsal.
- The contents of the referenced `aws-waf-security` repository (`Jenkinsfile`,
  pipeline parameters, `docs/iam/` role permissions) — external to this repository.
- Any production Jenkins deployment, agent fleet, or shared CI standard.

## Priorities

- The controller must stay local-only and contain no long-lived AWS credentials.
- Terraform version is pinned so plans are reproducible.
- Reproducibility over features: keep the image small and the CasC declarative.
