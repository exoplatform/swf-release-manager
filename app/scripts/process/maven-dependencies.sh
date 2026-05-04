#!/bin/bash -eu
set -o pipefail

# Replace a string in all pom.xml files under a given directory
# Args: $1=find_string $2=replace_string $3=directory
function utils_update_pom {
  local find_str="$1"
  local replace_str="$2"
  local dir="${3:-.}"
  grep -RIl "$find_str" --include="pom.xml" "$dir" \
    | xargs -r sed -i "s${SEP}${find_str}${SEP}${replace_str}${SEP}g"
}

# Update SNAPSHOT → RELEASE dependencies in POM files before a release
# Args: $1=project $2=issueId
function maven_dependencies_update_before_release {
  printHeader "Update dependencies BEFORE release for $1"
  release_status_write_step "$MAVEN_DEPS_BEFORE" "$STATUS_IN_PROGESS"

  local -a ARR
  mapfile -t ARR < <(jq -r '.[] | [.maven_property_version, .release.version, .release.current_snapshot_version, .release.next_snapshot_version] | join(",")' "${DATAS_DIR}/catalog.json")

  if [ ${#ARR[@]} -eq 0 ]; then
    echo "No maven properties to update."
  else
    for entry in "${ARR[@]}"; do
      IFS=',' read -r -a params <<< "$entry"
      local MAVEN_PROPERTY_VERSION="${params[0]}"
      local RELEASE_VERSION="${params[1]}"
      local RELEASE_CURRENT_SNAPSHOT_VERSION="${params[2]}"
      local find_str="<${MAVEN_PROPERTY_VERSION}>${RELEASE_CURRENT_SNAPSHOT_VERSION}</${MAVEN_PROPERTY_VERSION}>"
      local replace_str="<${MAVEN_PROPERTY_VERSION}>${RELEASE_VERSION}</${MAVEN_PROPERTY_VERSION}>"
      log "[DEBUG] Updating: $find_str → $replace_str in $PRJ_DIR/$1"
      utils_update_pom "$find_str" "$replace_str" "$PRJ_DIR/$1"
    done

    if [ "$(gitCommandIsThereFilesToCommit "$1")" = "true" ]; then
      gitCommand "$1" commit -a -m "$2: [exo-release] Update SNAPSHOT dependencies to RELEASE dependencies before Release."
    else
      log "[DEBUG] No dependency changes to commit."
    fi
  fi

  printFooter "Update dependencies BEFORE release for $1"
  release_status_write_step "$MAVEN_DEPS_BEFORE" "$STATUS_DONE"
}

# Update RELEASE → SNAPSHOT dependencies in POM files after a release
# Args: $1=project $2=issueId
function maven_dependencies_update_after_release {
  printHeader "Update dependencies AFTER release for $1"
  release_status_write_step "$MAVEN_DEPS_AFTER" "$STATUS_IN_PROGESS"

  local -a ARR
  mapfile -t ARR < <(jq -r '.[] | [.maven_property_version, .release.version, .release.current_snapshot_version, .release.next_snapshot_version] | join(",")' "${DATAS_DIR}/catalog.json")

  if [ ${#ARR[@]} -eq 0 ]; then
    log "[DEPENDENCIES] No maven properties to update."
  else
    for entry in "${ARR[@]}"; do
      IFS=',' read -r -a params <<< "$entry"
      local MAVEN_PROPERTY_VERSION="${params[0]}"
      local RELEASE_VERSION="${params[1]}"
      local RELEASE_NEXT_SNAPSHOT_VERSION="${params[3]}"
      local find_str="<${MAVEN_PROPERTY_VERSION}>${RELEASE_VERSION}</${MAVEN_PROPERTY_VERSION}>"
      local replace_str="<${MAVEN_PROPERTY_VERSION}>${RELEASE_NEXT_SNAPSHOT_VERSION}</${MAVEN_PROPERTY_VERSION}>"
      log "[DEPENDENCIES][DEBUG] Updating: $find_str → $replace_str in $PRJ_DIR/$1"
      utils_update_pom "$find_str" "$replace_str" "$PRJ_DIR/$1"
    done

    if [ "$(gitCommandIsThereFilesToCommit "$1")" = "true" ]; then
      gitCommand "$1" commit -a -m "[exo-release]($exo_user) $2: Update RELEASE dependencies to SNAPSHOT dependencies after Release."
    else
      log "[DEBUG] No dependency changes to commit."
    fi
  fi

  printFooter "Update dependencies AFTER release for $1"
  release_status_write_step "$MAVEN_DEPS_AFTER" "$STATUS_DONE"
}
