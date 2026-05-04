#!/bin/bash -e

# Store a base64-compressed credential in a file.
# Usage: storeCredential <key> <value> <file>
function storeCredential {
  local key="$1"
  local value="$2"
  local file="$3"
  local compressed
  compressed=$(echo -n "$value" | openssl enc -base64)
  echo "${key}=${compressed}" >> "$file"
}

# Decompress a base64-encoded value.
# Usage: decompress <encoded_value>
function decompress {
  echo "$1" | openssl enc -base64 -d
}
