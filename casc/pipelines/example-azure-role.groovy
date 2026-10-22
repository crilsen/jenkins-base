// Example 2/3 — Entra ID (Azure) workload identity: exchange an OIDC token for
// an access token and read one subscription back.
//
// There is no "role" object in Azure; the equivalent of assuming a role is a
// service principal whose federated credential trusts an OIDC issuer. The token
// must carry the audience `api://AzureADTokenExchange`.
//
// In a real workload-identity setup the platform injects the token as a file
// (AZURE_FEDERATED_TOKEN_FILE on AKS/Azure-hosted agents). This local demo has no
// such platform, so the token is supplied by the Jenkins secret credential
// `azure-demo-oidc-token` to show the exchange itself.
//
// Requires: curl and jq (both in the image). No Azure CLI needed.

pipeline {
  agent { label 'terraform' }
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30', artifactNumToKeepStr: '5'))
  }

  parameters {
    string(name: 'TENANT_ID', defaultValue: '',
           description: 'Entra ID tenant id (GUID).')
    string(name: 'CLIENT_ID', defaultValue: '',
           description: 'App registration (client) id carrying the federated credential.')
    string(name: 'SUBSCRIPTION_ID', defaultValue: '',
           description: 'Subscription read back to prove the token works.')
  }

  stages {
    stage('Federated credential exchange') {
      steps {
        withCredentials([string(credentialsId: 'azure-demo-oidc-token', variable: 'OIDC_TOKEN')]) {
          sh '''#!/bin/sh
set -eu

: "${TENANT_ID:?set the TENANT_ID parameter (Entra ID tenant id)}"
: "${CLIENT_ID:?set the CLIENT_ID parameter (app registration id)}"
: "${SUBSCRIPTION_ID:?set the SUBSCRIPTION_ID parameter}"

case "$OIDC_TOKEN" in
  ""|*"<"*|*REPLACE_ME*)
    echo "credential 'azure-demo-oidc-token' still holds a placeholder; paste an OIDC token (aud api://AzureADTokenExchange) in casc/jenkins.yaml" >&2
    exit 78
    ;;
esac

# Keep the assertion out of the process list: build the form in a private file.
umask 077
form=$(mktemp)
trap 'rm -f "$form"' EXIT

{
  printf 'client_id=%s' "$CLIENT_ID"
  printf '&scope=%s' 'https://management.azure.com/.default'
  printf '&grant_type=client_credentials'
  printf '&client_assertion_type=%s' 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
  printf '&client_assertion=%s' "$OIDC_TOKEN"
} > "$form"

resp=$(curl -sS -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  --data "@${form}")

access_token=$(printf '%s' "$resp" | jq -r '.access_token // empty')
if [ -z "$access_token" ]; then
  echo "token exchange failed:" >&2
  printf '%s' "$resp" | jq -r '.error_description // .error // .' >&2
  exit 1
fi

curl -sS -H "Authorization: Bearer ${access_token}" \
  "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}?api-version=2022-12-01" \
  | jq -c 'if .error then {error: .error.code, message: .error.message}
           else {subscriptionId, displayName, state} end'
'''
        }
      }
    }
  }
}
