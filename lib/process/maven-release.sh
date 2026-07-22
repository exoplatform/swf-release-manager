#!/bin/bash -eu
set -o pipefail

function maven_prepare_release {
  release_status_write_step "${MAVEN_RELEASE_PREPARE}" "${STATUS_IN_PROGESS}"

  local project=$1
  local isTestsSkipped=$2
  local tag=$3
  local releaseVersion=$4
  local devVersion=$5
  local issueId=$6
  local description=$7

  local releaseArgsSkipTests=""
  if [ "${isTestsSkipped}" = "true" ]; then
    releaseArgsSkipTests="-DskipTests"
  fi

  mvnCommand "${project}" release:prepare -DpushChanges=false -Darguments="${releaseArgsSkipTests}" -Dtag="${tag}" -DsignTag=true -DreleaseVersion="${releaseVersion}" -DdevelopmentVersion="${devVersion}" -DscmCommentPrefix="[exo-release](${exo_user}) ${issueId}: ${description}"

  release_status_write_step "${MAVEN_RELEASE_PREPARE}" "${STATUS_DONE}"
}

function maven_perform_release {
  local project=$1
  local isTestsSkipped=$2
  local releaseVersion=$3
  local releaseArgs="-DlocalCheckout=true"
  local releaseArgsSkipTests=""

  release_status_write_step "${MAVEN_RELEASE_PERFORM}" "${STATUS_IN_PROGESS}"

  if [ "${isTestsSkipped}" = "true" ]; then
    releaseArgsSkipTests="-DskipTests"
  fi

  mvnCommand "${project}" release:perform ${releaseArgs} "-Darguments=${releaseArgsSkipTests} -DaltDeploymentRepository=local::default::file://${LOCAL_STAGING_DIR}"

  release_status_write_step "${MAVEN_RELEASE_PERFORM}" "${STATUS_DONE}"
}
