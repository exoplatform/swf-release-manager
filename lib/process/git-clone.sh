#!/bin/bash -eu
set -o pipefail

function git_clone_all {
  printf '%s\n' "==============================================================================="
  printf '%s\n' "Clone all projects defined into the catalog"
  printf '%s\n' "==============================================================================="
  local ARR
  mapfile -t ARR < <(jq -r '.[] | [.name, .git_organization, .release.version, .release.branch] | join(",")' "${DATA_DIR}/catalog.json")
  if [ "${#ARR[@]}" -eq 0 ]; then
    error "No projects!"
  else
    for project in "${ARR[@]}"
    do
      IFS=',' read -r -a params <<< "$project"
      local PROJECT=${params[0]}
      local GIT_ORGANIZATION=${params[1]}
      local VERSION=${params[2]}
      local BRANCH=${params[3]}
      git_clone "${PROJECT}" "${GIT_ORGANIZATION}" "${BRANCH}" "${VERSION}"
    done
  fi
}

function git_clone_all_with_label {
  local label=$1
  local ARR
  mapfile -t ARR < <(jq -r --arg label "$label" '.[] | select(.labels | contains($label)) | [.name, .git_organization, .release.version, .release.branch] | join(",")' "${DATA_DIR}/catalog.json")
  if [ "${#ARR[@]}" -eq 0 ]; then
    error "No projects with label: $label"
  else
    for project in "${ARR[@]}"
    do
      IFS=',' read -r -a params <<< "$project"
      local PROJECT=${params[0]}
      local GIT_ORGANIZATION=${params[1]}
      local VERSION=${params[2]}
      local BRANCH=${params[3]}
      git_clone "${PROJECT}" "${GIT_ORGANIZATION}" "${BRANCH}" "${VERSION}"
    done
  fi
}

function git_clone_single {
  local name=$1
  local ARR
  mapfile -t ARR < <(jq -r --arg name "$name" '.[] | select(.name == $name) | .name, .git_organization, .release.version, .release.branch' "${DATA_DIR}/catalog.json")
  if [ "${#ARR[@]}" -eq 0 ]; then
    printf '%s %s\n' "No projects with name:" "$name"
  else
    local PROJECT=${ARR[0]}
    local GIT_ORGANIZATION=${ARR[1]}
    local VERSION=${ARR[2]}
    local BRANCH=${ARR[3]}

    git_clone "${PROJECT}" "${GIT_ORGANIZATION}" "${BRANCH}" "${VERSION}"
  fi
}

function git_clone {
  local project_name=$1
  local git_org=$2
  local branch=$3
  local version=$4

  if [ -e "${PRJ_DIR}/${project_name}" ]; then
    rm -rf "${PRJ_DIR:?}/${project_name}"
  fi
  log "==========================================================="
  log "Cloning ${project_name} from ${GIT_HOST} ${git_org} for Release Version ${version} on Branch ${branch}"
  log "==========================================================="
  release_status_write_step "${GIT_CLONE}" "${STATUS_IN_PROGESS}"

  gitCommand "${project_name}" clone --depth 1 --branch "${branch}" "git@${GIT_HOST}:${git_org}/${project_name}.git"

  if [ "${project_name}" = "platform-private-distributions" ] && [ ! -f ~/.tmpgitignore ]; then
    printf '%s\n' "Repository with LFS detected. Initializing..."
    gitCommand "${project_name}" lfs install
    gitCommand "${project_name}" lfs track "$(gitCommand "${project_name}" lfs ls-files | awk -F. '{ ext="*."$NF; print ext}' | uniq | xargs -r)"
    gitCommand "${project_name}" reset --hard "origin/${branch}"
    printf '%s\n' .gitattributes > ~/.tmpgitignore
    gitCommand "${project_name}" config core.excludesfile ~/.tmpgitignore
    printf '%s\n' "LFS initialization done."
  fi

  release_status_write_step "${GIT_CLONE}" "${STATUS_DONE}"
}
