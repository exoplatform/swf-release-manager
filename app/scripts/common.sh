#!/bin/bash -eu
set -o pipefail

DATE=`date "+%Y-%m-%d--%H-%M-%S"`
SEP="`echo | tr '\n' '\001'`"

DEBUG=1
# Debug function
# Usage: db message in parts
function db {
  if [ $DEBUG -eq 1 ];
  then
    echo "$@"
  fi
}
# Log function, handles input from stdin or from arguments
# Usage: log message in parts
# Usage2: echo message | log
function log {
  # If there are parameters read from parameters
  if [ $# -gt 0 ]; then
    echo "[$(date +"%D %T")] $@" | tee -a ${LOGS_DIR}/infos.log
    db "$@"
  else
    # If there are no parameters read from stdin
    while read data
    do
      echo "[$(date +"%D %T")] $data" | tee -a ${LOGS_DIR}/infos.log
      db "$data"
    done
  fi
}

# Error function
# Usage: error N message
function error {
  echo "[$(date +"%D %T")] $@" | tee -a ${LOGS_DIR}/errors.log
  db "$@"
}

#  ============= BEGIN: essential functions ===========================================
# Print header for log
function printHeader {
  log ""
  log "==============================================================================="
  log " Begin $1..."
  log "==============================================================================="
  log ""
}

# Print Footer for log
function printFooter {
  log ""
  log "==============================================================================="
  log " End $1..."
  log "==============================================================================="
  log ""
}


# Shell Environment
if [ -e $HOME/.bashrc ]; then
  echo "Loading ... $HOME/.bashrc"
  source $HOME/.bashrc
fi


# Check if the GPG key is installed
if [ ! -e $HOME/.gnupg/secring.gpg -o ! -e $HOME/.gnupg/pubring.gpg -o ! -e $HOME/.gnupg/gpg.conf ]; then
  echo "==============================================================================="
  echo "!!! Take care, GPG key isn't setup. It is required to do releases !!!"
  echo "==============================================================================="
fi




# Executes $2 git command with "$@" parameters in $1 project directory
function gitCommand {
  PRJ=$1
  COMMAND=$2
  shift
  shift
  log "Project $PRJ : git $COMMAND in progress ..."
  if [ "$COMMAND" = "clone" ]; then
    (cd $PRJ_DIR && git $COMMAND "$@" 2>&1 | tee -a ${LOGS_DIR}/infos.log)
  else
    (cd $PRJ_DIR/$PRJ && git $COMMAND "$@" 2>&1 | tee -a ${LOGS_DIR}/infos.log)
  fi
  if [ "$?" -ne "0" ]; then
    error "!!! Sorry, git failed in $PRJ_DIR/$PRJ. Process aborted. !!!"
    exit 1
  fi
  log "Done."
  log "==============================================================================="
}

# command to know if files have to be committed
function gitCommandIsThereFilesToCommit {
  PRJ=$1
  shift
  shift
  if [ -z "$(cd $PRJ_DIR/$PRJ && git status --porcelain  2>&1)" ];
  then
      echo "false"
  else
      # changes to commit
      echo "true"
  fi
}

function gitCommandIsDefaultBranchEqualsCOBranch {
  PRJ=$1
  BRANCH=$2
  shift
  shift
  if [ $BRANCH = $(cd $PRJ_DIR/$PRJ && git rev-parse --abbrev-ref HEAD) ];
  then
      echo "true"
  else
      # changes to commit
      echo "false"
  fi
}



# #############
# MVN Functions
# #############

# Call "$@" maven phases/plugins and args in $1 project directory
function mvnCommand {
  PRJ=$1
  shift
  log "Project $PRJ - mvn in progress ..."
  cd $PRJ_DIR/$PRJ
  mvn -B -e "$@" 2>&1 | tee -a ${LOGS_DIR}/infos.log
  if [ "$?" -ne "0" ]; then
    error "!!! Sorry, maven failed in $PRJ_DIR/$PRJ. Process aborted. !!!"
    exit 1
  fi
  cd -
  log "Done."
  log "==============================================================================="
}


#
# Define possible Exception during the process
export exReleasePrerequisite=100
export exReleasePrerequisiteKO=103
# Code 2xx for Maven errors
export exProjectBuild=200
export exProjectBuildKO=203
# Code 3xx for Nexus errors
export exNexusStaging=300

function displayAvailableProjects {
  log " ====== AVAILABLE PROJECTS ============"
  if [ -f ${DATAS_DIR}/catalog.json ]; then
    ARR=($(jq -r '.[] | [.name, .release.version, .labels, .release.branch] | join(":")' ${DATAS_DIR}/catalog.json))
    if [  -z ${ARR+x}  ]; then
      error "No projects available"
    else
      for project in "${ARR[@]}"
      do
        IFS=': ' read -r -a params <<< "$project"
        log "* ${params[0]} - ${params[1]} - ${params[3]} (${params[2]})"
      done
    fi
  else
     log "[ERROR] ${DATAS_DIR}/catalog.json not found."
     log "[HELP] You can do:"
     log " * eXoR.sh catalog-from-url <TASK-ID> "
     log "in order to download the <TASK-ID>.json file."
  fi
}

#
#
#
function getProjectByNameFromCatalog {
  local result=''
  # Look for the projectName into the catalog
  projectName="\"$1\""
  ARR=($(jq -r '.[] | select(.name == '"$projectName"') | [.name, .git_organization, .release.version, .release.branch, .release.next_snapshot_version, .release.nexus_host, .release.nexus_staging_profile] | join(":")' ${DATAS_DIR}/catalog.json))

  if [  -z ${ARR+x}  ]; then
    # "No projects with name: " $1
    result="0"
  else
    for project in "${ARR[@]}"
    do
     result=${project}
    done
  fi
  echo $result
}

function getUserAgent {

  result="eXo Release Manager v$EXOR_VERSION ($exo_user)"

  echo $result
}
