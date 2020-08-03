#!/bin/bash -eu
set -o pipefail

SCRIPTS_DIR=${0%/*}

source ${SCRIPTS_DIR}/common.sh
source ${SCRIPTS_DIR}/utils/credentials.sh
source ${SCRIPTS_DIR}/process/git-clone.sh
source ${SCRIPTS_DIR}/process/git-release.sh


function createReleaseBranches(){
    
}

function deleteReleaseBranches(){

}