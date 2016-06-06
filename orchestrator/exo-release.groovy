def doRelease(jiraID, project, releaseCMD, isInParallel) {

   def volume_name = "${jiraID}-${project.name}-workspace"
   def container_name = ""
   def container_run_option = ""
   def docker_image = "${project.container.image}"

   def nexus_id = "${NEXUS_STAGING_PROFILE_ID}"

   // Create the right command to run in the container
   if (releaseCMD == "start"){
        echo "Create volume ${volume_name}"
        sh "sudo docker volume create --name=${volume_name}"
        container_name = "${jiraID}-${project.name}"
        container_command = "release-start ${project.name} ${jiraID}"
   } else if (releaseCMD == "validate"){
       container_name = "${jiraID}-${project.name}-validate"
       container_command = "release-validate ${jiraID}"
   } else if (releaseCMD == "catalog-from-url"){
       container_name = "${jiraID}-${project.name}-debug"
       container_command = "catalog-from-url ${jiraID}"
   } else if (releaseCMD == "release-continue-from nexus:create"){
       container_name = "${jiraID}-${project.name}-nexus-create"
       container_command = "release-continue-from nexus:create"
   }

   if (isInParallel == "true"){
       container_run_option = "-d"
   }

   stage "[RELEASE] CMD: ${container_command} on container ${container_name} for project ${project.name} for ${jiraID}"
   sh "sudo docker run ${container_run_option} -v /home/${releaseUser}/.gnupg/pubring.gpg:/home/ciagent/.gnupg/pubring.gpg:ro \
        -v /home/${releaseUser}/.gnupg/secring.gpg:/home/ciagent/.gnupg/secring.gpg:ro \
        -v /home/${releaseUser}/.gnupg/gpg.conf:/home/ciagent/.gnupg/gpg.conf:ro \
        -v /home/${releaseUser}/.ssh/id_rsa:/home/ciagent/.ssh/id_rsa:ro \
        --env-file /home/${releaseUser}/.eXo/Releases/exo-release.properties \
        -v ${volume_name}:/opt/exo-release/workspace \
        -e NEXUS_STAGING_PROFILE_PRIVATE_ID=${nexus_id} \
        -e NEXUS_STAGING_PROFILE_PUBLIC_ID=${nexus_id} \
        -e NEXUS_STAGING_PROFILE_ADDONS_ID=${nexus_id} \
        --volumes-from ${jiraID}-m2_cache \
        --name ${container_name} \
        ${docker_image} \
        \"${container_command}\""
}

// Read Datas from JSON Catalog and executes releases
def doReleases(jiraID, projectsToRelease, releaseCMD, isInParallel) {

   def JSONCatalog = new URL("${CATALOG_BASE_URL}/${JIRA_ID}.json")
   def catalog = new groovy.json.JsonSlurper().parse(JSONCatalog.newReader())

    echo "Number of Projects in Catalog: ${catalog.size}"
    // Loop first on projectsToRelease to keep the order
    for (i = 0; i < projectsToRelease.length; i++) {
         def projectName = projectsToRelease[i];
         for (j = 0; j < catalog.size; j++) {
             if (catalog[j].name == projectName) {
                doRelease(jiraID, catalog[j], releaseCMD, isInParallel)
             }
         }
    }
}

// Execute Release on Jenkins Slave with Docker
node('docker') {

  // Init parameters
  stage "Init Releases parameters"
  def jiraID = "${JIRA_ID}"
  def releaseCMD = "${RELEASE_CMD}"
  def p = "${PROJECTS}"
  def projectsToRelease = p.split(',')
  def isInParallel = "${RELEASE_PROJECTS_IN_PARALLEL}"
  def releaseUser = "${RELEASE_USER}"
  echo "* Projects: ${PROJECTS}"
  echo "* Command: ${RELEASE_CMD}"
  echo "* Projects: ${PROJECTS}"
  echo "* Releases in Parallel? ${isInParallel}"

  stage "[START] Releases all ${JIRA_ID}"
  doReleases(jiraID, projectsToRelease, releaseCMD, isInParallel)
}
