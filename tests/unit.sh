#!/bin/bash
# Unit tests of the bash libraries (no network, no maven, no git remote).
# Run: tests/unit.sh
# shellcheck disable=SC1090,SC2034 # sourced files are chosen at runtime; LOG_SECRETS/CATALOG_BASE_URL are read by the sourced code
set -uo pipefail
HERE=$(cd "${0%/*}" && pwd)
ROOT=$(cd "$HERE/.." && pwd)
source "$HERE/lib.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export WORKSPACE_DIR=$TMP/ws DATAS_DIR=$TMP/ws/datas LOGS_DIR=$TMP/ws/logs PRJ_DIR=$TMP/ws/prj
export LOCAL_STAGING_DIR=$TMP/ws/staging BACKUPS_DIR=$TMP/backup HOME=$TMP/home
mkdir -p "$DATAS_DIR" "$PRJ_DIR" "$LOCAL_STAGING_DIR" "$BACKUPS_DIR" "$HOME"
export EXOR_VERSION=9.9.9 exo_user=tester

S=$ROOT/app/scripts
source "$S/common.sh" >/dev/null 2>&1
for f in utils/credentials utils/files process/release-catalog process/release-status process/maven-dependencies notifications/tasks; do
  source "$S/$f.sh"
done
set +e # the tests inspect failures themselves

CATALOG='[{"name":"wiki","git_organization":"exoplatform","labels":"plf","maven_property_version":"org.exoplatform.wiki.version","release":{"branch":"develop","version":"1.0.0","current_snapshot_version":"1.0.x-SNAPSHOT","next_snapshot_version":"1.1.x-SNAPSHOT","nexus_host":"exoplatform","nexus_staging_profile":"public"}},{"name":"we\"ird","git_organization":"o","labels":"x","release":{"branch":"b","version":"2","next_snapshot_version":"3","nexus_host":"jboss","nexus_staging_profile":"private"}}]'
printf '%s' "$CATALOG" >"$DATAS_DIR/catalog.json"

# ---------------------------------------------------------------- logging
t_start "logging"
: >"$LOGS_DIR/infos.log"; : >"$LOGS_DIR/errors.log"
out=$(log_info "hello" 2>/dev/null)
assert_contains "$out" "[INFO ] hello" "info on stdout with level"
assert_file_contains "$LOGS_DIR/infos.log" "[INFO ] hello" "info stored in infos.log"
out=$(log_debug "hidden" 2>&1)
assert_eq "" "$out" "debug hidden by default"
out=$(LOG_LEVEL=DEBUG log_debug "shown" 2>&1)
assert_contains "$out" "[DEBUG] shown" "debug shown with LOG_LEVEL=DEBUG"
out=$(log_error "boom" 2>&1 >/dev/null)
assert_contains "$out" "[ERROR] boom" "error on stderr"
assert_file_contains "$LOGS_DIR/errors.log" "boom" "error stored in errors.log"
out=$(log_warn "careful" 2>&1 >/dev/null)
assert_contains "$out" "[WARN ] careful" "warn on stderr"
out=$(printf 'a\nb\n' | log_info)
assert_eq 2 "$(printf '%s\n' "$out" | wc -l)" "stdin lines logged one by one"
out=$(log "legacy" 2>/dev/null)
assert_contains "$out" "legacy" "legacy log() still works"

t_start "logging secrets"
LOG_SECRETS=()
log_register_secret "s3cr3t/pass&word"
log_register_secret "abc"          # too short: ignored
out=$(log_info "token is s3cr3t/pass&word ok" 2>&1)
assert_contains "$out" "token is ******** ok" "secret masked (regex/sed special characters)"
assert_file_not_contains "$LOGS_DIR/infos.log" "s3cr3t/pass&word" "secret absent from infos.log"
out=$(echo "mvn says s3cr3t/pass&word" | log_stream)
assert_not_contains "$out" "s3cr3t" "log_stream masks its output"
assert_file_not_contains "$LOGS_DIR/infos.log" "s3cr3t/pass&word" "log_stream masks the log file"
out=$(log_info "abc stays" 2>&1)
assert_contains "$out" "abc stays" "short value not masked"
LOG_SECRETS=()

# ---------------------------------------------------------------- helpers
t_start "exception_message"
assert_contains "$(exception_message 203)" "Maven" "maven code"
assert_contains "$(exception_message 300)" "Nexus" "nexus code"
assert_contains "$(exception_message 42)" "unexpected" "unknown code"

t_start "throw"
( throw 77 ); assert_rc 77 $? "throw exits with the code"

t_start "credentials"
assert_eq "p@ss w/rd" "$(decompress "$(printf '%s' 'p@ss w/rd' | openssl enc -base64)")" "decompress base64"
storeCredential key "va lue" "$TMP/cred"
assert_eq "va lue" "$(decompress "$(sed 's/^key=//' "$TMP/cred")")" "storeCredential roundtrip"

t_start "curl_quote / curl_auth_config"
assert_eq '"a\"b\\c"' "$(curl_quote 'a"b\c')" "quote and backslash escaped"
assert_eq 'user = "bob:pa\"ss"' "$(curl_auth_config bob 'pa"ss')" "curl config line"

t_start "nexus_staging_profile_id"
export NEXUS_STAGING_PROFILE_PUBLIC_ID=pub-1
assert_eq "pub-1" "$(nexus_staging_profile_id public)" "lower-case profile resolved"
out=$(nexus_staging_profile_id nope 2>&1); rc=$?
assert_rc 1 $rc "unknown profile fails"
assert_contains "$out" "NEXUS_STAGING_PROFILE_NOPE_ID" "message names the variable"

t_start "json_update"
printf '{"a":1}' >"$TMP/j.json"
json_update "$TMP/j.json" '.v=$v' --arg v 'x"y $(touch /tmp/pwned) \n'
assert_eq 'x"y $(touch /tmp/pwned) \n' "$(jq -r .v "$TMP/j.json")" "values are data, never code"
assert_eq 1 "$(jq .a "$TMP/j.json")" "other keys kept"
json_update "$TMP/j.json" 'bad filter(' >/dev/null 2>&1; assert_rc 1 $? "invalid filter fails"
assert_eq 1 "$(jq .a "$TMP/j.json")" "file untouched after a failure"
assert_eq "" "$(compgen -G "$TMP/j.json.*")" "no temporary file left"

# ---------------------------------------------------------------- catalog
t_start "getProjectByNameFromCatalog"
assert_eq "wiki:exoplatform:1.0.0:develop:1.1.x-SNAPSHOT:exoplatform:public" "$(getProjectByNameFromCatalog wiki)" "known project"
assert_eq "0" "$(getProjectByNameFromCatalog unknown)" "unknown project"
assert_eq "we\"ird:o:2:b:3:jboss:private" "$(getProjectByNameFromCatalog 'we"ird')" "name with a quote"

t_start "displayAvailableProjects"
out=$(displayAvailableProjects 2>&1)
assert_contains "$out" "* wiki - 1.0.0 - develop (plf)" "lists projects"

t_start "getUserAgent"
assert_eq "eXo Release Manager v9.9.9 (tester)" "$(getUserAgent)"

t_start "catalog_yaml_to_json"
if command -v yq >/dev/null 2>&1 || python3 -c 'import yaml' 2>/dev/null; then
  out=$(printf -- '- name: a\n  release:\n    version: "1.0"\n' | catalog_yaml_to_json | jq -c .)
  assert_eq '[{"name":"a","release":{"version":"1.0"}}]' "$out" "yaml converted to json"
else
  printf '  skip %s (no yq / PyYAML)\n' "$T_NAME"
fi

t_start "release_catalog_download_from_url"
CATALOG_BASE_URL=http://catalog.test
declare -A FAKE_FILES=()
function catalog_fetch { [ -n "${FAKE_FILES[${1##*/}]+x}" ] && printf '%s' "${FAKE_FILES[${1##*/}]}"; }
FAKE_FILES[11.json]=$CATALOG
rm -f "$DATAS_DIR/catalog.json"
release_catalog_download_from_url 11 >/dev/null 2>&1; rc=$?
assert_rc 0 $rc "json catalog downloaded"
assert_eq "wiki" "$(jq -r '.[0].name' "$DATAS_DIR/catalog.json")" "catalog.json written"
if command -v yq >/dev/null 2>&1 || python3 -c 'import yaml' 2>/dev/null; then
  FAKE_FILES[12.yaml]=$'- name: ywiki\n  git_organization: exoplatform\n  release:\n    version: "3.0"\n'
  release_catalog_download_from_url 12 >/dev/null 2>&1; rc=$?
  assert_rc 0 $rc "yaml catalog downloaded"
  assert_eq "ywiki" "$(jq -r '.[0].name' "$DATAS_DIR/catalog.json")" "yaml converted into catalog.json"
  assert_eq "3.0" "$(jq -r '.[0].release.version' "$DATAS_DIR/catalog.json")" "yaml strings stay strings"
  FAKE_FILES[13.yml]=$'- name: yml-wiki\n'
  release_catalog_download_from_url 13 >/dev/null 2>&1
  assert_eq "yml-wiki" "$(jq -r '.[0].name' "$DATAS_DIR/catalog.json")" ".yml extension accepted"
  FAKE_FILES[14.json]='[{"name":"from-json"}]'; FAKE_FILES[14.yaml]='- name: from-yaml'
  release_catalog_download_from_url 14 >/dev/null 2>&1
  assert_eq "from-json" "$(jq -r '.[0].name' "$DATAS_DIR/catalog.json")" "json wins over yaml"
fi
release_catalog_download_from_url 99 >/dev/null 2>&1; assert_rc 1 $? "missing catalog fails"
FAKE_FILES[15.json]='{"not":"a list"}'
release_catalog_download_from_url 15 >/dev/null 2>&1; assert_rc 1 $? "non-list catalog refused"
FAKE_FILES[16.json]='not json'
release_catalog_download_from_url 16 >/dev/null 2>&1; assert_rc 0 $((! $?)) "invalid json refused"
FAKE_FILES[continuous-release-template.json]='[{"name":"w","release":{"version":"7.3.0-${release-version}"}}]'
release_catalog_download_from_url continuous-release-template 20221020 >/dev/null 2>&1
assert_eq "7.3.0-20221020" "$(jq -r '.[0].release.version' "$DATAS_DIR/catalog.json")" "continuous template suffix substituted"

# ---------------------------------------------------------------- release status
t_start "release_status"
cp "$ROOT/app/conf/release.json" "$WORKSPACE_DIR/release.json"
release_status_init 123 wiki >/dev/null 2>&1
assert_eq wiki "$(release_status_get_project_id)" "project id"
assert_eq 123 "$(release_status_get_issue_id)" "issue id"
assert_eq "success" "$(jq -r .step.status "$WORKSPACE_DIR/release.json")" "init step done"
release_status_staging_repo_created 'repo-"1"'
assert_eq 'repo-"1"' "$(release_status_get_repo_id)" "repo id kept verbatim"
release_status_write_step "$MAVEN_RELEASE_PREPARE" "$STATUS_IN_PROGRESS"
assert_eq "$MAVEN_RELEASE_PREPARE" "$(jq -r .step.name "$WORKSPACE_DIR/release.json")" "step name"
release_status_update_step_status "$STATUS_ERROR"
assert_eq "error" "$(jq -r .step.status "$WORKSPACE_DIR/release.json")" "step status updated"

# ---------------------------------------------------------------- maven dependencies / sed
t_start "sed escapes"
assert_eq '\[a\.b\*\]\/' "$(sed_escape_regex '[a.b*]/')" "regex escaped"
assert_eq 'a\&b\/c' "$(sed_escape_replacement 'a&b/c')" "replacement escaped"

t_start "utils_update_pom"
mkdir -p "$TMP/p/sub"
printf '<a>\n<org.x.version>1.0.x-SNAPSHOT</org.x.version>\n<orgxxversion>1.0.x-SNAPSHOT</orgxxversion>\n</a>\n' >"$TMP/p/pom.xml"
cp "$TMP/p/pom.xml" "$TMP/p/sub/pom.xml"
printf '<org.x.version>1.0.x-SNAPSHOT</org.x.version>\n' >"$TMP/p/other.xml"
utils_update_pom '<org.x.version>1.0.x-SNAPSHOT</org.x.version>' '<org.x.version>1.0.0</org.x.version>' "$TMP/p"
assert_file_contains "$TMP/p/pom.xml" '<org.x.version>1.0.0</org.x.version>' "root pom updated"
assert_file_contains "$TMP/p/sub/pom.xml" '<org.x.version>1.0.0</org.x.version>' "module pom updated"
assert_file_contains "$TMP/p/pom.xml" '<orgxxversion>1.0.x-SNAPSHOT</orgxxversion>' "regex dots are literal"
assert_file_contains "$TMP/p/other.xml" '1.0.x-SNAPSHOT' "non-pom files untouched"
utils_update_pom 'a/b' 'c&d' "$TMP/p"; assert_rc 0 $? "no match is not an error"

# ---------------------------------------------------------------- files
t_start "replaceInFile"
printf 'k=@@PWD@@\nagain=@@PWD@@\n' >"$TMP/conf"
replaceInFile "$TMP/conf" @@PWD@@ 'a&b/c\d "q" $x'
assert_eq 'k=a&b/c\d "q" $x' "$(sed -n 1p "$TMP/conf")" "special characters kept verbatim"
assert_eq 'again=a&b/c\d "q" $x' "$(sed -n 2p "$TMP/conf")" "all occurrences replaced"

t_start "installFile"
printf 'one' >"$TMP/src"; installFile "$TMP/src" "$TMP/dst/f" >/dev/null 2>&1
printf 'two' >"$TMP/src"; installFile "$TMP/src" "$TMP/dst/f" >/dev/null 2>&1
assert_eq two "$(cat "$TMP/dst/f")" "file installed"
assert_eq 1 "$(ls "$BACKUPS_DIR" | wc -l)" "previous file backed up"
assert_eq 700 "$(stat -c %a "$TMP/dst/f")" "restrictive permissions"

# ---------------------------------------------------------------- tribe comments
t_start "task comments"
assert_eq "&lt;b&gt; &amp; &quot;" "$(task_html_escape '<b> & "')" "html escaped"
card=$(task_build_comment "wiki:exoplatform:1.0.0:develop:1.1.x-SNAPSHOT:exoplatform:public" wiki release_prepare_OK)
assert_contains "$card" "Release prepared" "title"
assert_contains "$card" "1.0.0" "version"
assert_contains "$card" "Nexus profile: public" "profile"
card=$(task_build_comment 0 ghost ERROR_release_start_203)
assert_contains "$card" "Maven build error" "error reason"
assert_contains "$card" "ghost" "unknown project keeps its name"

t_summary
