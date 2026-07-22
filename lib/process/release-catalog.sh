#!/bin/bash -eu
set -o pipefail

#####
#
#  Process related to the JSON catalog required to start one or several releases.
#
#####

function release_catalog_download_from_url() {
  local withCredentials=false
  local params=""
  local versionSuffix=${2:-}

  if [ -n "${CATALOG_CREDENTIALS:-}" ]; then
    params="-u ${CATALOG_CREDENTIALS}"
    withCredentials=true
  fi

  printHeader "Download catalog from ${CATALOG_BASE_URL}/$1.json withCredential=${withCredentials}"
  local response
  response=$(curl -sS ${params} -H "Content-Type: application/json" "${CATALOG_BASE_URL}/$1.json" 2>/dev/null)

  if [[ "$1" =~ ^continuous-release-template ]]; then
    response=$(sed "s|\${release-version}|${versionSuffix}|g" <<< "${response}")
  fi

  local CATALOG
  CATALOG=$(printf '%s' "${response}" | jq -r)
  printf '%s\n' "${CATALOG}" > "${DATA_DIR}/catalog.json"

  printFooter "Download catalog."
}
