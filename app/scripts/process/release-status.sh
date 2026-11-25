#!/bin/bash
# All release steps are saved in the ${WORKSPACE_DIR}/release.json file.

export INIT_PARAMS="1-init_params"
export GIT_CLONE="2-git_clone"
export MAVEN_DEPS_BEFORE="3-maven_dependencies_update_before_release"
export MAVEN_RELEASE_PREPARE="4-maven_prepare_release"
export MAVEN_RELEASE_PERFORM="5-maven_perform_release"
export NEXUS_CREATE_STAGING_REPO="7-nexus_create_staging_repo"
export NEXUS_DEPLOY_IN_STAGING_REPO="8-nexus_deploy_in_staging_repo"
export NEXUS_CLOSE_STAGING_REPO="9-nexus_close_staging_repo"
export NEXUS_RELEASE_STAGING_REPO="10-nexus_release_staging_repo"
export NEXUS_DROP_STAGING_REPO="11-nexus_drop_staging_repo"

export STATUS_IN_PROGRESS="in-progress"
export STATUS_DONE="success"
export STATUS_ERROR="error"

# Initialize the release.json file: release_status_init <issueId> <project>
function release_status_init {
  json_update "${WORKSPACE_DIR}/release.json" \
    '.id=$i | .Task.issue_id=$i | .project=$p' --arg i "$1" --arg p "$2"
  release_status_write_step "$INIT_PARAMS" "$STATUS_DONE"
}

function release_status_get_project_id { jq -r '.project' "${WORKSPACE_DIR}/release.json"; }
function release_status_get_issue_id { jq -r '.Task.issue_id' "${WORKSPACE_DIR}/release.json"; }
function release_status_get_repo_id { jq -r '.nexus.staged_repository_id' "${WORKSPACE_DIR}/release.json"; }

function release_status_staging_repo_created {
  json_update "${WORKSPACE_DIR}/release.json" '.nexus.staged_repository_id=$r' --arg r "$1"
}

# Write the release step and status
function release_status_write_step {
  json_update "${WORKSPACE_DIR}/release.json" '.step.name=$n | .step.status=$s' --arg n "$1" --arg s "$2"
}

# Update the status of the last step (for errors)
function release_status_update_step_status {
  json_update "${WORKSPACE_DIR}/release.json" '.step.status=$s' --arg s "$1"
}
