#!/bin/bash -eu
set -o pipefail

# Clone all projects defined in catalog.json
function git_clone_all {
  echo "==============================================================================="
  echo "Clone all projects defined into the catalog"
  echo "==============================================================================="
  local -a ARR
  mapfile -t ARR < <(jq -r '.[] | [.name, .git_organization, .release.version, .release.branch] | join(",")' "${DATAS_DIR}/catalog.json")
  if [ ${#ARR[@]} -eq 0 ]; then
    error "No projects!"
  else
    for project in "${ARR[@]}"; do
      IFS=',' read -r -a params <<< "$project"
      git_clone "${params[0]}" "${params[1]}" "${params[3]}" "${params[2]}"
    done
  fi
}

# Clone all projects that carry a specific label
function git_clone_all_with_label {
  local label="$1"
  local -a ARR
  mapfile -t ARR < <(jq -r --arg lbl "$label" \
    '.[] | select(.labels | contains($lbl)) | [.name, .git_organization, .release.version, .release.branch] | join(",")' \
    "${DATAS_DIR}/catalog.json")

  if [ ${#ARR[@]} -eq 0 ]; then
    error "No projects with label: $label"
  else
    for project in "${ARR[@]}"; do
      IFS=',' read -r -a params <<< "$project"
      git_clone "${params[0]}" "${params[1]}" "${params[3]}" "${params[2]}"
    done
  fi
}

# Clone a single project identified by name
function git_clone_single {
  local name="$1"
  local -a ARR
  mapfile -t ARR < <(jq -r --arg name "$name" \
    '.[] | select(.name == $name) | [.name, .git_organization, .release.version, .release.branch] | @tsv' \
    "${DATAS_DIR}/catalog.json")

  if [ ${#ARR[@]} -eq 0 ]; then
    echo "No project with name: $name"
  else
    IFS=$'\t' read -r -a params <<< "${ARR[0]}"
    git_clone "${params[0]}" "${params[1]}" "${params[3]}" "${params[2]}"
  fi
}

# Clone a project: git_clone <project> <org> <branch> <version>
function git_clone {
  local project="$1" org="$2" branch="$3" version="$4"

  if [ -e "$PRJ_DIR/$project" ]; then
    rm -rf "$PRJ_DIR/$project"
  fi

  log "==========================================================="
  log "Cloning $project from $GIT_HOST/$org for Release Version $version on Branch $branch"
  log "==========================================================="
  release_status_write_step "$GIT_CLONE" "$STATUS_IN_PROGESS"

  gitCommand "$project" clone --depth 1 --branch "$branch" "git@$GIT_HOST:$org/$project.git"

  # LFS support for repositories that need it
  if [ "${project:-}" = "platform-private-distributions" ] && [ ! -f ~/.tmpgitignore ]; then
    echo "Repository with LFS detected. Initializing..."
    gitCommand "$project" lfs install
    # Track all extension types found in LFS
    local lfs_extensions
    lfs_extensions=$(cd "$PRJ_DIR/$project" && git lfs ls-files | awk -F. '{ print "*."$NF }' | sort -u)
    if [ -n "$lfs_extensions" ]; then
      while IFS= read -r ext; do
        gitCommand "$project" lfs track "$ext"
      done <<< "$lfs_extensions"
    fi
    gitCommand "$project" reset --hard "origin/$branch"
    # Prevent release process from committing .gitattributes
    echo ".gitattributes" > ~/.tmpgitignore
    gitCommand "$project" config core.excludesfile ~/.tmpgitignore
    echo "LFS initialization done."
  fi

  release_status_write_step "$GIT_CLONE" "$STATUS_DONE"
}
