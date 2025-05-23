#!/bin/bash -eu
set -o pipefail

SCRIPTS_DIR=${0%/*}

source ${SCRIPTS_DIR}/common.sh
source ${SCRIPTS_DIR}/utils/credentials.sh
source ${SCRIPTS_DIR}/utils/trycatch.sh
source ${SCRIPTS_DIR}/process/release-catalog.sh
source ${SCRIPTS_DIR}/process/release-status.sh
source ${SCRIPTS_DIR}/process/git-clone.sh
source ${SCRIPTS_DIR}/process/git-release.sh
source ${SCRIPTS_DIR}/process/nexus-repos.sh
source ${SCRIPTS_DIR}/process/maven-release.sh
source ${SCRIPTS_DIR}/process/maven-dependencies.sh
source ${SCRIPTS_DIR}/notifications/tasks.sh

echo "==============================================================================="
echo "         ***********       eXo Release Manager      ***********                "
echo "==============================================================================="

# Load credentials for subshell
source $CREDENTIALS_FILE

# Scripts to register github key file
eval "$(ssh-agent)"
$SCRIPTS_DIR/utils/ssh-add-pass.sh
unset SSH_PASS

#
# Clone one or severals projects
function clone {
  case $2 in
    "-a")
      git_clone_all
      exit;
      ;;
    "-l")
      git_clone_all_with_label $3
      exit;
      ;;
    *)
     git_clone_single $2
     exit;
     ;;
  esac
}

#
# Info about a project present into the catalog
function exor_project_info {
  getProjectByNameFromCatalog $1
}



#
# Check all parameters
# * git branch exist
# * git tag doesn't exist
function exor_release_check_prerequisites {
  printHeader "Check Prerequisite for Release"
  tagExist=$(git ls-remote --exit-code --tags git@$GIT_HOST:$2/$1.git $3 | wc -l)
  log "[DEBUG] Response from github for tag $3: " $tagExist

  if [ $tagExist -eq 1 ]; then
    error "[ERROR] The Git tag that you want to create already exist."
    # Tag already exist, we can't do a release
    return 1
  else
    log "[OK] Git Tag not exist."
    return 0
  fi
  printFooter "Check Prerequisite for Release"
}


#
# Release a Project from Catalog
# 1. Read project from catalog.json
# 2. Check release Prerequisite
# 3. Update release.json status
# 4. Clone project
# 5. Update Maven SNAPSHOT dependencies to RELEASE dependencies
# 6. Maven release:prepare
# 7. Maven release:perform
# 5. Update Maven RELEASE dependencies to SNAPSHOTdependencies
# 6. Nexus: Create Nexus Staging Repo
#
# 7. Nexus: Close Staging Repo
# 8.
function exor_release_project {
  # Init
  projectName=$2
  issueId=$3
  versionSuffix=${4:-}
  prepareReleaseSkipTests=false

  if [ ! -z "${versionSuffix}" ] && [[ ! "${versionSuffix}" =~ ^[0-9]{8}([0-9][0-9])?$ ]]; then 
    error "Invalid CONTINUOUS_RELEASE_SUFFIX parameter: ${versionSuffix}! Should be numeric with length 8 or 10 (eg 20221020 or 2022102001) or leave it blank!"
    throw $exReleasePrerequisiteKO
  fi

  if [[ ! "${issueId}" =~ ^([0-9]+|continuous-release-template(-[a-z]+)?)$ ]]; then 
    error "Invalid TASK_ID parameter: ${issueId}! Should be numeric or refer to a continuous release catalog!"
    throw $exReleasePrerequisiteKO
  fi
  
  # Skip unit tests for based CI/CD builds (eg weekly releases)
  if [ ! -z "${versionSuffix}" ] && [[ "${versionSuffix}" =~ ^[0-9]{8}([0-9][0-9])?$ ]] && [[ "${issueId}" =~ ^[0-9]+$ ]]; then 
    log "Skipping unit tests for this module as this release is already built and based on ${versionSuffix} suffix"
    prepareReleaseSkipTests=true
  fi

  log "[DEBUG]" $issueId

  log "Download catalog.json for release..."
  release_catalog_download_from_url $issueId $versionSuffix

  try
  (
      ##############  GET PROJECT INFO #########################
      project=$(getProjectByNameFromCatalog $projectName)
      if [ "$project" == "0" ]; then
         # Project not found, stop the process
        error "Project not found!"
        throw $exReleasePrerequisiteKO
      fi

      log "Project: " $project
      IFS=':' read -r -a params <<< "$project"
      # Project params
      gitOrganization=${params[1]}
      releaseVersion=${params[2]}
      tagName=$releaseVersion
      releaseBranch=${params[3]}
      releaseNextSnapshotVersion=${params[4]}
      nexus_host=${params[5]}
      nexus_profile=${params[6]}
      ##############  GET PROJECT INFO #########################

      # Check that all informations are OK for release
      exor_release_check_prerequisites $projectName $gitOrganization $tagName || throw $exReleasePrerequisite

      # Init Release Status (create release.json file)
      release_status_init $issueId $projectName

      # Clone project
      git_clone_single $projectName || throw $exReleasePrerequisite

      # Create a release branch locally
      git_release_create_branch $projectName $releaseVersion

      # Execute Maven release
      maven_dependencies_update_before_release $projectName $issueId

      maven_prepare_release $projectName $prepareReleaseSkipTests $tagName $releaseVersion $releaseNextSnapshotVersion $issueId $projectName || throw $exProjectBuild
      # Notification to Tribe Task
      task_add_comment $projectName "release_prepare_OK" $issueId

      # skip tests for release:perform as release:prepare just run them
      maven_perform_release $projectName true $releaseVersion || throw $exProjectBuild
      # Notification to Tribe Task
      task_add_comment $projectName "release_perform_OK" $issueId

      # Fix: Workaround to allow project release without resolving SNAPSHOT dependencies
      # during the staging repository's close and release process.
      #
      # Note: This step is unnecessary because the workflow doesn't push changes with
      # the next_snapshot_version to the release branch. It only creates a local
      # release/$releaseVersion branch without modifying the remote.
      # If push needed, this should be called after the release process, and complete the missing push part.
      #
      # maven_dependencies_update_after_release $projectName $issueId

      # Create Nexus Staging Repositry
      description="$issueId:$projectName:$tagName"
      nexus_create_staging_repo $description $nexus_host $nexus_profile || throw $exNexusStaging
      # Notification to Tribe Task
      task_add_comment $projectName "nexus_staging_repo_created_OK" $issueId

      # Upload Release artifacts
      nexus_deploy_staged_repo $(release_status_get_repo_id) $nexus_host $nexus_profile || throw $exNexusStaging
      # Notification to Tribe Task
      task_add_comment $projectName "nexus_deploy_to_stage_repo_OK" $issueId

      # Check if the CI/CD is enabled, if yes, close and release staging repository will performed. No need to perform validate action
      if [ -z "${versionSuffix:-}" ]; then 
        # Close Nexus Staging Repository
        nexus_close_staging_repo $projectName $(release_status_get_repo_id) $nexus_host $nexus_profile $description false || throw $exNexusStaging
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_staging_repo_closed_OK" $issueId
      else 
        # Close and Release Nexus Staging Repository
        nexus_close_staging_repo $projectName $(release_status_get_repo_id) $nexus_host $nexus_profile $description true || throw $exNexusStaging
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_staging_repo_closed_OK" $issueId
        task_add_comment $projectName "nexus_staging_repo_release_OK" $issueId
        git_release_clean_and_push $projectName $releaseVersion
      fi
  )
  catch || {
    # now you can handle
    error "[ERROR] The release can't be executed."

    # Update status in error
    release_status_update_step_status $STATUS_ERROR

    # Notification to Tribe Task
    msg="ERROR_release_start_$ex_code"
    # Notification to Tribe Task
    task_add_comment $projectName "$msg" $issueId

    case $ex_code in
        $exReleasePrerequisiteKO)
            error "[$ex_code] The Releases Prerequisite are not OK."
        ;;
        $exProjectBuildKO)
            error "[$ex_code] The Maven Project failed to build."
        ;;
        *)
            error "[$ex_code] An unexpected exception was thrown"
        ;;
    esac
    throw $ex_code # you can rethrow the "exception" causing the script to exit if not caught
  }
}

function exor_release_init_json {
  projectName=$2
  issueId=$3
  printHeader "Generate release.json file"
  installFile $CONFIG_DIR/release.json $WORKSPACE_DIR/release.json
  release_status_init $issueId $projectName
  printFooter "Generate release.json file"
}

#
# Validate a Release
# * Push git tag to the remote repository
# * Release Nexus repository
# * Add comment to the issue
function exor_validate_release {
  printHeader "Validate Release"

  ##############  GET PROJECT INFO #########################
  projectName=$(release_status_get_project_id)
  project=$(getProjectByNameFromCatalog $projectName)
  if [ "$project" == "0" ]; then
      # Project not found, stop the process
    error "Project not found!"
    throw $exReleasePrerequisiteKO
  fi

  log "Project: " $projectName
  IFS=':' read -r -a params <<< "$project"
  # Project params
  gitOrganization=${params[1]}
  releaseVersion=${params[2]}
  tagName=$releaseVersion
  ##############  GET PROJECT INFO #########################

  # Release Nexus Repository
  exor_release_from_step nexus:release

  # Push git tag to remote
  git_release_clean_and_push $projectName $releaseVersion
  printFooter "Validate Release"
}

#
# Cancel a release:
# * Remove git project 
# * Remove Nexus local staging 
# * Remote Nexus remote staging repository
#
function exor_cancel_release {
  printHeader "Cancel Release"

  ##############  GET PROJECT INFO #########################
  projectName=$(release_status_get_project_id)
  project=$(getProjectByNameFromCatalog $projectName)
  if [ "$project" == "0" ]; then
      # Project not found, stop the process
    error "Project not found!"
    throw $exReleasePrerequisiteKO
  fi

  log "Project: " $projectName
  IFS=':' read -r -a params <<< "$project"
  # Project params
  gitOrganization=${params[1]}
  releaseVersion=${params[2]}
  tagName=$releaseVersion
  ##############  GET PROJECT INFO #########################

  # Drop Remote Nexus Repository
  exor_release_from_step nexus:drop

  # Remove git project datas
  rm -rf ${PRJ_DIR}/*
  # Remove Nexus local staging
  rm -rf ${LOCAL_STAGING_DIR}/*
  # Remove release.json
  rm ${WORKSPACE_DIR}/release.json

  printFooter "Cancel Release"
}


#
# Use it to continue a release after a problem
#
function exor_release_from_step {

  ##############  GET PROJECT INFO #########################
  issueId=$(release_status_get_issue_id)
  projectName=$(release_status_get_project_id)
  project=$(getProjectByNameFromCatalog $projectName)
  if [ "$project" == "0" ]; then
     # Project not found, stop the process
    error "Project not found!"
    throw $exReleasePrerequisiteKO
  fi

  log "Project: " $project
  IFS=':' read -r -a params <<< "$project"
  # Project params
  gitOrganization=${params[1]}
  releaseVersion=${params[2]}
  tagName=$releaseVersion
  releaseBranch=${params[3]}
  releaseNextSnapshotVersion=${params[4]}
  nexus_host=${params[5]}
  nexus_profile=${params[6]}
  ##############  GET PROJECT INFO #########################

  try
  (
    case $1 in
      "nexus:create")
        log $projectName
        description=$projectName":"$tagName
        nexus_create_staging_repo $description $nexus_host $nexus_profile || throw $exNexusStaging
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_staging_repo_created_OK" $issueId
        exit;
        ;;
      "nexus:deploy")
        log $projectName
        nexus_deploy_staged_repo $(release_status_get_repo_id) $nexus_host $nexus_profile || throw $exNexusStaging        
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_deploy_to_stage_repo_OK" $issueId
        exit;
        ;;
      "nexus:close")
       description=$projectName":"$tagName
        nexus_close_staging_repo $projectName $(release_status_get_repo_id) $nexus_host $nexus_profile $description || throw $exNexusStaging
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_staging_repo_closed_OK" $issueId
        exit;
        ;;
      "nexus:drop")
        description=$projectName":"$tagName
        nexus_drop_staging_repo $(release_status_get_repo_id) $nexus_host $nexus_profile $description  || throw $exNexusStaging
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_staging_repo_drop_OK" $issueId
        exit;
        ;;
      "nexus:release")
        description=$projectName":"$tagName
        nexus_release_staging_repo $(release_status_get_repo_id) $nexus_host $nexus_profile $description  || throw $exNexusStaging
        # Notification to Tribe Task
        task_add_comment $projectName "nexus_staging_repo_release_OK" $issueId
        exit;
        ;;
      "git:tagpush")
        git_push_release_tag $projectName $tagName
        exit;
        ;;
      *)
         throw $exNexusStaging
         exit;
         ;;
    esac
  )
  catch || {
      # now you can handle
      error "[ERROR] Unable to continue the release."
      # Notification to Tribe Task
      msg="ERROR_release_continue_from_$ex_code"
      # Update status in error
      release_status_update_step_status $STATUS_ERROR
      # Notification to Tribe Task
      task_add_comment $projectName "$msg" $issueId

      case $ex_code in
          $exReleasePrerequisiteKO)
              error "[$ex_code] The Releases Prerequisite are not OK."
          ;;
          $exProjectBuildKO)
              error "[$ex_code] The Maven Project failed to build."
          ;;
          *)
              error "[$ex_code] An unexpected exception was thrown"
          ;;
      esac
      throw $ex_code # you can rethrow the "exception" causing the script to exit if not caught
  }
}

function checkSoftwareVersions {

  log "***** eXo Platform Release Manager (v ${EXOR_VERSION}) !!! *******"
  printHeader "Check software for release"
  log "-----"
  log "JAVA VERSION "
  log "-----"
  java -version 2>&1 | tee -a ${LOGS_DIR}/infos.log
  log "JAVA_HOME = $JAVA_HOME"
  log "-----"
  log "GIT VERSION"
  log "-----"
  git --version 2>&1 | tee -a ${LOGS_DIR}/infos.log
  log "-----"
  log "MAVEN VERSION"
  log "-----"
  mvn --version 2>&1 | tee -a ${LOGS_DIR}/infos.log
  log "-----"
  log "JQ VERSION"
  log "-----"
  jq --version 2>&1 | tee -a ${LOGS_DIR}/infos.log
  log "-----"
  printFooter "Check software for release"

}

function usage {
  echo "==== HELP ===="
  echo "Usage: eXoR [command] [options]"
  echo " --- Catalog commands --- "
  echo "* eXoR list"
  echo "* eXoR catalog-from-url <TASK_ID>"
  echo "* eXoR info PROJECT"
  echo " "
  echo " --- Project commands --- "
  echo "* eXoR project-clone <PROJECT>"
  echo "* eXoR project-info <PROJECT>"
  echo " "
  echo " --- Release commands --- "
  echo "* eXoR release-start PROJECT TASK_ID CONTINUOUS_RELEASE_SUFFIX"
  echo "* eXoR release-continue-from STEP "
  echo "** STEP = nexus:create / nexus:deploy / nexus:close / nexus:drop / nexus:release / git:tagpush"
  echo "* eXoR release-validate TASK_ID"
  echo "* eXoR release-cancel TASK_ID"
  echo "* eXoR release-init-json PROJECT TASK_ID"
  echo "==== HELP ===="
}

# Infinite loop to be able to let the container started
function letContainerStarted {
  log "==== CONTAINER IS RUNNING... ===="
  while :; do
    sleep ${1}
  done
  log "==== CONTAINER STOPPED ===="
}


case $1 in
  "bkg-process")
    letContainerStarted "$2"
    exit;
    ;;
  "project-clone")
    clone "$@"
    exit;
    ;;
  "project-info")
    exor_project_info $2
    exit;
    ;;
  "release-info")
    echo "TODO "
    exit;
    ;;
  "release-start")
    exor_release_project $@
    exit;
    ;;
  "release-init-json")
    exor_release_init_json $@
    exit;
    ;;
  "release-continue-from")
    if [ $2 == "nexus:create" ] || [ $2 == "nexus:deploy" ] || [ $2 == "nexus:close" ] || [ $2 == "nexus:drop" ] || [ $2 == "nexus:release" ] || [ $2 == "git:tagpush" ] ; then
      exor_release_from_step $2
    else
      error "[ERROR] Unknown step command."
    fi
    exit;
    ;;
  "release-validate")
    exor_validate_release $@
    exit;
    ;;
  "release-cancel")
    exor_cancel_release $@
    exit;
    ;;
  "list")
    displayAvailableProjects
    exit;
    ;;
  "maven-update-dependencies-before-release")
    maven_dependencies_update_before_release $2
    exit;
    ;;
  "catalog-from-url")
    release_catalog_download_from_url $2 ${3:-}
    displayAvailableProjects
    exit;
    ;;
  "log-software-versions")
    checkSoftwareVersions
    exit;
    ;;
  *)
     usage
     exit;
     ;;
esac
