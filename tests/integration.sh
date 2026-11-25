#!/bin/bash
# Integration tests: run the REAL eXoR.sh / setup-env.sh scripts against
#  - a local HTTP server (catalogs in json and yaml, Nexus staging REST API, Tribe comments)
#  - a local bare git repository (reached through git's insteadOf, like git@github.com:org/prj.git)
#  - a fake mvn / ssh-agent (see tests/integration/bin)
# Run: tests/integration.sh
set -uo pipefail
HERE=$(cd "${0%/*}" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
source "$HERE/lib.sh"

command -v jq >/dev/null || { echo "jq is required"; exit 2; }
command -v git >/dev/null || { echo "git is required"; exit 2; }
command -v python3 >/dev/null || { echo "python3 is required"; exit 2; }

TMP=$(mktemp -d)
SERVER_PID=""
trap '[ -n "$SERVER_PID" ] && kill "$SERVER_PID" 2>/dev/null; rm -rf "$TMP"' EXIT

# ---- layout: scripts are copied so that the ssh passphrase helper (needs expect) can be replaced
export HOME=$TMP/home
mkdir -p "$HOME" "$TMP/remotes" "$TMP/catalog" "$TMP/fakelog" "$TMP/exor"
cp -R "$ROOT/app/scripts" "$TMP/exor/scripts"
cp -R "$ROOT/app/conf" "$TMP/exor/config"
printf '#!/bin/bash\nexit 0\n' >"$TMP/exor/scripts/utils/ssh-add-pass.sh"
chmod +x "$TMP/exor/scripts/"*.sh "$TMP/exor/scripts/utils/"*.sh

export EXOR_VERSION=0.0.test exo_user=itest
export WORKSPACE_DIR=$TMP/ws DATAS_DIR=$TMP/ws/datas LOGS_DIR=$TMP/ws/logs PRJ_DIR=$TMP/ws/projects
export LOCAL_STAGING_DIR=$TMP/ws/local-staging BACKUPS_DIR=$TMP/backup CONFIG_DIR=$TMP/exor/config
export SCRIPTS_DIR=$TMP/exor/scripts TOOLS_DIR=$TMP/tools LOCAL_DEPENDENCIES_DIR=$TMP/deps
export CREDENTIALS_FILE=$HOME/.exo_cred FAKE_LOG=$TMP/fakelog
mkdir -p "$DATAS_DIR" "$LOGS_DIR" "$PRJ_DIR" "$LOCAL_STAGING_DIR" "$BACKUPS_DIR" "$TOOLS_DIR" "$LOCAL_DEPENDENCIES_DIR"
export PATH=$HERE/integration/bin:$PATH

SECRET_NEXUS='N3xus/t0ken&secret'
SECRET_SSH='ssh-pass-phrase'
SECRET_GPG='gpg-pass-phrase'
SECRET_JBOSS='jb0ss-pass'
SECRET_TRIBE='tribe-p4ss'
b64() { printf '%s' "$1" | openssl enc -base64; }
{
  echo "ssh_passphrase=$(b64 "$SECRET_SSH")"
  echo "nexus_token=$(b64 "$SECRET_NEXUS")"
  echo "gpg_passphrase=$(b64 "$SECRET_GPG")"
  echo "jboss_password=$(b64 "$SECRET_JBOSS")"
} >"$CREDENTIALS_FILE"

# ---- fake HTTP server
python3 "$HERE/integration/fake_server.py" "$TMP/catalog" "$TMP/requests.jsonl" "$TMP/port" &
SERVER_PID=$!
for _ in $(seq 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
PORT=$(cat "$TMP/port")
export CATALOG_BASE_URL=http://127.0.0.1:$PORT/catalog
export NEXUS_REPO_URL=http://127.0.0.1:$PORT NEXUS_JBOSS_REPO_URL=http://127.0.0.1:$PORT
export NEXUS_STAGING_SERVER_ID=exo-staging NEXUS_JBOSS_STAGING_SERVER_ID=jboss-staging
export NEXUS_STAGING_PROFILE_PUBLIC_ID=profile-public NEXUS_STAGING_PROFILE_PRIVATE_ID=profile-private
export nexus_login=nexus-user jboss_login=jboss-user
export TRIBE_RELEASE_USER=tribe-user TRIBE_RELEASE_PASSWORD=$SECRET_TRIBE
export TRIBE_RELEASE_TASK_REST_PREFIXE_URL=http://127.0.0.1:$PORT/tasks/comments
export GIT_HOST=github.com CATALOG_CREDENTIALS=

# ---- fake git remote: git@github.com:exoplatform/<prj>.git -> $TMP/remotes/<prj>.git
export GIT_CONFIG_GLOBAL=$TMP/gitconfig
git config --global user.name tester
git config --global user.email tester@example.org
git config --global init.defaultBranch develop
git config --global commit.gpgsign false
git config --global tag.gpgsign false
git config --global protocol.file.allow always
git config --global url."$TMP/remotes/".insteadOf "git@github.com:exoplatform/"
make_remote() { # name
  local w=$TMP/seed-$1
  git init -q "$w" && (cd "$w" && printf '<project><properties><org.wiki.version>1.0.x-SNAPSHOT</org.wiki.version></properties></project>' >pom.xml \
    && git add . && git commit -q -m init)
  git clone -q --bare "$w" "$TMP/remotes/$1.git"
}
make_remote wiki

# ---- catalogs
cat >"$TMP/catalog/1001.json" <<'JSON'
[{"name":"wiki","git_organization":"exoplatform","labels":"plf","maven_property_version":"org.wiki.version",
  "release":{"branch":"develop","version":"1.0.0","current_snapshot_version":"1.0.x-SNAPSHOT","next_snapshot_version":"1.1.x-SNAPSHOT","nexus_host":"exoplatform","nexus_staging_profile":"public"}}]
JSON
cat >"$TMP/catalog/1002.yaml" <<'YAML'
- name: wiki
  git_organization: exoplatform
  labels: plf
  maven_property_version: org.wiki.version
  release:
    branch: develop
    version: "2.0.0"
    current_snapshot_version: 1.0.x-SNAPSHOT
    next_snapshot_version: 2.1.x-SNAPSHOT
    nexus_host: exoplatform
    nexus_staging_profile: public
YAML
sed 's/1.0.0/3.0.0/' "$TMP/catalog/1001.json" >"$TMP/catalog/1003.json"
sed 's/1.0.0/4.0.0/' "$TMP/catalog/1001.json" >"$TMP/catalog/1004.json"
sed 's/"1.0.0"/"5.0.0-${release-version}"/' "$TMP/catalog/1001.json" >"$TMP/catalog/continuous-release-template.json"

EXOR=$SCRIPTS_DIR/eXoR.sh
new_workspace() {
  rm -rf "$WORKSPACE_DIR" "$FAKE_LOG" "$TMP/requests.jsonl"
  mkdir -p "$DATAS_DIR" "$LOGS_DIR" "$PRJ_DIR" "$LOCAL_STAGING_DIR" "$FAKE_LOG"
  cp "$ROOT/app/conf/release.json" "$WORKSPACE_DIR/release.json"
  : >"$TMP/requests.jsonl"
}
run() { OUT=$("$EXOR" "$@" 2>&1); RC=$?; }
remote_has_tag() { git ls-remote --tags "$TMP/remotes/wiki.git" "refs/tags/$1" | grep -q .; }
wait_comments() { # expected-count  (comments are posted in the background)
  for _ in $(seq 50); do
    [ "$(grep -c '/tasks/comments/' "$TMP/requests.jsonl")" -ge "$1" ] && return 0
    sleep 0.1
  done
}
comments() { jq -r 'select(.path|startswith("/tasks/comments/")) | .body' "$TMP/requests.jsonl" | python3 -c '
import sys, urllib.parse
for l in sys.stdin: print(urllib.parse.unquote(l.strip()))'; }

# =============================================================================
t_start "help / list"
new_workspace
run help;  assert_rc 0 $RC "help exit code"; assert_contains "$OUT" "release-start PROJECT TASK_ID" "usage printed"
run;       assert_rc 0 $RC "no argument prints the usage"
run bogus; assert_rc 1 $RC "unknown command fails"
run list;  assert_rc 0 $RC "list without catalog"; assert_contains "$OUT" "catalog.json not found" "tells how to get a catalog"

t_start "catalog-from-url"
run catalog-from-url 1001
assert_rc 0 $RC "json catalog"
assert_contains "$OUT" "* wiki - 1.0.0 - develop (plf)" "project listed"
if command -v yq >/dev/null 2>&1 || python3 -c 'import yaml' 2>/dev/null; then
  run catalog-from-url 1002
  assert_rc 0 $RC "yaml catalog"
  assert_contains "$OUT" "* wiki - 2.0.0 - develop (plf)" "yaml project listed"
else
  printf '  skip yaml catalog (no yq / PyYAML)\n'
fi
run catalog-from-url 9999
assert_rc 1 $RC "unknown catalog"
assert_contains "$OUT" "Unable to download the catalog" "clear error"
run project-info wiki >/dev/null
run release-start wiki not-a-number
assert_rc 103 $RC "invalid TASK_ID refused"
run release-start wiki 1001 12345
assert_rc 103 $RC "invalid CONTINUOUS_RELEASE_SUFFIX refused"

# =============================================================================
t_start "release-start (manual validation flow)"
new_workspace
run release-start wiki 1001
assert_rc 0 $RC "release-start succeeds"
[ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | tail -20
MVN=$FAKE_LOG/mvn.log
assert_file_contains "$MVN" "release:prepare" "release:prepare called"
assert_file_contains "$MVN" "-Dtag=1.0.0" "tag name"
assert_file_contains "$MVN" "-DsignTag=true" "signed tag requested"
assert_file_contains "$MVN" "-DdevelopmentVersion=1.1.x-SNAPSHOT" "next snapshot version"
assert_file_contains "$MVN" "release:perform" "release:perform called"
assert_file_contains "$MVN" "nexus-staging:deploy-staged-repository" "deployed to the staging repository"
assert_file_contains "$MVN" "-DstagingProfileId=profile-public" "staging profile resolved from the environment"
assert_file_contains "$MVN" "-DstagingRepositoryId=repo-1" "uses the repository id returned by Nexus"
assert_file_contains "$MVN" "nexus-staging:rc-close" "staging repository closed"
assert_file_not_contains "$MVN" "rc-release" "not released before the validation"
assert_eq 0 "$(grep release:prepare "$MVN" | grep -c -- "-Darguments=-DskipTests")" "tests are run by release:prepare for a regular release"
assert_eq "repo-1" "$(jq -r .nexus.staged_repository_id "$WORKSPACE_DIR/release.json")" "release.json keeps the repository id"
assert_eq "wiki" "$(jq -r .project "$WORKSPACE_DIR/release.json")" "release.json keeps the project"
assert_eq "success" "$(jq -r .step.status "$WORKSPACE_DIR/release.json")" "last step is successful"
assert_file_contains "$PRJ_DIR/wiki/pom.xml" "<org.wiki.version>1.0.0</org.wiki.version>" "SNAPSHOT dependency switched to the release version"
assert_eq "release/1.0.0" "$(git -C "$PRJ_DIR/wiki" rev-parse --abbrev-ref HEAD)" "local release branch created"
assert_eq "false" "$(remote_has_tag 1.0.0 && echo true || echo false)" "tag NOT pushed before validation"
# the Nexus request
nexus_req=$(jq -c 'select(.path|test("/start$"))' "$TMP/requests.jsonl")
assert_contains "$nexus_req" "/service/local/staging/profiles/profile-public/start" "Nexus profile URL"
assert_contains "$nexus_req" "$(printf 'nexus-user:%s' "$SECRET_NEXUS" | base64 -w0 | head -c 0)" "request sent"
assert_eq "Basic $(printf 'nexus-user:%s' "$SECRET_NEXUS" | base64 -w0)" "$(jq -r .auth <<<"$nexus_req")" "basic auth used"
assert_eq "1001:wiki:1.0.0" "$(jq -r '.body|fromjson|.data.description' <<<"$nexus_req")" "description sent as JSON"
assert_contains "$(jq -r .agent <<<"$nexus_req")" "eXo Release Manager v0.0.test (itest)" "user agent"
wait_comments 5
c=$(comments)
assert_contains "$c" "Release prepared" "Tribe: prepare comment"
assert_contains "$c" "Release performed" "Tribe: perform comment"
assert_contains "$c" "Nexus staging repository created" "Tribe: staging created"
assert_contains "$c" "Nexus staging repository closed" "Tribe: staging closed"
tribe_req=$(jq -c 'select(.path|startswith("/tasks/comments/"))' "$TMP/requests.jsonl" | head -1)
assert_contains "$tribe_req" "/tasks/comments/1001" "comment posted on the task"
# logs
assert_file_contains "$LOGS_DIR/infos.log" "[INFO ]" "log lines carry a level"
for s in "$SECRET_NEXUS" "$SECRET_SSH" "$SECRET_GPG" "$SECRET_TRIBE"; do
  assert_file_not_contains "$LOGS_DIR/infos.log" "$s" "no secret in infos.log"
  assert_not_contains "$OUT" "$s" "no secret on the console"
done

t_start "release-continue-from / release-validate"
run release-continue-from nexus:bogus
assert_rc 1 $RC "unknown step refused"
run release-continue-from nexus:close
assert_rc 0 $RC "nexus:close"
run release-validate
assert_rc 0 $RC "release-validate"
assert_file_contains "$MVN" "nexus-staging:rc-release" "staging repository released"
assert_eq "true" "$(remote_has_tag 1.0.0 && echo true || echo false)" "tag pushed to the remote"
assert_eq "develop" "$(git -C "$PRJ_DIR/wiki" rev-parse --abbrev-ref HEAD)" "release branch removed after the push"

t_start "release-start with an existing tag"
new_workspace
run release-start wiki 1001
assert_rc 100 $RC "refused (tag already on the remote)"
assert_contains "$OUT" "already exist" "explains why"
wait_comments 1
assert_contains "$(comments)" "Release failed: prerequisites not met" "Tribe is told about the failure"
assert_eq "error" "$(jq -r .step.status "$WORKSPACE_DIR/release.json")" "release.json is in error"
[ ! -s "$FAKE_LOG/mvn.log" ] && t_ok "maven never called" || t_ko "maven was called"

t_start "release-start with a maven failure"
new_workspace
FAKE_MVN_FAIL=release:prepare FAKE_SECRET=$SECRET_GPG run release-start wiki 1003
assert_rc 200 $RC "exit code 200 for a Maven failure"
assert_contains "$OUT" "The Maven Project failed to build" "explained"
assert_not_contains "$OUT" "$SECRET_GPG" "secret printed by maven is masked on the console"
assert_file_not_contains "$LOGS_DIR/infos.log" "$SECRET_GPG" "secret printed by maven is masked in the log"
assert_contains "$OUT" "********" "mask visible"
wait_comments 1
assert_contains "$(comments)" "Maven build error" "Tribe: error reason"
assert_eq "error" "$(jq -r .step.status "$WORKSPACE_DIR/release.json")" "release.json is in error"
assert_eq "false" "$(remote_has_tag 3.0.0 && echo true || echo false)" "nothing pushed"

t_start "release-cancel"
new_workspace
run release-start wiki 1004
assert_rc 0 $RC "start"
run release-cancel
assert_rc 0 $RC "cancel"
assert_file_contains "$FAKE_LOG/mvn.log" "nexus-staging:rc-drop" "staging repository dropped"
[ ! -e "$WORKSPACE_DIR/release.json" ] && t_ok "release.json removed" || t_ko "release.json still there"
assert_eq 0 "$(ls -A "$PRJ_DIR" | wc -l)" "projects removed"

t_start "continuous release (CI/CD)"
new_workspace
run release-start wiki continuous-release-template 20221020
assert_rc 0 $RC "continuous release"
[ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | tail -20
assert_file_contains "$FAKE_LOG/mvn.log" "nexus-staging:rc-close nexus-staging:rc-release" "closed and released in one go"
assert_eq "true" "$(remote_has_tag 5.0.0-20221020 && echo true || echo false)" "tag pushed without validation"
wait_comments 1
assert_eq 0 "$(comments | wc -l)" "no Tribe comment for continuous releases"

t_start "weekly release with a suffix skips the unit tests"
new_workspace
git -C "$TMP/remotes/wiki.git" tag -d 1.0.0 >/dev/null 2>&1
run release-start wiki 1001 20221020
assert_rc 0 $RC "start with suffix"
assert_file_contains "$FAKE_LOG/mvn.log" "-Darguments=-DskipTests" "tests skipped for prepare"

t_start "project-clone"
new_workspace
run catalog-from-url 1001 >/dev/null
run project-clone wiki
assert_rc 0 $RC "project-clone"
[ -f "$PRJ_DIR/wiki/pom.xml" ] && t_ok "project cloned" || t_ko "project missing"
run project-clone -l plf; assert_rc 0 $RC "clone by label"
run project-clone -l nothing; assert_not_contains "$OUT" "Cloning wiki" "no project for an unknown label"
run project-clone ghost; assert_rc 1 $RC "unknown project"

# =============================================================================
# setup-env.sh: the real entrypoint (configuration files, single-argument command)
t_start "setup-env.sh"
new_workspace
export github_login=gh-user github_fullname="Full Name" github_email=me@example.org
export ssh_signing_key_path=$HOME/.ssh/sign gpg_keyname=KEYNAME
SETUP_HOME=$TMP/setup-home
mkdir -p "$SETUP_HOME"
OUT=$(HOME=$SETUP_HOME "$SCRIPTS_DIR/setup-env.sh" "catalog-from-url 1001" 2>&1); RC=$?
[ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | tail -15
assert_rc 0 $RC "setup-env succeeds with the command as ONE argument"
assert_contains "$OUT" "* wiki - 1.0.0 - develop (plf)" "command split and executed"
assert_file_contains "$SETUP_HOME/.gitconfig" "email = me@example.org" "gitconfig generated"
assert_file_contains "$SETUP_HOME/.gitconfig" "format = ssh" "ssh signing"
assert_file_contains "$SETUP_HOME/.m2/settings.xml" "$SECRET_NEXUS" "secret with & and / written verbatim in settings.xml"
assert_file_not_contains "$SETUP_HOME/.m2/settings.xml" "@@" "no placeholder left"
assert_not_contains "$OUT" "$SECRET_NEXUS" "no secret on the console"
OUT=$(HOME=$SETUP_HOME "$SCRIPTS_DIR/setup-env.sh" "release-start wiki not-a-number; touch $TMP/INJECTED" 2>&1); RC=$?
[ ! -e "$TMP/INJECTED" ] && t_ok "the command line is never evaluated by a shell" || t_ko "command injection"
OUT=$(HOME=$SETUP_HOME "$SCRIPTS_DIR/setup-env.sh" help 2>&1); RC=$?
assert_rc 0 $RC "default CMD (help)"

t_summary
