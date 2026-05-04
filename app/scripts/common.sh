#!/bin/bash -eu
set -o pipefail

DATE=$(date "+%Y-%m-%d--%H-%M-%S")
SEP="$(echo | tr '\n' '\001')"

DEBUG=${DEBUG:-0}

# Debug function
function db {
  [[ $DEBUG -eq 1 ]] && echo "$@" >&2 || true
}

# Log function: reads from arguments or stdin
function log {
  if [ $# -gt 0 ]; then
    echo "[$(date +"%D %T")] $*" | tee -a "${LOGS_DIR}/infos.log"
    db "$*"
  else
    while IFS= read -r data; do
      echo "[$(date +"%D %T")] $data" | tee -a "${LOGS_DIR}/infos.log"
      db "$data"
    done
  fi
}

# Error function — writes to stderr and to the error log
function error {
  echo "[$(date +"%D %T")] $*" | tee -a "${LOGS_DIR}/errors.log" >&2
  db "$*"
}

function printHeader {
  log ""
  log "==============================================================================="
  log " Begin $1..."
  log "==============================================================================="
  log ""
}

function printFooter {
  log ""
  log "==============================================================================="
  log " End $1..."
  log "==============================================================================="
  log ""
}

# Source bashrc if present
if [ -e "$HOME/.bashrc" ]; then
  echo "Loading ... $HOME/.bashrc"
  source "$HOME/.bashrc"
fi

# Warn if GPG key is missing (required for releases)
if [ ! -e "$HOME/.gpg.key" ]; then
  echo "==============================================================================="
  echo "!!! Take care, GPG key isn't provided. It is required to do releases !!!"
  echo "==============================================================================="
fi

# Run a git command inside the project directory
# Usage: gitCommand <project> <git-command> [args...]
function gitCommand {
  local PRJ=$1
  local COMMAND=$2
  shift 2
  log "Project $PRJ : git $COMMAND in progress ..."
  if [ "$COMMAND" = "clone" ]; then
    (cd "$PRJ_DIR" && git "$COMMAND" "$@" 2>&1 | tee -a "${LOGS_DIR}/infos.log")
  else
    (cd "$PRJ_DIR/$PRJ" && git "$COMMAND" "$@" 2>&1 | tee -a "${LOGS_DIR}/infos.log")
  fi
  local git_exit=${PIPESTATUS[0]}
  if [ "$git_exit" -ne 0 ]; then
    error "!!! Sorry, git failed in $PRJ_DIR/$PRJ. Process aborted. !!!"
    exit 1
  fi
  log "Done."
  log "==============================================================================="
}

# Returns "true" if the working tree has uncommitted changes, "false" otherwise
function gitCommandIsThereFilesToCommit {
  local PRJ=$1
  if [ -z "$(cd "$PRJ_DIR/$PRJ" && git status --porcelain 2>&1)" ]; then
    echo "false"
  else
    echo "true"
  fi
}

# Returns "true" if the current HEAD branch matches BRANCH
function gitCommandIsDefaultBranchEqualsCOBranch {
  local PRJ=$1
  local BRANCH=$2
  if [ "$BRANCH" = "$(cd "$PRJ_DIR/$PRJ" && git rev-parse --abbrev-ref HEAD)" ]; then
    echo "true"
  else
    echo "false"
  fi
}

# Run a Maven command inside the project directory
# Usage: mvnCommand <project> [mvn-args...]
function mvnCommand {
  local PRJ=$1
  shift
  log "Project $PRJ - mvn in progress ..."
  (cd "$PRJ_DIR/$PRJ" && mvn -B -e "$@" 2>&1 | tee -a "${LOGS_DIR}/infos.log")
  local mvn_exit=${PIPESTATUS[0]}
  if [ "$mvn_exit" -ne 0 ]; then
    error "!!! Sorry, maven failed in $PRJ_DIR/$PRJ. Process aborted. !!!"
    exit 1
  fi
  log "Done."
  log "==============================================================================="
}

# Exception codes
export exReleasePrerequisite=100
export exReleasePrerequisiteKO=103
export exProjectBuild=200
export exProjectBuildKO=203
export exNexusStaging=300

function displayAvailableProjects {
  log " ====== AVAILABLE PROJECTS ============"
  if [ -f "${DATAS_DIR}/catalog.json" ]; then
    local -a ARR
    mapfile -t ARR < <(jq -r '.[] | [.name, .release.version, .labels, .release.branch] | join(":")' "${DATAS_DIR}/catalog.json")
    if [ ${#ARR[@]} -eq 0 ]; then
      error "No projects available"
    else
      for project in "${ARR[@]}"; do
        IFS=':' read -r -a params <<< "$project"
        log "* ${params[0]} - ${params[1]} - ${params[3]} (${params[2]})"
      done
    fi
  else
    log "[ERROR] ${DATAS_DIR}/catalog.json not found."
    log "[HELP] You can do:"
    log " * eXoR.sh catalog-from-url <TASK-ID>"
    log "in order to download the <TASK-ID>.json file."
  fi
}

function getProjectByNameFromCatalog {
  local project_name="$1"
  local catalog_file="${DATAS_DIR}/catalog.json"
  local result

  result=$(jq -r --arg name "$project_name" \
    '.[] | select(.name == $name) |
     [.name, .git_organization, .release.version, .release.branch,
      .release.next_snapshot_version, .release.nexus_host,
      .release.nexus_staging_profile] | join(":")' "$catalog_file")

  if [[ -z "$result" ]]; then
    echo "0"
  else
    echo "$result"
  fi
}

function getUserAgent {
  echo "eXo Release Manager v$EXOR_VERSION ($exo_user)"
}
