#!/bin/bash -eu
set -o pipefail

#
# 1- Execute release:prepare Maven command
# 2- Store release status in release.json
#
function maven_prepare_release {
  # log status
  release_status_write_step $MAVEN_RELEASE_PREPARE $STATUS_IN_PROGESS

  # init
  project=$1
  tag=$2
  releaseVersion=$3
  devVersion=$4
  issueId=$5
  description=$6

  # Execute maven release prepare command (Don't push change on remote repository)
  mvnCommand $project release:prepare -DpushChanges=false  -Dtag=$tag -DreleaseVersion=$releaseVersion -DdevelopmentVersion=$devVersion -DscmCommentPrefix="[exo-release]($exo_user) $issueId: $description"

 # log status
 release_status_write_step $MAVEN_RELEASE_PREPARE $STATUS_DONE
}


# Execute release:perform Maven command
# * Add the ability to skip tests for release-perform
#
# 1- Check release args (skipTest or not)
# 2- Execute maven release perform command with local branch
# 3- Drop release branch and clean useless commits
function maven_perform_release {
  # init
  project=$1
  isTestsSkipped=$2
  releaseVersion=$3
  releaseArgs="-DlocalCheckout=true"
  releaseArgsSkipTests=""

  # log status
  release_status_write_step $MAVEN_RELEASE_PERFORM $STATUS_IN_PROGESS

  if [ $isTestsSkipped = true ]; then
    releaseArgsSkipTests="-DskipTests"
  fi

  # Execute maven release perform command
  mvnCommand $project release:perform $releaseArgs "-Darguments=${releaseArgsSkipTests} -DaltDeploymentRepository=local::default::file://${LOCAL_STAGING_DIR}"

  # Drop release branch and clean useless commits and push
  git_release_clean_and_push $project $releaseVersion

  # log status
  release_status_write_step $MAVEN_RELEASE_PERFORM $STATUS_DONE
}
