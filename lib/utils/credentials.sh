#!/bin/bash -eu
set -o pipefail

function storeCredential {
  printf '%s' "$2" | openssl base64
}

function decompress {
  printf '%s' "$1" | openssl base64 -d
}
