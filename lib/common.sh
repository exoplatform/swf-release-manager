#!/bin/bash -eu
set -o pipefail

DATE=$(date "+%Y-%m-%d--%H-%M-%S")
SEP=$'\001'

# Color support for terminal output (stripped from log files)
if [ -t 1 ] || [ -n "${JENKINS_HOME:-}" ] || [ -n "${BUILD_URL:-}" ]; then
  COLOR_RESET=$'\033[0m'
  COLOR_GREEN=$'\033[32m'
  COLOR_RED=$'\033[31m'
  COLOR_YELLOW=$'\033[33m'
  COLOR_BLUE=$'\033[34m'
  COLOR_CYAN=$'\033[36m'
  COLOR_BOLD=$'\033[1m'
else
  COLOR_RESET=''
  COLOR_GREEN=''
  COLOR_RED=''
  COLOR_YELLOW=''
  COLOR_BLUE=''
  COLOR_CYAN=''
  COLOR_BOLD=''
fi

DEBUG=1
# Debug function
# Usage: db message in parts
function db {
  if [ "${DEBUG:-0}" -eq 1 ];
  then
    echo "$@"
  fi
}
# Log function, handles input from stdin or from arguments
# Usage: log message in parts
# Usage2: echo message | log
function log {
  if [ $# -gt 0 ]; then
    printf '%s[%s]%s %s\n' "${COLOR_BLUE}" "$(date +"%D %T")" "${COLOR_RESET}" "$*" | tee -a "${LOGS_DIR}/infos.log"
    db "$@"
  else
    while read -r data
    do
      printf '%s[%s]%s %s\n' "${COLOR_BLUE}" "$(date +"%D %T")" "${COLOR_RESET}" "$data" | tee -a "${LOGS_DIR}/infos.log"
      db "$data"
    done
  fi
}

# Error function
# Usage: error N message
function error {
  printf '%s[%s]%s %s\n' "${COLOR_RED}" "$(date +"%D %T")" "${COLOR_RESET}" "$*" | tee -a "${LOGS_DIR}/errors.log"
  db "$@"
}

#  ============= BEGIN: essential functions ===========================================
# Print header for log
function printHeader {
  log ""
  log "${COLOR_CYAN}${COLOR_BOLD}===============================================================================${COLOR_RESET}"
  log "${COLOR_CYAN}${COLOR_BOLD} Begin $1...${COLOR_RESET}"
  log "${COLOR_CYAN}${COLOR_BOLD}===============================================================================${COLOR_RESET}"
  log ""
}

# Print Footer for log
function printFooter {
  log ""
  log "${COLOR_CYAN}${COLOR_BOLD}===============================================================================${COLOR_RESET}"
  log "${COLOR_CYAN}${COLOR_BOLD} End $1...${COLOR_RESET}"
  log "${COLOR_CYAN}${COLOR_BOLD}===============================================================================${COLOR_RESET}"
  log ""
}


# Shell Environment
if [ -e "${HOME}/.bashrc" ]; then
  printf 'Loading ... %s\n' "${HOME}/.bashrc"
  source "${HOME}/.bashrc"
fi

# Check if the GPG key is installed
if [ ! -e "${HOME}/.gpg.key" ]; then
  printf '%s\n' "==============================================================================="
  printf '%s\n' "!!! Take care, GPG key isn't provided. It is required to do releases !!!"
  printf '%s\n' "==============================================================================="
fi




# Executes $2 git command with "$@" parameters in $1 project directory
function gitCommand {
  local PRJ=$1
  local COMMAND=$2
  shift
  shift
  log "Project ${PRJ} : git ${COMMAND} in progress ..."
  if [ "${COMMAND}" = "clone" ]; then
    (cd "${PRJ_DIR}" && git "${COMMAND}" "$@" 2>&1 | tee -a "${LOGS_DIR}/infos.log")
  else
    (cd "${PRJ_DIR}/${PRJ}" && git "${COMMAND}" "$@" 2>&1 | tee -a "${LOGS_DIR}/infos.log")
  fi
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    error "!!! Sorry, git failed in ${PRJ_DIR}/${PRJ}. Process aborted. !!!"
    exit 1
  fi
  log "Done."
  log "==============================================================================="
}

# command to know if files have to be committed
function gitCommandIsThereFilesToCommit {
  local PRJ=$1
  if [ -z "$(cd "${PRJ_DIR}/${PRJ}" && git status --porcelain 2>&1)" ]; then
      echo "false"
  else
      echo "true"
  fi
}

function gitCommandIsDefaultBranchEqualsCOBranch {
  local PRJ=$1
  local BRANCH=$2
  if [ "${BRANCH}" = "$(cd "${PRJ_DIR}/${PRJ}" && git rev-parse --abbrev-ref HEAD)" ]; then
      echo "true"
  else
      echo "false"
  fi
}



# #############
# MVN Functions
# #############

# Call "$@" maven phases/plugins and args in $1 project directory
function mvnCommand {
  local PRJ=$1
  shift
  log "Project ${PRJ} - mvn in progress ..."
  (
    cd "${PRJ_DIR}/${PRJ}"
    mvn -B -e "$@" 2>&1 | tee -a "${LOGS_DIR}/infos.log"
  )
  if [ "${PIPESTATUS[0]}" -ne 0 ]; then
    error "!!! Sorry, maven failed in ${PRJ_DIR}/${PRJ}. Process aborted. !!!"
    exit 1
  fi
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
  if [ -f "${DATA_DIR}/catalog.json" ]; then
    local ARR
    mapfile -t ARR < <(jq -r '.[] | [.name, .release.version, .labels, .release.branch] | join(":")' "${DATA_DIR}/catalog.json")
    if [ "${#ARR[@]}" -eq 0 ]; then
      error "No projects available"
    else
      for project in "${ARR[@]}"
      do
        IFS=': ' read -r -a params <<< "$project"
        log "* ${params[0]} - ${params[1]} - ${params[3]} (${params[2]})"
      done
    fi
  else
     log "[ERROR] ${DATA_DIR}/catalog.json not found."
     log "[HELP] You can do:"
     log " * eXoR.sh catalog-from-url <TASK-ID> "
     log "in order to download the <TASK-ID>.json file."
  fi
}

#
#
#
function getProjectByNameFromCatalog {
  local project_name="$1"
  local catalog_file="${DATA_DIR}/catalog.json"
  local result=""

  # Escape double quotes for jq
  local jq_project_name
  jq_project_name=$(printf '%s' "$project_name" | sed 's/"/\\"/g')

  result=$(jq -r --arg name "$jq_project_name" \
    '.[] | select(.name == $name) |
     [.name, .git_organization, .release.version, .release.branch,
      .release.next_snapshot_version, .release.nexus_host,
      .release.nexus_staging_profile] | join(":")' "$catalog_file")

  # If result is empty, return "0"
  if [[ -z "$result" ]]; then
    echo "0"
  else
    echo "$result"
  fi
}


function getUserAgent {
  local result="eXo Release Manager v${EXOR_VERSION} (${exo_user})"
  printf '%s' "$result"
}
