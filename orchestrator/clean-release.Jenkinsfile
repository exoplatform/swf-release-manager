#!/usr/bin/groovy

def logInfo(msg)    { ansiColor('xterm') { echo "\033[34m[INFO]\033[0m ${msg}" } }
def logSuccess(msg) { ansiColor('xterm') { echo "\033[32m[OK]\033[0m ${msg}" } }
def logWarn(msg)    { ansiColor('xterm') { echo "\033[33m[WARN]\033[0m ${msg}" } }
def logError(msg)   { ansiColor('xterm') { echo "\033[31m[ERROR]\033[0m ${msg}" } }

@NonCPS
def jsonParser(def json) {
    new groovy.json.JsonSlurperClassic().parse(json)
}

@NonCPS
def createBasicAuthString(credentials) {
    def authString = credentials.getBytes().encodeBase64().toString()
    [Authorization: "Basic " + authString]
}

def getDockerCommand() {
    return env.DOCKER_CMD ?: 'sudo docker'
}

def doCleanM2Cache(taskID) {
    def m2cacheVolumeName = "${taskID}-m2_cache"
    stage("[Cleanup] Remove Maven Cache for Task ID: ${taskID}") {
        def dockerCmd = getDockerCommand()
        def createdAt = sh(returnStdout: true, script: "${dockerCmd} volume inspect -f '{{ .CreatedAt }}' ${m2cacheVolumeName} 2>/dev/null || :").trim()
        if (createdAt) {
            logInfo("Dropping Maven cache volume ${m2cacheVolumeName}. Creation date: ${createdAt}.")
            sh "${dockerCmd} volume rm ${m2cacheVolumeName}"
        } else {
            logWarn("Maven cache volume ${m2cacheVolumeName} does not exist!")
        }
    }
}

def doClean(taskID, projectname, action) {
    def dockerCmd = getDockerCommand()
    def entity_name = ''
    def docker_command = ''
    def docker_inspect_command = ''

    switch (action) {
        case 'clean-containers':
            entity_name = "${taskID}-${projectname}"
            docker_command = "rm -f"
            docker_inspect_command = "inspect -f '{{ .Created }}'"
            break
        case 'clean-volumes':
            entity_name = "${taskID}-${projectname}-workspace"
            docker_command = "volume rm"
            docker_inspect_command = "volume inspect -f '{{ .CreatedAt }}'"
            break
        default:
            logError("Unknown action: ${action}")
            return
    }

    stage("[Cleanup] ${action.capitalize()} for Project: ${projectname} (Task ID: ${taskID})") {
        def createdAt = sh(returnStdout: true, script: "${dockerCmd} ${docker_inspect_command} ${entity_name} 2>/dev/null || :").trim()
        if (createdAt) {
            logInfo("Dropping ${entity_name}. Creation date: ${createdAt}.")
            sh "${dockerCmd} ${docker_command} ${entity_name}"
        } else {
            logWarn("${entity_name} does not exist!")
        }
    }
}

def doCleans(taskID, projectsToClean, action, cleanM2Cache, catalog) {
    if (cleanM2Cache) {
        doCleanM2Cache(taskID)
    }

    def catalogNames = catalog.collect { it.name }

    if (projectsToClean && projectsToClean.get(0) == '*') {
        catalogNames.each { doClean(taskID, it, action) }
    } else {
        projectsToClean.each { projectName ->
            if (catalogNames.contains(projectName)) {
                doClean(taskID, projectName, action)
            }
        }
    }
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
        timeout(time: 4, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '30', daysToKeepStr: '90'))
        ansiColor('xterm')
    }

    parameters {
        string(name: 'TASK_ID', description: 'Release Task ID (e.g. SWF-1234)')
        string(name: 'PROJECTS', defaultValue: '*', description: 'Comma-separated list of projects to clean, or * for all')
        choice(name: 'ACTION', choices: [
            'clean-containers',
            'clean-volumes'
        ], description: 'Cleanup action to execute')
        booleanParam(name: 'CLEAN_M2_CACHE', defaultValue: false, description: 'Also clean Maven cache volume')
    }

    stages {
        stage('[Initialization] Prepare Parameters for Cleanup') {
            steps {
                script {
                    env.CATALOG_BASE_URL = params.CATALOG_BASE_URL ?: env.CATALOG_BASE_URL

                    def taskID = "${params.TASK_ID}".trim()
                    def action = "${params.ACTION}".trim()
                    def projectsRaw = "${params.PROJECTS}".trim()
                    def projectsToClean = projectsRaw ? projectsRaw.split(',').collect { it.trim() } : []
                    def catalogCredentialsId = env.CATALOG_CREDENTIALS_ID ?: ''
                    def cleanM2Cache = params.CLEAN_M2_CACHE

                    def nodeName = env.NODE_NAME ?: 'unknown'

                    logInfo("Projects: ${projectsToClean}")
                    logInfo("Command: ${action}")
                    logInfo("Clean Maven Cache: ${cleanM2Cache}")
                    logInfo("Credentials ID: ${catalogCredentialsId}")
                    logInfo("Agent Node: ${nodeName}")
                    logInfo("Catalog URL: ${CATALOG_BASE_URL}/${taskID}.json")

                    // Fetch catalog with proper credentials scope
                    def catalogURL = "${CATALOG_BASE_URL}/${taskID}.json"
                    def catalog = []

                    if (catalogCredentialsId) {
                        withCredentials([usernamePassword(credentialsId: catalogCredentialsId, usernameVariable: 'CRED_USER', passwordVariable: 'CRED_PASS')]) {
                            logInfo("Downloading catalog from ${catalogURL} (with credentials)")
                            def authHeaders = createBasicAuthString("${CRED_USER}:${CRED_PASS}")
                            catalog = jsonParser(new URL(catalogURL).newReader(requestProperties: authHeaders))
                        }
                    } else {
                        logInfo("Downloading catalog from ${catalogURL} (no credentials)")
                        catalog = jsonParser(new URL(catalogURL).newReader(requestProperties: [:]))
                    }

                    logInfo("Projects in Catalog: ${catalog.size()}")

                    doCleans(taskID, projectsToClean, action, cleanM2Cache, catalog)
                }
            }
        }
    }

    post {
        failure {
            logError("Cleanup pipeline failed for TASK_ID: ${params.TASK_ID}")
        }
        success {
            logSuccess("Cleanup pipeline completed successfully for TASK_ID: ${params.TASK_ID}")
        }
    }
}
