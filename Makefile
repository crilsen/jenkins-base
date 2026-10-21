# jenkins-base — make targets
#
# `make up` always builds first: Compose otherwise silently reuses the old
# jenkins-base:1.0 image after a Dockerfile edit (the tag never changes).
#
# State lives in ${JENKINS_HOME_DIR:-./data/jenkins_home} — a plain host directory,
# so `docker compose down -v` cannot delete it.
SHELL := /bin/sh
COMPOSE := docker compose
PORT ?= 8082
AGENT_PORT ?= 50001
IMAGE ?= jenkins-base:1.0

.DEFAULT_GOAL := help

.PHONY: help secrets build up start down restart logs shell status verify tools jobs backup restore reset

help: ## show this help
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed 's/:.*## /  →  /'

secrets: ## create casc/jenkins.yaml from the example with a random admin password
	@if [ -f casc/jenkins.yaml ]; then \
	  echo "casc/jenkins.yaml exists — left untouched"; \
	else \
	  PASS=$$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 16); \
	  sed "s/password: \"change-me\"/password: \"$$PASS\"/" casc/jenkins.yaml.example > casc/jenkins.yaml; \
	  echo "created casc/jenkins.yaml"; \
	  echo "admin password: $$PASS   (store it in a password manager)"; \
	fi

build: ## build the image (pulls the base tag first)
	$(COMPOSE) build --pull

up: secrets build ## secrets + build + start (use after editing any image file)
	JENKINS_PORT=$(PORT) JENKINS_AGENT_PORT=$(AGENT_PORT) $(COMPOSE) up -d

start: ## start the existing image without rebuilding (fast)
	JENKINS_PORT=$(PORT) JENKINS_AGENT_PORT=$(AGENT_PORT) $(COMPOSE) up -d

down: ## stop the container; keeps the state directory
	$(COMPOSE) down

restart: ## stop + start without rebuilding
	$(COMPOSE) down
	JENKINS_PORT=$(PORT) JENKINS_AGENT_PORT=$(AGENT_PORT) $(COMPOSE) up -d

logs: ## follow the controller log
	$(COMPOSE) logs -f --tail=100 jenkins

shell: ## shell inside the container as the jenkins user
	docker exec -it jenkins-base sh

status: ## container state + size of the state directory
	@$(COMPOSE) ps
	@printf 'state: '; du -sh "$${JENKINS_HOME_DIR:-./data/jenkins_home}" 2>/dev/null | cut -f1 || echo "absent"

verify: ## wait for Jenkins, then check the API and the job count
	@./scripts/verify.sh

tools: ## print the pinned tool versions inside the image
	docker run --rm --entrypoint sh $(IMAGE) -c '\
	  terraform version | head -1; aws --version; kubectl version --client | head -1; \
	  helm version --short; gcloud --version | head -1; oci --version; az version | head -3; \
	  python3 --version'

jobs: ## list jobs through the API (needs the admin password)
	@./scripts/jobs.sh

backup: ## snapshot the state directory into backups/
	@./scripts/backup.sh

restore: ## restore a backup (make restore FILE=backups/...) — destructive
	@./scripts/restore.sh "$(FILE)"

reset: ## delete the state directory — destructive
	@./scripts/reset.sh
