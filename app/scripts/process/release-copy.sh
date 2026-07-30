#!/bin/bash -eu
set -o pipefail

##
# Copy released Maven artifacts from one version to another.
# Downloads artifacts via Maven, re-versions them, re-signs with GPG,
# stages locally, and deploys to a new Nexus staging repo.
#
# Usage: eXoR release-copy PROJECT TASK_ID
# Expects catalog entry with 'copy.src_version'; target is release.version
##

function release_copy_get_coordinates {
  local projectName=$1
  local pomFile="${PRJ_DIR}/${projectName}/pom.xml"

  if [ ! -f "$pomFile" ]; then
    error "POM file not found: $pomFile"
    return 1
  fi

  local afterParent
  if grep -q '</parent>' "$pomFile"; then
    afterParent=$(sed -n '/<\/parent>/,$p' "$pomFile")
  else
    afterParent=$(cat "$pomFile")
  fi
  local artifactId=$(echo "$afterParent" | grep -m1 '<artifactId>' | head -1 | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | xargs)
  local groupId=$(echo "$afterParent" | grep -m1 '<groupId>' | head -1 | sed 's/.*<groupId>\(.*\)<\/groupId>.*/\1/' | xargs)

  if [ -z "$groupId" ]; then
    groupId=$(grep -A 10 '<parent>' "$pomFile" | grep -m1 '<groupId>' | head -1 | sed 's/.*<groupId>\(.*\)<\/groupId>.*/\1/' | xargs)
  fi

  echo "${groupId}:${artifactId}"
}

function release_copy_process_artifact {
  local groupId=$1
  local artifactId=$2
  local nexusHost=$3

  rm -rf "$downloadDir"/* "$reversionDir"/*

  release_copy_download $nexusHost $groupId $artifactId $srcVersion $downloadDir || return 1
  release_copy_reversion $srcVersion $targetVersion $downloadDir $reversionDir || return 1
  release_copy_sign $reversionDir || return 1
  release_copy_stage $groupId $artifactId $targetVersion $reversionDir || return 1
  return 0
}

function release_copy_get_modules {
  local projectName=$1
  local pomFile="${PRJ_DIR}/${projectName}/pom.xml"

  local modules=$(grep '<module>' "$pomFile" | sed 's/.*<module>\(.*\)<\/module>.*/\1/' | xargs)

  if [ -n "$modules" ]; then
    echo "$modules"
  fi
}

function release_copy_download {
  local nexusHost=$1
  local groupId=$2
  local artifactId=$3
  local version=$4
  local outputDir=$5

  local groupPath=$(echo "$groupId" | tr '.' '/')
  local m2Dir="${HOME}/.m2/repository/${groupPath}/${artifactId}/${version}"

  log "Resolving artifacts via Maven for ${groupId}:${artifactId}:${version}..."

  # Purge any stale negative cache entries for this artifact
  rm -rf "$m2Dir"

  # Download POM (required)
  mvn -B -U org.apache.maven.plugins:maven-dependency-plugin:get \
    -Dartifact=${groupId}:${artifactId}:${version}:pom \
    -Dtransitive=false >> ${LOGS_DIR}/infos.log 2>&1
  if [ "$?" -ne "0" ]; then
    error "[ERROR] Failed to resolve POM for ${groupId}:${artifactId}:${version}"
    return 1
  fi

  # Determine packaging type from downloaded POM in m2 cache
  local packaging=$(grep '<packaging>' "$m2Dir"/*.pom 2>/dev/null | head -1 | sed 's/.*<packaging>\(.*\)<\/packaging>.*/\1/' | xargs)
  packaging=${packaging:-jar}

  if [ "$packaging" != "pom" ]; then
    # Download main artifact with correct packaging type (jar, war, ear, bundle, etc.)
    mvn -B -U org.apache.maven.plugins:maven-dependency-plugin:get \
      -Dartifact=${groupId}:${artifactId}:${version}:${packaging} \
      -Dtransitive=false >> ${LOGS_DIR}/infos.log 2>&1 || true
  else
    # POM packaging may have attached zip artifacts (assembly plugin)
    mvn -B -U org.apache.maven.plugins:maven-dependency-plugin:get \
      -Dartifact=${groupId}:${artifactId}:${version}:zip \
      -Dtransitive=false >> ${LOGS_DIR}/infos.log 2>&1 || true
  fi

  # Try optional classifiers (sources, javadoc always use jar packaging)
  for classifier in sources javadoc tests; do
    mvn -B -U org.apache.maven.plugins:maven-dependency-plugin:get \
      -Dartifact=${groupId}:${artifactId}:${version}:jar:${classifier} \
      -Dtransitive=false >> ${LOGS_DIR}/infos.log 2>&1 || true
  done

  if [ ! -d "$m2Dir" ]; then
    error "[ERROR] No artifacts found in ${m2Dir}"
    return 1
  fi

  cp "$m2Dir"/* "$outputDir"/ 2>/dev/null || true
  rm -f "$outputDir"/*.lastUpdated "$outputDir"/_remote.repositories "$outputDir"/resolver-status.properties
  local count=$(find "$outputDir" -type f ! -name '*.lastUpdated' ! -name '_remote.repositories' ! -name 'resolver-status.properties' | wc -l)
  log "Downloaded ${count} files for ${groupId}:${artifactId}:${version} (packaging=${packaging})"

  # Verify main artifact exists for non-POM packaging
  if [ "$packaging" != "pom" ]; then
    local mainFile="${outputDir}/${artifactId}-${version}.${packaging}"
    if [ ! -f "$mainFile" ]; then
      error "[ERROR] Missing ${packaging} artifact for ${groupId}:${artifactId}:${version}"
      return 1
    fi
  fi
  return 0
}

function release_copy_reversion {
  local srcVersion=$1
  local targetVersion=$2
  local inputDir=$3
  local outputDir=$4

  for file in "$inputDir"/*; do
    [ -f "$file" ] || continue
    local filename=$(basename "$file")
    local newFilename="${filename//${srcVersion}/${targetVersion}}"
    local outFile="${outputDir}/${newFilename}"

    if [[ "$filename" == *.pom ]] && [[ "$filename" != *.pom.* ]]; then
      sed "s/${srcVersion}/${targetVersion}/g" "$file" > "$outFile"
      log "  Re-versioned POM: ${filename} -> ${newFilename}"
    elif [[ "$filename" == *.jar ]] || [[ "$filename" == *.war ]] || [[ "$filename" == *.ear ]] || [[ "$filename" == *.zip ]]; then
      cp "$file" "$outFile"
      local tmpd=$(mktemp -d)
      mkdir -p "$tmpd/META-INF"
      echo "${targetVersion}" > "$tmpd/META-INF/release-copy-version"
      jar uf "$outFile" -C "$tmpd" META-INF/release-copy-version 2>/dev/null
      rm -rf "$tmpd"
      log "  Re-versioned binary: ${filename} -> ${newFilename}"
    else
      cp "$file" "$outFile"
      log "  Copied: ${filename} -> ${newFilename}"
    fi
  done
}

function release_copy_sign {
  local dir=$1

  for file in "$dir"/*.jar "$dir"/*.war "$dir"/*.ear "$dir"/*.zip "$dir"/*.pom; do
    [ -f "$file" ] || continue
    local filename=$(basename "$file")
    [[ "$filename" == *.asc ]] && continue
    [[ "$filename" == *.sha1 ]] && continue
    [[ "$filename" == *.md5 ]] && continue

    gpg --batch --yes --passphrase "$(decompress $gpg_passphrase)" -ab "$file" 2>&1 | tee -a ${LOGS_DIR}/infos.log
    log "  Signed: ${filename}"
  done
}

function release_copy_stage {
  local groupId=$1
  local artifactId=$2
  local version=$3
  local srcDir=$4

  local groupPath=$(echo "$groupId" | tr '.' '/')
  local targetDir="${LOCAL_STAGING_DIR}/${groupPath}/${artifactId}/${version}"

  rm -rf "$targetDir"
  mkdir -p "$targetDir"

  for file in "$srcDir"/*; do
    [ -f "$file" ] || continue
    mv "$file" "$targetDir"/
  done

  # Generate SHA1 and MD5 checksums
  for file in "$targetDir"/*; do
    [ -f "$file" ] || continue
    local filename=$(basename "$file")
    [[ "$filename" == *.sha1 ]] && continue
    [[ "$filename" == *.md5 ]] && continue
    [[ "$filename" == *.asc ]] && continue

    sha1sum "$file" | awk '{print $1}' > "${file}.sha1"
    md5sum "$file" | awk '{print $1}' > "${file}.md5"
  done

  log "Staged artifacts in: ${targetDir}"
  ls -la "$targetDir" | tee -a ${LOGS_DIR}/infos.log
}

function release_copy_get_versions {
  local projectName=$1

  local srcVer=$(jq -r --arg name "$projectName" \
    '.[] | select(.name == $name) | .copy.src_version // empty' ${DATAS_DIR}/catalog.json 2>/dev/null)

  if [ -z "$srcVer" ]; then
    error "Missing copy.src_version in catalog for project '${projectName}'"
    return 1
  fi

  echo "${srcVer}"
}

function release_copy_tag {
  local projectName=$1
  local gitOrganization=$2
  local targetVersion=$3
  local issueId=$4
  local srcVersion=$5

  # Update POMs: replace source version with target version
  log "Updating POM files: ${srcVersion} -> ${targetVersion}..."
  find ${PRJ_DIR}/${projectName} -name pom.xml -exec sed -i "s/${srcVersion}/${targetVersion}/g" {} \;

  # Check if there are changes to commit
  if [ -z "$(cd ${PRJ_DIR}/${projectName} && git status --porcelain 2>&1)" ]; then
    log "No POM changes to commit."
  else
    gitCommand $projectName add -A
    local commitMsg="[exo-release]($exo_user) $issueId: copy ${srcVersion} -> ${targetVersion}"
    gitCommand $projectName commit -m "$commitMsg"
    log "Committed POM version updates."
  fi

  local tagMsg="[exo-release]($exo_user) $issueId: copy ${srcVersion} -> ${targetVersion}"
  gitCommand $projectName tag -a -s "$targetVersion" -m "$tagMsg"
  log "Created local signed tag: ${targetVersion}"
}

function release_copy_generate_metadata {
  local groupId=$1
  local artifactId=$2
  local version=$3

  local groupPath=$(echo "$groupId" | tr '.' '/')
  local artifactDir="${LOCAL_STAGING_DIR}/${groupPath}/${artifactId}"
  local versionDir="${artifactDir}/${version}"
  local now=$(date -u +%Y%m%d%H%M%S)

  # Artifact-level metadata
  if [ -f "${versionDir}/${artifactId}-${version}.pom" ]; then
    cat > "${artifactDir}/maven-metadata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>${groupId}</groupId>
  <artifactId>${artifactId}</artifactId>
  <versioning>
    <release>${version}</release>
    <versions>
      <version>${version}</version>
    </versions>
    <lastUpdated>${now}</lastUpdated>
  </versioning>
</metadata>
EOF
    sha1sum "${artifactDir}/maven-metadata.xml" | awk '{print $1}' > "${artifactDir}/maven-metadata.xml.sha1"
    md5sum "${artifactDir}/maven-metadata.xml" | awk '{print $1}' > "${artifactDir}/maven-metadata.xml.md5"
    log "Generated metadata for: ${groupId}:${artifactId}"
  fi
}

function exor_release_copy {
  local projectName=$2
  local issueId=$3

  if [[ ! "${issueId}" =~ ^([0-9]+|continuous-release-template(-[a-z]+)?)$ ]]; then
    error "Invalid TASK_ID parameter: ${issueId}!"
    throw $exReleasePrerequisiteKO
  fi

  log "Download catalog.json for release..."
  release_catalog_download_from_url $issueId

  try
  (
    local project=$(getProjectByNameFromCatalog $projectName)
    if [ "$project" == "0" ]; then
      error "Project not found in catalog!"
      throw $exReleasePrerequisiteKO
    fi

    IFS=':' read -r -a params <<< "$project"
    local gitOrganization=${params[1]}
    local catalogVersion=${params[2]}
    local releaseBranch=${params[3]}
    local nexus_host=${params[5]}
    local nexus_profile=${params[6]}

    local srcVersion=$(release_copy_get_versions $projectName)
    if [ "$?" -ne "0" ]; then
      throw $exReleasePrerequisiteKO
    fi
    local targetVersion=$catalogVersion

    printHeader "Copy Release: ${projectName} ${srcVersion} -> ${targetVersion}"

    log "Project: ${projectName} (catalog version: ${catalogVersion})"
    log "Nexus: host=${nexus_host}, profile=${nexus_profile}"
    log "Source version: ${srcVersion}"
    log "Target version: ${targetVersion}"

    # Check prerequisites
    exor_release_check_prerequisites $projectName $gitOrganization $targetVersion || throw $exReleasePrerequisite

    # Init release status
    release_status_init $issueId $projectName

    # Clone project to extract Maven coordinates from POM
    log "Clone project to extract Maven coordinates..."
    git_clone_single $projectName || throw $exReleasePrerequisite

    # Create release branch (needed for validate to push tag later)
    git_release_create_branch $projectName $targetVersion

    # Update cross-project Maven dependency versions
    maven_dependencies_update_before_release $projectName $issueId

    # Update POMs and create local signed git tag for the target version
    release_copy_tag $projectName $gitOrganization $targetVersion $issueId $srcVersion || throw $exReleasePrerequisite
    task_add_comment $projectName "release_prepare_OK" $issueId

    local coordinates=$(release_copy_get_coordinates $projectName)
    IFS=':' read -r parentGroupId parentArtifactId <<< "$coordinates"
    log "Maven GAV (parent): ${parentGroupId}:${parentArtifactId}"

    if [ -z "$parentGroupId" ] || [ -z "$parentArtifactId" ]; then
      error "Failed to extract Maven coordinates from POM"
      throw $exReleasePrerequisiteKO
    fi

    local downloadDir=$(mktemp -d ${WORKSPACE_DIR}/release-copy-dl-XXXXXX)
    local reversionDir=$(mktemp -d ${WORKSPACE_DIR}/release-copy-rev-XXXXXX)
    trap "rm -rf $downloadDir $reversionDir" EXIT

    # Clear local staging
    rm -rf ${LOCAL_STAGING_DIR}/*

    # Download and stage parent POM
    release_copy_process_artifact $parentGroupId $parentArtifactId $nexus_host || throw $exNexusStaging
    release_copy_generate_metadata $parentGroupId $parentArtifactId $targetVersion

    # Download and stage submodule artifacts
    local modules=$(release_copy_get_modules $projectName)
    if [ -n "$modules" ]; then
      log "Found submodules, processing each..."
      for module in $modules; do
        local modulePom="${PRJ_DIR}/${projectName}/${module}/pom.xml"
        if [ -f "$modulePom" ]; then
          local afterParent
          if grep -q '</parent>' "$modulePom"; then
            afterParent=$(sed -n '/<\/parent>/,$p' "$modulePom")
          else
            afterParent=$(cat "$modulePom")
          fi
          local moduleArtifactId=$(echo "$afterParent" | grep -m1 '<artifactId>' | head -1 | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | xargs)
          log "Module: ${module} (artifactId: ${moduleArtifactId})"
          release_copy_process_artifact $parentGroupId $moduleArtifactId $nexus_host || throw $exNexusStaging
          release_copy_generate_metadata $parentGroupId $moduleArtifactId $targetVersion
        else
          log "Module POM not found, skipping: ${module}"
        fi
      done
    fi
    task_add_comment $projectName "release_perform_OK" $issueId

    # Create Nexus Staging Repository
    local description="$issueId:$projectName:$targetVersion"
    nexus_create_staging_repo $description $nexus_host $nexus_profile || throw $exNexusStaging
    task_add_comment $projectName "nexus_staging_repo_created_OK" $issueId

    # Deploy artifacts to staging repo
    nexus_deploy_staged_repo $(release_status_get_repo_id) $nexus_host $nexus_profile || throw $exNexusStaging
    task_add_comment $projectName "nexus_deploy_to_stage_repo_OK" $issueId

    # Close Nexus Staging Repository (requires manual validate to release)
    nexus_close_staging_repo $projectName $(release_status_get_repo_id) $nexus_host $nexus_profile $description false || throw $exNexusStaging
    task_add_comment $projectName "nexus_staging_repo_closed_OK" $issueId

    printFooter "Copy Release: ${projectName} ${srcVersion} -> ${targetVersion}"
  )
  catch || {
    error "[ERROR] Release copy failed."
    release_status_update_step_status $STATUS_ERROR
    local msg="ERROR_release_copy_$ex_code"
    task_add_comment $projectName "$msg" $issueId

    case $ex_code in
      $exReleasePrerequisiteKO)
        error "[$ex_code] Release prerequisite check failed."
        ;;
      $exNexusStaging)
        error "[$ex_code] Nexus staging operation failed."
        ;;
      *)
        error "[$ex_code] An unexpected exception was thrown"
        ;;
    esac
    throw $ex_code
  }
}
