# Learnings

Append-only buffer of reusable, non-obvious learnings captured while working, so future sessions and tools do not rediscover them. This is not task state (`TASKS.md`), not a session handoff (`HANDOFF.md`), and not a durable decision record (`DECISIONS.md`).

## How to use

- Append one entry per learning. Do not rewrite or delete entries; to correct one, mark it `superseded` and add a new entry.
- Capture only learnings that are non-obvious and likely to recur. Skip anything already stated in `CONVENTIONS.md`, `DECISIONS.md`, `TOOLS.md`, or `VALIDATION.md`.
- Keep each entry short and evidence-based. Prefer `observed` facts over speculation.
- This file is a buffer, not a permanent home: promote durable learnings and keep the entry as a breadcrumb.

## Entry format

```text
### L-001 — <short title>
Date: YYYY-MM-DD
Status: active | superseded | promoted
Confidence: observed | inferred
Scope: repo | <path-or-glob> | <technology>
Context: <what was being done>
Evidence: <file:line, command output, or concrete observation>
Pattern / rule: <the reusable takeaway>
Promotion: none | CONVENTIONS.md | DECISIONS.md#ADR-nnn | TOOLS.md | VALIDATION.md
```

## Promotion rules

- Recurring pattern → `CONVENTIONS.md`
- Durable architectural choice → `DECISIONS.md` (ADR), cross-referenced here
- Safe or restricted command rule → `TOOLS.md`
- Completion or validation check → `VALIDATION.md`

After promotion, set the entry to `Status: promoted` and keep it as a breadcrumb; do not duplicate the rule body.

## Compaction

- Keep at most 40 active entries. When exceeded, consolidate related entries, promote what is durable, and mark the rest `superseded`.
- Compaction means summarizing and promoting, not erasing history. Record the compaction in `HANDOFF.md`.

## Entries

### L-001 — The repository is not a git checkout
Date: 2026-10-21
Status: active
Confidence: observed
Scope: repo
Context: adopting the `.ai/` template and trying to record branch/HEAD in the handoff.
Evidence: `git rev-parse --is-inside-work-tree` → `fatal: not a git repository`; no `.git` directory, but `.gitignore` exists.
Pattern / rule: do not attempt commits, `git diff`, or branch-based resume steps here; describe the working tree as files on disk.
Promotion: none

### L-002 — `*:Zone.Identifier` sidecars exist next to every file
Date: 2026-10-21
Status: active
Confidence: observed
Scope: `**/*:Zone.Identifier`
Context: listing the repository.
Evidence: e.g. `AGENTS.md:Zone.Identifier`, `.ai/PROJECT.md:Zone.Identifier`, created 2026-10-21 16:13 while the real files date from Oct 1.
Pattern / rule: these are Windows download metadata, not project files. Ignore them in searches and never treat their presence as content changes; removal needs user authorization.
Promotion: none

### L-003 — `TERRAFORM_VERSION` is duplicated between Dockerfile and Compose
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `Dockerfile`, `docker-compose.yml`
Context: reading the build definition.
Evidence: `Dockerfile:6` `ARG TERRAFORM_VERSION=1.16.1`; `docker-compose.yml:6` `TERRAFORM_VERSION: "1.16.1"`.
Pattern / rule: bump both together; a mismatch silently changes the effective build arg without any error.
Promotion: VALIDATION.md

### L-004 — Jenkins home state is only in the `jenkins_home` volume
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `docker-compose.yml`
Context: assessing how destructive a cleanup is.
Evidence: `docker-compose.yml:13` mounts the named volume at `/var/jenkins_home`; `README.md:81` documents `down -v` as deleting it.
Pattern / rule: `docker compose down` is safe; `down -v` destroys jobs, credential and build history. Treat volume deletion as irreversible.
Promotion: TOOLS.md

### L-005 — The template's `.ai/` files referenced paths that do not exist here
Date: 2026-10-21
Status: active
Confidence: observed
Scope: `.ai/`
Context: replacing placeholders.
Evidence: `DECISIONS.md` pointed to `../docs/design.md`; `SPECS.md` and `REQUIREMENTS.md` reference `docs/spec/` and `docs/prd/`, and there is no `docs/` directory.
Pattern / rule: the context was copied from the `ai-agent-relay` template repository; do not assume referenced `docs/` files exist until a change creates them.
Promotion: none

### L-006 — CasC files are supplementary: one top-level key per file
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `casc/`
Context: splitting job definitions out of the secret-bearing `jenkins.yaml`.
Evidence: Jenkins docs (`/doc/book/managing/casc/`): "all configuration files that are discovered MUST be supplementary. If a file attempts to overwrite configuration values from another file, it creates a conflict and raises a ConfiguratorException"; `CASC_JENKINS_CONFIG` accepts a comma-separated list.
Pattern / rule: never split `jobs:`/`credentials:` across two CasC files, and list files explicitly instead of pointing at the directory (the directory scan would also load `jenkins.yaml.example`).
Promotion: CONVENTIONS.md, DECISIONS.md#ADR-005

### L-007 — A running container may come from a different checkout
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: runtime
Context: checking whether context changes had reached the live instance.
Evidence: `docker inspect <container>` showed a compose project and `casc`/`init` mounts pointing at a directory other than the one being edited, and a container/image name different from the compose file in hand.
Pattern / rule: editing files here does not reconfigure a controller started elsewhere. Check `docker inspect <container>` (compose project, config file, mounts) before claiming a runtime effect.
Promotion: TOOLS.md

### L-008 — Escape hell in nested CasC/Job DSL/Pipeline/Groovy/sh
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `casc/jobs.yaml`, `casc/pipelines/`
Context: writing pipeline definitions inside a CasC YAML block.
Evidence: YAML literal block → Job DSL Groovy → `script('…')` → declarative pipeline → `sh '''…'''`; shell `$` must survive three layers.
Pattern / rule: keep pipeline bodies in separate `.groovy` files read with `new File(dir, name).text`; use `'''` for shell blocks (literal `$`) and `"""` only where Groovy interpolation is wanted. Never nest `'''` inside `'''`.
Promotion: CONVENTIONS.md

### L-009 — CasC also interpolates `${...}` inside job DSL scripts
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `casc/*.yaml`
Context: first boot logged `SecretSourceResolver$UnresolvedLookup: Found unresolved variable 'file'`.
Evidence: `casc/jobs.yaml` had `"Pipeline script not found: ${file}."`; after rewriting it as string concatenation, `docker logs --since … | grep -c unresolved` returned 0 following a reload.
Pattern / rule: in CasC, `${NAME}` is treated as a secret/environment lookup even inside a `jobs: - script:` body. Use `+` concatenation (or `$${...}`) instead of Groovy interpolation when the value is not an env var.
Promotion: CONVENTIONS.md

### L-010 — Jenkins POSTs need a session-bound crumb, not just basic auth
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: runtime / API
Context: triggering a build and reloading CasC from curl.
Evidence: `curl --netrc-file` GET `/api/json` → 200; POST with a crumb fetched in a separate request → `403 No valid crumb was included`; adding `-c jar`/`-b jar` around both calls → reload 302, build 201.
Pattern / rule: fetch the crumb and POST while sharing a cookie jar (`-c jar -b jar --netrc-file netrc`), and send the `Jenkins-Crumb` header. Basic auth alone is enough for GET only.
Promotion: VALIDATION.md

### L-011 — `command -v a b c` is bash-only
Date: 2026-10-21
Status: active
Confidence: observed
Scope: `sh` steps
Context: checking image tooling with `docker exec … sh -c 'command -v aws jq curl'`.
Evidence: dash printed only the first tool; looping per tool showed all present.
Pattern / rule: in POSIX `sh` (dash in the image), test one name per `command -v`. Pipelines using `sh` must assume dash, not bash — no `[[ ]]`, no arrays.
Promotion: none

### L-012 — The git plugin refuses local checkouts by default
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `Dockerfile`, job SCM config
Context: the example jobs clone `/opt/demo/repo.git` from inside the image.
Evidence: build log: "Checkout of Git remote '/opt/demo/repo.git' aborted because it references a local directory, which may be insecure … set 'hudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT' to true" (git plugin 5.11.0). Adding the property to `JAVA_OPTS` fixed all five builds.
Pattern / rule: for an offline demo repo, add `-Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true` and document that it is demo-only. For anything shared, serve the repo over HTTP/SSH instead.
Promotion: CONVENTIONS.md, README.md

### L-013 — Multibranch child jobs live under `branches/`, not `jobs/`
Date: 2026-10-21
Status: active
Confidence: observed
Scope: runtime
Context: checking whether the multibranch scan had created its branches.
Evidence: `$JENKINS_HOME/jobs/example-multibranch/branches/{main,feature-demo.*}/{config.xml,builds}`; `…/jobs` is empty. The REST API (`/job/example-multibranch/api/json?tree=jobs[name]`) correctly lists `main` and `feature%2Fdemo`.
Pattern / rule: inspect multibranch children through the API (`curl -g` to stop globbing the `[]`), not by listing `jobs/` on disk.
Promotion: none

### L-014 — A literal three-quote sequence inside a nested heredoc breaks Groovy
Date: 2026-10-21
Status: promoted
Confidence: observed
Scope: `Jenkinsfile`
Context: the self-check pipeline extracts `sh '''…'''` blocks with Python embedded in a `sh '''…'''` block.
Evidence: `WorkflowScript: 75: expecting anything but ''\n''` at runtime; the file parsed fine as standalone Python, so only Jenkins caught it.
Pattern / rule: never write three consecutive quotes inside a `sh '''…'''` body; build the delimiter at runtime (`q3 = "'" * 3`). Validate Jenkinsfiles by running them, not only by reading them.
Promotion: CONVENTIONS.md

### L-015 — The demo repo is baked into the image
Date: 2026-10-21
Status: active
Confidence: observed
Scope: `Dockerfile`
Context: iterating on `Jenkinsfile` / `examples/*` while the jobs clone `/opt/demo/repo.git`.
Evidence: a fix to the root `Jenkinsfile` had no effect on builds until the image was rebuilt and the container recreated.
Pattern / rule: expect a rebuild (`docker compose build && up -d`) after any edit under `Jenkinsfile`, `examples/`, `casc/jobs.yaml`, `casc/jenkins.yaml.example`, `casc/pipelines/`, or `docker-compose.yml`, because those are copied into the snapshot.
Promotion: none
