// Self-check pipeline for this repository.
//
// It is what the single-branch and multibranch example jobs run: it validates the
// files a change to this project touches, without needing credentials or network.
// Keep it runnable on the controller label `terraform`.

pipeline {
  agent { label 'terraform' }
  options {
    timestamps()
    // Retention: without this a job grows forever. See the README.
    buildDiscarder(logRotator(numToKeepStr: '20', daysToKeepStr: '30', artifactNumToKeepStr: '5'))
  }

  environment {
    TF_IN_AUTOMATION = '1'
  }

  stages {
    stage('Context') {
      steps {
        sh '''#!/bin/sh
set -eu

echo "branch:    ${BRANCH_NAME:-<none: single-branch job has no BRANCH_NAME>}"
echo "build:     ${BUILD_NUMBER:-?}"
echo "node:      ${NODE_NAME:-?}"
echo "workspace: ${WORKSPACE:-?}"
echo "commit:    $(git rev-parse --short HEAD 2>/dev/null || echo '<unknown>')"
echo
terraform version | head -1
aws --version
'''
      }
    }

    stage('Repository checks') {
      steps {
        // Same checks as .github/workflows/check.yml: one definition, two callers.
        sh 'scripts/check.sh'
      }
    }
  }

  post {
    always {
      echo "Self-check finished: ${currentBuild.currentResult}"
    }
  }
}
