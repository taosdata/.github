#!/bin/bash
set -e

# Default values
ORGANIZATION=${ORGANIZATION:-"taosdata"}
GROUP_ID=${GROUP_ID:-"com.taosdata.tdasset"}
GROUP_PATH=${GROUP_ID//\.//}
VERSION=${VERSION:-"latest"}
EXTRACT=${EXTRACT:-"false"}
EXTRACT_DIR=${EXTRACT_DIR:-"$(pwd)"}
BACKUP=${BACKUP:-"false"}
BACKUP_DIR=${BACKUP_DIR:-""}
REPO_NAME=${REPO_NAME:-"tdasset"}
GITHUB_TOKEN=""

# Show help function
show_help() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  --type TYPE          Package type (npm or maven), required"
  echo "  --name NAME          Package name, required"
  echo "  --token TOKEN        GitHub token for authentication, required"
  echo "  --group-id ID        Group ID for maven packages (default: com.taosdata.tdasset)"
  echo "  --version VER        Package version (default: latest)"
  echo "  --repo-name NAME     Repository name for maven packages (default: tdasset)"
  echo "  --extract            Extract package after download"
  echo "  --extract-path PATH  Path to extract package to (default: current directory)"
  echo "  --backup             Backup downloaded package"
  echo "  --backup-dir DIR     Directory to store backup"
  echo "  --help               Show this help message"
  echo ""
  echo "Example:"
  echo "  $0 --type npm --name tdasset-frontend --token ghp_xxxx --extract --extract-path ./dist"
  echo "  $0 --type maven --name tdasset-backend --token ghp_xxxx --group-id com.taosdata.tdasset --repo-name backend-repo --version 0.9.0"
  exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --type)
      PACKAGE_TYPE="$2"
      shift 2
      ;;
    --name)
      PACKAGE_NAME="$2"
      shift 2
      ;;
    --token)
      GITHUB_TOKEN="$2"
      shift 2
      ;;
    --group-id)
      GROUP_ID="$2"
      GROUP_PATH=${GROUP_ID//\.//}
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --repo-name)
      REPO_NAME="$2"
      shift 2
      ;;
    --extract)
      EXTRACT="true"
      shift
      ;;
    --extract-path)
      EXTRACT_DIR="$2"
      shift 2
      ;;
    --backup)
      BACKUP="true"
      shift
      ;;
    --backup-dir)
      BACKUP_DIR="$2"
      shift 2
      ;;
    --help)
      show_help
      ;;
    *)
      echo "Unknown option: $1"
      show_help
      ;;
  esac
done

# Validate required parameters
if [ -z "$PACKAGE_TYPE" ] || [ -z "$PACKAGE_NAME" ]; then
  echo "Error: Package type and name are required"
  show_help
fi

if [ -z "$GITHUB_TOKEN" ]; then
  echo "Error: GitHub token is required for authentication"
  show_help
fi

# Validate package type
if [ "$PACKAGE_TYPE" != "npm" ] && [ "$PACKAGE_TYPE" != "maven" ]; then
  echo "Error: Package type must be 'npm' or 'maven'"
  show_help
fi

# Download npm package (frontend)
download_npm_package() {
  local PACKAGE_NAME="$1"
  local VERSION="$2"
  local EXTRACT="$3"
  local EXTRACT_DIR="$4"
  local TOKEN="$5"
  
  echo "Downloading npm package: ${PACKAGE_NAME}"
  
  # Create temporary directory
  local WORK_DIR=$(mktemp -d)
  cd "${WORK_DIR}"
  
  # Setup npm authentication
  echo "//npm.pkg.github.com/:_authToken=${TOKEN}" > .npmrc
  echo "@${ORGANIZATION}:registry=https://npm.pkg.github.com" >> .npmrc
  
  # Get version information
  local PACKAGE_INFO=""
  local PACKAGE_VERSION=""
  local DIST_TARBALL=""
  
  if [ "${VERSION}" == "latest" ]; then
    echo "Getting latest npm package version..."
    PACKAGE_INFO=$(npm view "@${ORGANIZATION}/${PACKAGE_NAME}" --json)
    PACKAGE_VERSION=$(echo "${PACKAGE_INFO}" | jq -r '.version')
    DIST_TARBALL=$(echo "${PACKAGE_INFO}" | jq -r '.dist.tarball')
  else
    echo "Looking for specified version: ${VERSION}"
    PACKAGE_INFO=$(npm view "@${ORGANIZATION}/${PACKAGE_NAME}@${VERSION}" --json 2>/dev/null)
    NPM_RESULT=$?
    
    if [[ $NPM_RESULT -eq 0 && -n "${PACKAGE_INFO}" ]]; then
      PACKAGE_VERSION=$(echo "${PACKAGE_INFO}" | jq -r '.version')
      DIST_TARBALL=$(echo "${PACKAGE_INFO}" | jq -r '.dist.tarball')
    else
      echo "Error: Specified version ${VERSION} not found!"
      exit 1
    fi
  fi
  
  echo "Package version: ${PACKAGE_VERSION}"
  echo "Tarball URL: ${DIST_TARBALL}"
  
  # Set output (if GITHUB_OUTPUT is defined)
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "${PACKAGE_NAME//-/_}_version=${PACKAGE_VERSION}" >> $GITHUB_OUTPUT
  fi

  # Download package
  local OUTPUT_FILE="${PACKAGE_NAME}-${PACKAGE_VERSION}.tar.gz"
  
  echo "Downloading to file: ${OUTPUT_FILE}"
  curl -L -H "Authorization: token ${TOKEN}" "${DIST_TARBALL}" -o "${OUTPUT_FILE}"
  
  # Backup package
  if [ "${BACKUP}" == "true" ] && [ -n "${BACKUP_DIR}" ]; then
    echo "Backing up package to ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    cp "${OUTPUT_FILE}" "${BACKUP_DIR}/${OUTPUT_FILE}"
  fi
  
  # Extract package
  if [ "${EXTRACT}" == "true" ]; then
    echo "Extracting package to ${EXTRACT_DIR}"
    mkdir -p "${EXTRACT_DIR}"
    tar -xzf "${OUTPUT_FILE}" -C "${EXTRACT_DIR}" --strip-components=1
  fi
  
  # Cleanup
  rm -f "${OUTPUT_FILE}"
  rm -f .npmrc
  cd - > /dev/null
  rm -rf "${WORK_DIR}"
  
  echo "npm package downloaded successfully"
}

# Download maven package (backend, standalone, lib)
download_maven_package() {
  local ARTIFACT_ID="$1"
  local VERSION="$2"
  local EXTRACT="$3"
  local EXTRACT_DIR="$4"
  local TOKEN="$5"
  local REPO="$6"
  
  echo "Downloading maven package: ${GROUP_ID}.${ARTIFACT_ID} from ${REPO} repository"
  
  # Create temporary directory
  local WORK_DIR=$(mktemp -d)
  cd "${WORK_DIR}"
  
  # Handle version
  local DOWNLOAD_VERSION="${VERSION}"
  local OUTPUT_FILE=""
  
  # If version is latest, get the latest version
  if [ "${VERSION}" == "latest" ]; then
    echo "Getting latest maven package version..."
    
    # Get all versions from GitHub API
    VERSIONS_JSON=$(curl -s -L \
      -H "Accept: application/vnd.github+json" \
      -H "Authorization: Bearer ${TOKEN}" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com/orgs/${ORGANIZATION}/packages/maven/${GROUP_ID}.${ARTIFACT_ID}/versions")
    
    # Extract latest version
    LATEST_VERSION_INFO=$(echo "${VERSIONS_JSON}" | jq -r 'sort_by(.created_at) | .[-1]')
    DOWNLOAD_VERSION=$(echo "${LATEST_VERSION_INFO}" | jq -r '.name')
    echo "Latest version: ${DOWNLOAD_VERSION}"
  fi
 
  # Special handling for SNAPSHOT versions
  if [[ "${DOWNLOAD_VERSION}" == *"SNAPSHOT"* ]]; then
    echo "Handling SNAPSHOT version: ${DOWNLOAD_VERSION}"
    
    # Extract base SNAPSHOT version
    if [[ "${DOWNLOAD_VERSION}" == *"-SNAPSHOT-"* ]]; then
      local BASE_SNAPSHOT_VERSION=$(echo "${DOWNLOAD_VERSION}" | sed 's/\(.*-SNAPSHOT\).*/\1/')
      echo "Extracted base SNAPSHOT version: ${BASE_SNAPSHOT_VERSION} from ${DOWNLOAD_VERSION}"
      DOWNLOAD_VERSION="${BASE_SNAPSHOT_VERSION}"
    fi
    
    # Get metadata for SNAPSHOT version
    local META_URL="https://maven.pkg.github.com/${ORGANIZATION}/${REPO}/${GROUP_PATH}/${ARTIFACT_ID}/${DOWNLOAD_VERSION}/maven-metadata.xml"
    echo "Fetching metadata from: ${META_URL}"
    
    local META_FILE=$(mktemp)
    local HTTP_CODE=$(curl -s -L -o "${META_FILE}" -w "%{http_code}" \
      -H "Authorization: token ${TOKEN}" \
      -H "Accept: application/octet-stream" \
      "${META_URL}")
    
    # Check if metadata download was successful
    if [[ "${HTTP_CODE}" != "200" ]]; then
      echo "Failed to download metadata: HTTP ${HTTP_CODE}"
      cat "${META_FILE}"
      rm -f "${META_FILE}"
      exit 1
    fi
    
    # Extract timestamp and build number
    local TIMESTAMP=$(grep -oP '<timestamp>\K[^<]+' "${META_FILE}")
    local BUILD_NUMBER=$(grep -oP '<buildNumber>\K[^<]+' "${META_FILE}")
    
    if [[ -n "${TIMESTAMP}" && -n "${BUILD_NUMBER}" ]]; then
      local VERSION_BASE=${DOWNLOAD_VERSION%-SNAPSHOT}
      local SNAPSHOT_VERSION="${VERSION_BASE}-${TIMESTAMP}-${BUILD_NUMBER}"
      echo "Latest SNAPSHOT build: ${SNAPSHOT_VERSION}"
      
      # Set download path and output file
      DOWNLOAD_PATH="${GROUP_PATH}/${ARTIFACT_ID}/${DOWNLOAD_VERSION}/${ARTIFACT_ID}-${SNAPSHOT_VERSION}.tar.gz"
      OUTPUT_FILE="${ARTIFACT_ID}-${SNAPSHOT_VERSION}.tar.gz"
    else
      echo "Failed to parse timestamp or build number from metadata"
      cat "${META_FILE}"
      rm -f "${META_FILE}"
      exit 1
    fi
    
    rm -f "${META_FILE}"
  else
    # Standard version
    DOWNLOAD_PATH="${GROUP_PATH}/${ARTIFACT_ID}/${DOWNLOAD_VERSION}/${ARTIFACT_ID}-${DOWNLOAD_VERSION}.tar.gz"
    OUTPUT_FILE="${ARTIFACT_ID}-${DOWNLOAD_VERSION}.tar.gz"
  fi
  
  # Set output
  if [ -n "${GITHUB_OUTPUT}" ]; then
    echo "${ARTIFACT_ID//-/_}_version=${DOWNLOAD_VERSION}" >> $GITHUB_OUTPUT
  fi
  
  # Download URL
  local DOWNLOAD_URL="https://maven.pkg.github.com/${ORGANIZATION}/${REPO}/${DOWNLOAD_PATH}"
  echo "Download URL: ${DOWNLOAD_URL}"
  echo "Output file: ${OUTPUT_FILE}"
  
  # Download package
  wget --header="Authorization: token ${TOKEN}" \
    --header="Accept: application/octet-stream" \
    --output-document="${OUTPUT_FILE}" \
    "${DOWNLOAD_URL}"
  
  # Backup package
  if [ "${BACKUP}" == "true" ] && [ -n "${BACKUP_DIR}" ]; then
    echo "Backing up ${ARTIFACT_ID} package to ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"
    cp -- "${OUTPUT_FILE}" "${BACKUP_DIR}/${OUTPUT_FILE}"
  fi
  
  # Extract package
  if [ "${EXTRACT}" == "true" ]; then
    echo "Extracting package to ${EXTRACT_DIR}..."
    mkdir -p "${EXTRACT_DIR}"
    tar -xzf "${OUTPUT_FILE}" -C "${EXTRACT_DIR}" --strip-components=1
  fi
  
  # Cleanup
  rm -f "${OUTPUT_FILE}"
  cd - > /dev/null
  rm -rf "${WORK_DIR}"
  
  echo "Maven package downloaded successfully"
}

# Main function to download a specified package
main() {
  echo "::group::Downloading package ${PACKAGE_NAME} (${PACKAGE_TYPE})"
  
  case "${PACKAGE_TYPE}" in
    "npm")
      download_npm_package "${PACKAGE_NAME}" "${VERSION}" "${EXTRACT}" "${EXTRACT_DIR}" "${GITHUB_TOKEN}"
      ;;
    "maven")
      download_maven_package "${PACKAGE_NAME}" "${VERSION}" "${EXTRACT}" "${EXTRACT_DIR}" "${GITHUB_TOKEN}" "${REPO_NAME}"
      ;;
  esac
  
  echo "Package ${PACKAGE_NAME} processed successfully"
  echo "::endgroup::"
}

# Run the main function
main
