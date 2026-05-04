#!/bin/bash -eu
set -o pipefail

##
# Communication with the Tribe task tracker
##

# Post a comment to a Tribe task (fire-and-forget, non-blocking)
# Args: $1=project  $2=status  $3=task_id
function task_add_comment {
  local project status task_id msg
  project=$(getProjectByNameFromCatalog "$1")
  status="$2"
  task_id="$3"

  # Skip comment posting for continuous-release catalog references
  if [[ "$task_id" =~ ^continuous-release-template ]]; then
    return 0
  fi

  msg="@${TRIBE_RELEASE_USER} (v ${EXOR_VERSION}) <tt>${project}</tt>: ${status}"
  log "Add comment '$msg' to task $task_id"

  # Post asynchronously so a transient API failure never blocks the release
  (curl -sSL -o /dev/null \
    -u "${TRIBE_RELEASE_USER}:${TRIBE_RELEASE_PASSWORD}" \
    -X POST \
    -H "Content-Type: application/json" \
    -d "<p>${msg}</p>" \
    "${TRIBE_RELEASE_TASK_REST_PREFIXE_URL}/${task_id}" 2>/dev/null &)
}
