#!/bin/bash -eu
set -o pipefail

if [ $# -lt 1 ]; then
  printf '%s\n' "Usage: $0 whattofind filename [wheretofind]" >&2
  exit 1
fi

if [ $# -eq 3 ]; then
  find "$3" -name "$2" -type f -exec grep -Hn "$1" {} \;
else
  find . -name "$2" -type f -exec grep -Hn "$1" {} \;
fi
