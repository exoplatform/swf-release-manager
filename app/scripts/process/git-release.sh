#!/bin/bash -eu

#
function git_release_create_branch {
  log "Create release branch release/$2"
  gitCommand $1 checkout -b "release/$2"
}

function git_release_delete_branch {
    log "Delete release branch release/$2"
    gitCommand $1 branch -D "release/$2"
}

function git_release_clean_and_push {

   # TODO if current and next versions are different,
   # then push 1 commit on base branch
   log "Push only the tag to the remote repo"
   git_release_delete_branch $1 $2
   gitCommand $1 push --tags
}
