#!/bin/bash
# Parse (not run) the Jenkinsfiles with Groovy in a container. @NonCPS is a Jenkins annotation: stripped.
set -euo pipefail
cd "${0%/*}/.."
docker run --rm -v "$PWD/orchestrator:/o:ro" groovy:4.0-jdk17 bash -c '
  for f in /o/*/Jenkinsfile; do
    sed "s/^@NonCPS//" "$f" >/tmp/x.groovy
    groovy -e "new GroovyShell().parse(new File(\"/tmp/x.groovy\")); println \"parsed OK $f\""
  done'
