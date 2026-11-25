#!/bin/bash

# Replace the fixed string $1 by $2 in the files named $3 under the directory $4 (default .)
function utils_update_file {
  local from=$1 to=$2 name=$3 dir=${4:-.}
  local re rep
  re=$(sed_escape_regex "$from")
  rep=$(sed_escape_replacement "$to")
  # grep exits with 1 when no file matches: not an error
  { grep -RIlF --include="$name" -- "$from" "$dir" || [ $? -eq 1 ]; } | xargs -r sed -i "s/${re}/${rep}/g"
}

function utils_update_pom { utils_update_file "$1" "$2" pom.xml "${3:-.}"; }

# Update the maven properties which define the versions of the released projects:
# current SNAPSHOT version -> release version, in the POMs of project $1.
# Usage: maven_dependencies_update_before_release <project> <TASK_ID>
function maven_dependencies_update_before_release {
  printHeader "Update dependencies BEFORE release for $1"
  release_status_write_step "$MAVEN_DEPS_BEFORE" "$STATUS_IN_PROGRESS"

  local prop version current from to
  while IFS=$'\t' read -r prop version current; do
    [ -z "$prop" ] && continue
    from="<${prop}>${current}</${prop}>"
    to="<${prop}>${version}</${prop}>"
    log_debug "cmd to update: $from $to $PRJ_DIR/$1"
    utils_update_pom "$from" "$to" "$PRJ_DIR/$1"
  done < <(jq -r '.[] | select(.maven_property_version != null and .maven_property_version != "") | [.maven_property_version, .release.version, .release.current_snapshot_version] | @tsv' "${DATAS_DIR}/catalog.json")

  if [ "$(gitCommandIsThereFilesToCommit "$1")" = "true" ]; then
    gitCommand "$1" commit -a -m "$2: [exo-release] Update SNAPSHOT dependencies to RELEASE dependencies before Release."
  else
    log_debug "no update deps to commit."
  fi

  printFooter "Update dependencies BEFORE release for $1"
  release_status_write_step "$MAVEN_DEPS_BEFORE" "$STATUS_DONE"
}
