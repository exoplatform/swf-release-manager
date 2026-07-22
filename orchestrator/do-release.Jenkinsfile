#!/usr/bin/groovy

def logInfo(msg)    { ansiColor('xterm') { echo "\033[34m[INFO]\033[0m ${msg}" } }
def logSuccess(msg) { ansiColor('xterm') { echo "\033[32m[OK]\033[0m ${msg}" } }
def logWarn(msg)    { ansiColor('xterm') { echo "\033[33m[WARN]\033[0m ${msg}" } }
def logError(msg)   { ansiColor('xterm') { echo "\033[31m[ERROR]\033[0m ${msg}" } }
def logStage(msg)   { ansiColor('xterm') { echo "\033[36m\033[1m${msg}\033[0m" } }

@NonCPS
def jsonParser(def json) {
    new groovy.json.JsonSlurperClassic().parse(json)
}

@NonCPS
def createBasicAuthString(credentials) {
    def authString = credentials.getBytes().encodeBase64().toString()
    [Authorization: "Basic " + authString]
}

@NonCPS
def buildCatalogIndex(def catalog) {
    def index = [:]
    catalog.each { index[it.name] = it }
    return index
}

def doRelease(exoUser, jenkinsAgentRootPath, taskID, project, releaseCMD, isInParallel, config, continuousReleaseSuffix) {
    def volume_name = "${taskID}-${project.name}-workspace"
    def container_name = "${taskID}-${project.name}"
    def container_run_option = "--dns=8.8.8.8 --dns=8.8.8.4 --sysctl net.ipv6.conf.all.disable_ipv6=1"
    def docker_image = "${project.container.image}"
    def MAVEN_EXTRA_OPTS = "${config.MAVEN_EXTRA_OPTS}"
    def BUILD_TIMEOUT = config.BUILD_TIMEOUT

    def container_command = ''
    switch (releaseCMD) {
        case 'start':
            sh "${config.DOCKER_CMD} volume create --name=${volume_name}"
            container_command = "release-start ${project.name} ${taskID} ${continuousReleaseSuffix}"
            break
        case 'validate':
            container_command = "release-validate ${taskID}"
            break
        case 'cancel':
            container_command = "release-cancel ${project.name} ${taskID}"
            break
        case 'catalog-from-url':
            container_command = "catalog-from-url ${taskID} ${continuousReleaseSuffix}"
            break
        case { it.startsWith('release-continue-from') }:
            container_command = releaseCMD
            break
        default:
            echo "Nothing to do."
            return
    }

    if (isInParallel == "true") {
        container_run_option = "${container_run_option} -d"
    }

    stage("Container ${container_name}") {
        try {
            timeout(BUILD_TIMEOUT) {
                sh "${config.DOCKER_CMD} run --rm ${container_run_option} \
                    -v /opt/ciagent/.gpg.key:/home/ciagent/.gpg.key:ro \
                    -v /${jenkinsAgentRootPath}/.ssh/id_ed25519:/home/ciagent/.ssh/id_ed25519:ro \
                    --env-file /${jenkinsAgentRootPath}/.eXo/Release/exo-release.properties \
                    --env-file ${config.ENV_FILE_FROM_JENKINS} \
                    -e CATALOG_BASE_URL=${CATALOG_BASE_URL} \
                    -e MAVEN_EXTRA_OPTS=${MAVEN_EXTRA_OPTS} \
                    -e exo_user=${exoUser} \
                    -v ${volume_name}:/opt/exo-release/workspace \
                    -v ${taskID}-m2_cache:/home/ciagent/.m2/repository \
                    --name ${container_name} \
                    ${docker_image} \
                    '${container_command}'"
            }
        } catch (err) {
            logError("Failed to release ${project.name}!")
            throw err
        } finally {
            sh "docker rm -f ${container_name} 2>/dev/null || true"
        }
    }

    if (releaseCMD == "cancel") {
        stage("Container ${container_name} (cleanup)") {
            sh "${config.DOCKER_CMD} volume rm ${volume_name}"
            sh "${config.DOCKER_CMD} volume rm ${taskID}-m2_cache"
        }
    }
}

def executeActionOnProjects(projects, catalogIndex, action) {
    for (int i = 0; i < projects.length; i++) {
        def projectName = projects[i]
        def project = catalogIndex[projectName]
        if (project) {
            action(project)
        }
    }
}

def validateProjectsToRelease(projects, catalogIndex) {
    def valid = true
    def releasedProjects = [:]

    projects.each { name ->
        releasedProjects[name] = releasedProjects.containsKey(name) ? releasedProjects[name] + 1 : 1
    }

    def unreleasedProjects = projects.findAll { !catalogIndex.containsKey(it) }
    if (unreleasedProjects) {
        logError("The project(s) ${unreleasedProjects} were not found in the catalog file.")
        valid = false
    }

    def duplicates = releasedProjects.findAll { it.value > 1 }.keySet()
    if (duplicates) {
        logError("The project(s) ${duplicates} are released several times or are present several times in the project list.")
        valid = false
    }

    return valid
}

def selectReleaseNode() {
    def DEFAULT_RELEASE_LABEL = 'docker'
    try {
        return RELEASE_AGENT ?: DEFAULT_RELEASE_LABEL
    } catch (ex) {
        return DEFAULT_RELEASE_LABEL
    }
}

pipeline {
    agent { label selectReleaseNode() }

    options {
        timeout(time: 24, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '30', daysToKeepStr: '90'))
        disableConcurrentBuilds()
        ansiColor('xterm')
    }

    parameters {
        string(name: 'TASK_ID', description: 'Release Task ID (e.g. SWF-1234)')
        string(name: 'PROJECTS', description: 'Comma-separated list of projects to release')
        choice(name: 'RELEASE_CMD', choices: [
            'start',
            'validate',
            'cancel',
            'catalog-from-url',
            'release-continue-from nexus:create',
            'release-continue-from nexus:deploy',
            'release-continue-from nexus:close',
            'release-continue-from git:tagpush'
        ], description: 'Release command to execute')
        booleanParam(name: 'RELEASE_PROJECTS_IN_PARALLEL', defaultValue: false, description: 'Release projects in parallel')
        string(name: 'JENKINS_AGENT_ROOT_PATH', defaultValue: 'home/ciagent', description: 'Root path on Jenkins agent')
        string(name: 'BUILD_USER_ID', description: 'User ID triggering the build')
        string(name: 'CONTINUOUS_RELEASE_SUFFIX', defaultValue: '', description: 'Suffix for continuous release version')
        string(name: 'CATALOG_BASE_URL', defaultValue: '', description: 'Base URL for JSON catalog (overrides default)')
        string(name: 'MAVEN_EXTRA_OPTS', defaultValue: '', description: 'Extra Maven options')
        string(name: 'BUILD_TIMEOUT', defaultValue: '120', description: 'Timeout in minutes per project')
    }

    stages {
        stage('Check Release Parameters') {
            steps {
                script {
                    env.CATALOG_BASE_URL = params.CATALOG_BASE_URL ?: env.CATALOG_BASE_URL

                    def config = [:]
                    def taskID = "${params.TASK_ID}".trim()
                    def projectsRaw = "${params.PROJECTS}".trim()
                    def projectsToRelease = projectsRaw ? projectsRaw.split(',').collect { it.trim() } : []
                    def releaseCMD = "${params.RELEASE_CMD}".trim()
                    def isInParallel = "${params.RELEASE_PROJECTS_IN_PARALLEL}"
                    def jenkinsAgentRootPath = "${params.JENKINS_AGENT_ROOT_PATH}".trim()
                    def exoUser = "${params.BUILD_USER_ID}".trim()
                    def catalogCredentialsId = env.CATALOG_CREDENTIALS_ID ?: ''
                    def continuousReleaseSuffix = "${params.CONTINUOUS_RELEASE_SUFFIX}".trim()

                    config.ENV_FILE_FROM_JENKINS = "${WORKSPACE}/${taskID.replaceAll('/', '-')}.env"
                    config.DOCKER_CMD = env.DOCKER_CMD ?: 'sudo docker'
                    config.MAVEN_EXTRA_OPTS = params.MAVEN_EXTRA_OPTS ?: ''
                    config.BUILD_TIMEOUT = (params.BUILD_TIMEOUT ?: '120') as int
                    config.taskID = taskID

                    logInfo("Projects: ${PROJECTS}")
                    logInfo("Projects computed: ${projectsToRelease}")
                    logInfo("Command: ${releaseCMD}")
                    logInfo("Releases in Parallel? ${isInParallel}")
                    logInfo("Catalog Credentials ID: ${catalogCredentialsId}")

                    // Write env file
                    sh "echo > ${config.ENV_FILE_FROM_JENKINS}"
                    sh "chmod 600 ${config.ENV_FILE_FROM_JENKINS}"

                    if (catalogCredentialsId) {
                        withCredentials([usernamePassword(credentialsId: catalogCredentialsId, usernameVariable: 'CRED_USER', passwordVariable: 'CRED_PASS')]) {
                            sh "echo CATALOG_CREDENTIALS=${CRED_USER}:${CRED_PASS} >> ${config.ENV_FILE_FROM_JENKINS}"
                        }
                    }

                    // Fetch catalog
                    def catalogURL = "${CATALOG_BASE_URL}/${taskID}.json"
                    logInfo("Downloading catalog from ${catalogURL}")

                    def catalog = [:]
                    if (catalogCredentialsId) {
                        withCredentials([usernamePassword(credentialsId: catalogCredentialsId, usernameVariable: 'CRED_USER', passwordVariable: 'CRED_PASS')]) {
                            def authHeaders = createBasicAuthString("${CRED_USER}:${CRED_PASS}")
                            catalog = jsonParser(new URL(catalogURL).newReader(requestProperties: authHeaders))
                        }
                    } else {
                        catalog = jsonParser(new URL(catalogURL).newReader(requestProperties: [:]))
                    }

                    logInfo("Number of Projects in Catalog: ${catalog.size()}")
                    def catalogIndex = buildCatalogIndex(catalog)

                    if (!validateProjectsToRelease(projectsToRelease, catalogIndex)) {
                        error 'Project validation failed'
                    }

                    // Create m2 cache volume
                    sh "${config.DOCKER_CMD} volume create --name ${taskID}-m2_cache"

                    // Execute releases
                    logStage("Launching release...")
                    def releaseAction = { project ->
                        doRelease(exoUser, jenkinsAgentRootPath, taskID, project, releaseCMD, isInParallel, config, continuousReleaseSuffix)
                    }
                    executeActionOnProjects(projectsToRelease, catalogIndex, releaseAction)

                    // Cleanup
                    logInfo("Removing environment file")
                    sh "rm -v ${config.ENV_FILE_FROM_JENKINS}"
                }
            }
        }
    }

    post {
        always {
            script {
                def taskID = "${params.TASK_ID}".trim()
                def envFile = "${WORKSPACE}/${taskID.replaceAll('/', '-')}.env"
                sh "rm -f ${envFile} || true"
            }
        }
        failure {
            logError("Release pipeline failed for TASK_ID: ${params.TASK_ID}")
        }
        success {
            logSuccess("Release pipeline completed successfully for TASK_ID: ${params.TASK_ID}")
        }
    }
}
