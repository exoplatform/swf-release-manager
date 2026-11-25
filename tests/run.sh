#!/bin/bash
# Lint + unit + integration tests
set -euo pipefail
cd "${0%/*}"
./lint.sh
./unit.sh
./integration.sh
