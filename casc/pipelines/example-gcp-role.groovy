// Example 3/3 — GCP Workload Identity Federation: exchange an OIDC token for a
// federated token, then impersonate a service account (GCP's "role" step) and
// read one project back.
//
// As with Azure, a real workload-identity deployment injects the token from the
// platform. Here the Jenkins secret credential `gcp-demo-oidc-token` supplies it
// so the exchange itself is visible.
//
// Requires: curl and jq (both in the image). No gcloud needed.

pipeline {
  agent { label 'terraform' }
  options { timestamps() }

  parameters {
    string(name: 'WIF_AUDIENCE', defaultValue: '',
           description: 'projects/<number>/locations/global/workloadIdentityPools/<pool>/providers/<provider>')
    string(name: 'SERVICE_ACCOUNT', defaultValue: '',
           description: 'Service account email to impersonate.')
    string(name: 'PROJECT_ID', defaultValue: '',
           description: 'Project read back to prove the token works.')
  }

  stages {
    stage('WIF token exchange') {
      steps {
        withCredentials([string(credentialsId: 'gcp-demo-oidc-token', variable: 'OIDC_TOKEN')]) {
          sh '''#!/bin/sh
set -eu

: "${WIF_AUDIENCE:?set the WIF_AUDIENCE parameter}"
: "${SERVICE_ACCOUNT:?set the SERVICE_ACCOUNT parameter}"
: "${PROJECT_ID:?set the PROJECT_ID parameter}"

case "$OIDC_TOKEN" in
  ""|*"<"*|*REPLACE_ME*)
    echo "credential 'gcp-demo-oidc-token' still holds a placeholder; paste an OIDC token in casc/jenkins.yaml" >&2
    exit 78
    ;;
esac

umask 077
body=$(mktemp)
resp=$(mktemp)
trap 'rm -f "$body" "$resp"' EXIT

jq -n --arg aud "$WIF_AUDIENCE" --arg tok "$OIDC_TOKEN" '{
  audience:           $aud,
  grantType:          "urn:ietf:params:oauth:grant-type:token-exchange",
  requestedTokenType: "urn:ietf:params:oauth:token-type:access_token",
  subjectTokenType:   "urn:ietf:params:oauth:token-type:jwt",
  subjectToken:       $tok
}' > "$body"

curl -sS -X POST https://sts.googleapis.com/v1/token \
  -H 'Content-Type: application/json' \
  --data "@${body}" > "$resp"

federated=$(jq -r '.access_token // empty' "$resp")
if [ -z "$federated" ]; then
  echo "WIF token exchange failed:" >&2
  jq -r '.error_description // .error.message // .error // .' "$resp" >&2
  exit 1
fi

# Impersonate the service account: this is the step that grants the actual role.
printf '{"scope":["https://www.googleapis.com/auth/cloud-platform"]}' > "$body"

curl -sS -X POST \
  "https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/${SERVICE_ACCOUNT}:generateAccessToken" \
  -H "Authorization: Bearer ${federated}" \
  -H 'Content-Type: application/json' \
  --data "@${body}" > "$resp"

sa_token=$(jq -r '.accessToken // empty' "$resp")
if [ -z "$sa_token" ]; then
  echo "service account impersonation failed:" >&2
  jq -r '.error.message // .error // .' "$resp" >&2
  exit 1
fi

curl -sS -H "Authorization: Bearer ${sa_token}" \
  "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}" \
  | jq -c 'if .error then {error: .error.status, message: .error.message}
           else {projectId, projectNumber, lifecycleState} end'
'''
        }
      }
    }
  }
}
