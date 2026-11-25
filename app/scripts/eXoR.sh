#!/bin/bash
# shellcheck disable=SC2154 # exception codes and credentials come from common.sh / the environment
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
SCRIPTS_DIR=${0%/*}

# shellcheck source=common.sh
source "${SCRIPTS_DIR}/common.sh"
source "${SCRIPTS_DIR}/utils/credentials.sh"
source "${SCRIPTS_DIR}/utils/files.sh"
source "${SCRIPTS_DIR}/process/release-catalog.sh"
source "${SCRIPTS_DIR}/process/release-status.sh"
source "${SCRIPTS_DIR}/process/git-clone.sh"
source "${SCRIPTS_DIR}/process/git-release.sh"
source "${SCRIPTS_DIR}/process/nexus-repos.sh"
source "${SCRIPTS_DIR}/process/maven-release.sh"
source "${SCRIPTS_DIR}/process/maven-dependencies.sh"
source "${SCRIPTS_DIR}/notifications/tasks.sh"

# Steps accepted by "release-continue-from"
RELEASE_STEPS="nexus:create nexus:deploy nexus:close nexus:drop nexus:release git:tagpush"

function usage {
  cat <<'USAGE'
==== HELP ====
Usage: eXoR [command] [options]
 --- Catalog commands ---
* eXoR list
* eXoR catalog-from-url <TASK_ID> [CONTINUOUS_RELEASE_SUFFIX]   (<TASK_ID>.json, .yaml or .yml)
 --- Project commands ---
* eXoR project-clone <PROJECT> | -a | -l <LABEL>
* eXoR project-info <PROJECT>
 --- Release commands ---
* eXoR release-start PROJECT TASK_ID [CONTINUOUS_RELEASE_SUFFIX]
* eXoR release-continue-from STEP
** STEP = nexus:create / nexus:deploy / nexus:close / nexus:drop / nexus:release / git:tagpush
* eXoR release-validate
* eXoR release-cancel
* eXoR release-init-json PROJECT TASK_ID
 --- Misc ---
* eXoR log-software-versions
* eXoR bkg-process SECONDS
==== HELP ====
USAGE
}

# Mask every credential known by the process in the logs
function register_secrets {
  local v
  for v in "${nexus_token:-}" "${jboss_password:-}" "${gpg_passphrase:-}" "${ssh_passphrase:-}"; do
    [ -n "$v" ] && log_register_secret "$(decompress "$v")"
  done
  log_register_secret "${TRIBE_RELEASE_PASSWORD:-}"
  local catalog_credentials=${CATALOG_CREDENTIALS:-}
  log_register_secret "${catalog_credentials#*:}"
}

# Load the catalog entry of a project in the global variables
# gitOrganization, releaseVersion, tagName, releaseBranch, releaseNextSnapshotVersion, nexus_host, nexus_profile
function load_project_info {
  local project
  project=$(getProjectByNameFromCatalog "$1")
  if [ "$project" = "0" ]; then
    error "Project $1 not found in the catalog!"
    throw "$exReleasePrerequisiteKO"
  fi
  log_debug "Project: $project"
  # shellcheck disable=SC2034 # some variables are only used by some callers
  IFS=':' read -r _ gitOrganization releaseVersion releaseBranch releaseNextSnapshotVersion nexus_host nexus_profile <<<"$project"
  tagName=$releaseVersion
}

# Handle an exception raised in a guarded block: eXoR_guard <prefix of the status> <exit code>
function release_failed {
  local code=$1 status=$2
  error "The release can't be executed."
  release_status_update_step_status "$STATUS_ERROR"
  task_add_comment "$projectName" "${status}_${code}" "$issueId"
  error "[$code] $(exception_message "$code")"
  throw "$code"
}

function clone {
  case ${2:-} in
    "-a") git_clone_all ;;
    "-l") git_clone_all_with_label "${3:?label required}" ;;
    *) git_clone_single "${2:?project required}" ;;
  esac
}

# Check that the git tag doesn't exist yet: exor_release_check_prerequisites <project> <organization> <tag>
function exor_release_check_prerequisites {
  printHeader "Check Prerequisite for Release"
  local tag_exists
  tag_exists=$(git ls-remote --tags "git@$GIT_HOST:$2/$1.git" "refs/tags/$3" | wc -l)
  log_debug "Response from github for tag $3: $tag_exists"
  if [ "$tag_exists" -ge 1 ]; then
    error "The Git tag $3 that you want to create already exist."
    return 1
  fi
  log_info "Git Tag $3 does not exist."
  printFooter "Check Prerequisite for Release"
}

# Release a project from the catalog:
# check prerequisites, clone, update the SNAPSHOT dependencies, release:prepare, release:perform,
# create the Nexus staging repository, deploy, close (and release for continuous releases), push the tag.
function exor_release_project {
  projectName=${2:?project required}
  issueId=${3:?TASK_ID required}
  local versionSuffix=${4:-} skip_tests=false

  if [ -n "$versionSuffix" ] && [[ ! "$versionSuffix" =~ ^[0-9]{8}([0-9][0-9])?$ ]]; then
    error "Invalid CONTINUOUS_RELEASE_SUFFIX parameter: ${versionSuffix}! Should be numeric with length 8 or 10 (eg 20221020 or 2022102001) or leave it blank!"
    throw "$exReleasePrerequisiteKO"
  fi
  if [[ ! "$issueId" =~ ^([0-9]+|continuous-release-template(-[a-z]+)?)$ ]]; then
    error "Invalid TASK_ID parameter: ${issueId}! Should be numeric or refer to a continuous release catalog!"
    throw "$exReleasePrerequisiteKO"
  fi
  # Skip unit tests for based CI/CD builds (eg weekly releases)
  if [ -n "$versionSuffix" ] && [[ "$issueId" =~ ^[0-9]+$ ]]; then
    log "Skipping unit tests for this module as this release is already built and based on ${versionSuffix} suffix"
    skip_tests=true
  fi

  release_catalog_download_from_url "$issueId" "$versionSuffix"

  local rc=0
  (
    load_project_info "$projectName"
    exor_release_check_prerequisites "$projectName" "$gitOrganization" "$tagName" || throw "$exReleasePrerequisite"
    release_status_init "$issueId" "$projectName"
    git_clone_single "$projectName" || throw "$exReleasePrerequisite"
    git_release_create_branch "$projectName" "$releaseVersion"
    maven_dependencies_update_before_release "$projectName" "$issueId"

    maven_prepare_release "$projectName" "$skip_tests" "$tagName" "$releaseVersion" "$releaseNextSnapshotVersion" "$issueId" "$projectName" || throw "$exProjectBuild"
    task_add_comment "$projectName" "release_prepare_OK" "$issueId"

    # skip tests for release:perform as release:prepare just ran them
    maven_perform_release "$projectName" true "$releaseVersion" || throw "$exProjectBuild"
    task_add_comment "$projectName" "release_perform_OK" "$issueId"

    local description="$issueId:$projectName:$tagName" repo_id
    nexus_create_staging_repo "$description" "$nexus_host" "$nexus_profile" || throw "$exNexusStaging"
    task_add_comment "$projectName" "nexus_staging_repo_created_OK" "$issueId"

    repo_id=$(release_status_get_repo_id)
    nexus_deploy_staged_repo "$repo_id" "$nexus_host" "$nexus_profile" || throw "$exNexusStaging"
    task_add_comment "$projectName" "nexus_deploy_to_stage_repo_OK" "$issueId"

    if [ -z "$versionSuffix" ]; then
      nexus_close_staging_repo "$projectName" "$repo_id" "$nexus_host" "$nexus_profile" "$description" false || throw "$exNexusStaging"
      task_add_comment "$projectName" "nexus_staging_repo_closed_OK" "$issueId"
    else
      # CI/CD release: close and release the staging repository, no validation step
      nexus_close_staging_repo "$projectName" "$repo_id" "$nexus_host" "$nexus_profile" "$description" true || throw "$exNexusStaging"
      task_add_comment "$projectName" "nexus_staging_repo_closed_OK" "$issueId"
      task_add_comment "$projectName" "nexus_staging_repo_release_OK" "$issueId"
      git_release_clean_and_push "$projectName" "$releaseVersion"
    fi
  ) || rc=$?
  if [ "$rc" -ne 0 ]; then release_failed "$rc" "ERROR_release_start"; fi
}

function exor_release_init_json {
  printHeader "Generate release.json file"
  installFile "$CONFIG_DIR/release.json" "$WORKSPACE_DIR/release.json"
  release_status_init "${3:?TASK_ID required}" "${2:?project required}"
  printFooter "Generate release.json file"
}

# Validate a release: release the Nexus repository then push the git tag
function exor_validate_release {
  printHeader "Validate Release"
  projectName=$(release_status_get_project_id)
  load_project_info "$projectName"
  exor_release_from_step nexus:release
  git_release_clean_and_push "$projectName" "$releaseVersion"
  printFooter "Validate Release"
}

# Cancel a release: drop the remote Nexus repository, remove the local data
function exor_cancel_release {
  printHeader "Cancel Release"
  projectName=$(release_status_get_project_id)
  load_project_info "$projectName"
  exor_release_from_step nexus:drop
  rm -rf "${PRJ_DIR:?}"/* "${LOCAL_STAGING_DIR:?}"/*
  rm -f "${WORKSPACE_DIR}/release.json"
  printFooter "Cancel Release"
}

# Continue a release after a problem
function exor_release_from_step {
  issueId=$(release_status_get_issue_id)
  projectName=$(release_status_get_project_id)
  load_project_info "$projectName"
  local description="$projectName:$tagName" repo_id comment rc=0
  repo_id=$(release_status_get_repo_id)

  (
    case $1 in
      "nexus:create")
        nexus_create_staging_repo "$description" "$nexus_host" "$nexus_profile" || throw "$exNexusStaging"
        comment="nexus_staging_repo_created_OK"
        ;;
      "nexus:deploy")
        nexus_deploy_staged_repo "$repo_id" "$nexus_host" "$nexus_profile" || throw "$exNexusStaging"
        comment="nexus_deploy_to_stage_repo_OK"
        ;;
      "nexus:close")
        nexus_close_staging_repo "$projectName" "$repo_id" "$nexus_host" "$nexus_profile" "$description" false || throw "$exNexusStaging"
        comment="nexus_staging_repo_closed_OK"
        ;;
      "nexus:drop")
        nexus_drop_staging_repo "$repo_id" "$nexus_host" "$nexus_profile" "$description" || throw "$exNexusStaging"
        comment="nexus_staging_repo_drop_OK"
        ;;
      "nexus:release")
        nexus_release_staging_repo "$repo_id" "$nexus_host" "$nexus_profile" "$description" || throw "$exNexusStaging"
        comment="nexus_staging_repo_release_OK"
        ;;
      "git:tagpush")
        git_push_release_tag "$projectName" "$tagName"
        comment=""
        ;;
      *) throw "$exNexusStaging" ;;
    esac
    if [ -n "$comment" ]; then task_add_comment "$projectName" "$comment" "$issueId"; fi
  ) || rc=$?
  if [ "$rc" -ne 0 ]; then release_failed "$rc" "ERROR_release_continue_from"; fi
}

function checkSoftwareVersions {
  log "***** eXo Platform Release Manager (v ${EXOR_VERSION:-unknown}) !!! *******"
  printHeader "Check software for release"
  java -version 2>&1 | log_stream
  log "JAVA_HOME = ${JAVA_HOME:-unset}"
  git --version 2>&1 | log_stream
  mvn --version 2>&1 | log_stream
  jq --version 2>&1 | log_stream
  printFooter "Check software for release"
}

# Infinite loop to be able to let the container started
function letContainerStarted {
  log "==== CONTAINER IS RUNNING... ===="
  while :; do
    sleep "${1:?seconds required}"
  done
}

function main {
  local command=${1:-}
  case $command in
    "" | help | -h | --help) usage; return 0 ;;
    list) displayAvailableProjects; return 0 ;;
    log-software-versions) checkSoftwareVersions; return 0 ;;
  esac

  # Everything else needs the credentials and the git/ssh access
  log "eXo Release Manager (v ${EXOR_VERSION:-unknown}): $command"
  # shellcheck disable=SC1090
  source "$CREDENTIALS_FILE"
  register_secrets
  eval "$(ssh-agent)" >/dev/null
  SSH_PASS=$(decompress "$ssh_passphrase") "$SCRIPTS_DIR/utils/ssh-add-pass.sh"

  case $command in
    bkg-process) letContainerStarted "${2:-}" ;;
    project-clone) clone "$@" ;;
    project-info) getProjectByNameFromCatalog "${2:?project required}" ;;
    release-start) exor_release_project "$@" ;;
    release-init-json) exor_release_init_json "$@" ;;
    release-continue-from)
      if [[ " $RELEASE_STEPS " == *" ${2:-} "* ]]; then
        exor_release_from_step "$2"
      else
        error "Unknown step command '${2:-}'. Steps: $RELEASE_STEPS"
        return 1
      fi
      ;;
    release-validate) exor_validate_release ;;
    release-cancel) exor_cancel_release ;;
    maven-update-dependencies-before-release) maven_dependencies_update_before_release "${2:?project required}" "${3:-}" ;;
    catalog-from-url)
      release_catalog_download_from_url "${2:?TASK_ID required}" "${3:-}"
      displayAvailableProjects
      ;;
    *) usage; return 1 ;;
  esac
}

main "$@"
