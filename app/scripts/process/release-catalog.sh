#!/bin/bash -eu
set -o pipefail

#####
# Downloads the release catalog JSON and saves it as catalog.json.
# The catalog filename is based on the TASK ID: <TASK_ID>.json
#####

# Args: $1=task_id  $2=versionSuffix (optional)
function release_catalog_download_from_url {
  local task_id="$1"
  local versionSuffix="${2:-}"
  local curl_auth_args=()
  local withCredentials=false

  if [ -n "${CATALOG_CREDENTIALS:-}" ]; then
    curl_auth_args=(-u "${CATALOG_CREDENTIALS}")
    withCredentials=true
  fi

  printHeader "Download catalog from ${CATALOG_BASE_URL}/${task_id}.json withCredentials=${withCredentials}"

  local response
  response=$(curl -sS "${curl_auth_args[@]}" \
    -H "Content-Type: application/json" \
    "${CATALOG_BASE_URL}/${task_id}.json" 2>/dev/null)

  if [[ "$task_id" =~ ^continuous-release-template ]]; then
    response=$(sed "s|\${release-version}|${versionSuffix}|g" <<< "$response")
  fi

  echo "$response" | jq -r > "${DATAS_DIR}/catalog.json"

  printFooter "Download catalog."
}
