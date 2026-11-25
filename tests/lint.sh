#!/bin/bash
# Lint every bash script of the project (the expect script ssh-add-pass.sh is not bash).
set -euo pipefail
cd "${0%/*}/.."
files=$(find app/scripts app/conf tests -type f \( -name '*.sh' -o -path 'tests/integration/bin/*' \) ! -name ssh-add-pass.sh | sort)
# shellcheck disable=SC2086
shellcheck -x -S warning $files
echo "shellcheck OK"
