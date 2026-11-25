#!/bin/bash
# Config file helpers (need common.sh)

# Copy $1 to $2 after having backed up $2 if it existed
function installFile {
  log_info "Setup $2"
  # Backup if exists
  if [ -e "$2" ]; then
    mv "$2" "$2.$DATE"
    mv "$2.$DATE" "$BACKUPS_DIR"
    log_info "Old $2 is backup at $BACKUPS_DIR"
  fi
  mkdir -p "${2%/*}"
  cp "$1" "$2"
  chmod 700 "$2" # Some files contain passwords
}

# Replaces all occurences of $2 by $3 in file $1 ($3 may contain any character)
function replaceInFile {
  local rep
  rep=$(sed_escape_replacement "$3")
  sed "s${SEP}$2${SEP}${rep}${SEP}g" "$1" >"$1.tmp"
  mv "$1.tmp" "$1"
}
