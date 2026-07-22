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

function release_status_init {
  local issue_id=$1
  local project_id=$2
  local release_file="${WORKSPACE_DIR}/release.json"

  jq --arg id "$issue_id" --arg project "$project_id" \
    '.id = $id | .Task.issue_id = $id | .project = $project' \
    "${release_file}" | sponge "${release_file}"

  release_status_write_step "${INIT_PARAMS}" "${STATUS_DONE}"
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
  local repo_id=$1
  local release_file="${WORKSPACE_DIR}/release.json"

  jq --arg rid "$repo_id" '.nexus.staged_repository_id = $rid' \
    "${release_file}" | sponge "${release_file}"
}

function release_status_write_step {
  local step=$1
  local status=$2
  local release_file="${WORKSPACE_DIR}/release.json"

  jq --arg step "$step" --arg status "$status" \
    '.step.name = $step | .step.status = $status' \
    "${release_file}" | sponge "${release_file}"
}

function release_status_update_step_status {
  local status=$1
  local release_file="${WORKSPACE_DIR}/release.json"

  jq --arg status "$status" '.step.status = $status' \
    "${release_file}" | sponge "${release_file}"
}
