#!/bin/bash -eu
set -o pipefail

##
# All commands related to Nexus Staging Repositories
# * create Nexus Staging Repositories with REST application
# * drop, close, release it with maven plugins
#
# NOTE: Those commands are executed on both eXo and JBoss Nexus.
#

function _nexus_resolve_config {
  local host=$1
  local profile=$2
  local profile_upper
  profile_upper=$(printf '%s' "$profile" | tr '[:lower:]' '[:upper:]')
  local profile_var="NEXUS_STAGING_PROFILE_${profile_upper}_ID"
  NEXUS_STAGING_PROFILE_ID="${!profile_var}"
  NEXUS_URL="${NEXUS_REPO_URL}"
  NEXUS_SERVER_ID="${NEXUS_STAGING_SERVER_ID}"

  if [ "${host}" = "jboss" ]; then
    NEXUS_URL="${NEXUS_JBOSS_REPO_URL}"
    NEXUS_SERVER_ID="${NEXUS_JBOSS_STAGING_SERVER_ID}"
  fi
}

# All eXo Staging Repositories
function nexus_all_staging_repos {
  local STAGING_SERVER_URL="${NEXUS_REPO_URL}/service/local/staging"
  log "============ Display all eXo Staging Repositories ================"
  mvnCommand "$1" nexus-staging:rc-list -DserverId="${STAGING_SERVER_ID}" -DnexusUrl="${STAGING_SERVER_URL}"
}

# Create a Nexus Staging Repository with REST API.
#
# Params required:
# $1: description (task info)
# $2: Nexus Host (exoplatform or jboss)
# $3: Nexus Staging Profile
function nexus_create_staging_repo {
  printHeader "Create Nexus Repository"
  release_status_write_step "${NEXUS_CREATE_STAGING_REPO}" "${STATUS_IN_PROGESS}"

  local nexus_host=$2
  local nexus_profile=$3

  _nexus_resolve_config "${nexus_host}" "${nexus_profile}"
  local STAGING_SERVER_URL="${NEXUS_URL}/service/local/staging"

  local user=$nexus_login
  local pwd
  pwd=$(decompress "${nexus_token}")

  if [ "${nexus_host}" = "jboss" ]; then
    user=$jboss_login
    pwd=$(decompress "${jboss_password}")
  fi

  local nexus_json="${DATA_DIR}/nexus-staging.json"
  jq --arg desc "$1" '.data.description = $desc' "${nexus_json}" | sponge "${nexus_json}"

  local userAgent
  userAgent=$(getUserAgent)
  local response
  response=$(curl -sS -H "Content-Type: application/json" -H "User-Agent: ${userAgent}" -X POST -d "@${nexus_json}" -u "${user}:${pwd}" "${STAGING_SERVER_URL}/profiles/${NEXUS_STAGING_PROFILE_ID}/start" 2>/dev/null)

  local id
  id=$(printf '%s' "$response" | jq -r '.data.stagedRepositoryId')

  if [ -z "${id+x}" ]; then
    error "[ERROR] Nexus Staging Repository not created."
    return 1
  fi

  release_status_staging_repo_created "${id}"
  printFooter "Create Nexus Repository (ID: ${id})"
  release_status_write_step "${NEXUS_CREATE_STAGING_REPO}" "${STATUS_DONE}"
}

# Close 1 or several Nexus Repositoy(ies)
# Params required:
# $1: Project name
# $2: STAGING_REPO_ID
# $3: Nexus Host (exoplatform or jboss)
# $4: Nexus Staging Profile
# $5: description
# $6: autorelease (true or false)
function nexus_close_staging_repo {
  printHeader "Close Nexus Repository (Repo ID: $2)"
  log "Closing Repo ID: $2"
  release_status_write_step "${NEXUS_CLOSE_STAGING_REPO}" "${STATUS_IN_PROGESS}"

  _nexus_resolve_config "$3" "$4"

  if [ "${6:-false}" = "true" ]; then
    mvnCommand "$1" nexus-staging:rc-close nexus-staging:rc-release -DserverId="${NEXUS_SERVER_ID}" -DnexusUrl="${NEXUS_URL}" -DstagingRepositoryId="$2" -DstagingDescription="$5" 2>&1 | tee -a "${LOGS_DIR}/infos.log"
  else
    mvnCommand "$1" nexus-staging:rc-close -DserverId="${NEXUS_SERVER_ID}" -DnexusUrl="${NEXUS_URL}" -DstagingRepositoryId="$2" -DstagingDescription="$5" 2>&1 | tee -a "${LOGS_DIR}/infos.log"
  fi

  printFooter "Close Nexus Repository (Repo ID: $2)"
  release_status_write_step "${NEXUS_CLOSE_STAGING_REPO}" "${STATUS_DONE}"
}

# Drop 1 or several Nexus Repositoy(ies)
#
# Params required:
# $1: STAGING_REPO_ID
# $2: Nexus Host (exoplatform or jboss)
# $3: Nexus Staging Profile
# $4: description
function nexus_drop_staging_repo {
  printHeader "Drop Nexus Repository (Repo ID: $1)"
  release_status_write_step "${NEXUS_DROP_STAGING_REPO}" "${STATUS_IN_PROGESS}"

  _nexus_resolve_config "$2" "$3"

  mvnCommand "$1" nexus-staging:rc-drop -DserverId="${NEXUS_SERVER_ID}" -DnexusUrl="${NEXUS_URL}" -DstagingRepositoryId="$1" -DstagingDescription="$4"

  printFooter "Drop Nexus Repository  (Repo ID: $1)"
  release_status_write_step "${NEXUS_DROP_STAGING_REPO}" "${STATUS_DONE}"
}

# Deploy artifcats to a Nexus Staging Repository.
#
# Params required:
# $1: STAGING_REPO_ID
# $2: Nexus Host (exoplatform or jboss)
# $3: Nexus Staging Profile
function nexus_deploy_staged_repo {
  printHeader "Deploy Nexus Repository  (Repo ID: $1)"
  release_status_write_step "${NEXUS_DEPLOY_IN_STAGING_REPO}" "${STATUS_IN_PROGESS}"

  local maven_profile="exo-staging"
  _nexus_resolve_config "$2" "$3"

  if [ "$2" = "jboss" ]; then
    maven_profile="jboss-staging"
  fi

  log "[NEXUS] ${NEXUS_URL} - ${NEXUS_SERVER_ID} - ${NEXUS_STAGING_PROFILE_ID} - ${maven_profile}"

  mvnCommand "$1" nexus-staging:deploy-staged-repository -DnexusUrl="${NEXUS_URL}" -DserverId="${NEXUS_SERVER_ID}" -DrepositoryDirectory="${LOCAL_STAGING_DIR}" -DstagingProfileId="${NEXUS_STAGING_PROFILE_ID}" -DstagingRepositoryId="$1" -P"exo-release,${maven_profile}"

  printFooter "Deploy Nexus Repository  (Repo ID: $1)"
  release_status_write_step "${NEXUS_DEPLOY_IN_STAGING_REPO}" "${STATUS_DONE}"
}

# Release 1 or several Nexus Repositoy(ies)
function nexus_release_staging_repo {
  printHeader "Release Nexus Repository  (Repo ID: $1)"
  release_status_write_step "${NEXUS_RELEASE_STAGING_REPO}" "${STATUS_IN_PROGESS}"

  _nexus_resolve_config "$2" "$3"

  mvnCommand "$1" nexus-staging:rc-release -DnexusUrl="${NEXUS_URL}" -DserverId="${NEXUS_SERVER_ID}" -DstagingRepositoryId="$1" -DstagingDescription="$4"

  printFooter "Release Nexus Repository  (Repo ID: $1)"
  release_status_write_step "${NEXUS_RELEASE_STAGING_REPO}" "${STATUS_DONE}"
}
