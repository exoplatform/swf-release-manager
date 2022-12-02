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
    msg="@swf-release-manager (v ${EXOR_VERSION}) {{$project}}: $status"  
    log "Add comment $msg to task $task_id";  
    curl -s -L -u $TRIBE_RELEASE_USER:$TRIBE_RELEASE_PASSWORD -XPOST -d " $msg " -v "$TRIBE_RELEASE_TASK_REST_PREFIXE_URL/$task_id" 2> /dev/null
  fi
}
