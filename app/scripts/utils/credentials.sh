#!/bin/bash -e

# Store value $2 with 64b compression under key $1 in $3 file
function storeCompressedValue {
  COMPRESSED_VALUE=`echo -n "$2" | openssl enc -base64`
  echo "$1=$COMPRESSED_VALUE" >> "$3"
}

# Store a value named $2 compressed in 64b under key $1 in $3 file
function storeCredential {
  storeCompressedValue "$1" "$2" "$3"
}

# decompress value $1 compressed in base64
function decompress {
  echo "$1" | openssl enc -base64 -d
}
