#!/bin/bash
WORK_DIR=/opt
# Function to display help
function display_help() {
    echo "Usage: $0 <version> <download_url>"
    echo
    echo "Parameters:"
    echo "  version      The version number, e.g., 3.3.5.1"
    echo "  download_url The URL for downloading TDengine. It must contain either 'nas' or 'assets-down'."
    echo
    echo "Example:"
    echo "  $0 3.3.5.1 https://example.com/nas"
    exit 1
}

# Function to validate input parameters
function validate_parameters() {
    if [ "$#" -ne 2 ]; then
        echo "::error ::Invalid number of parameters."
        display_help
    fi
}

# Function to construct download URL
function construct_download_url() {
    VERSION="$1"
    DOWNLOAD_URL="$2"

    if [[ "$DOWNLOAD_URL" == *"nas"* ]]; then
        MAJOR_VERSION=$(echo "$VERSION" | cut -d '.' -f 1-2)
        echo "${DOWNLOAD_URL}/TDengine/${MAJOR_VERSION}/v${VERSION}/enterprise/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
    elif [[ "$DOWNLOAD_URL" == *"assets-download"* ]]; then
        echo "${DOWNLOAD_URL}/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
    else
        echo "::error ::Invalid download URL. It must contain either 'nas' or 'assets-download'."
        exit 1
    fi
}

# Function to download TDengine
function download_tdengine() {
    URL="$1"
    OUTPUT_FILE="${WORK_DIR}/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"

    # Check if file already exists
    if [ -f "$OUTPUT_FILE" ]; then
        echo "TDengine package already exists, skipping download."
        return 0
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
    if ! tar -xzvf "${WORK_DIR}/TDengine-enterprise-${VERSION}-Linux-x64.tar.gz" -C ${WORK_DIR}; then
        echo "::error ::Failed to extract TDengine archive"
        exit 1
    fi
}

# Function to install TDengine
function install_tdengine() {
    VERSION="$1"
    cd "${WORK_DIR}/TDengine-enterprise-${VERSION}" || {
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
    # rm -f "TDengine-enterprise-${VERSION}-Linux-x64.tar.gz"
    rm -rf "TDengine-enterprise-${VERSION}"
}

# Main script execution

# Validate input parameters
validate_parameters "$@"

# Input parameters
VERSION="$1"      # Version number, e.g., 3.3.5.1
DOWNLOAD_URL="$2" # Download URL

# Construct download URL
URL=$(construct_download_url "$VERSION" "$DOWNLOAD_URL")
echo "Download URL: $URL"

# Download TDengine
download_tdengine "$URL"

# Extract TDengine
extract_tdengine "$VERSION"

# Install TDengine
install_tdengine "$VERSION"

# Clean up temporary files
cleanup "$VERSION"