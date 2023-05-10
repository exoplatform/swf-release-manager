#!/bin/bash -eu
set -o pipefail

#
# Update maven properties which defines maven dependencies versions.
# $1 project name
# $2 TASK_ID
#
function maven_dependencies_update_before_release {
   printHeader "Update dependencies BEFORE release for $1"
   # log status
   release_status_write_step $MAVEN_DEPS_BEFORE $STATUS_IN_PROGESS

   # Find all maven_property_version and then release.version, current and next
   ARR=($(jq -r '.[] | [.maven_property_version, .release.version, .release.current_snapshot_version, .release.next_snapshot_version] | join(",")' ${DATAS_DIR}/catalog.json))

   if [  -z ${ARR+x}  ]; then
     # "No projects with name: " $1
     echo "No maven properties to update."
   else
     for project in "${ARR[@]}"
       do
         IFS=',' read -r -a params <<< "$project"
         MAVEN_PROPERTY_VERSION=${params[0]}
         RELEASE_VERSION=${params[1]}
         RELEASE_CURRENT_SNAPSHOT_VERSION=${params[2]}
         RELEASE_NEXT_SNAPSHOT_VERSION=${params[3]}
         string_to_find="<"${MAVEN_PROPERTY_VERSION}">${RELEASE_CURRENT_SNAPSHOT_VERSION}</"${MAVEN_PROPERTY_VERSION}">"
         string_to_write="<"${MAVEN_PROPERTY_VERSION}">${RELEASE_VERSION}</"${MAVEN_PROPERTY_VERSION}">"

         # update POM.xml
         log "[DEBUG] cmd to update: $string_to_find $string_to_write $PRJ_DIR/$1"
         utils_update_pom  $string_to_find $string_to_write $PRJ_DIR/$1
       done
       ## Commit all modifications
       if [ $(gitCommandIsThereFilesToCommit $1) = "true" ]; then
         gitCommand $1 commit -a -m "$2: [exo-release] Update SNAPSHOT dependencies to RELEASE dependencies before Release."
       else
           log "[DEBUG] no update deps to commit."
       fi

   fi
   printFooter "Update dependencies BEFORE release for $1"
   # log status
   release_status_write_step $MAVEN_DEPS_BEFORE $STATUS_DONE
}

#
# Update maven properties which defines maven dependencies versions.
# $1 project name
# $2 TASK_ID
#
function maven_dependencies_update_after_release {
   printHeader "Update dependencies AFTER release for $1"
   # log status
   release_status_write_step $MAVEN_DEPS_AFTER $STATUS_IN_PROGESS

   # Find all maven_property_version and then release.version, current and next
   ARR=($(jq -r '.[] | [.maven_property_version, .release.version, .release.current_snapshot_version, .release.next_snapshot_version] | join(",")' ${DATAS_DIR}/catalog.json))

   if [  -z ${ARR+x}  ]; then
     # "No projects with name: " $1
     log "[DEPENDENCIES] No maven properties to update."
   else
     for project in "${ARR[@]}"
       do
         IFS=',' read -r -a params <<< "$project"
         MAVEN_PROPERTY_VERSION=${params[0]}
         RELEASE_VERSION=${params[1]}
         RELEASE_CURRENT_SNAPSHOT_VERSION=${params[2]}
         RELEASE_NEXT_SNAPSHOT_VERSION=${params[3]}
         string_to_write="<"${MAVEN_PROPERTY_VERSION}">${RELEASE_NEXT_SNAPSHOT_VERSION}</"${MAVEN_PROPERTY_VERSION}">"
         string_to_find="<"${MAVEN_PROPERTY_VERSION}">${RELEASE_VERSION}</"${MAVEN_PROPERTY_VERSION}">"

         # update POM.xml
         log "[DEPENDENCIES][DEBUG] cmd to update: $string_to_find $string_to_write $PRJ_DIR/$1"
         utils_update_pom  $string_to_find $string_to_write $PRJ_DIR/$1
       done
       ## Commit all modifications
       if [ $(gitCommandIsThereFilesToCommit $1) = "true" ]; then
         gitCommand $1 commit -a -m "[exo-release]($exo_user) $2: Update RELEASE dependencies to SNAPSHOT dependencies after Release."
       else
           log "[DEBUG] no update deps to commit."
       fi
   fi
   printFooter "Update dependencies AFTER release for $1"
   # log status
   release_status_write_step $MAVEN_DEPS_AFTER $STATUS_DONE
}

function utils_update_file {

  if [ $# -eq 3 ]; then
    grep -RiIl "$1" --include="$3" . | xargs -r sed -i "s${SEP}$1${SEP}$2${SEP}g"
  else
    grep -RiIl "$1" --include="$3" "$4" | xargs -r sed -i "s${SEP}$1${SEP}$2${SEP}g" 
  fi
}

function utils_update_pom {

  if [ $# -eq 2 ]; then
      utils_update_file "$1" "$2" "pom.xml"
  else
      utils_update_file "$1" "$2" "pom.xml" "$3"
  fi


}
