#!/bin/bash -eu
set -o pipefail

SCRIPT_DIR="${0%/*}"

if [ $# -lt 2 ]; then
  printf '%s\n' "Usage: $0 whattoreplace replacement" >&2
  exit 1
fi

if [ $# -eq 3 ]; then
  "${SCRIPT_DIR}/replace-in-files.sh" "$1" "$2" "pom.xml" "$3"
else
  "${SCRIPT_DIR}/replace-in-files.sh" "$1" "$2" "pom.xml"
fi
