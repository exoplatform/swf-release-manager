#!/bin/bash
# shellcheck disable=SC2154 # exception codes and credentials come from common.sh / the environment
# All commands related to Nexus Staging Repositories (eXo and JBoss Nexus):
# create with the REST API, deploy/close/drop/release with the maven plugin.

# Resolve the Nexus settings for a host and a staging profile.
# Usage: nexus_resolve <host: exoplatform|jboss> <profile>
# Sets: nexus_url, maven_server_id, maven_profile, nexus_user, nexus_pwd, NEXUS_STAGING_PROFILE_ID
function nexus_resolve {
  local host=$1 profile=$2
  nexus_url=$NEXUS_REPO_URL
  maven_server_id=$NEXUS_STAGING_SERVER_ID
  maven_profile="exo-staging"
  nexus_user=${nexus_login:-}
  nexus_pwd=$(decompress "${nexus_token:-}")
  if [ "$host" = "jboss" ]; then
    nexus_url=$NEXUS_JBOSS_REPO_URL
    maven_server_id=$NEXUS_JBOSS_STAGING_SERVER_ID
    maven_profile="jboss-staging"
    nexus_user=${jboss_login:-}
    nexus_pwd=$(decompress "${jboss_password:-}")
  fi
  NEXUS_STAGING_PROFILE_ID=$(nexus_staging_profile_id "$profile")
}

# Run a nexus-staging maven goal and abort the process on failure
function nexus_mvn {
  local what=$1
  shift
  if ! mvn "$@" 2>&1 | log_stream; then
    error "!!! Sorry, maven failed to ${what}. Process aborted. !!!"
    exit "$exNexusStaging"
  fi
}

# Create a Nexus Staging Repository with the REST API.
# $1: description, $2: Nexus host (exoplatform or jboss), $3: Nexus Staging Profile
function nexus_create_staging_repo {
  printHeader "Create Nexus Repository"
  release_status_write_step "$NEXUS_CREATE_STAGING_REPO" "$STATUS_IN_PROGRESS"
  nexus_resolve "$2" "$3"

  local payload response id
  payload=$(jq -n --arg d "$1" '{data: {description: $d}}')
  if ! response=$(curl_auth_config "$nexus_user" "$nexus_pwd" |
    curl -fsS -K - -X POST -H "Content-Type: application/json" -H "Accept: application/json" \
      -H "User-Agent: $(getUserAgent)" -d "$payload" \
      "${nexus_url}/service/local/staging/profiles/${NEXUS_STAGING_PROFILE_ID}/start"); then
    error "Nexus Staging Repository not created (request failed)."
    return 1
  fi
  id=$(jq -r '.data.stagedRepositoryId // empty' <<<"$response")
  if [ -z "$id" ]; then
    error "Nexus Staging Repository not created."
    return 1
  fi

  release_status_staging_repo_created "$id"
  printFooter "Create Nexus Repository (ID:  ${id})"
  release_status_write_step "$NEXUS_CREATE_STAGING_REPO" "$STATUS_DONE"
}

# Close a Nexus Repository (and release it when autorelease is true)
# $1: Project name, $2: STAGING_REPO_ID, $3: Nexus host, $4: Nexus profile, $5: description,
# $6: autorelease (true or false)
function nexus_close_staging_repo {
  printHeader "Close Nexus Repository (Repo ID: $2)"
  release_status_write_step "$NEXUS_CLOSE_STAGING_REPO" "$STATUS_IN_PROGRESS"
  nexus_resolve "$3" "$4"

  local goals=(nexus-staging:rc-close)
  local action=close
  if [ "${6:-false}" = "true" ]; then
    goals+=(nexus-staging:rc-release)
    action=autorelease
  fi
  nexus_mvn "$action Nexus Repository (Repo ID: $2)" "${goals[@]}" \
    "-DserverId=$maven_server_id" "-DnexusUrl=$nexus_url" "-DstagingRepositoryId=$2" "-DstagingDescription=$5"

  printFooter "Close Nexus Repository (Repo ID: $2)"
  release_status_write_step "$NEXUS_CLOSE_STAGING_REPO" "$STATUS_DONE"
}

# Drop a Nexus Repository: $1: STAGING_REPO_ID, $2: Nexus host, $3: Nexus profile, $4: description
function nexus_drop_staging_repo {
  printHeader "Drop Nexus Repository (Repo ID: $1)"
  release_status_write_step "$NEXUS_DROP_STAGING_REPO" "$STATUS_IN_PROGRESS"
  nexus_resolve "$2" "$3"

  nexus_mvn "drop Nexus Repository (Repo ID: $1)" nexus-staging:rc-drop \
    "-DserverId=$maven_server_id" "-DnexusUrl=$nexus_url" "-DstagingRepositoryId=$1" "-DstagingDescription=$4"

  printFooter "Drop Nexus Repository  (Repo ID: $1)"
  release_status_write_step "$NEXUS_DROP_STAGING_REPO" "$STATUS_DONE"
}

# Deploy the artifacts to a Nexus Staging Repository: $1: STAGING_REPO_ID, $2: Nexus host, $3: Nexus profile
function nexus_deploy_staged_repo {
  printHeader "Deploy Nexus Repository  (Repo ID: $1)"
  release_status_write_step "$NEXUS_DEPLOY_IN_STAGING_REPO" "$STATUS_IN_PROGRESS"
  nexus_resolve "$2" "$3"

  log "[NEXUS] $nexus_url - $maven_server_id - $NEXUS_STAGING_PROFILE_ID - $maven_profile"
  nexus_mvn "deploy Nexus Repository (Repo ID: $1)" nexus-staging:deploy-staged-repository \
    "-DnexusUrl=$nexus_url" "-DserverId=$maven_server_id" "-DrepositoryDirectory=${LOCAL_STAGING_DIR}" \
    "-DstagingProfileId=$NEXUS_STAGING_PROFILE_ID" "-DstagingRepositoryId=$1" "-Pexo-release,$maven_profile"

  printFooter "Deploy Nexus Repository  (Repo ID: $1)"
  release_status_write_step "$NEXUS_DEPLOY_IN_STAGING_REPO" "$STATUS_DONE"
}

# Release a Nexus Repository: $1: STAGING_REPO_ID, $2: Nexus host, $3: Nexus profile, $4: description
function nexus_release_staging_repo {
  printHeader "Release Nexus Repository  (Repo ID: $1)"
  release_status_write_step "$NEXUS_RELEASE_STAGING_REPO" "$STATUS_IN_PROGRESS"
  nexus_resolve "$2" "$3"

  nexus_mvn "release Nexus Repository (Repo ID: $1)" nexus-staging:rc-release \
    "-DnexusUrl=$nexus_url" "-DserverId=$maven_server_id" "-DstagingRepositoryId=$1" "-DstagingDescription=$4"

  printFooter "Release Nexus Repository  (Repo ID: $1)"
  release_status_write_step "$NEXUS_RELEASE_STAGING_REPO" "$STATUS_DONE"
}
