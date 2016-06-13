#!/bin/bash -eu

#
function git_clone_all {
  echo "==============================================================================="
  echo "Clone all projects defined into the catalog"
  echo "==============================================================================="
  ARR=( $(json -f ${DATAS_DIR}/catalog.json -M -a name git_organization release.version release.branch -d,) )

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
  ARR=( $(json -f ${DATAS_DIR}/catalog.json -M -c 'this.labels.indexOf('${request}')>-1' -a name git_organization release.version release.branch -d,) )

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
  ARR=( $(json -f ${DATAS_DIR}/catalog.json -M -c 'this.name == '${request}' ' -a name git_organization release.version release.branch) )
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
  gitCommand $1 clone git@$GIT_HOST:$2/$1.git
  # check if default branch is same as branch to checkout
  if [ $(gitCommandIsDefaultBranchEqualsCOBranch $1 $3) = "false" ]; then
     log "Git checkout the right branch"
     gitCommand $1 checkout -b $3 remotes/origin/$3
  fi

  release_status_write_step $GIT_CLONE $STATUS_DONE
}
