#!/bin/bash -eu
set -o pipefail

#
function git_clone_all {
  echo "==============================================================================="
  echo "Clone all projects defined into the catalog"
  echo "==============================================================================="
  ARR=($(jq -r '.[] | [.name, .git_organization, .release.version, .release.branch] | join(",")' ${DATAS_DIR}/catalog.json))
  if [  -z ${ARR+x}  ]; then
    error "No projects!"
  else
    for project in "${ARR[@]}"
    do
      IFS=',' read -r -a params <<< "$project"
      PROJECT=${params[0]}
      GIT_ORGANIZATION=${params[1]}
      VERSION=${params[2]}
      BRANCH=${params[3]}
      git_clone ${PROJECT} ${GIT_ORGANIZATION} ${BRANCH} ${VERSION}
    done
  fi
}

function git_clone_all_with_label {
  request="\"$1\""
  ARR=($(jq -r '.[] | select(.labels | contains('${request}')) | [.name, .git_organization, .release.version, .release.branch] | join(",")' ${DATAS_DIR}/catalog.json))

  if [  -z ${ARR+x}  ]; then
    error "No projects with label: " $1
  else
    for project in "${ARR[@]}"
    do
      IFS=',' read -r -a params <<< "$project"
      PROJECT=${params[0]}
      GIT_ORGANIZATION=${params[1]}
      VERSION=${params[2]}
      BRANCH=${params[3]}
      git_clone ${PROJECT} ${GIT_ORGANIZATION} ${BRANCH} ${VERSION}
    done
  fi
}

#
# Clone 1 project via its github name
function git_clone_single {
  request="\"$1\""
  ARR=($(jq -r '.[] | select(.name == '$request') | [.name, .git_organization, .release.version, .release.branch] | join(" ")' ${DATAS_DIR}/catalog.json))
  if [  -z ${ARR+x}  ]; then
    echo "No projects with name: " $1
  else
    PROJECT=${ARR[0]}
    GIT_ORGANIZATION=${ARR[1]}
    VERSION=${ARR[2]}
    BRANCH=${ARR[3]}

    git_clone ${PROJECT} ${GIT_ORGANIZATION} ${BRANCH} ${VERSION}
  fi
}

#
# Clone <git project> <git organization> <git branch> <version>
function git_clone {
  if [ -e $PRJ_DIR/$1 ]; then
    rm -rf $PRJ_DIR/$1
  fi
  log "==========================================================="
  log "Cloning $1 from $GIT_HOST $2 for Release Version $4 on Branch $3"
  log "==========================================================="
  release_status_write_step $GIT_CLONE $STATUS_IN_PROGESS
  gitCommand $1 clone --depth 1 --branch $3 git@$GIT_HOST:$2/$1.git
  if [ "${1:-}" = "platform-private-distributions" ] && [ ! -f ~/.tmpgitignore ]; then 
    echo "Repository with LFS detected. Initializing..."
    gitCommand $1 lfs install 
    gitCommand $1 lfs track $(gitCommand $1 lfs ls-files | awk -F. '{ ext="*."$NF; print ext}' | uniq | xargs -r)
    gitCommand $1 reset --hard origin/$3
    # Hack: to prevent committing .gitattributes with Release process
    echo .gitattributes > ~/.tmpgitignore 
    gitCommand $1 config core.excludesfile ~/.tmpgitignore
    # End of Hack
    echo "LFS initialization done."
  fi
  release_status_write_step $GIT_CLONE $STATUS_DONE
}
