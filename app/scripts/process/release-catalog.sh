#!/bin/bash -eu

#####
#
#  Process related to the JSON catalog required to start one or several releases.
#
#####

#
# Download a JSON file and save it as catalog.json.
# The JSOn filename is based on the JIRA ID: <JIRA_ID>.json
#
function release_catalog_download_from_url {
  printHeader "Download catalog from ${CATALOG_BASE_URL}/$1.json"

  response=$(curl -sS -H "Content-Type: application/json" -v ${CATALOG_BASE_URL}/$1.json 2>/dev/null)
  CATALOG=$(echo $response | json -g)
  echo  $CATALOG > $DATAS_DIR/catalog.json

  printFooter "Download catalog."
}

#
# For eXo Tribe response=$(curl -u $exo_tribe_login:$exo_tribe_password -sS -H "Content-Type: application/json" -v $URL 2>/dev/null)
#
