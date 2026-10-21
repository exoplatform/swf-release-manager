#!/bin/bash -eu
set -o pipefail

##
# All commands related to Nexus Repository 3 (Pro) staging.
#
# Nexus 3 Pro staging is tag based (there is no staging profile / "close" like in Nexus 2):
# * create  : generate the tag that identifies this release (no server call)
# * deploy  : upload the locally staged artifacts to the staging repository with the tag
# * close   : check that the tag holds components in the staging repository
# * release : move the tagged components from the staging repository to the release repository
# * drop    : delete the tagged components
# The Sonatype nxrm3-maven-plugin does the upload/move/delete.
#
# The catalog "nexus_staging_profile" selects the repositories pair, configured with:
#   NEXUS_STAGING_REPO_<PROFILE>  (hosted repository with staging enabled)
#   NEXUS_RELEASE_REPO_<PROFILE>  (destination of the move)
#
# NOTE: the nexus_host catalog field is not used any more (a single Nexus 3 server).
##

# Nexus Repository 3 server (fixed, not configurable)
NEXUS_REPO_URL="https://repository2.exoplatform.org"

NXRM3_PLUGIN="org.sonatype.plugins:nxrm3-maven-plugin:${NXRM3_PLUGIN_VERSION:-1.0.13}"

function usage {
 echo "Usage: $0 action tag"
 echo "  action  : close | drop | release | list"
 echo "  tag     : The Nexus 3 staging tag of the release"
}

# Nexus 3 tag names only allow a restricted charset
function nexus_sanitize_tag {
  echo "$1" | tr -c 'A-Za-z0-9._\n-' '-'
}

# Set NEXUS_STAGING_REPO and NEXUS_RELEASE_REPO from the catalog staging profile
# $1: Nexus Staging Profile
function nexus_resolve_repos {
  local profile stagingVar releaseVar
  profile=$(echo "$1" | tr '[:lower:]' '[:upper:]' | tr -c 'A-Z0-9\n' '_')
  stagingVar=NEXUS_STAGING_REPO_${profile}
  releaseVar=NEXUS_RELEASE_REPO_${profile}
  NEXUS_STAGING_REPO="${!stagingVar:-}"
  NEXUS_RELEASE_REPO="${!releaseVar:-}"
  if [ -z "$NEXUS_STAGING_REPO" ] || [ -z "$NEXUS_RELEASE_REPO" ]; then
    error "[ERROR] $stagingVar and $releaseVar must be defined for the Nexus profile '$1'."
    return 1
  fi
}

# Run a nxrm3 plugin goal (none of the used goals needs a project)
function nexus_mvn {
  if ! mvn -B -e "$@" 2>&1 | tee -a ${LOGS_DIR}/infos.log; then
    return 1
  fi
}

# Number of components carrying a tag in a repository
# $1: repository $2: tag
function nexus_count_tagged_components {
  curl -sS -G -u "$nexus_login:$(decompress $nexus_token)" -H "User-Agent: $(getUserAgent)" \
    --data-urlencode "repository=$1" --data-urlencode "tag=$2" \
    "$NEXUS_REPO_URL/service/rest/v1/search" | jq -r '.items | length'
}

#
# All components of a Staging Repository
# $1: Nexus Staging Profile
function nexus_all_staging_repos {
  nexus_resolve_repos $1 || return 1
  log "============ Display components of $NEXUS_STAGING_REPO ================"
  curl -sS -u "$nexus_login:$(decompress $nexus_token)" -H "User-Agent: $(getUserAgent)" \
    "$NEXUS_REPO_URL/service/rest/v1/components?repository=$NEXUS_STAGING_REPO" | jq -r '.items[] | [.group, .name, .version] | join(":")'
}

# "Create" the Nexus staging: Nexus 3 creates the tag on the first upload, so only
# generate the tag (saved as the staged repository id of release.json).
#
# Params required:
# $1: description (task id / project / version)
# $2: Nexus Host (unused)
# $3: Nexus Staging Profile
function nexus_create_staging_repo {
  printHeader "Create Nexus Staging Tag"
  release_status_write_step $NEXUS_CREATE_STAGING_REPO $STATUS_IN_PROGESS

  nexus_resolve_repos $3 || return 1
  local tag
  tag=$(nexus_sanitize_tag "$1")
  if [ -z "$tag" ]; then
    error "[ERROR] Nexus staging tag is empty."
    return 1
  fi

  release_status_staging_repo_created $tag
  printFooter "Create Nexus Staging Tag (${tag} in ${NEXUS_STAGING_REPO})"
  release_status_write_step $NEXUS_CREATE_STAGING_REPO $STATUS_DONE
}

# Upload the locally staged artifacts (${LOCAL_STAGING_DIR}) to the staging repository, tagged.
#
# Params required:
# $1: tag
# $2: Nexus Host (unused)
# $3: Nexus Staging Profile
function nexus_deploy_staged_repo {
  printHeader "Deploy Nexus Staging Tag (Tag: $1)"
  release_status_write_step $NEXUS_DEPLOY_IN_STAGING_REPO $STATUS_IN_PROGESS

  nexus_resolve_repos $3 || return 1
  log "[NEXUS]" $NEXUS_REPO_URL " - " $NEXUS_STAGING_SERVER_ID " - " $NEXUS_STAGING_REPO " - " $1

  if ! nexus_mvn $NXRM3_PLUGIN:upload -DnexusUrl=$NEXUS_REPO_URL -DserverId=$NEXUS_STAGING_SERVER_ID \
        -Drepository=$NEXUS_STAGING_REPO -Dtag=$1 -DaltStagingDirectory=${LOCAL_STAGING_DIR}; then
    error "!!! Sorry, maven failed to upload to Nexus staging (Tag: $1). Process aborted. !!!"
    return 1
  fi
  printFooter "Deploy Nexus Staging Tag (Tag: $1)"
  release_status_write_step $NEXUS_DEPLOY_IN_STAGING_REPO $STATUS_DONE
}

#
# "Close": there is no close in Nexus 3, check that the tag holds components and,
# when autorelease is requested, release them.
# Params required:
# $1: Project name
# $2: tag
# $3: Nexus Host (unused)
# $4: Nexus Staging Profile
# $5: description
# $6: autorelease (true or false)
function nexus_close_staging_repo {
  printHeader "Close Nexus Staging Tag (Tag: $2)"
  release_status_write_step $NEXUS_CLOSE_STAGING_REPO $STATUS_IN_PROGESS

  nexus_resolve_repos $4 || return 1
  local count
  count=$(nexus_count_tagged_components $NEXUS_STAGING_REPO $2) || count=0
  if ! [[ "$count" =~ ^[0-9]+$ ]] || [ "$count" -eq 0 ]; then
    error "!!! No component tagged '$2' found in Nexus repository $NEXUS_STAGING_REPO. Process aborted. !!!"
    return 1
  fi
  log "$count component(s) tagged '$2' staged in $NEXUS_STAGING_REPO"
  printFooter "Close Nexus Staging Tag (Tag: $2)"
  release_status_write_step $NEXUS_CLOSE_STAGING_REPO $STATUS_DONE

  if [ "${6:-false}" = "true" ]; then
    nexus_release_staging_repo $2 $3 $4 $5
  fi
}

# Drop (delete) the components of the tag
#
# Params required:
# $1: tag
# $2: Nexus Host (unused)
# $3: Nexus Staging Profile
# $4: description
function nexus_drop_staging_repo {
  printHeader "Drop Nexus Staging Tag (Tag: $1)"
  release_status_write_step $NEXUS_DROP_STAGING_REPO $STATUS_IN_PROGESS

  if ! nexus_mvn $NXRM3_PLUGIN:staging-delete -DnexusUrl=$NEXUS_REPO_URL -DserverId=$NEXUS_STAGING_SERVER_ID -Dtag=$1; then
    error "!!! Sorry, maven failed to drop Nexus staging (Tag: $1). Process aborted. !!!"
    return 1
  fi
  printFooter "Drop Nexus Staging Tag (Tag: $1)"
  release_status_write_step $NEXUS_DROP_STAGING_REPO $STATUS_DONE
}

# Release: move the tagged components from the staging repository to the release repository
# ./nexus-repos.sh release tag
#
# Params required:
# $1: tag
# $2: Nexus Host (unused)
# $3: Nexus Staging Profile
# $4: description
function nexus_release_staging_repo {
  printHeader "Release Nexus Staging Tag (Tag: $1)"
  release_status_write_step $NEXUS_RELEASE_STAGING_REPO $STATUS_IN_PROGESS

  nexus_resolve_repos $3 || return 1
  if ! nexus_mvn $NXRM3_PLUGIN:staging-move -DnexusUrl=$NEXUS_REPO_URL -DserverId=$NEXUS_STAGING_SERVER_ID \
        -Dtag=$1 -Drepository=$NEXUS_STAGING_REPO -DsourceRepository=$NEXUS_STAGING_REPO -DdestinationRepository=$NEXUS_RELEASE_REPO; then
    error "!!! Sorry, maven failed to release Nexus staging (Tag: $1). Process aborted. !!!"
    return 1
  fi
  printFooter "Release Nexus Staging Tag (Tag: $1)"
  release_status_write_step $NEXUS_RELEASE_STAGING_REPO $STATUS_DONE
}
