#!/bin/bash -eu
set -o pipefail

#####
#
#  Process related to the JSON catalog required to start one or several releases.
#
#####

#
# Download a JSON file and save it as catalog.json.
# The JSOn filename is based on the TASK ID: <TASK_ID>.json
#
function release_catalog_download_from_url() {

	withCredentials=false
	params=""
	set +e
	if [ ! -z "${CATALOG_CREDENTIALS}" ]; then
		params="-u ${CATALOG_CREDENTIALS}"
		withCredentials=true
	fi
	set -e

      versionSuffix=${2:-}
	printHeader "Download catalog from ${CATALOG_BASE_URL}/$1.json withCredential=${withCredentials}"
	response=$(curl -sS ${params} -H "Content-Type: application/json" -v ${CATALOG_BASE_URL}/$1.json 2>/dev/null)

	if [[ "$1" =~ ^continuous-release-template ]]; then
		response=$(sed "s|\${release-version}|${versionSuffix}|g" <<< $response)
	fi

	CATALOG=$(echo $response | jq --raw-output)
	echo $CATALOG >$DATAS_DIR/catalog.json

	printFooter "Download catalog."
}

#
# For eXo Tribe response=$(curl -u $exo_tribe_login:$exo_tribe_password -sS -H "Content-Type: application/json" -v $URL 2>/dev/null)
#
