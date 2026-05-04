#!/bin/bash -eu
set -o pipefail

SCRIPTS_DIR="${0%/*}"

source "${SCRIPTS_DIR}/common.sh"
source "${SCRIPTS_DIR}/utils/credentials.sh"
source "${SCRIPTS_DIR}/utils/trycatch.sh"
source "${SCRIPTS_DIR}/process/release-catalog.sh"
source "${SCRIPTS_DIR}/process/release-status.sh"
source "${SCRIPTS_DIR}/process/git-clone.sh"
source "${SCRIPTS_DIR}/process/git-release.sh"
source "${SCRIPTS_DIR}/process/nexus-repos.sh"
source "${SCRIPTS_DIR}/process/maven-release.sh"
source "${SCRIPTS_DIR}/process/maven-dependencies.sh"
source "${SCRIPTS_DIR}/notifications/tasks.sh"

echo "==============================================================================="
echo "         ***********       eXo Release Manager      ***********                "
echo "==============================================================================="

source "$CREDENTIALS_FILE"

eval "$(ssh-agent)"
"${SCRIPTS_DIR}/utils/ssh-add-pass.sh"
unset SSH_PASS

# -----------------------------------------------------------------------
# Clone one or several projects
# -----------------------------------------------------------------------
function clone {
  case "${2:-}" in
    "-a") git_clone_all;                    exit ;;
    "-l") git_clone_all_with_label "$3";    exit ;;
    *)    git_clone_single "$2";            exit ;;
  esac
}

# -----------------------------------------------------------------------
# Print catalog info for a project
# -----------------------------------------------------------------------
function exor_project_info {
  getProjectByNameFromCatalog "$1"
}

# -----------------------------------------------------------------------
# Prerequisite check: tag must not already exist
# Args: $1=project  $2=gitOrganization  $3=tag
# -----------------------------------------------------------------------
function exor_release_check_prerequisites {
  printHeader "Check Prerequisite for Release"
  local tagExist
  tagExist=$(git ls-remote --exit-code --tags "git@${GIT_HOST}:${2}/${1}.git" "$3" | wc -l)
  log "[DEBUG] Response from github for tag $3: $tagExist"

  if [ "$tagExist" -eq 1 ]; then
    error "[ERROR] The Git tag $3 already exists."
    return 1
  fi
  log "[OK] Git Tag does not exist."
  printFooter "Check Prerequisite for Release"
}

# -----------------------------------------------------------------------
# Parse catalog entry → set project variables
# Args: $1=project_name; sets globals: gitOrganization, releaseVersion,
#       tagName, releaseBranch, releaseNextSnapshotVersion,
#       nexus_host, nexus_profile
# -----------------------------------------------------------------------
function _load_project_from_catalog {
  local projectName="$1"
  local project
  project=$(getProjectByNameFromCatalog "$projectName")
  if [ "$project" = "0" ]; then
    error "Project '$projectName' not found in catalog!"
    throw "$exReleasePrerequisiteKO"
  fi
  log "Project: $project"
  IFS=':' read -r -a params <<< "$project"
  gitOrganization="${params[1]}"
  releaseVersion="${params[2]}"
  tagName="$releaseVersion"
  releaseBranch="${params[3]}"
  releaseNextSnapshotVersion="${params[4]}"
  nexus_host="${params[5]}"
  nexus_profile="${params[6]}"
}

# -----------------------------------------------------------------------
# Release a project end-to-end
# Args: $1=command  $2=project  $3=issueId  $4=versionSuffix (optional)
# -----------------------------------------------------------------------
function exor_release_project {
  local projectName="$2"
  local issueId="$3"
  local versionSuffix="${4:-}"
  local prepareReleaseSkipTests=false

  if [ -n "$versionSuffix" ] && [[ ! "$versionSuffix" =~ ^[0-9]{8}([0-9]{2})?$ ]]; then
    error "Invalid CONTINUOUS_RELEASE_SUFFIX: '${versionSuffix}'. Must be 8 or 10 digits (e.g. 20221020 or 2022102001)."
    throw "$exReleasePrerequisiteKO"
  fi

  if [[ ! "$issueId" =~ ^([0-9]+|continuous-release-template(-[a-z]+)?)$ ]]; then
    error "Invalid TASK_ID: '${issueId}'. Must be numeric or a continuous-release catalog reference."
    throw "$exReleasePrerequisiteKO"
  fi

  # Skip unit tests for builds already stamped with a versionSuffix (weekly releases)
  if [ -n "$versionSuffix" ] && [[ "$issueId" =~ ^[0-9]+$ ]]; then
    log "Skipping unit tests: this release is already built against suffix ${versionSuffix}"
    prepareReleaseSkipTests=true
  fi

  log "Download catalog.json for release..."
  release_catalog_download_from_url "$issueId" "$versionSuffix"

  try
  (
    _load_project_from_catalog "$projectName"

    exor_release_check_prerequisites "$projectName" "$gitOrganization" "$tagName" \
      || throw "$exReleasePrerequisite"

    release_status_init "$issueId" "$projectName"

    git_clone_single "$projectName" || throw "$exReleasePrerequisite"
    git_release_create_branch "$projectName" "$releaseVersion"

    maven_dependencies_update_before_release "$projectName" "$issueId"

    maven_prepare_release "$projectName" "$prepareReleaseSkipTests" "$tagName" \
      "$releaseVersion" "$releaseNextSnapshotVersion" "$issueId" "$projectName" \
      || throw "$exProjectBuild"
    task_add_comment "$projectName" "release_prepare_OK" "$issueId"

    maven_perform_release "$projectName" true "$releaseVersion" \
      || throw "$exProjectBuild"
    task_add_comment "$projectName" "release_perform_OK" "$issueId"

    local description="${issueId}:${projectName}:${tagName}"
    nexus_create_staging_repo "$description" "$nexus_host" "$nexus_profile" \
      || throw "$exNexusStaging"
    task_add_comment "$projectName" "nexus_staging_repo_created_OK" "$issueId"

    nexus_deploy_staged_repo "$(release_status_get_repo_id)" "$nexus_host" "$nexus_profile" \
      || throw "$exNexusStaging"
    task_add_comment "$projectName" "nexus_deploy_to_stage_repo_OK" "$issueId"

    if [ -z "$versionSuffix" ]; then
      nexus_close_staging_repo "$projectName" "$(release_status_get_repo_id)" \
        "$nexus_host" "$nexus_profile" "$description" false || throw "$exNexusStaging"
      task_add_comment "$projectName" "nexus_staging_repo_closed_OK" "$issueId"
    else
      nexus_close_staging_repo "$projectName" "$(release_status_get_repo_id)" \
        "$nexus_host" "$nexus_profile" "$description" true || throw "$exNexusStaging"
      task_add_comment "$projectName" "nexus_staging_repo_closed_OK" "$issueId"
      task_add_comment "$projectName" "nexus_staging_repo_release_OK" "$issueId"
      git_release_clean_and_push "$projectName" "$releaseVersion"
    fi
  )
  catch || {
    error "[ERROR] The release could not be completed."
    release_status_update_step_status "$STATUS_ERROR"
    task_add_comment "$projectName" "ERROR_release_start_${ex_code}" "$issueId"

    case "$ex_code" in
      "$exReleasePrerequisiteKO") error "[$ex_code] Release prerequisites failed." ;;
      "$exProjectBuildKO")        error "[$ex_code] Maven project build failed."   ;;
      *)                          error "[$ex_code] Unexpected exception."          ;;
    esac
    throw "$ex_code"
  }
}

# -----------------------------------------------------------------------
# Generate an initial release.json file
# -----------------------------------------------------------------------
function exor_release_init_json {
  local projectName="$2"
  local issueId="$3"
  printHeader "Generate release.json file"
  installFile "$CONFIG_DIR/release.json" "$WORKSPACE_DIR/release.json"
  release_status_init "$issueId" "$projectName"
  printFooter "Generate release.json file"
}

# -----------------------------------------------------------------------
# Validate a release: push tag + release Nexus repo
# -----------------------------------------------------------------------
function exor_validate_release {
  printHeader "Validate Release"
  local projectName gitOrganization releaseVersion tagName releaseBranch
  local releaseNextSnapshotVersion nexus_host nexus_profile
  projectName=$(release_status_get_project_id)
  _load_project_from_catalog "$projectName"

  exor_release_from_step "nexus:release"
  git_release_clean_and_push "$projectName" "$releaseVersion"
  printFooter "Validate Release"
}

# -----------------------------------------------------------------------
# Cancel a release: drop Nexus repo + clean local artefacts
# -----------------------------------------------------------------------
function exor_cancel_release {
  printHeader "Cancel Release"
  local projectName gitOrganization releaseVersion tagName releaseBranch
  local releaseNextSnapshotVersion nexus_host nexus_profile
  projectName=$(release_status_get_project_id)
  _load_project_from_catalog "$projectName"

  exor_release_from_step "nexus:drop"
  rm -rf "${PRJ_DIR:?}"/*
  rm -rf "${LOCAL_STAGING_DIR:?}"/*
  rm -f  "${WORKSPACE_DIR}/release.json"
  printFooter "Cancel Release"
}

# -----------------------------------------------------------------------
# Resume a release from a specific step
# -----------------------------------------------------------------------
function exor_release_from_step {
  local step="$1"
  local issueId projectName gitOrganization releaseVersion tagName
  local releaseBranch releaseNextSnapshotVersion nexus_host nexus_profile

  issueId=$(release_status_get_issue_id)
  projectName=$(release_status_get_project_id)
  _load_project_from_catalog "$projectName"
  local description="${projectName}:${tagName}"

  try
  (
    case "$step" in
      "nexus:create")
        nexus_create_staging_repo "$description" "$nexus_host" "$nexus_profile" \
          || throw "$exNexusStaging"
        task_add_comment "$projectName" "nexus_staging_repo_created_OK" "$issueId"
        ;;
      "nexus:deploy")
        nexus_deploy_staged_repo "$(release_status_get_repo_id)" "$nexus_host" "$nexus_profile" \
          || throw "$exNexusStaging"
        task_add_comment "$projectName" "nexus_deploy_to_stage_repo_OK" "$issueId"
        ;;
      "nexus:close")
        nexus_close_staging_repo "$projectName" "$(release_status_get_repo_id)" \
          "$nexus_host" "$nexus_profile" "$description" false || throw "$exNexusStaging"
        task_add_comment "$projectName" "nexus_staging_repo_closed_OK" "$issueId"
        ;;
      "nexus:drop")
        nexus_drop_staging_repo "$(release_status_get_repo_id)" \
          "$nexus_host" "$nexus_profile" "$description" || throw "$exNexusStaging"
        task_add_comment "$projectName" "nexus_staging_repo_drop_OK" "$issueId"
        ;;
      "nexus:release")
        nexus_release_staging_repo "$(release_status_get_repo_id)" \
          "$nexus_host" "$nexus_profile" "$description" || throw "$exNexusStaging"
        task_add_comment "$projectName" "nexus_staging_repo_release_OK" "$issueId"
        ;;
      "git:tagpush")
        git_push_release_tag "$projectName" "$tagName"
        ;;
      *)
        error "[ERROR] Unknown step: $step"
        throw "$exNexusStaging"
        ;;
    esac
  )
  catch || {
    error "[ERROR] Unable to continue the release from step '$step'."
    release_status_update_step_status "$STATUS_ERROR"
    task_add_comment "$projectName" "ERROR_release_continue_from_${ex_code}" "$issueId"

    case "$ex_code" in
      "$exReleasePrerequisiteKO") error "[$ex_code] Release prerequisites failed." ;;
      "$exProjectBuildKO")        error "[$ex_code] Maven project build failed."   ;;
      *)                          error "[$ex_code] Unexpected exception."          ;;
    esac
    throw "$ex_code"
  }
}

# -----------------------------------------------------------------------
# Log installed tool versions
# -----------------------------------------------------------------------
function checkSoftwareVersions {
  log "***** eXo Platform Release Manager (v ${EXOR_VERSION}) *******"
  printHeader "Check software for release"
  for tool in "java -version" "git --version" "mvn --version" "jq --version"; do
    log "--- $tool ---"
    $tool 2>&1 | tee -a "${LOGS_DIR}/infos.log"
  done
  log "JAVA_HOME = ${JAVA_HOME:-<unset>}"
  printFooter "Check software for release"
}

# -----------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------
function usage {
  cat <<EOF
==== HELP ====
Usage: eXoR [command] [options]

 --- Catalog commands ---
  eXoR list
  eXoR catalog-from-url <TASK_ID> [CONTINUOUS_RELEASE_SUFFIX]
  eXoR project-info <PROJECT>

 --- Project commands ---
  eXoR project-clone <PROJECT>
  eXoR project-clone -a                         (all projects)
  eXoR project-clone -l <LABEL>                 (by label)

 --- Release commands ---
  eXoR release-start <PROJECT> <TASK_ID> [CONTINUOUS_RELEASE_SUFFIX]
  eXoR release-continue-from <STEP>
      STEP: nexus:create | nexus:deploy | nexus:close | nexus:drop | nexus:release | git:tagpush
  eXoR release-validate
  eXoR release-cancel
  eXoR release-init-json <PROJECT> <TASK_ID>

 --- Misc ---
  eXoR log-software-versions
  eXoR bkg-process <SLEEP_SECONDS>
==== HELP ====
EOF
}

# Keep a container alive (background process)
function letContainerStarted {
  log "==== CONTAINER IS RUNNING... ===="
  while :; do sleep "$1"; done
}

# -----------------------------------------------------------------------
# Dispatcher
# -----------------------------------------------------------------------
case "${1:-}" in
  "bkg-process")             letContainerStarted "$2"                     ;;
  "project-clone")           clone "$@"                                   ;;
  "project-info")            exor_project_info "$2"                       ;;
  "release-info")            echo "TODO"                                  ;;
  "release-start")           exor_release_project "$@"                    ;;
  "release-init-json")       exor_release_init_json "$@"                  ;;
  "release-continue-from")
    valid_steps="nexus:create nexus:deploy nexus:close nexus:drop nexus:release git:tagpush"
    if echo "$valid_steps" | grep -qw "${2:-}"; then
      exor_release_from_step "$2"
    else
      error "[ERROR] Unknown step command: '${2:-}'. Valid steps: $valid_steps"
      exit 1
    fi
    ;;
  "release-validate")        exor_validate_release "$@"                   ;;
  "release-cancel")          exor_cancel_release "$@"                     ;;
  "list")                    displayAvailableProjects                      ;;
  "maven-update-dependencies-before-release")
                             maven_dependencies_update_before_release "$2" ;;
  "catalog-from-url")        release_catalog_download_from_url "$2" "${3:-}"
                             displayAvailableProjects                      ;;
  "log-software-versions")   checkSoftwareVersions                        ;;
  *)                         usage                                         ;;
esac
