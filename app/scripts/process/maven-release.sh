#!/bin/bash -eu

# Execute release:prepare Maven command
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

  # -DpushChanges=true : specific for GateIn pom whihc override it to false
  mvnCommand $project release:prepare -DpushChanges=true  -Dtag=$tag -DreleaseVersion=$releaseVersion -DdevelopmentVersion=$devVersion -DscmCommentPrefix="[exo-release]($exo_user) $issueId: $description"

 # log status
 release_status_write_step $MAVEN_RELEASE_PREPARE $STATUS_DONE
}


# Execute release:perform Maven command
# * Add the ability to skip tests for release-perform
function maven_perform_release {
  # init
  project=$1
  isTestsSkipped=$2
  releaseArgsSkipTests=""

  # log status
  release_status_write_step $MAVEN_RELEASE_PERFORM $STATUS_IN_PROGESS

  if [ $isTestsSkipped = true ]; then
    releaseArgsSkipTests="-DskipTests"
  fi

  mvnCommand $project release:perform  "-Darguments=${releaseArgsSkipTests} -DaltDeploymentRepository=local::default::file://${LOCAL_STAGING_DIR}"

  # log status
  release_status_write_step $MAVEN_RELEASE_PERFORM $STATUS_DONE
}
