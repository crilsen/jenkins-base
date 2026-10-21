# Pinned base image. The tag stays for readability; the digest is the actual pin,
# so a re-tagged lts-jdk17 cannot silently change this image.
FROM jenkins/jenkins:lts-jdk17@sha256:cce1eeb79902722f3cf7a8831c41e95c39f4a42b9a2981959630cc66539b3c2d

USER root

# ---------------------------------------------------------------------------
# Pinned versions. One place to bump; the matching checksum makes a changed
# upstream artifact fail the build instead of silently changing the image.
# `sha256sum -c` is used everywhere a checksum is available.
# ---------------------------------------------------------------------------
ARG TERRAFORM_VERSION=1.16.1
ARG TERRAFORM_SHA256=745d33b4b02b7980c62a38ec1beea24ee084ea8caf3f503c200554bd9a0cbe49

ARG AWSCLI_VERSION=2.38.4
ARG AWSCLI_SHA256=10ab32a95b27138d7cc1c1ac4ebb4d3acab60cd0a0df2fc37c4e2c440ed40bce

ARG KUBECTL_VERSION=v1.37.1
ARG KUBECTL_SHA256=65691ff77eb6fa44c908b77a1082c9f092c3b9733b5cefabec0d1104890e21a8

ARG HELM_VERSION=v4.3.1
ARG HELM_SHA256=0403a88ae20913d11b10a2467b50087721fea7581736da6b9d3992f5357fe54b

ARG GCLOUD_VERSION=590.0.0
ARG GCLOUD_SHA256=1503a6fcda689d1e1013a421e2c85850e7f58382c0be7064877b5e1a1038bc64

ARG AZURE_CLI_VERSION=2.91.0
ARG OCI_CLI_VERSION=3.95.1

# Base OS packages, pinned to the versions published for the pinned base image.
# Debian drops superseded versions from the pool, so a bump is required after a
# point release; that is the intended trade for reproducibility.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      ca-certificates=20250419+deb13u1 \
      curl=8.14.1-2+deb13u7 \
      unzip=6.0-29+deb13u1 \
      jq=1.7.1-6+deb13u4 \
      git=1:2.47.3-0+deb13u1 \
      python3=3.13.5-1 \
      python3-venv=3.13.5-1 \
      python3-yaml=6.0.2-1+b2 \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/*

# Terraform, AWS CLI v2, kubectl and helm: single static artifacts, verified
# against the checksum recorded above before anything is installed.
RUN set -eux; \
    curl -fsSL -o /tmp/terraform.zip \
      "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip"; \
    echo "${TERRAFORM_SHA256}  /tmp/terraform.zip" | sha256sum -c -; \
    unzip -q /tmp/terraform.zip -d /usr/local/bin; \
    chmod +x /usr/local/bin/terraform; \
    rm -f /tmp/terraform.zip; \
    \
    curl -fsSL -o /tmp/awscliv2.zip \
      "https://awscli.amazonaws.com/awscli-exe-linux-x86_64-${AWSCLI_VERSION}.zip"; \
    echo "${AWSCLI_SHA256}  /tmp/awscliv2.zip" | sha256sum -c -; \
    unzip -q /tmp/awscliv2.zip -d /tmp; \
    /tmp/aws/install; \
    rm -rf /tmp/aws /tmp/awscliv2.zip; \
    \
    curl -fsSL -o /usr/local/bin/kubectl \
      "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"; \
    echo "${KUBECTL_SHA256}  /usr/local/bin/kubectl" | sha256sum -c -; \
    chmod +x /usr/local/bin/kubectl; \
    \
    curl -fsSL -o /tmp/helm.tar.gz \
      "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"; \
    echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/helm.tar.gz -C /tmp; \
    install -m 0755 /tmp/linux-amd64/helm /usr/local/bin/helm; \
    rm -rf /tmp/helm.tar.gz /tmp/linux-amd64

# Google Cloud CLI: a self-contained tarball. Google does not publish a checksum
# file for it, so the hash above was computed from the pinned version once and is
# verified on every build.
RUN set -eux; \
    curl -fsSL -o /tmp/gcloud.tar.gz \
      "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${GCLOUD_VERSION}-linux-x86_64.tar.gz"; \
    echo "${GCLOUD_SHA256}  /tmp/gcloud.tar.gz" | sha256sum -c -; \
    tar -xzf /tmp/gcloud.tar.gz -C /opt; \
    /opt/google-cloud-sdk/install.sh --quiet --usage-reporting false \
      --path-update false --command-completion false; \
    rm -f /tmp/gcloud.tar.gz

ENV PATH=/opt/google-cloud-sdk/bin:$PATH

# Azure CLI and OCI CLI are Python applications. Each gets its own venv so their
# dependencies cannot fight with the system Python, and pip comes from the pinned
# Debian python3-venv package (no `pip install --upgrade pip`, which would float).
RUN set -eux; \
    python3 -m venv /opt/azure-cli; \
    /opt/azure-cli/bin/pip install --no-cache-dir "azure-cli==${AZURE_CLI_VERSION}"; \
    ln -s /opt/azure-cli/bin/az /usr/local/bin/az; \
    \
    python3 -m venv /opt/oci-cli; \
    /opt/oci-cli/bin/pip install --no-cache-dir "oci-cli==${OCI_CLI_VERSION}"; \
    ln -s /opt/oci-cli/bin/oci /usr/local/bin/oci

# Fully resolved and pinned plugin set (see the header in plugins.txt).
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Snapshot of this project's pipelines, used as the SCM source for the example
# jobs. `casc/jenkins.yaml` is deliberately NOT copied: it holds the admin
# password and the real role ARN (also excluded through .dockerignore).
COPY Jenkinsfile /opt/demo/src/Jenkinsfile
COPY examples /opt/demo/src/examples
COPY casc/jobs.yaml /opt/demo/src/casc/jobs.yaml
COPY casc/jenkins.yaml.example /opt/demo/src/casc/jenkins.yaml.example
COPY casc/pipelines /opt/demo/src/casc/pipelines
COPY docker-compose.yml /opt/demo/src/docker-compose.yml

# Make it a repository with two branches. Built here instead of fetched so the
# examples work offline, and owned by `jenkins` because git refuses repositories
# owned by another user (dubious ownership).
RUN git init -q /opt/demo/src \
 && git -C /opt/demo/src add -A \
 && git -C /opt/demo/src -c user.name=jenkins -c user.email=jenkins@localhost \
      commit -qm "demo: initial branch" \
 && git -C /opt/demo/src branch -M main \
 && git -C /opt/demo/src checkout -q -b feature/demo \
 && git -C /opt/demo/src -c user.name=jenkins -c user.email=jenkins@localhost \
      commit -q --allow-empty -m "demo: second branch" \
 && git -C /opt/demo/src checkout -q main \
 && git clone -q --bare /opt/demo/src /opt/demo/repo.git \
 && chown -R jenkins:jenkins /opt/demo

USER jenkins

# ALLOW_LOCAL_CHECKOUT is required because the example jobs clone the offline repo
# baked into this image (/opt/demo/repo.git). It lets any job clone a local path, so
# it is acceptable only on a single-operator demo controller — drop it and point the
# examples at a real remote before sharing this instance.
ENV JAVA_OPTS="-Djenkins.install.runSetupWizard=false -Djenkins.model.Jenkins.slaveAgentPort=50000 -Dhudson.plugins.git.GitSCM.ALLOW_LOCAL_CHECKOUT=true"
ENV CASC_JENKINS_CONFIG=/opt/casc/jenkins.yaml,/opt/casc/jobs.yaml
