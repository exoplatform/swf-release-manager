#!/bin/bash -eu
set -o pipefail

SCRIPT_DIR="${0%/*}"

if [ $# -lt 1 ]; then
  printf '%s\n' "Usage: $0 whattofind" >&2
  exit 1
fi

if [ $# -eq 2 ]; then
  "${SCRIPT_DIR}/find-in-files.sh" "$1" "pom.xml" "$2"
else
  "${SCRIPT_DIR}/find-in-files.sh" "$1" "pom.xml"
fi
