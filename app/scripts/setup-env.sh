#!/bin/bash
# shellcheck disable=SC2154 # credentials and settings come from the environment / $CREDENTIALS_FILE
set -euo pipefail

# shellcheck source-path=SCRIPTDIR
SCRIPTS_DIR=${0%/*}
source "${SCRIPTS_DIR}/common.sh"
source "${SCRIPTS_DIR}/utils/credentials.sh"
source "${SCRIPTS_DIR}/utils/files.sh"

log "==============================================================================="
log "eXo Platform Release Manager (v ${EXOR_VERSION})"
log "==============================================================================="

printHeader "Load credentials from $CREDENTIALS_FILE"
# shellcheck disable=SC1090
source "$CREDENTIALS_FILE"
for _v in "${nexus_token:-}" "${jboss_password:-}" "${gpg_passphrase:-}" "${ssh_passphrase:-}"; do
  if [ -n "$_v" ]; then log_register_secret "$(decompress "$_v")"; fi
done
log_register_secret "${TRIBE_RELEASE_PASSWORD:-}"

printHeader "System Information"
log ">>> Operating System :"
uname -a | log

printHeader "Configuration file preparation"
# BASH Config
installFile "$CONFIG_DIR/bashrc" "$HOME/.bashrc"
chmod u+x $HOME/.bashrc
replaceInFile "$HOME/.bashrc" @@TOOLS_DIR@@ "$TOOLS_DIR"
replaceInFile "$HOME/.bashrc" @@SCRIPTS_DIR@@ "$SCRIPTS_DIR"

# Git Config
installFile "$CONFIG_DIR/gitconfig" "$HOME/.gitconfig"
replaceInFile "$HOME/.gitconfig" @@GITHUB_LOGIN@@ "$github_login"
replaceInFile "$HOME/.gitconfig" @@GITHUB_FULLNAME@@ "$github_fullname"
replaceInFile "$HOME/.gitconfig" @@GITHUB_EMAIL@@ "$github_email"
replaceInFile "$HOME/.gitconfig" @@GITHUB_SIGNING_KEY@@ "$ssh_signing_key_path"
replaceInFile "$HOME/.gitconfig" @@GPG_FORMAT@@ "ssh"
installFile "$CONFIG_DIR/initgpg.sh" "$HOME/initgpg.sh"
replaceInFile "$HOME/initgpg.sh" @@GPG_KEY_PASSPHRASE@@ "$(decompress $gpg_passphrase)"
chmod +x $HOME/initgpg.sh

installFile "$CONFIG_DIR/gitignore" "$HOME/.gitignore"
git config --global core.excludesfile $HOME/.gitignore

# MAVEN Config
# Maven 3.10+ scopes server credentials by repository origin and understands
# <repositoryOrigins>; older versions only warn about the unknown tag, so pick
# the settings template matching the installed Maven.
maven_version=""
if command -v mvn >/dev/null 2>&1; then
  maven_version=$(mvn -version 2>/dev/null | awk '/Apache Maven/{print $3; exit}') || maven_version=""
fi
maven_settings=$CONFIG_DIR/settings.xml
if [ -n "$maven_version" ] && [ "$(printf '%s\n' "3.10" "$maven_version" | sort -V | sed -n 1p)" = "3.10" ]; then
  maven_settings=$CONFIG_DIR/settings-maven310.xml
fi
log "Maven ${maven_version:-unknown} detected, installing ${maven_settings##*/} as \$HOME/.m2/settings.xml"
installFile $maven_settings $HOME/.m2/settings.xml
replaceInFile "$HOME/.m2/settings.xml" @@NEXUS_LOGIN@@ "$nexus_login"
replaceInFile "$HOME/.m2/settings.xml" @@NEXUS_TOKEN@@ "$(decompress $nexus_token)"
replaceInFile "$HOME/.m2/settings.xml" @@EXO_USER@@ "$exo_user"
replaceInFile "$HOME/.m2/settings.xml" @@EXOR_VERSION@@ "$EXOR_VERSION"
replaceInFile "$HOME/.m2/settings.xml" @@JBOSS_LOGIN@@ "$jboss_login"
replaceInFile "$HOME/.m2/settings.xml" @@JBOSS_PASSWORD@@ "$(decompress $jboss_password)"
replaceInFile "$HOME/.m2/settings.xml" @@GPG_KEY_PASSPHRASE@@ "$(decompress $gpg_passphrase)"
replaceInFile "$HOME/.m2/settings.xml" @@GPG_KEY_NAME@@ "$gpg_keyname"
replaceInFile "$HOME/.m2/settings.xml" @@TOOLS_DIR@@ "$TOOLS_DIR"
replaceInFile "$HOME/.m2/settings.xml" @@SERVER_DIR@@ "$LOCAL_DEPENDENCIES_DIR"

# Extra Maven OPTS
# The local repository (~/.m2) and the workspace are on different filesystems
# (docker volumes), so Maven Resolver 2.x cannot hard-link on install and logs a
# long "Invalid cross-device link" stack trace before falling back to a copy.
# Copy directly instead (property ignored by Resolver 1.x / Maven 3.9).
export MAVEN_OPTS="${MAVEN_OPTS:-} -Daether.installer.hardLink=false ${MAVEN_EXTRA_OPTS:-}"

# Install release.json file only if it doesn't already exist
if [ -f "$WORKSPACE_DIR/release.json" ]
then
	log "$WORKSPACE_DIR/release.json already exist (do not override)."
else
  log "Install release.json file"
	installFile $CONFIG_DIR/release.json $WORKSPACE_DIR/release.json
fi

printHeader " ==> Github Crendentials (exo-swf)..."
SSH_PASS=$(decompress "$ssh_passphrase")
export SSH_PASS
eval "$(ssh-agent)"
$SCRIPTS_DIR/utils/ssh-add-pass.sh
mkdir -p ~/.ssh
ssh-keyscan -H "${GIT_HOST:-github.com}" >>~/.ssh/known_hosts
$HOME/initgpg.sh
printFooter " ==> Credentials..."

# The orchestrator passes the whole command as ONE argument ("release-start prj 123 2022"):
# split it on spaces, without ever evaluating it with a shell
if [ $# -eq 1 ]; then
  read -r -a _args <<<"$1"
  set -- "${_args[@]}"
fi
log "Execute eXo Release command...($*)"
exec "$SCRIPTS_DIR/eXoR.sh" "$@"
