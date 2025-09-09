#!/bin/bash
WORK_DIR=/opt

# Function to check if version is >= 3.3.7.0
function version_ge_3370() {
    local version="$1"
    local version_num=$(echo "$version" | sed 's/\.//g' | sed 's/$/0000/' | cut -c1-4)
    [ "$version_num" -ge 3370 ]
}

# Function to display help
function display_help() {
    echo "Usage: $0 <version> <download_url>"
    echo
    echo "Parameters:"
    echo "  version      The version number, e.g., 3.3.5.1"
    echo "  download_url The URL for downloading TDengine. It must contain either 'nas' or 'assets-down'."
    echo "  clean        Optional. Set to 'true' to remove existing TDengine installation and data before installing (default: false)"
    echo
    echo "Example:"
    echo "  $0 3.3.5.1 https://example.com/nas"
    echo "  $0 3.3.5.1 https://example.com/nas true"
    exit 1
}

# Function to validate input parameters
function validate_parameters() {
    if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
        echo "::error ::Invalid number of parameters."
        display_help
    fi
}

# Function to remove existing TDengine installation and data
function remove_existing_tdengine() {
    echo "Checking if TDengine is installed..."

    TAOSD_INSTALLED=false
    
    if command -v taosd &> /dev/null || \
       [ -f "/usr/local/taos/bin/taosd" ] || \
       [ -f "/usr/bin/taosd" ] || \
       [ -f "/etc/systemd/system/taosd.service" ] || \
       [ -d "/usr/local/taos" ]; then
        TAOSD_INSTALLED=true
    fi
    
    if [ "$TAOSD_INSTALLED" = false ]; then
        echo "TDengine is not installed, skipping removal."
        return 0
    fi
    
    echo "TDengine installation detected, proceeding with removal..."
    
    # Run rmtao if it exists
    if command -v rmtaos &> /dev/null; then
        echo "Running rmtaos to remove TDengine..."
        # Provide both responses: 'y' and the confirmation text
        {
            echo "y"
            echo "I confirm that I would like to delete all data, log and configuration files"
        } | rmtaos
    else
        echo "rmtaos command not found"
    fi
    
    echo "Existing TDengine installation and data removed."
}

# Function to construct download URL
function construct_download_url() {
    VERSION="$1"
    DOWNLOAD_URL="$2"

    if [[ "$DOWNLOAD_URL" == *"nas"* ]]; then
        MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f 1-2)
        if version_ge_3370 "$VERSION"; then
            # Use new package name format for versions >= 3.3.7.0
            echo "${DOWNLOAD_URL}/TDengine/${MAJOR_VERSION}/v${VERSION}/enterprise/tdengine-tsdb-enterprise-${VERSION}-linux-x64.tar.gz"
        else
            # Use old package name format for versions < 3.3.7.0
            echo "${DOWNLOAD_URL}/TDengine/${MAJOR_VERSION}/v${VERSION}/enterprise/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
        fi
    elif [[ "$DOWNLOAD_URL" == *"assets-download"* ]]; then
        if version_ge_3370 "$VERSION"; then
            echo "Not supported for assets-download URL for versions >=3.3.7.0. Please use download center."
            exit 1
        fi
        echo "${DOWNLOAD_URL}/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
    elif [[ "$DOWNLOAD_URL" == *"downloads"* ]]; then
        if version_ge_3370 "$VERSION"; then
            echo "${DOWNLOAD_URL}/tdengine-tsdb-enterprise/${VERSION}/tdengine-tsdb-enterprise-${VERSION}-linux-x64.tar.gz"
        else
            echo "Not supported for download center for versions < 3.3.7.0"
            exit 1
        fi
    else
        echo "::error ::Invalid download URL. It must contain either 'nas' or 'assets-download'."
        exit 1
    fi
}

# Function to download TDengine
function download_tdengine() {
    URL="$1"
    if version_ge_3370 "$VERSION"; then
        OUTPUT_FILE="${WORK_DIR}/tdengine-tsdb-enterprise-${VERSION}-Linux-x64.tar.gz"
    else
        OUTPUT_FILE="${WORK_DIR}/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
    fi

    # Check if file already exists and is valid
    if [ -f "$OUTPUT_FILE" ]; then
        echo "TDengine package file exists, checking if it's a valid tar archive..."
        
        # Check if the file is a valid gzipped tar archive
        if tar -tzf "$OUTPUT_FILE" > /dev/null 2>&1; then
            echo "Existing TDengine package is valid, skipping download."
            return 0
        else
            echo "Existing file is corrupted or not a valid tar archive, removing and re-downloading..."
            rm -f "$OUTPUT_FILE"
        fi
    fi

    if ! wget -O "$OUTPUT_FILE" "$URL"; then
        echo "::error ::Failed to download TDengine from $URL"
        exit 1
    fi

    echo "Successfully downloaded TDengine package."
}

# Function to extract TDengine
function extract_tdengine() {
    VERSION="$1"

    if version_ge_3370 "$VERSION"; then
        PACKAGE_FILE="${WORK_DIR}/tdengine-tsdb-enterprise-${VERSION}-Linux-x64.tar.gz"
    else
        PACKAGE_FILE="${WORK_DIR}/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
    fi
    
    if ! tar -xzvf "$PACKAGE_FILE" -C ${WORK_DIR}; then
        echo "::error ::Failed to extract TDengine archive"
        exit 1
    fi
}

# Function to install TDengine
function install_tdengine() {
    VERSION="$1"
    if version_ge_3370 "$VERSION"; then
        INSTALL_DIR="${WORK_DIR}/tdengine-tsdb-enterprise-${VERSION}"
    else
        INSTALL_DIR="${WORK_DIR}/TDengine-enterprise-${VERSION}"
    fi
    
    cd "$INSTALL_DIR" || {
        echo "::error ::Failed to enter TDengine directory"
        exit 1
    }
    ./install.sh -e no
}

# Function to clean up temporary files
function cleanup() {
    echo "Cleaning up pkg files..."
    VERSION="$1"
    cd ..
    if version_ge_3370 "$VERSION"; then
        rm -rf "tdengine-tsdb-enterprise-${VERSION}"
    else
        rm -rf "TDengine-enterprise-${VERSION}"
    fi
}

# Main script execution

# Validate input parameters
validate_parameters "$@"

# Input parameters
VERSION="$1"      # Version number, e.g., 3.3.5.1
DOWNLOAD_URL="$2" # Download URL
CLEAN_INSTALL="${3:-false}" # Whether to clean existing installation, default to false

# Construct download URL
URL=$(construct_download_url "$VERSION" "$DOWNLOAD_URL")
echo "Download URL: $URL"

# Download TDengine
download_tdengine "$URL"

# Remove existing installation if requested
if [ "$CLEAN_INSTALL" = "true" ]; then
    remove_existing_tdengine
fi

# Extract TDengine
extract_tdengine "$VERSION"

# Install TDengine
install_tdengine "$VERSION"

# Clean up temporary files
cleanup "$VERSION"