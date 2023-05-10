#!/bin/bash -eu
set -o pipefail

##
# All commands related to Nexus Staging Repositories
# * create Nexus Staging Repositories with REST application
# * drop, close, release it with maven plugins
#
# NOTE: Those commands are executed on both eXo and JBoss Nexus.
#
##



function usage {
 echo "Usage: $0 action repo1,repo2..."
 echo "  action  : The action to do"
 echo "    close | drop | release | list"
 echo "  repo : The ID repository(ies) where action must be done (separated by comma)"
 echo "    repo1,repo2,repo3 "
}

#
# All eXo Staging Repositories
#
function nexus_all_staging_repos {
  STAGING_SERVER_URL=$NEXUS_REPO_URL"/service/local/staging"

  log "============ Display all eXo Staging Repositories ================"
  mvnCommand $1 nexus-staging:rc-list -DserverId=$STAGING_SERVER_ID -DnexusUrl=$STAGING_SERVER_URL
}


# Create a Nexus Staging Repository with REST API.
#
# Params required:
# $1: TASK_ID
# $2: Nexus Host (exoplatform or jboss)
# $3: Nexus Staging Profile
function nexus_create_staging_repo {
  printHeader "Create Nexus Repository"
  # log status
  release_status_write_step $NEXUS_CREATE_STAGING_REPO $STATUS_IN_PROGESS

  request="\"$1\""
  STAGING_SERVER_URL=$NEXUS_REPO_URL"/service/local/staging"
  user=$nexus_login
  pwd=$(decompress $nexus_token)

  # Concat NEXUS PROFILE ID env variable with id from catalog
  ## to uppercase
  profile=$(echo $3 | tr [a-z] [A-Z])
  NEXUS_PROFILE_STRING=NEXUS_STAGING_PROFILE_${profile}_ID
  eval NEXUS_STAGING_PROFILE_ID="\$$NEXUS_PROFILE_STRING"

  ## Update variables if we need to use JBoss infrastructure
  if [ $2 == "jboss" ]; then
   user=$jboss_login
   pwd=$(decompress $jboss_password)
   STAGING_SERVER_URL=$NEXUS_JBOSS_REPO_URL"/service/local/staging"
  fi

  # Update JSON to send datas with JIRA ID and comments
  a=$(jq -r '.data.description='"${request}"'' ${DATAS_DIR}/api/nexus-staging.json | sponge ${DATAS_DIR}/api/nexus-staging.json)
  # Create the Staging Repo
  userAgent=$(getUserAgent)
  response=$(curl -sS -H "Content-Type: application/json" -H "User-Agent: $userAgent" -v -X POST -d @${DATAS_DIR}/api/nexus-staging.json -u $user:$pwd $STAGING_SERVER_URL/profiles/$NEXUS_STAGING_PROFILE_ID/start 2>/dev/null)
  # Extraire ID from JSON response
  id=$(echo $response | jq -r '.data.stagedRepositoryId')

  if [  -z ${id+x}  ]; then
    error "[ERROR] Nexus Staging Repository not created."
    return 1
  fi

  # Update Release Status
  release_status_staging_repo_created $id
  printFooter "Create Nexus Repository (ID:  ${id})"
  # log status
  release_status_write_step $NEXUS_CREATE_STAGING_REPO $STATUS_DONE
}


#
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
  # log status
  release_status_write_step $NEXUS_CLOSE_STAGING_REPO $STATUS_IN_PROGESS

  nexus_url=$NEXUS_REPO_URL
  maven_server_id=$NEXUS_STAGING_SERVER_ID
  # Concat NEXUS PROFILE ID env variable with id from catalog
  ## to uppercase
  profile=$(echo $4 | tr [a-z] [A-Z])
  NEXUS_PROFILE_STRING=NEXUS_STAGING_PROFILE_${profile}_ID
  eval NEXUS_STAGING_PROFILE_ID="\$$NEXUS_PROFILE_STRING"

  ######################  NEXUS JBOSS TESTS #####################
  ## Update variables if we need to use JBoss infrastructure
  if [ $3 == "jboss" ]; then
   nexus_url=$NEXUS_JBOSS_REPO_URL
   maven_server_id=$NEXUS_JBOSS_STAGING_SERVER_ID
  fi
  ######################  NEXUS JBOSS TESTS #####################
  if [ ${6:-false} = "true" ]; then
    mvnCommand $1 nexus-staging:rc-close nexus-staging:rc-release -DserverId=$maven_server_id -DnexusUrl=$nexus_url -DstagingRepositoryId=$2 -DstagingDescription=$5 2>&1 | tee -a ${LOGS_DIR}/infos.log
  else
    mvnCommand $1 nexus-staging:rc-close -DserverId=$maven_server_id -DnexusUrl=$nexus_url -DstagingRepositoryId=$2 -DstagingDescription=$5 2>&1 | tee -a ${LOGS_DIR}/infos.log
  fi
  if [ "$?" -ne "0" ]; then
    if [ ${6:-false} = "true" ]; then
      error "!!! Sorry, maven failed to autorelease Nexus Repository (Repo ID: $2). Process aborted. !!!"
    else
      error "!!! Sorry, maven failed to close Nexus Repository (Repo ID: $2). Process aborted. !!!"
    fi
    exit 1
  fi
  printFooter "Close Nexus Repository (Repo ID: $2)"
  # log status
  release_status_write_step $NEXUS_CLOSE_STAGING_REPO $STATUS_DONE
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
  # log status
  release_status_write_step $NEXUS_DROP_STAGING_REPO $STATUS_IN_PROGESS

  nexus_url=$NEXUS_REPO_URL
  maven_server_id=$NEXUS_STAGING_SERVER_ID
  # Concat NEXUS PROFILE ID env variable with id from catalog
  ## to uppercase
  profile=$(echo $3 | tr [a-z] [A-Z])
  NEXUS_PROFILE_STRING=NEXUS_STAGING_PROFILE_${profile}_ID
  eval NEXUS_STAGING_PROFILE_ID="\$$NEXUS_PROFILE_STRING"

  ######################  NEXUS JBOSS TESTS #####################
  ## Update variables if we need to use JBoss infrastructure
  if [ $2 == "jboss" ]; then
   nexus_url=$NEXUS_JBOSS_REPO_URL
   maven_server_id=$NEXUS_JBOSS_STAGING_SERVER_ID
  fi
  ######################  NEXUS JBOSS TESTS #####################

  mvn nexus-staging:rc-drop -DserverId=$maven_server_id -DnexusUrl=$nexus_url -DstagingRepositoryId=$1 -DstagingDescription=$4 2>&1 | tee -a ${LOGS_DIR}/infos.log
  if [ "$?" -ne "0" ]; then
    error "!!! Sorry, maven failed to close Drop Repository (Repo ID: $1). Process aborted. !!!"
    exit 1
  fi
  printFooter "Drop Nexus Repository  (Repo ID: $1)"
  # log status
  release_status_write_step $NEXUS_DROP_STAGING_REPO $STATUS_DONE
}

# Deploy artifcats to a Nexus Staging Repository.
#
# Params required:
# $1: STAGING_REPO_ID
# $2: Nexus Host (exoplatform or jboss)
# $3: Nexus Staging Profile
function nexus_deploy_staged_repo {
  printHeader "Deploy Nexus Repository  (Repo ID: $1)"
  # log status
  release_status_write_step $NEXUS_DEPLOY_IN_STAGING_REPO $STATUS_IN_PROGESS

  nexus_url=$NEXUS_REPO_URL
  maven_server_id=$NEXUS_STAGING_SERVER_ID
  maven_profile="exo-staging"
  # Concat NEXUS PROFILE ID env variable with id from catalog
  ## to uppercase
  profile=$(echo $3 | tr [a-z] [A-Z])
  NEXUS_PROFILE_STRING=NEXUS_STAGING_PROFILE_${profile}_ID
  eval NEXUS_STAGING_PROFILE_ID="\$$NEXUS_PROFILE_STRING"

  ######################  NEXUS JBOSS TESTS #####################
  ## Update variables if we need to use JBoss infrastructure
  if [ $2 == "jboss" ]; then
   nexus_url=$NEXUS_JBOSS_REPO_URL
   maven_server_id=$NEXUS_JBOSS_STAGING_SERVER_ID
   maven_profile="jboss-staging"
  fi
  ######################  NEXUS JBOSS TESTS #####################

  ##DEBUG
  log "[NEXUS]" $nexus_url " - " $maven_server_id " - " $NEXUS_STAGING_PROFILE_ID "-" $maven_profile

  mvn nexus-staging:deploy-staged-repository -DnexusUrl=$nexus_url -DserverId=$maven_server_id -DrepositoryDirectory=${LOCAL_STAGING_DIR} -DstagingProfileId=$NEXUS_STAGING_PROFILE_ID -DstagingRepositoryId=$1 -Pexo-release,$maven_profile 2>&1 | tee -a ${LOGS_DIR}/infos.log
  if [ "$?" -ne "0" ]; then
    error "!!! Sorry, maven failed to deploy Nexus Repository (Repo ID: $1). Process aborted. !!!"
    exit 1
  fi
  printFooter "Deploy Nexus Repository  (Repo ID: $1)"
  # log status
  release_status_write_step $NEXUS_DEPLOY_IN_STAGING_REPO $STATUS_DONE
}

# Release 1 or several Nexus Repositoy(ies)
# ./plf-staging-repos.sh release id1,id2,id3
function nexus_release_staging_repo {
  printHeader "Release Nexus Repository  (Repo ID: $1)"
  release_status_write_step $NEXUS_RELEASE_STAGING_REPO $STATUS_IN_PROGESS

  nexus_url=$NEXUS_REPO_URL
  maven_server_id=$NEXUS_STAGING_SERVER_ID

  # Concat NEXUS PROFILE ID env variable with id from catalog
  ## to uppercase
  profile=$(echo $3 | tr [a-z] [A-Z])
  NEXUS_PROFILE_STRING=NEXUS_STAGING_PROFILE_${profile}_ID
  eval NEXUS_STAGING_PROFILE_ID="\$$NEXUS_PROFILE_STRING"

  ######################  NEXUS JBOSS TESTS #####################
  ## Update variables if we need to use JBoss infrastructure
  if [ $2 == "jboss" ]; then
   nexus_url=$NEXUS_JBOSS_REPO_URL
   maven_server_id=$NEXUS_JBOSS_STAGING_SERVER_ID
  fi
  ######################  NEXUS JBOSS TESTS #####################

  mvn nexus-staging:rc-release -DnexusUrl=$nexus_url -DserverId=$maven_server_id  -DstagingRepositoryId=$1 -DstagingDescription=$4 2>&1 | tee -a ${LOGS_DIR}/infos.log
  if [ "$?" -ne "0" ]; then
    error "!!! Sorry, maven failed to release Nexus Repository (Repo ID: $2). Process aborted. !!!"
    exit 1
  fi
  printFooter "Release Nexus Repository  (Repo ID: $1)"
  release_status_write_step $NEXUS_RELEASE_STAGING_REPO $STATUS_DONE
}
