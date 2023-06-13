#!/bin/bash -eu
set -o pipefail

SCRIPTS_DIR=${0%/*}
source ${SCRIPTS_DIR}/common.sh
source ${SCRIPTS_DIR}/utils/credentials.sh

log "==============================================================================="
log "eXo Platform Release Manager (v ${EXOR_VERSION})"
log "==============================================================================="

# Copy $1 to $2 after having backed up $2 if it existed
function installFile {
  echo "Setup $2"
  # Backup if exists
  if [ -e $2 ]; then
    mv $2 $2.$DATE
    mv $2.$DATE $BACKUPS_DIR
    echo "Old $2 is backup at $BACKUPS_DIR"
  fi
  mkdir -p ${2%/*}
  cp $1 $2
  chmod 700 $2 #Some files contain passwords
}


# Replaces all occurences of $2 by $3 in file $1
function replaceInFile {
  sed "s${SEP}$2${SEP}$3${SEP}g" $1 > $1.tmp
  mv $1.tmp $1
}

printHeader "Load credentials from $CREDENTIALS_FILE"
source $CREDENTIALS_FILE

printHeader "System Information"
log ">>> Operating System :"
uname -a | log

printHeader "Configuration file preparation"
# BASH Config
installFile $CONFIG_DIR/bashrc $HOME/.bashrc
chmod u+x $HOME/.bashrc
replaceInFile $HOME/.bashrc @@TOOLS_DIR@@ $TOOLS_DIR
replaceInFile $HOME/.bashrc @@SCRIPTS_DIR@@ $SCRIPTS_DIR

# Git Config
installFile $CONFIG_DIR/gitconfig $HOME/.gitconfig
replaceInFile $HOME/.gitconfig @@GITHUB_LOGIN@@          $github_login
replaceInFile $HOME/.gitconfig @@GITHUB_FULLNAME@@       $github_fullname
replaceInFile $HOME/.gitconfig @@GITHUB_EMAIL@@          $github_email
replaceInFile $HOME/.gitconfig @@GITHUB_SIGNING_KEY@@    $gpg_keyname
replaceInFile $HOME/.gitconfig @@GPG_PROGRAM@@ $HOME/gpg-no-tty.sh 
installFile $CONFIG_DIR/gpg-no-tty.sh $HOME/gpg-no-tty.sh 
replaceInFile $HOME/gpg-no-tty.sh @@GPG_KEY_PASSPHRASE@@  $(decompress $gpg_passphrase)
chmod +x $HOME/gpg-no-tty.sh 
installFile $CONFIG_DIR/initgpg.sh $HOME/initgpg.sh
replaceInFile $HOME/initgpg.sh @@GPG_KEY_PASSPHRASE@@  $(decompress $gpg_passphrase)
chmod +x $HOME/initgpg.sh

installFile $CONFIG_DIR/gitignore $HOME/.gitignore
git config --global core.excludesfile $HOME/.gitignore

# MAVEN Config
installFile $CONFIG_DIR/settings.xml $HOME/.m2/settings.xml
replaceInFile $HOME/.m2/settings.xml @@NEXUS_LOGIN@@          $nexus_login
replaceInFile $HOME/.m2/settings.xml @@NEXUS_TOKEN@@          $(decompress $nexus_token)
replaceInFile $HOME/.m2/settings.xml @@EXO_USER@@             $exo_user
replaceInFile $HOME/.m2/settings.xml @@EXOR_VERSION@@         $EXOR_VERSION
replaceInFile $HOME/.m2/settings.xml @@JBOSS_LOGIN@@          $jboss_login
replaceInFile $HOME/.m2/settings.xml @@JBOSS_PASSWORD@@       $(decompress $jboss_password)
replaceInFile $HOME/.m2/settings.xml @@GPG_KEY_PASSPHRASE@@   $(decompress $gpg_passphrase)
replaceInFile $HOME/.m2/settings.xml @@GPG_KEY_NAME@@         $gpg_keyname
replaceInFile $HOME/.m2/settings.xml @@TOOLS_DIR@@            $TOOLS_DIR
replaceInFile $HOME/.m2/settings.xml @@SERVER_DIR@@           $LOCAL_DEPENDENCIES_DIR

# Extra Maven OPTS
export MAVEN_OPTS="${MAVEN_OPTS:-} ${MAVEN_EXTRA_OPTS:-}"

# Install release.json file only if it doesn't already exist
if [ -f "$WORKSPACE_DIR/release.json" ]
then
	log "$WORKSPACE_DIR/release.json already exist (do not override)."
else
  log "Install release.json file"
	installFile $CONFIG_DIR/release.json $WORKSPACE_DIR/release.json
fi

printHeader " ==> Github Crendentials (exo-swf)..."
export SSH_PASS=$(decompress $ssh_passphrase)
eval "$(ssh-agent)"
$SCRIPTS_DIR/utils/ssh-add-pass.sh
ssh-keyscan -H github.com >> ~/.ssh/known_hosts
$HOME/initgpg.sh
printFooter " ==> Credentials..."

log "Execute eXo Release command...($@)"
bash -c "$SCRIPTS_DIR/eXoR.sh $@"
