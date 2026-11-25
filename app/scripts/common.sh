#!/bin/bash
# Shared helpers: logging, git/maven wrappers, JSON and catalog helpers.
# Meant to be sourced by eXoR.sh / setup-env.sh (which set -euo pipefail).

# shellcheck disable=SC2034 # used by setup-env.sh
DATE=$(date "+%Y-%m-%d--%H-%M-%S")
# shellcheck disable=SC2034 # used by setup-env.sh, maven-dependencies.sh
SEP=$(printf '\001')

# ###############
# Logging
#   LOG_LEVEL=DEBUG|INFO|WARN|ERROR (default INFO; DEBUG=1 is kept as an alias of DEBUG)
#   Everything goes to ${LOGS_DIR}/infos.log, WARN/ERROR also to stderr and errors.log.
#   Registered secrets are masked in every line.
# ###############
LOG_LEVEL=${LOG_LEVEL:-INFO}
[ "${DEBUG:-0}" = "1" ] && LOG_LEVEL=DEBUG
LOG_SECRETS=()
mkdir -p "${LOGS_DIR:?LOGS_DIR must be set}"

# Escape a string for the regex part of a sed s/// command
function sed_escape_regex { printf '%s' "$1" | sed 's/[][\.*^$/]/\\&/g'; }
# Escape a string for the replacement part of a sed s/// command
function sed_escape_replacement { printf '%s' "$1" | sed 's/[\&/]/\\&/g'; }

# Register a value to mask in the logs (values shorter than 4 characters are ignored)
function log_register_secret {
  if [ "${#1}" -ge 4 ]; then LOG_SECRETS+=("$1"); fi
  return 0
}

# Mask the registered secrets: stdin -> stdout
function log_mask {
  local args=() secret
  for secret in ${LOG_SECRETS[@]+"${LOG_SECRETS[@]}"}; do
    args+=(-e "s/$(sed_escape_regex "$secret")/********/g")
  done
  if [ ${#args[@]} -eq 0 ]; then cat; else sed "${args[@]}"; fi
}

function log_level_num {
  case "$1" in DEBUG) echo 0 ;; INFO) echo 1 ;; WARN) echo 2 ;; *) echo 3 ;; esac
}

# Usage: log_write LEVEL message...   (or message lines on stdin when no message is given)
function log_write {
  local level=$1 line ts
  shift
  if [ "$(log_level_num "$level")" -lt "$(log_level_num "$LOG_LEVEL")" ]; then
    if [ $# -eq 0 ]; then cat >/dev/null; fi
    return 0
  fi
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  {
    if [ $# -gt 0 ]; then printf '%s\n' "$*"; else cat; fi
  } | log_mask | while IFS= read -r line; do
    line=$(printf '[%s] [%-5s] %s' "$ts" "$level" "$line")
    printf '%s\n' "$line" >>"${LOGS_DIR}/infos.log"
    case "$level" in
      WARN | ERROR)
        printf '%s\n' "$line" >>"${LOGS_DIR}/errors.log"
        printf '%s\n' "$line" >&2
        ;;
      *) printf '%s\n' "$line" ;;
    esac
  done
}

function log_debug { log_write DEBUG "$@"; }
function log_info { log_write INFO "$@"; }
function log_warn { log_write WARN "$@"; }
function log_error { log_write ERROR "$@"; }
# Backward compatible names
function log { log_write INFO "$@"; }
function error { log_write ERROR "$@"; }
function db { log_write DEBUG "$@"; }

# Mask, store and display the output of a command: some_command 2>&1 | log_stream
function log_stream {
  log_mask | tee -a "${LOGS_DIR}/infos.log"
}

function printHeader {
  log_info "==============================================================================="
  log_info " Begin $1..."
  log_info "==============================================================================="
}

function printFooter {
  log_info "==============================================================================="
  log_info " End $1..."
  log_info "==============================================================================="
}

# Shell Environment
if [ -e "$HOME/.bashrc" ]; then
  log_debug "Loading ... $HOME/.bashrc"
  # The user shell config is not written for "set -eu": relax them while loading it
  _opts=$-
  set +eu
  # shellcheck disable=SC1091
  source "$HOME/.bashrc"
  [[ $_opts == *e* ]] && set -e
  [[ $_opts == *u* ]] && set -u
  unset _opts
fi

# Check if the GPG key is installed
if [ ! -e "$HOME/.gpg.key" ]; then
  echo "==============================================================================="
  echo "!!! Take care, GPG key isn't provided. It is required to do releases !!!"
  echo "==============================================================================="
fi

# ###############
# Exceptions (exit codes) possible during the process
# ###############
export exReleasePrerequisite=100
export exReleasePrerequisiteKO=103
# Code 2xx for Maven errors
export exProjectBuild=200
export exProjectBuildKO=203
# Code 3xx for Nexus errors
export exNexusStaging=300

# Stop the current (sub)shell with the given exception code
function throw {
  exit "$1"
}

# Human readable text of an exception code
function exception_message {
  case "$1" in
    "$exReleasePrerequisite" | "$exReleasePrerequisiteKO") echo "The Releases Prerequisite are not OK." ;;
    "$exProjectBuild" | "$exProjectBuildKO") echo "The Maven Project failed to build." ;;
    "$exNexusStaging") echo "The Nexus staging operation failed." ;;
    *) echo "An unexpected exception was thrown" ;;
  esac
}

# ###############
# Git
# ###############

# Executes $2 git command with the remaining parameters in the $1 project directory
function gitCommand {
  local prj=$1 command=$2
  shift 2
  local dir="$PRJ_DIR/$prj"
  [ "$command" = "clone" ] && dir="$PRJ_DIR"
  log "Project $prj : git $command in progress ..."
  if ! (cd "$dir" && git "$command" "$@" 2>&1 | log_stream); then
    error "!!! Sorry, git failed in $PRJ_DIR/$prj. Process aborted. !!!"
    exit 1
  fi
  log "Done."
  log "==============================================================================="
}

# Prints "true" if the project has files to commit, "false" otherwise
function gitCommandIsThereFilesToCommit {
  if [ -z "$(cd "$PRJ_DIR/$1" && git status --porcelain 2>&1)" ]; then
    echo "false"
  else
    echo "true"
  fi
}

# ###############
# Maven
# ###############

# Call maven with the given phases/plugins and args in the $1 project directory
function mvnCommand {
  local prj=$1
  shift
  log "Project $prj - mvn in progress ..."
  if ! (cd "$PRJ_DIR/$prj" && mvn -B -e "$@" 2>&1 | log_stream); then
    error "!!! Sorry, maven failed in $PRJ_DIR/$prj. Process aborted. !!!"
    exit "$exProjectBuild"
  fi
  log "Done."
  log "==============================================================================="
}

# ###############
# JSON
# ###############

# Rewrite a JSON file in place: json_update FILE JQ_FILTER [jq options...]
# Values must be given with --arg, never concatenated into the filter.
function json_update {
  local file=$1 filter=$2 tmp
  shift 2
  tmp=$(mktemp "${file}.XXXXXX")
  if jq "$@" "$filter" "$file" >"$tmp"; then
    cat "$tmp" >"$file"
    rm -f "$tmp"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Quote a value for a curl config file (curl -K): escape \ and "
function curl_quote {
  local v=${1//\\/\\\\}
  printf '"%s"' "${v//\"/\\\"}"
}

# Config for `curl -K -` carrying basic auth, so credentials stay out of the process list
# Usage: curl_auth_config user password | curl -K - ...
function curl_auth_config {
  printf 'user = %s\n' "$(curl_quote "$1:$2")"
}

# Value of the NEXUS_STAGING_PROFILE_<PROFILE>_ID environment variable
function nexus_staging_profile_id {
  local var
  var="NEXUS_STAGING_PROFILE_$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')_ID"
  if [ -z "${!var:-}" ]; then
    error "$var is not defined"
    return 1
  fi
  printf '%s' "${!var}"
}

# ###############
# Catalog
# ###############

function displayAvailableProjects {
  log " ====== AVAILABLE PROJECTS ============"
  if [ -f "${DATAS_DIR}/catalog.json" ]; then
    local name version labels branch
    while IFS=$'\t' read -r name version labels branch; do
      log "* ${name} - ${version} - ${branch} (${labels})"
    done < <(jq -r '.[] | [.name, .release.version, .labels, .release.branch] | @tsv' "${DATAS_DIR}/catalog.json")
  else
    log_error "${DATAS_DIR}/catalog.json not found."
    log_info "You can do:"
    log " * eXoR.sh catalog-from-url <TASK-ID> "
    log "in order to download the catalog (<TASK-ID>.json, .yaml or .yml)."
  fi
}

# Prints "name:org:version:branch:next_snapshot:nexus_host:nexus_profile" for the project, or "0"
function getProjectByNameFromCatalog {
  local result
  result=$(jq -r --arg name "$1" \
    '.[] | select(.name == $name) |
     [.name, .git_organization, .release.version, .release.branch,
      .release.next_snapshot_version, .release.nexus_host,
      .release.nexus_staging_profile] | join(":")' "${DATAS_DIR}/catalog.json")
  # If result is empty, return "0"
  echo "${result:-0}"
}

function getUserAgent {
  echo "eXo Release Manager v${EXOR_VERSION:-unknown} (${exo_user:-unknown})"
}
