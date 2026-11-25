#!/bin/bash

# 1- Execute release:prepare (changes are not pushed)
# Usage: maven_prepare_release <project> <skipTests> <tag> <releaseVersion> <devVersion> <issueId> <description>
function maven_prepare_release {
  local project=$1 skip_tests=$2 tag=$3 release_version=$4 dev_version=$5 issue_id=$6 description=$7
  local skip_arg=""
  release_status_write_step "$MAVEN_RELEASE_PREPARE" "$STATUS_IN_PROGRESS"
  [ "$skip_tests" = true ] && skip_arg="-DskipTests"

  mvnCommand "$project" release:prepare -DpushChanges=false "-Darguments=${skip_arg}" "-Dtag=$tag" -DsignTag=true \
    "-DreleaseVersion=$release_version" "-DdevelopmentVersion=$dev_version" \
    "-DscmCommentPrefix=[exo-release](${exo_user:-unknown}) $issue_id: $description"

  release_status_write_step "$MAVEN_RELEASE_PREPARE" "$STATUS_DONE"
}

# Execute release:perform on the local checkout, deploying to the local staging directory
# Usage: maven_perform_release <project> <skipTests> <releaseVersion>
function maven_perform_release {
  local project=$1 skip_tests=$2
  local skip_arg=""
  release_status_write_step "$MAVEN_RELEASE_PERFORM" "$STATUS_IN_PROGRESS"
  [ "$skip_tests" = true ] && skip_arg="-DskipTests"

  mvnCommand "$project" release:perform -DlocalCheckout=true \
    "-Darguments=${skip_arg} -DaltDeploymentRepository=local::default::file://${LOCAL_STAGING_DIR}"

  release_status_write_step "$MAVEN_RELEASE_PERFORM" "$STATUS_DONE"
}
