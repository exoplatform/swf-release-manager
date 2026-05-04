#!/bin/bash -eu
set -o pipefail

##
# All commands related to Nexus Staging Repositories
##

function usage {
  echo "Usage: $0 action repo1,repo2..."
  echo "  action  : The action to do"
  echo "    close | drop | release | list"
  echo "  repo    : The ID repository(ies) where action must be done (separated by comma)"
}

# Resolve Nexus URL and Maven server ID for the given host ($1: "jboss" or default)
function _nexus_resolve_config {
  local host=$1
  local profile_key
  profile_key=$(echo "$2" | tr '[:lower:]' '[:upper:]')
  local profile_var="NEXUS_STAGING_PROFILE_${profile_key}_ID"

  if [ "$host" = "jboss" ]; then
    RESOLVED_NEXUS_URL="$NEXUS_JBOSS_REPO_URL"
    RESOLVED_SERVER_ID="$NEXUS_JBOSS_STAGING_SERVER_ID"
  else
    RESOLVED_NEXUS_URL="$NEXUS_REPO_URL"
    RESOLVED_SERVER_ID="$NEXUS_STAGING_SERVER_ID"
  fi
  RESOLVED_PROFILE_ID="${!profile_var}"
}

# List all staging repositories
function nexus_all_staging_repos {
  local STAGING_SERVER_URL="${NEXUS_REPO_URL}/service/local/staging"
  log "============ Display all eXo Staging Repositories ================"
  mvnCommand "$1" nexus-staging:rc-list -DserverId="$NEXUS_STAGING_SERVER_ID" -DnexusUrl="$STAGING_SERVER_URL"
}

# Create a Nexus Staging Repository via REST API.
# Args: $1=description  $2=nexus_host  $3=nexus_profile
function nexus_create_staging_repo {
  printHeader "Create Nexus Repository"
  release_status_write_step "$NEXUS_CREATE_STAGING_REPO" "$STATUS_IN_PROGESS"

  _nexus_resolve_config "$2" "$3"
  local staging_url="${RESOLVED_NEXUS_URL}/service/local/staging"
  local user pwd
  if [ "$2" = "jboss" ]; then
    user="$jboss_login"
    pwd="$(decompress "$jboss_password")"
  else
    user="$nexus_login"
    pwd="$(decompress "$nexus_token")"
  fi

  # Inject description into the request payload
  jq --arg desc "$1" '.data.description = $desc' "${DATAS_DIR}/api/nexus-staging.json" \
    | sponge "${DATAS_DIR}/api/nexus-staging.json"

  local userAgent response id
  userAgent="$(getUserAgent)"
  response=$(curl -sS \
    -H "Content-Type: application/json" \
    -H "User-Agent: $userAgent" \
    -X POST \
    -d @"${DATAS_DIR}/api/nexus-staging.json" \
    -u "$user:$pwd" \
    "${staging_url}/profiles/${RESOLVED_PROFILE_ID}/start" 2>/dev/null)

  id=$(echo "$response" | jq -r '.data.stagedRepositoryId // empty')

  if [[ -z "$id" ]]; then
    error "[ERROR] Nexus Staging Repository not created. Response: $response"
    return 1
  fi

  release_status_staging_repo_created "$id"
  printFooter "Create Nexus Repository (ID: ${id})"
  release_status_write_step "$NEXUS_CREATE_STAGING_REPO" "$STATUS_DONE"
}

# Close (and optionally auto-release) a Nexus Staging Repository.
# Args: $1=project  $2=repo_id  $3=nexus_host  $4=nexus_profile  $5=description  $6=autorelease (true|false)
function nexus_close_staging_repo {
  printHeader "Close Nexus Repository (Repo ID: $2)"
  log "Closing Repo ID: $2"
  release_status_write_step "$NEXUS_CLOSE_STAGING_REPO" "$STATUS_IN_PROGESS"

  _nexus_resolve_config "$3" "$4"
  local autorelease="${6:-false}"

  if [ "$autorelease" = "true" ]; then
    mvnCommand "$1" nexus-staging:rc-close nexus-staging:rc-release \
      -DserverId="$RESOLVED_SERVER_ID" \
      -DnexusUrl="$RESOLVED_NEXUS_URL" \
      -DstagingRepositoryId="$2" \
      -DstagingDescription="$5"
  else
    mvnCommand "$1" nexus-staging:rc-close \
      -DserverId="$RESOLVED_SERVER_ID" \
      -DnexusUrl="$RESOLVED_NEXUS_URL" \
      -DstagingRepositoryId="$2" \
      -DstagingDescription="$5"
  fi

  printFooter "Close Nexus Repository (Repo ID: $2)"
  release_status_write_step "$NEXUS_CLOSE_STAGING_REPO" "$STATUS_DONE"
}

# Drop a Nexus Staging Repository.
# Args: $1=repo_id  $2=nexus_host  $3=nexus_profile  $4=description
function nexus_drop_staging_repo {
  printHeader "Drop Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_DROP_STAGING_REPO" "$STATUS_IN_PROGESS"

  _nexus_resolve_config "$2" "$3"

  mvn nexus-staging:rc-drop \
    -DserverId="$RESOLVED_SERVER_ID" \
    -DnexusUrl="$RESOLVED_NEXUS_URL" \
    -DstagingRepositoryId="$1" \
    -DstagingDescription="$4" 2>&1 | tee -a "${LOGS_DIR}/infos.log"

  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    error "!!! Sorry, maven failed to drop Nexus Repository (Repo ID: $1). Process aborted. !!!"
    exit 1
  fi

  printFooter "Drop Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_DROP_STAGING_REPO" "$STATUS_DONE"
}

# Deploy artifacts to a Nexus Staging Repository.
# Args: $1=repo_id  $2=nexus_host  $3=nexus_profile
function nexus_deploy_staged_repo {
  printHeader "Deploy Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_DEPLOY_IN_STAGING_REPO" "$STATUS_IN_PROGESS"

  _nexus_resolve_config "$2" "$3"
  local maven_profile="exo-staging"
  [ "$2" = "jboss" ] && maven_profile="jboss-staging"

  log "[NEXUS] url=$RESOLVED_NEXUS_URL server=$RESOLVED_SERVER_ID profile=$RESOLVED_PROFILE_ID maven_profile=$maven_profile"

  mvn nexus-staging:deploy-staged-repository \
    -DnexusUrl="$RESOLVED_NEXUS_URL" \
    -DserverId="$RESOLVED_SERVER_ID" \
    -DrepositoryDirectory="${LOCAL_STAGING_DIR}" \
    -DstagingProfileId="$RESOLVED_PROFILE_ID" \
    -DstagingRepositoryId="$1" \
    -Pexo-release,"$maven_profile" 2>&1 | tee -a "${LOGS_DIR}/infos.log"

  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    error "!!! Sorry, maven failed to deploy Nexus Repository (Repo ID: $1). Process aborted. !!!"
    exit 1
  fi

  printFooter "Deploy Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_DEPLOY_IN_STAGING_REPO" "$STATUS_DONE"
}

# Release a closed Nexus Staging Repository.
# Args: $1=repo_id  $2=nexus_host  $3=nexus_profile  $4=description
function nexus_release_staging_repo {
  printHeader "Release Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_RELEASE_STAGING_REPO" "$STATUS_IN_PROGESS"

  _nexus_resolve_config "$2" "$3"

  mvn nexus-staging:rc-release \
    -DnexusUrl="$RESOLVED_NEXUS_URL" \
    -DserverId="$RESOLVED_SERVER_ID" \
    -DstagingRepositoryId="$1" \
    -DstagingDescription="$4" 2>&1 | tee -a "${LOGS_DIR}/infos.log"

  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    error "!!! Sorry, maven failed to release Nexus Repository (Repo ID: $1). Process aborted. !!!"
    exit 1
  fi

  printFooter "Release Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_RELEASE_STAGING_REPO" "$STATUS_DONE"
}
