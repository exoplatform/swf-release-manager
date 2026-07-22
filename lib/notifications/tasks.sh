#!/bin/bash -eu
set -o pipefail

##
# All actions related to the communication with Tasks
#

function task_add_comment {
  local project=$1
  local status=$2
  local task_id=$3

  if [[ ! "${task_id}" =~ ^continuous-release-template ]]; then
    local msg="@${TRIBE_RELEASE_USER} (v ${EXOR_VERSION}) <tt>${project}</tt>: ${status}"
    log "Add comment ${msg} to task ${task_id}"
    curl -sSL -o /dev/null -u "${TRIBE_RELEASE_USER}:${TRIBE_RELEASE_PASSWORD}" -XPOST -H "Content-Type: application/json" -d "<p>${msg}</p>" "${TRIBE_RELEASE_TASK_REST_PREFIXE_URL}/${task_id}" 2>/dev/null &
  fi
}
