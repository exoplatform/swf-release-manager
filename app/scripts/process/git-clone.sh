#!/bin/bash

# Clone every project selected by a jq filter on the catalog
# Usage: git_clone_selected <jq select filter> [jq options...]
function git_clone_selected {
  local filter=$1 name org version branch
  shift
  local found=0
  while IFS=$'\t' read -r name org version branch; do
    found=1
    git_clone "$name" "$org" "$branch" "$version"
  done < <(jq -r "$@" ".[] | select($filter) | [.name, .git_organization, .release.version, .release.branch] | @tsv" "${DATAS_DIR}/catalog.json")
  return $((found == 0))
}

function git_clone_all {
  echo "Clone all projects defined into the catalog"
  git_clone_selected 'true' || error "No projects!"
}

function git_clone_all_with_label {
  git_clone_selected '(.labels // "") | contains($label)' --arg label "$1" || error "No projects with label: $1"
}

# Clone 1 project via its github name
function git_clone_single {
  git_clone_selected '.name == $name' --arg name "$1" || {
    error "No projects with name: $1"
    return 1
  }
}

# Clone <git project> <git organization> <git branch> <version>
function git_clone {
  local prj=$1 org=$2 branch=$3 version=$4
  rm -rf "${PRJ_DIR:?}/$prj"
  log "==========================================================="
  log "Cloning $prj from $GIT_HOST $org for Release Version $version on Branch $branch"
  log "==========================================================="
  release_status_write_step "$GIT_CLONE" "$STATUS_IN_PROGRESS"
  gitCommand "$prj" clone --depth 1 --branch "$branch" "git@$GIT_HOST:$org/$prj.git"
  if [ "$prj" = "platform-private-distributions" ] && [ ! -f ~/.tmpgitignore ]; then
    log "Repository with LFS detected. Initializing..."
    gitCommand "$prj" lfs install
    # Track one pattern per extension of the LFS files
    (cd "$PRJ_DIR/$prj" && git lfs ls-files -n | sed -n 's/.*\.\([^./]*\)$/*.\1/p' | sort -u | xargs -r git lfs track)
    gitCommand "$prj" reset --hard "origin/$branch"
    # Hack: to prevent committing .gitattributes with Release process
    echo .gitattributes >~/.tmpgitignore
    gitCommand "$prj" config core.excludesfile ~/.tmpgitignore
    log "LFS initialization done."
  fi
  release_status_write_step "$GIT_CLONE" "$STATUS_DONE"
}
