#!/bin/bash -eu
set -o pipefail

#####
#
#  All Release important steps are saved in the ${WORKSPACE_DIR}/release.json file.
#
#####
export INIT_PARAMS="1-init_params"
export GIT_CLONE="2-git_clone"
export MAVEN_DEPS_BEFORE="3-maven_dependencies_update_before_release"
export MAVEN_RELEASE_PREPARE="4-maven_prepare_release"
export MAVEN_RELEASE_PERFORM="5-maven_perform_release"
export MAVEN_DEPS_AFTER="6-maven_dependencies_update_after_release"
export NEXUS_CREATE_STAGING_REPO="7-nexus_create_staging_repo"
export NEXUS_DEPLOY_IN_STAGING_REPO="8-nexus_deploy_in_staging_repo"
export NEXUS_CLOSE_STAGING_REPO="9-nexus_close_staging_repo"
export NEXUS_RELEASE_STAGING_REPO="10-nexus_release_staging_repo"
export NEXUS_DROP_STAGING_REPO="11-nexus_drop_staging_repo"

export STATUS_IN_PROGESS="in-progress"
export STATUS_DONE="success"
export STATUS_ERROR="error"

#
# Initialize the release.json file with parameters:
# * issueId: JIRA issue ID for report
function release_status_init {
  myIssueId="\"$1\""
  myProjectId="\"$2\""
  # Save the ID in the release.json file
  saveId=$(json -I -f ${WORKSPACE_DIR}/release.json -e 'this.id='${myIssueId}';  this.jira.issue_id='${myIssueId}'; this.project='${myProjectId}' ' )

  release_status_write_step $INIT_PARAMS $STATUS_DONE
}

function release_status_has_id {
  issueId="\"$1\""
  #TODO

}

function release_status_get_project_id {
  id=$(json -f ${WORKSPACE_DIR}/release.json -a project)
  echo $id
}

function release_status_get_issue_id {
  id=$(json -f ${WORKSPACE_DIR}/release.json -a jira.issue_id)
  echo $id
}

function release_status_get_repo_id {
  id=$(json -f ${WORKSPACE_DIR}/release.json -a nexus.staged_repository_id)
  echo $id
}


function release_status_staging_repo_created {
  repoId="\"$1\""
  # Save the Nexus Repository ID in the release.json file
  saveId=$(json -I -f ${WORKSPACE_DIR}/release.json -e 'this.nexus.staged_repository_id='${repoId}'' )
}

# Write the release step and status on the release.json file
function release_status_write_step {
  step="\"$1\""
  status="\"$2\""

    $(json -I -f ${WORKSPACE_DIR}/release.json -e 'this.step.name='${step}'' )
    $(json -I -f ${WORKSPACE_DIR}/release.json -e 'this.step.status='${status}'' )
}

# update the status of the last step (for errors)
function release_status_update_step_status {
  status="\"$1\""
    $(json -I -f ${WORKSPACE_DIR}/release.json -e 'this.step.status='${status}'' )
}
