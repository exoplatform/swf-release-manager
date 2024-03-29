#!/bin/bash -eu

set -o pipefail

##
# All actions related to the communication with Tasks
#
##

## Add a comment to the Tribe Task 
function task_add_comment {
  project=$(getProjectByNameFromCatalog $1)
  status=$2
  task_id=$3
  if [[ ! "${task_id}" =~ ^continuous-release-template ]]; then 
    msg="@${TRIBE_RELEASE_USER} (v ${EXOR_VERSION}) <tt>$project</tt>: $status"
    log "Add comment $msg to task $task_id";
    # Run posting comment in subshell asynchronously  
    (curl -sSL -o /dev/null -u $TRIBE_RELEASE_USER:$TRIBE_RELEASE_PASSWORD -XPOST -H "Content-Type: application/json" -d "<p>$msg</p>" -v "$TRIBE_RELEASE_TASK_REST_PREFIXE_URL/$task_id" 2>/dev/null &)
  fi
}
