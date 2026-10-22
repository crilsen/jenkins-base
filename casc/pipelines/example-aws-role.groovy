// Example 1/3 — assume an IAM role with STS and prove the identity.
//
// No static keys anywhere:
//   * the base identity comes from the operator's ~/.aws, mounted read-only at
//     $JENKINS_HOME/.aws;
//   * the role ARN comes from the Jenkins credential `aws-demo-role-arn`;
//   * the resulting credentials are temporary and live only inside this shell.
//
// Requires: aws CLI (in the image), jq (in the image).

pipeline {
  agent { label 'terraform' }
  options {
    timestamps()
    buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30', artifactNumToKeepStr: '5'))
  }

  parameters {
    string(name: 'AWS_REGION', defaultValue: 'us-east-1',
           description: 'Region for the STS call.')
    string(name: 'SESSION_NAME', defaultValue: 'jenkins-demo',
           description: 'Role session name; it shows up in CloudTrail.')
    string(name: 'DURATION_SECONDS', defaultValue: '900',
           description: 'Lifetime of the temporary credentials (900-43200).')
  }

  environment {
    AWS_REGION        = "${params.AWS_REGION}"
    SESSION_NAME      = "${params.SESSION_NAME}"
    DURATION_SECONDS  = "${params.DURATION_SECONDS}"
  }

  stages {
    stage('Assume role (STS)') {
      steps {
        withCredentials([string(credentialsId: 'aws-demo-role-arn', variable: 'ROLE_ARN')]) {
          sh '''#!/bin/sh
set -eu

case "$ROLE_ARN" in
  ""|*"<ACCOUNT_ID>"*|*REPLACE_ME*)
    echo "credential 'aws-demo-role-arn' still holds a placeholder; set the real ARN in casc/jenkins.yaml" >&2
    exit 78
    ;;
esac

umask 077
creds=$(mktemp)
trap 'rm -f "$creds"' EXIT

aws sts assume-role \
  --role-arn "$ROLE_ARN" \
  --role-session-name "$SESSION_NAME" \
  --duration-seconds "$DURATION_SECONDS" \
  --output json > "$creds"

AWS_ACCESS_KEY_ID=$(jq -r '.Credentials.AccessKeyId' "$creds")
AWS_SECRET_ACCESS_KEY=$(jq -r '.Credentials.SecretAccessKey' "$creds")
AWS_SESSION_TOKEN=$(jq -r '.Credentials.SessionToken' "$creds")
export AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Prove the assumption. Only the ARN is printed, never the keys.
aws sts get-caller-identity --output json \
  | jq -c '{arn: .Arn, account: .Account, userId: .UserId}'
'''
        }
      }
    }
  }
}
