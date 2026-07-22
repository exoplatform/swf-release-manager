#!/bin/bash -eu
set -o pipefail

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
  printf 'Usage: %s findtext replacement filepattern [wheretofind]\n' "$0" >&2
  exit 1
fi

if [ $# -eq 4 ]; then
  find "$4" -name "$3" -type f -exec sed -i "s${SEP}$1${SEP}$2${SEP}g" {} \;
else
  find . -name "$3" -type f -exec sed -i "s${SEP}$1${SEP}$2${SEP}g" {} \;
fi
