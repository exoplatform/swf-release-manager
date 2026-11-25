#!/bin/bash

# Store value $2 with base64 encoding under key $1 in $3 file
function storeCompressedValue {
  local value
  value=$(printf '%s' "$2" | openssl enc -base64)
  echo "$1=$value" >>"$3"
}

function storeCredential { storeCompressedValue "$@"; }

# Decode value $1 encoded in base64
function decompress {
  printf '%s\n' "$1" | openssl enc -base64 -d
}
