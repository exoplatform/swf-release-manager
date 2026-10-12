#!/bin/bash -eu

set -o pipefail

##
# All actions related to the communication with Tasks
#
##

## Escape the characters having a meaning in HTML
function task_html_escape {
  printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&#39;/g"
}

## Human readable reason of an error code (see the exceptions defined in common.sh)
function task_error_reason {
  case "$1" in
    100|103) echo "prerequisites not met" ;;
    200|203) echo "Maven build error" ;;
    300)     echo "Nexus staging error" ;;
    *)       echo "error code $1" ;;
  esac
}

## Describe a status as "<icon>|<color>|<title>"
## The status is either a release step (eg release_prepare_OK) or an error (ERROR_release_start_<code>)
function task_status_describe {
  case "$1" in
    release_prepare_OK)             echo "🔖|#2da44e|Release prepared" ;;
    release_perform_OK)             echo "📦|#2da44e|Release performed" ;;
    nexus_staging_repo_created_OK)  echo "🗂️|#0969da|Nexus staging repository created" ;;
    nexus_deploy_to_stage_repo_OK)  echo "⬆️|#0969da|Artifacts deployed to the staging repository" ;;
    nexus_staging_repo_closed_OK)   echo "🔒|#0969da|Nexus staging repository closed" ;;
    nexus_staging_repo_drop_OK)     echo "🗑️|#bf8700|Nexus staging repository dropped" ;;
    nexus_staging_repo_release_OK)  echo "🚀|#8250df|Nexus staging repository released" ;;
    ERROR_release_start_*)          echo "❌|#cf222e|Release failed: $(task_error_reason "${1##*_}")" ;;
    ERROR_release_continue_from_*)  echo "❌|#cf222e|Release failed when continuing: $(task_error_reason "${1##*_}")" ;;
    *)                              echo "ℹ️|#6c757d|$1" ;;
  esac
}

## Build the HTML card of a comment: task_build_comment <project line from the catalog> <project name> <status>
## The project line is "name:organization:version:branch:next_snapshot:nexus_host:nexus_profile" or "0" if unknown
function task_build_comment {
  local project=$1 name=$2 status=$3
  local icon color title version="" branch="" snapshot="" profile=""
  IFS='|' read -r icon color title <<< "$(task_status_describe "$status")"
  if [ "$project" != "0" ]; then
    IFS=':' read -r name _ version branch snapshot _ profile <<< "$project"
  fi

  local badge='padding:2px 8px;border-radius:4px;font-family:monospace;font-size:12px;'
  local card="<p><div style=\"display:inline-block;background:#f6f8fa;border-left:4px solid ${color};border-radius:8px;padding:12px 16px;margin:8px 0;font-size:14px;line-height:1.6;color:#212529;\">"
  card+="<span style=\"font-size:16px;margin-right:8px;\">${icon}</span><strong>$(task_html_escape "$title")</strong><br/>"
  card+="<span style=\"background:#ddf4ff;color:#0969da;${badge}\">$(task_html_escape "$name")</span>"
  if [ -n "$version" ]; then
    card+=" <span style=\"background:#fff8c5;color:#9a6700;${badge}\">$(task_html_escape "$version")</span>"
  fi
  if [ -n "$branch" ]; then
    card+=" <span style=\"color:#57606a;font-size:12px;\">$(task_html_escape "$branch") → $(task_html_escape "$snapshot")</span>"
  fi
  if [ -n "$profile" ]; then
    card+="<br/><span style=\"color:#57606a;font-size:12px;\">Nexus profile: $(task_html_escape "$profile")</span>"
  fi
  card+="<br/><span style=\"color:#57606a;font-size:12px;\"><code>$(task_html_escape "$status")</code> · eXoR $(task_html_escape "${EXOR_VERSION:-unknown}")</span>"
  card+="</div></p>"
  printf '%s' "$card"
}

## Add a comment to the Tribe Task
function task_add_comment {
  local project_name=$1 status=$2 task_id=$3
  local project
  project=$(getProjectByNameFromCatalog "$project_name")
  if [[ ! "${task_id}" =~ ^continuous-release-template ]]; then
    local card body
    card=$(task_build_comment "$project" "$project_name" "$status")
    log "Add comment $status for $project_name to task $task_id";
    # Percent-encode the body (spaces as %20): form encoding leaves "+" in the comment
    body=$(printf '%s' "$card" | jq -sRr @uri | tr -d '\n')
    # Run posting comment in subshell asynchronously
    (curl -sSL -o /dev/null -u $TRIBE_RELEASE_USER:$TRIBE_RELEASE_PASSWORD -XPOST -H "Content-Type: application/x-www-form-urlencoded" --data-binary "$body" "$TRIBE_RELEASE_TASK_REST_PREFIXE_URL/$task_id" 2>/dev/null &)
  fi
}
