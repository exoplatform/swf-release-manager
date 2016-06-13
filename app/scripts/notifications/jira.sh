#!/bin/bash -eu

##
# All actions related to the communication with JIRA
#
##

## Add a comment to the JIRA issue
function jira_add_comment {
  project=$(getProjectByNameFromCatalog $1)
  status=$2
  jira_id=$3
  auth=$(decompress $jira_auth_header)
  msg="\"@swf-release-manager (v ${EXOR_VERSION}) {{$project}}: *$2*\""
  body="\"body\""
  log "Add comment $msg to $jira_id";

  echo '{ '${body}' : '${msg}' }' > ${DATAS_DIR}/api/jira.json
  datas=$(curl -sS -H "Content-Type: application/json" -H "Authorization: Basic $auth" -v -X POST -d @${DATAS_DIR}/api/jira.json  ${JIRA_API_URL}issue/$jira_id/comment 2>/dev/null)
}


function jira_read_from_issue {
  echo "";
  #TODO
  #datas=$(curl -D- -u $exo_jira_login:$exo_jira_password -X POST -d @conf/jira.json "Content-Type: application/json" $JIRA_API_URL/issue/$1/comment)
}
