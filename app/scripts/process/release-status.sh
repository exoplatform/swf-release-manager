#!/bin/bash -eu
set -o pipefail

#####
# All release steps are persisted in ${WORKSPACE_DIR}/release.json
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

# Initialise release.json with the issueId and projectId
function release_status_init {
  jq --arg id "$1" --arg proj "$2" \
    '.id = $id | .Task.issue_id = $id | .project = $proj' \
    "${WORKSPACE_DIR}/release.json" | sponge "${WORKSPACE_DIR}/release.json"
  release_status_write_step "$INIT_PARAMS" "$STATUS_DONE"
}

function release_status_get_project_id {
  jq -r '.project' "${WORKSPACE_DIR}/release.json"
}

function release_status_get_issue_id {
  jq -r '.Task.issue_id' "${WORKSPACE_DIR}/release.json"
}

function release_status_get_repo_id {
  jq -r '.nexus.staged_repository_id' "${WORKSPACE_DIR}/release.json"
}

function release_status_staging_repo_created {
  jq --arg id "$1" '.nexus.staged_repository_id = $id' \
    "${WORKSPACE_DIR}/release.json" | sponge "${WORKSPACE_DIR}/release.json"
}

# Persist step name and status atomically (single jq call)
function release_status_write_step {
  jq --arg name "$1" --arg status "$2" \
    '.step.name = $name | .step.status = $status' \
    "${WORKSPACE_DIR}/release.json" | sponge "${WORKSPACE_DIR}/release.json"
}

# Update only the status of the current step (used for error reporting)
function release_status_update_step_status {
  jq --arg status "$1" '.step.status = $status' \
    "${WORKSPACE_DIR}/release.json" | sponge "${WORKSPACE_DIR}/release.json"
}
