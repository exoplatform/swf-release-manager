#!/bin/bash -eu
set -o pipefail

# Execute release:prepare
# Args: $1=project $2=skipTests(bool) $3=tag $4=releaseVersion $5=devVersion $6=issueId $7=description
function maven_prepare_release {
  release_status_write_step "$MAVEN_RELEASE_PREPARE" "$STATUS_IN_PROGESS"

  local project="$1"
  local isTestsSkipped="$2"
  local tag="$3"
  local releaseVersion="$4"
  local devVersion="$5"
  local issueId="$6"
  local description="$7"
  local releaseArgsSkipTests=""

  [ "$isTestsSkipped" = true ] && releaseArgsSkipTests="-DskipTests"

  mvnCommand "$project" release:prepare \
    -DpushChanges=false \
    -Darguments="${releaseArgsSkipTests}" \
    -Dtag="$tag" \
    -DsignTag=true \
    -DreleaseVersion="$releaseVersion" \
    -DdevelopmentVersion="$devVersion" \
    -DscmCommentPrefix="[exo-release]($exo_user) $issueId: $description"

  release_status_write_step "$MAVEN_RELEASE_PREPARE" "$STATUS_DONE"
}

# Execute release:perform
# Args: $1=project $2=skipTests(bool) $3=releaseVersion
function maven_perform_release {
  release_status_write_step "$MAVEN_RELEASE_PERFORM" "$STATUS_IN_PROGESS"

  local project="$1"
  local isTestsSkipped="$2"
  local releaseArgsSkipTests=""

  [ "$isTestsSkipped" = true ] && releaseArgsSkipTests="-DskipTests"

  mvnCommand "$project" release:perform \
    -DlocalCheckout=true \
    "-Darguments=${releaseArgsSkipTests} -DaltDeploymentRepository=local::default::file://${LOCAL_STAGING_DIR}"

  release_status_write_step "$MAVEN_RELEASE_PERFORM" "$STATUS_DONE"
}
