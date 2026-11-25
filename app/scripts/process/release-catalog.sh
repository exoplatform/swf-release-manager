#!/bin/bash
# Download the catalog of a release and store it as ${DATAS_DIR}/catalog.json.
# The catalog is <TASK_ID>.json, or <TASK_ID>.yaml / <TASK_ID>.yml (converted to JSON).

# Convert YAML (stdin) to JSON (stdout) with yq (mikefarah) or python3 + PyYAML
function catalog_yaml_to_json {
  if command -v yq >/dev/null 2>&1; then
    yq -o=json '.'
  elif python3 -c 'import yaml' >/dev/null 2>&1; then
    python3 -c 'import json, sys, yaml; json.dump(yaml.safe_load(sys.stdin), sys.stdout)'
  else
    error "A YAML catalog needs 'yq' or python3 with PyYAML in the image."
    return 1
  fi
}

# Fetch one catalog URL on stdout (credentials stay off the command line)
function catalog_fetch {
  local url=$1
  if [ -n "${CATALOG_CREDENTIALS:-}" ]; then
    curl_auth_config "${CATALOG_CREDENTIALS%%:*}" "${CATALOG_CREDENTIALS#*:}" |
      curl -fsS -K - -H "User-Agent: $(getUserAgent)" "$url" 2>/dev/null
  else
    curl -fsS -H "User-Agent: $(getUserAgent)" "$url" 2>/dev/null
  fi
}

# Download the catalog: release_catalog_download_from_url <TASK_ID> [version suffix]
function release_catalog_download_from_url {
  local task_id=$1 version_suffix=${2:-} ext response="" found="" json
  printHeader "Download catalog ${CATALOG_BASE_URL}/${task_id}.(json|yaml|yml) withCredential=$([ -n "${CATALOG_CREDENTIALS:-}" ] && echo true || echo false)"

  for ext in json yaml yml; do
    if response=$(catalog_fetch "${CATALOG_BASE_URL}/${task_id}.${ext}"); then
      found=$ext
      break
    fi
  done
  if [ -z "$found" ]; then
    error "Unable to download the catalog ${CATALOG_BASE_URL}/${task_id}.(json|yaml|yml)"
    return 1
  fi
  log "Catalog found: ${task_id}.${found}"

  if [[ "$task_id" =~ ^continuous-release-template ]]; then
    response=${response//\$\{release-version\}/$version_suffix}
  fi

  if [ "$found" = "json" ]; then
    json=$(jq . <<<"$response")
  else
    json=$(catalog_yaml_to_json <<<"$response" | jq .)
  fi
  if ! jq -e 'type == "array"' >/dev/null <<<"$json"; then
    error "The catalog must be a list of projects."
    return 1
  fi
  printf '%s\n' "$json" >"${DATAS_DIR}/catalog.json"

  printFooter "Download catalog."
}
