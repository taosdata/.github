#!/bin/bash


# ==============================================
# Parameter Parsing Module
# ==============================================

MODE="build"
SYSTEM_PACKAGES=""
PYTHON_VERSION=""
PYTHON_PACKAGES=""
PYTHON_REQUIREMENTS=""
PKG_LABEL=""
BINARY_TOOLS=("bpftrace")
TDGPT=""
TDGPT_ALL=""  # Install all model venvs (mirrors install_tdgpt.sh -a flag)
TDENGINE_TSDB_VER=""  # TDengine version for downloading requirements files (e.g. 3.4.0.8)
IDMP_VER=""  # IDMP version for downloading requirements from TDasset repo (e.g. 1.0.12.10, maps to tag ver-1.0.12.10)
GH_TOKEN=""  # GitHub personal access token for private repos (required for TDasset)
PIP_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"  # Default pip index mirror
DOCKER_VERSION="latest"
DOCKER_COMPOSE_VERSION="latest"
INSTALL_DOCKER=""
INSTALL_DOCKER_COMPOSE=""
JAVA_VERSION="21"
INSTALL_JAVA=""
IDMP=""
CACHE_DIR="/tmp/taos-packages"
BPFTRACE_VERSION="0.23.2"  # Configurable bpftrace version
TDGPT_BASE_DIR="/var/lib/taos/taosanode"  # Configurable TDgpt base directory
IDMP_VENV_DIR="/usr/local/taos/idmp/venv"  # Configurable IDMP venv directory
PYTORCH_WHL_URL="https://mirrors.aliyun.com/pytorch-wheels/cpu"  # PyTorch CPU wheel mirror (China CDN)
BUILD_NOTES=()  # Post-build notes collected during the run, re-printed in summary()

# Install uv with download caching (shared via $CACHE_DIR across container runs)
# Populates BUILD_NOTES with PATH reminder if uv was newly installed.
install_uv_cached() {
    local uv_bin="$HOME/.local/bin/uv"
    local cached_uv="$CACHE_DIR/uv"

    if command -v uv &>/dev/null; then
        return 0  # already on PATH, nothing to do
    fi

    mkdir -p "$HOME/.local/bin"

    if [[ -f "$cached_uv" ]]; then
        yellow_echo "Restoring uv from cache: $cached_uv"
        cp "$cached_uv" "$uv_bin"
        chmod +x "$uv_bin"
    else
        yellow_echo "Downloading and installing uv..."
        if [[ -f /etc/kylin-release || "$OS_ID" == "openEuler" ]]; then
            if ! curl -LsSf https://astral.sh/uv/install.sh | sh; then
                red_echo "Failed to install uv"
                exit 1
            fi
        else
            local setup_env="$script_dir/setup_env.sh"
            if ! curl -o "$setup_env" https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh; then
                red_echo "Failed to download setup_env.sh"
                exit 1
            fi
            chmod +x "$setup_env"
            if ! "$setup_env" install_uv; then
                red_echo "Failed to install uv"
                exit 1
            fi
        fi
        # Cache the binary for next run
        if [[ -f "$uv_bin" ]]; then
            cp "$uv_bin" "$cached_uv"
            green_echo "uv binary cached: $cached_uv"
        fi
    fi

    # Update PATH for current shell session.
    # Always export ~/.local/bin first (handles cache-restore path where
    # ~/.local/bin/env does not exist but the binary is already there).
    export PATH="$HOME/.local/bin:$PATH"
    # Also source the env file if it exists (sets any extra vars the installer created)
    if [[ -f "$HOME/.local/bin/env" ]]; then
        # shellcheck source=/dev/null
        source "$HOME/.local/bin/env"
    fi

    # Persist uv's wheel/package cache on the host-mounted CACHE_DIR so that large
    # wheels (torch ~200 MB, tensorflow ~600 MB) are only downloaded once across
    # container runs.  Without this, every new container re-downloads from scratch.
    export UV_CACHE_DIR="${CACHE_DIR}/uv-cache"
    mkdir -p "$UV_CACHE_DIR"
    # Cache dir is on a host-mounted volume; venv targets are inside the container,
    # so they are on different filesystems — hardlinks won't work.  Tell uv to use
    # copy mode explicitly to suppress the "Failed to hardlink" warning.
    export UV_LINK_MODE=copy

    # Sanity check — fail loudly rather than silently proceeding with uv missing
    if ! command -v uv &>/dev/null; then
        red_echo "ERROR: uv still not found on PATH after install/restore."
        red_echo "  Expected location: $uv_bin"
        red_echo "  PATH: $PATH"
        exit 1
    fi

    # Record PATH reminder for summary
    BUILD_NOTES+=("  uv installed to: $uv_bin")
    BUILD_NOTES+=("  To make uv available in new shells, run:")
    BUILD_NOTES+=("    source \$HOME/.local/bin/env          (sh, bash, zsh)")
    BUILD_NOTES+=("    source \$HOME/.local/bin/env.fish     (fish)")
}

function show_usage() {
    echo "Usage:"
    echo "  Option      Mode: $0 [--build|--test] --system-packages=<pkgs> --python-version=<ver> --python-packages=<pkgs> --pkg-label=<label>"
    echo "  Docker Options: [--install-docker] [--docker-version=<version>] [--install-docker-compose] [--docker-compose-version=<version>]"
    echo "  Java Options: [--install-java] [--java-version=<version>] (default: 21, supported: 8,11,17,21,23)"
    echo "  Python Options: [--python-requirements=<url_or_path>] (alternative to --python-packages)"
    echo "  Special Options: [--tdgpt=<true|false>] [--tdgpt-all] [--idmp=<true|false>] [--idmp-ver=<ver>] [--gh-token=<token>]"
    echo "  Mirror Options:  [--pip-index-url=<url>] (default: https://pypi.tuna.tsinghua.edu.cn/simple, set empty to use PyPI)"
    echo "                   [--pytorch-whl-url=<url>] (default: https://mirrors.aliyun.com/pytorch-wheels/cpu, Aliyun PyTorch mirror)"
    echo "  Path Options: [--bpftrace-version=<version>] (default: 0.23.2) [--tdgpt-base-dir=<path>] (default: /var/lib/taos/taosanode) [--idmp-venv-dir=<path>] (default: /usr/local/taos/idmp/venv)"
    echo ""
    echo "TDgpt Model Options:"
    echo "  --tdengine-tsdb-ver=<ver>  TDengine version to download requirements files from GitHub"
    echo "                            (e.g. 3.4.0.8). Downloads tools/tdgpt/requirements_*.txt from tag ver-<ver>."
    echo "                            If not specified, falls back to local requirements files in script dir."
    echo "  --tdgpt-all               Build all model venvs (mirrors install_tdgpt.sh -a flag)"
    echo "                            Default (without --tdgpt-all): only build main venv for tdtsfm/timemoe"
    echo "                            With --tdgpt-all: also build timesfm/moirai/chronos/moment extra venvs"
    echo ""
    echo "IDMP Options:"
    echo "  --idmp-ver=<ver>          IDMP version to download requirements from TDasset repo"
    echo "                            (e.g. 1.0.12.10). Downloads ai-server/requirements.txt from tag ver-<ver>."
    echo "                            Requires --gh-token since TDasset is a private repository."
    echo "  --gh-token=<token>        GitHub personal access token for accessing private repositories."
    echo ""
    echo "Example:"
    echo "  $0 --build --system-packages=vim,ntp --python-version=3.10 --python-packages=fabric2,requests --pkg-label=1.0.20250409"
    echo "  $0 --build --python-version=3.10 --python-requirements=https://github.com/user/repo/blob/main/requirements.txt --pkg-label=test"
    echo "  $0 --build --install-docker --docker-version=27.5.1 --install-docker-compose --docker-compose-version=v2.40.2 --pkg-label=test"
    echo "  $0 --build --install-java --java-version=21 --pkg-label=java-test"
    echo "  $0 --build --install-java --idmp=true --pkg-label=idmp-env"
    echo "  $0 --build --idmp=true --idmp-ver=1.0.12.10 --gh-token=ghp_xxx --python-version=3.10 --pkg-label=idmp-ai"
    echo "  $0 --build --tdgpt=true --tdengine-tsdb-ver=3.4.0.8 --pkg-label=tdgpt-default  # Download requirements from ver"
    echo "  $0 --build --tdgpt=true --tdengine-tsdb-ver=3.4.0.8 --tdgpt-all --pkg-label=tdgpt-all  # All venvs from ver"
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build|--test)
            MODE="${1#--}"
            shift
            ;;
        --system-packages=*)
            SYSTEM_PACKAGES="${1#*=}"
            shift
            ;;
        --python-version=*)
            PYTHON_VERSION="${1#*=}"
            shift
            ;;
        --python-packages=*)
            PYTHON_PACKAGES="${1#*=}"
            shift
            ;;
        --python-requirements=*)
            PYTHON_REQUIREMENTS="${1#*=}"
            shift
            ;;
        --pkg-label=*)
            PKG_LABEL="${1#*=}"
            shift
            ;;
        --deploy-type=*)
            # External-facing alias: tsdb (default) | idmp | tdgpt
            case "${1#*=}" in
                idmp)  IDMP="true"  ;;
                tdgpt) TDGPT="true" ;;
                tsdb)  ;;  # default — no extra venv flag needed
                *) echo "[WARNING] Unknown --deploy-type value: ${1#*=}"; ;;
            esac
            shift
            ;;
        --tdgpt=*)
            TDGPT="${1#*=}"
            shift
            ;;
        --tdgpt-all)
            TDGPT_ALL="true"
            shift
            ;;
        --tdengine-tsdb-ver=*)
            TDENGINE_TSDB_VER="${1#*=}"
            shift
            ;;
        --idmp-ver=*)
            IDMP_VER="${1#*=}"
            shift
            ;;
        --gh-token=*)
            GH_TOKEN="${1#*=}"
            shift
            ;;
        --pip-index-url=*)
            PIP_INDEX_URL="${1#*=}"
            shift
            ;;
        --pytorch-whl-url=*)
            PYTORCH_WHL_URL="${1#*=}"
            shift
            ;;
        --install-docker)
            INSTALL_DOCKER="true"
            shift
            ;;
        --docker-version=*)
            DOCKER_VERSION="${1#*=}"
            shift
            ;;
        --install-docker-compose)
            INSTALL_DOCKER_COMPOSE="true"
            shift
            ;;
        --docker-compose-version=*)
            DOCKER_COMPOSE_VERSION="${1#*=}"
            shift
            ;;
        --install-java)
            INSTALL_JAVA="true"
            shift
            ;;
        --java-version=*)
            JAVA_VERSION="${1#*=}"
            shift
            ;;
        --idmp=*)
            IDMP="${1#*=}"
            shift
            ;;
        --bpftrace-version=*)
            BPFTRACE_VERSION="${1#*=}"
            shift
            ;;
        --tdgpt-base-dir=*)
            TDGPT_BASE_DIR="${1#*=}"
            shift
            ;;
        --idmp-venv-dir=*)
            IDMP_VENV_DIR="${1#*=}"
            shift
            ;;
        -h|--help)
            show_usage
            ;;
        *)
            if [[ -n "$SYSTEM_PACKAGES" ]]; then
                SYSTEM_PACKAGES="$1"
            elif [[ -n "$PYTHON_VERSION" ]]; then
                PYTHON_VERSION="$1"
            elif [[ -n "$PYTHON_PACKAGES" ]]; then
                PYTHON_PACKAGES="$1"
            elif [[ -n "$PKG_LABEL" ]]; then
                PKG_LABEL="$1"
            elif [[ -n "$TDGPT" ]]; then
                TDGPT="$1"
            else
                echo "[WARNING] Excess parameters detected: $1"
            fi
            shift
            ;;
    esac
done

# ==============================================
# Parameter Validation Module
# ==============================================
function validate_params() {
    # local missing_required=()
    local package_error=""

    # Check required parameters (required for all modes)
    # [[ -z "$PYTHON_VERSION" ]] && missing_required+=("PYTHON_VERSION")
    # [[ -z "$PKG_LABEL" ]] && missing_required+=("PKG_LABEL")

    # Check package logic: at least one exists
    if [[ -z "$SYSTEM_PACKAGES" && -z "$PYTHON_PACKAGES" && -z "$PYTHON_REQUIREMENTS" && -z "$INSTALL_DOCKER" && -z "$INSTALL_DOCKER_COMPOSE" && -z "$INSTALL_JAVA" && -z "$IDMP" && -z "$TDGPT" ]]; then
        package_error="At least one of **SYSTEM_PACKAGES**, **PYTHON_PACKAGES**, **PYTHON_REQUIREMENTS**, **INSTALL_DOCKER**, **INSTALL_DOCKER_COMPOSE**, **INSTALL_JAVA**, **IDMP**, or **TDGPT** must be provided."
    fi
    
    # Check if both python-packages and python-requirements are specified
    if [[ -n "$PYTHON_PACKAGES" && -n "$PYTHON_REQUIREMENTS" ]]; then
        package_error="Cannot specify both **PYTHON_PACKAGES** and **PYTHON_REQUIREMENTS** at the same time. Please use only one."
    fi

    # Check PYTHON_VERSION is provided when python packages are specified, or when
    # TDGPT/IDMP is enabled (both require a Python venv at a specific version).
    if [[ ( -n "$PYTHON_PACKAGES" || -n "$PYTHON_REQUIREMENTS" || -n "$TDGPT" || -n "$IDMP" ) && -z "$PYTHON_VERSION" ]]; then
        package_error="**PYTHON_VERSION** is required when **PYTHON_PACKAGES**, **PYTHON_REQUIREMENTS**, **TDGPT**, or **IDMP** is specified."
    fi

    # Combined error message
    local error_msg=""
    # if [ ${#missing_required[@]} -gt 0 ]; then
    #     error_msg+="Required parameter is missing: ${missing_required[*]}. "
    # fi
    [[ -n "$package_error" ]] && error_msg+="$package_error"

    # Error handle
    if [[ -n "$error_msg" ]]; then
        echo -e "[ERROR] Parameter validation failed:"
        echo -e "  • ${error_msg//. /$'\n  • '}"
        show_usage
    fi
}
validate_params

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'
red_echo() { echo -e "${RED}$*${RESET}"; }
green_echo() { echo -e "${GREEN}$*${RESET}"; }
yellow_echo() { echo -e "${YELLOW}$*${RESET}"; }

# Build pip index args (mirrors install_tdgpt.sh pip_extra_args logic)
# Usage: uv pip install <pkg> "${pip_index_args[@]}"
pip_index_args=()
if [ -n "$PIP_INDEX_URL" ]; then
    pip_index_args+=(-i "$PIP_INDEX_URL")
fi

# Build PyTorch wheel args (uses --find-links with Chinese CDN mirror)
# Aliyun mirror serves a flat directory listing (not PEP 503), so --find-links is required.
# The index page (~940KB) downloads in ~1s from Chinese CDN, and wheels download at ~10 MB/s.
# Usage: uv pip install torch "${pytorch_index_args[@]}"
pytorch_index_args=()
if [ -n "$PYTORCH_WHL_URL" ]; then
    pytorch_index_args=(--find-links "$PYTORCH_WHL_URL")
fi

# Detect system architecture and normalize to standard format
# Returns: x86_64 or aarch64
get_system_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x86_64"
            ;;
        aarch64|arm64)
            echo "aarch64"
            ;;
        *)
            red_echo "Unsupported architecture: $arch"
            return 1
            ;;
    esac
}

# Get simplified architecture name for package naming
# Returns: x64 or arm64
get_simplified_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)
            echo "x64"
            ;;
        aarch64|arm64)
            echo "arm64"
            ;;
        *)
            red_echo "Unsupported architecture: $arch"
            return 1
            ;;
    esac
}

function init() {
    SUB_VERSION=""
    if [ -f /etc/os-release ]; then
        # Safely extract OS information using grep instead of source
        OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
        
        case "$OS_ID" in
            ubuntu|debian)
                PKG_MGR="apt"
                PKG_CONFIRM="dpkg -l"
                ;;
            centos|rhel|rocky|kylin)
                if [ "$OS_ID" = "kylin" ]; then
                    # Extract SP version + code name from /etc/.productinfo
                    # Handles multiple real-world formats:
                    #   SP3-2403 format:  "release V10 SP3 2403/(Halberd)-x86_64-Build20/20240426"
                    #   SP2 format:       "release V10 (SP2) /(Sword)-aarch64-Build09/20210524"
                    # Regex: match SPx (with or without parens), then /(CodeName)
                    if [ -f /etc/.productinfo ]; then
                        SUB_VERSION="$(sed -n '2p' /etc/.productinfo | sed -n 's/.*V10[[:space:]]*[( ]*\(SP[0-9]\+\)[) ].*\/(\([^)]*\)).*/\1-\2/p')-"
                    fi
                    # Fallback: extract from /etc/os-release VERSION field
                    # Example: VERSION="V10 (Halberd)" → Halberd
                    if [ -z "$SUB_VERSION" ] || [ "$SUB_VERSION" = "-" ]; then
                        local os_codename
                        os_codename=$(grep -E '^VERSION=' /etc/os-release | sed -n 's/.*( *\([^)]*\) *).*/\1/p')
                        if [ -n "$os_codename" ]; then
                            SUB_VERSION="${os_codename}-"
                        fi
                    fi
                fi
                PKG_MGR="yum"
                PKG_CONFIRM="rpm -q"
                ;;
            openEuler)
                # openEuler uses yum/dnf, extract LTS-SP version if exists
                # Check VERSION field (not VERSION_ID) for LTS-SP information
                OS_VERSION_FULL=$(grep -E '^VERSION=' /etc/os-release | cut -d= -f2 | tr -d '"')
                if echo "$OS_VERSION_FULL" | grep -q "LTS-SP"; then
                    SP_VERSION=$(echo "$OS_VERSION_FULL" | sed -n 's/.*\(LTS-SP[0-9]\+\).*/\1/p')
                    if [ -n "$SP_VERSION" ]; then
                        SUB_VERSION="${SP_VERSION}-"
                    fi
                fi
                PKG_MGR="yum"
                PKG_CONFIRM="rpm -q"
                ;;
            sles|opensuse*|suse)
                # Extract SP version for SLES
                if [ "$OS_ID" = "sles" ]; then
                    SP_VERSION=$(grep -E '^VERSION=' /etc/os-release | cut -d= -f2 | tr -d '"' | sed -n 's/.*SP\([0-9]\+\).*/SP\1/p')
                    if [ -n "$SP_VERSION" ]; then
                        SUB_VERSION="${SP_VERSION}-"
                    fi
                fi
                PKG_MGR="zypper"
                PKG_CONFIRM="rpm -q"
                ;;
            *)
                red_echo "Unsupported OS and set OS_ID and OS_VERSION to unknown"
                OS_ID=unknown_os
                OS_VERSION=""
                PKG_MGR=""
                PKG_CONFIRM=""
        esac

    else
        red_echo "Cannot detect OS and set OS_ID and OS_VERSION to unknown"
        OS_ID=unknown_os
        OS_VERSION=""
    fi

    # Validate: only allow characters that are safe in package names
    if [[ -n "$SYSTEM_PACKAGES" ]] && ! [[ "$SYSTEM_PACKAGES" =~ ^[a-zA-Z0-9_.+,-]+$ ]]; then
        red_echo "ERROR: --system-packages contains invalid characters."
        red_echo "       Allowed: letters, digits, dash, underscore, dot, plus, comma"
        exit 1
    fi
    IFS=',' read -r -a formated_system_packages <<< "$SYSTEM_PACKAGES"
    formated_python_packages=$(echo "$PYTHON_PACKAGES" | tr ',' ' ')
    formated_python_requirements="$PYTHON_REQUIREMENTS"
    if [[ -z "$PARENT_DIR" ]]; then
        parent_dir=/opt/offline-env
    else
        parent_dir=$PARENT_DIR
    fi
    mkdir -p "$parent_dir"
    # Create cache directory for downloads
    mkdir -p "$CACHE_DIR"
    yellow_echo "Using cache directory: $CACHE_DIR"
    local simplified_arch
    simplified_arch=$(get_simplified_arch) || exit 1
    offline_env_dir="offline-pkgs-$PKG_LABEL-$OS_ID-$OS_VERSION-${SUB_VERSION}${simplified_arch}"
    offline_env_path="$parent_dir/$offline_env_dir"
    system_packages_dir="$offline_env_path/system_packages"
    tar_file="$system_packages_dir/system_packages.tar"
    py_venv_dir="$offline_env_path/py_venv"
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Force clean and create dir
    if [ "$MODE" == "build" ];then
        rm -rf "$offline_env_path"
        if [[ -n "$SYSTEM_PACKAGES" ]]; then
            mkdir -p "$system_packages_dir"
        fi
        if [[ -n "$PYTHON_PACKAGES" ]] || [[ -n "$PYTHON_REQUIREMENTS" ]] || [[ "$TDGPT" == "true" ]] || [[ "$IDMP" == "true" && -n "$IDMP_VER" ]]; then
            mkdir -p "$py_venv_dir"
        fi
    fi
}


function config_yum() {
    # Define the line to be added
    if ! curl -o "$script_dir"/setup_env.sh https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh; then
        red_echo "Failed to download setup_env.sh"
        exit 1
    fi
    chmod +x "$script_dir"/setup_env.sh
    if ! "$script_dir"/setup_env.sh replace_sources; then
        red_echo "Failed to replace sources"
        exit 1
    fi
    EXCLUDE_LINE="exclude=*.i?86"

    # Check if the /etc/yum.conf file exists
    if [ -f /etc/yum.conf ]; then
        # Check if the line already exists
        if grep -q "^exclude=*.i?86" /etc/yum.conf; then
            yellow_echo "The line already exists in /etc/yum.conf."
        else
            # Append the line after the [main] section
            sed -i "/^\[main\]/a $EXCLUDE_LINE" /etc/yum.conf
            green_echo "Successfully added '$EXCLUDE_LINE' to /etc/yum.conf."
        fi
    else
        red_echo "/etc/yum.conf file does not exist."
    fi
}

function download_bpftrace_binary() {
    local os_type="$1"  # e.g., "CentOS/RHEL" or "SUSE/SLES"
    yellow_echo "Handling bpftrace specially for ${os_type}..."

    local host_arch
    host_arch=$(uname -m)

    # bpftrace releases only provide a static binary for x86_64.
    # aarch64 has no prebuilt binary; users must install via package manager or build from source.
    if [ "$host_arch" != "x86_64" ]; then
        red_echo "No prebuilt bpftrace binary is available for arch=${host_arch} on GitHub Releases."
        red_echo "Please install bpftrace via your package manager or build from source:"
        red_echo "  https://github.com/bpftrace/bpftrace/blob/master/INSTALL.md"
        exit 1
    fi

    local BPFTRACE_URL="https://github.com/bpftrace/bpftrace/releases/download/v${BPFTRACE_VERSION}/bpftrace"
    mkdir -p "$offline_env_path/binary_tools"

    if ! wget -q "$BPFTRACE_URL" -O "$offline_env_path/binary_tools/bpftrace"; then
        red_echo "Failed to download bpftrace binary"
        exit 1
    fi

    chmod +x "$offline_env_path/binary_tools/bpftrace"
    green_echo "Successfully downloaded bpftrace binary (x86_64) for ${os_type}"
}

function download_docker() {
    if [ "$INSTALL_DOCKER" != "true" ]; then
        return 0
    fi
    
    yellow_echo "Downloading Docker..."
    
    # Detect system architecture
    local arch
    arch=$(get_system_arch) || exit 1
    
    mkdir -p "$offline_env_path/docker"
    
    # Get latest version if not specified
    if [ "$DOCKER_VERSION" = "latest" ]; then
        yellow_echo "Fetching latest Docker version..."
        DOCKER_VERSION=$(curl -s https://download.docker.com/linux/static/stable/$arch/ | \
            grep -oP 'docker-[0-9]+\.[0-9]+\.[0-9]+\.tgz' | \
            sed 's/docker-//' | sed 's/\.tgz//' | \
            sort -V | tail -1)
        if [ -z "$DOCKER_VERSION" ]; then
            red_echo "Failed to fetch latest Docker version"
            exit 1
        fi
        yellow_echo "Latest Docker version: $DOCKER_VERSION"
    fi
    
    local DOCKER_URL="https://download.docker.com/linux/static/stable/$arch/docker-${DOCKER_VERSION}.tgz"
    yellow_echo "Downloading from: $DOCKER_URL"
    
    if ! wget -q "$DOCKER_URL" -O "$offline_env_path/docker/docker-${DOCKER_VERSION}.tgz"; then
        red_echo "Failed to download Docker ${DOCKER_VERSION}"
        exit 1
    fi
    
    # Save version info
    echo "$DOCKER_VERSION" > "$offline_env_path/docker/version.txt"
    echo "$arch" > "$offline_env_path/docker/arch.txt"
    
    green_echo "Successfully downloaded Docker ${DOCKER_VERSION} for ${arch}"
}

function download_java() {
    if [ "$INSTALL_JAVA" != "true" ]; then
        return 0
    fi
    
    yellow_echo "Downloading Java JRE ${JAVA_VERSION}..."
    
    # Detect system architecture
    local arch
    arch=$(get_system_arch) || exit 1
    
    # Map architecture to Adoptium naming
    local jre_arch
    case "$arch" in
        x86_64)
            jre_arch="x64"
            ;;
        aarch64)
            jre_arch="aarch64"
            ;;
        *)
            red_echo "Unsupported architecture for Java: $arch"
            exit 1
            ;;
    esac
    
    mkdir -p "$offline_env_path/java"
    
    # Version-specific URLs and checksums
    local base_url tar_name sha256_x64 sha256_aarch64
    
    case "$JAVA_VERSION" in
        8)
            base_url="https://github.com/adoptium/temurin8-binaries/releases/download/jdk8u432-b06"
            tar_name="OpenJDK8U-jre_${jre_arch}_linux_hotspot_8u432b06.tar.gz"
            ;;
        11)
            base_url="https://github.com/adoptium/temurin11-binaries/releases/download/jdk-11.0.26%2B8"
            tar_name="OpenJDK11U-jre_${jre_arch}_linux_hotspot_11.0.26_8.tar.gz"
            ;;
        17)
            base_url="https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.14%2B8"
            tar_name="OpenJDK17U-jre_${jre_arch}_linux_hotspot_17.0.14_8.tar.gz"
            ;;
        21)
            base_url="https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.6%2B7"
            tar_name="OpenJDK21U-jre_${jre_arch}_linux_hotspot_21.0.6_7.tar.gz"
            sha256_x64="7fc9d6837da5fa1f12e0f41901fd70a73154914b8c8ecbbcad2d44176a989937"
            sha256_aarch64="f1b78f2bd6d505d5e0539261737740ad11ade3233376b4ca52e6c72fbefd2bf6"
            ;;
        23)
            base_url="https://github.com/adoptium/temurin23-binaries/releases/download/jdk-23.0.2%2B7"
            tar_name="OpenJDK23U-jre_${jre_arch}_linux_hotspot_23.0.2_7.tar.gz"
            ;;
        *)
            red_echo "Unsupported Java version: $JAVA_VERSION (supported: 8, 11, 17, 21, 23)"
            exit 1
            ;;
    esac
    
    local download_url="${base_url}/${tar_name}"
    local cached_file="$CACHE_DIR/${tar_name}"

    # Helper: download (or re-download) the JRE into the cache
    _download_jre() {
        yellow_echo "Downloading from: $download_url"
        if ! curl -fsSL "$download_url" -o "$cached_file"; then
            red_echo "Failed to download Java JRE ${JAVA_VERSION}"
            exit 1
        fi
        green_echo "Downloaded to cache: $cached_file ($(du -sh "$cached_file" 2>/dev/null | cut -f1))"
    }

    # Check if a non-empty file already exists in cache
    if [ -f "$cached_file" ] && [ -s "$cached_file" ]; then
        yellow_echo "Using cached Java JRE from: $cached_file ($(du -sh "$cached_file" 2>/dev/null | cut -f1))"
    else
        if [ -f "$cached_file" ]; then
            yellow_echo "Cached file is empty/corrupt, re-downloading: $cached_file"
            rm -f "$cached_file"
        fi
        _download_jre
    fi

    # SHA256 verification for Java 21 only
    if [ "$JAVA_VERSION" = "21" ]; then
        yellow_echo "Verifying SHA256 checksum..."
        local expected_sha256
        if [ "$jre_arch" = "x64" ]; then
            expected_sha256="$sha256_x64"
        else
            expected_sha256="$sha256_aarch64"
        fi

        if ! echo "${expected_sha256}  $cached_file" | sha256sum -c - &>/dev/null; then
            red_echo "SHA256 checksum verification failed!"
            red_echo "  File:     $cached_file"
            red_echo "  Expected: $expected_sha256"
            red_echo "  Actual:   $(sha256sum "$cached_file" 2>/dev/null | awk '{print $1}')"
            red_echo "Removing corrupt cached file and re-downloading..."
            rm -f "$cached_file"
            _download_jre
            # Verify freshly downloaded file
            if ! echo "${expected_sha256}  $cached_file" | sha256sum -c - &>/dev/null; then
                red_echo "SHA256 verification failed again after re-download. Aborting."
                exit 1
            fi
        fi
        green_echo "SHA256 checksum verified"
    fi
    
    # Copy from cache to offline package directory
    cp "$cached_file" "$offline_env_path/java/${tar_name}"
    
    # Save version and arch info
    echo "$JAVA_VERSION" > "$offline_env_path/java/version.txt"
    echo "$arch" > "$offline_env_path/java/arch.txt"
    echo "$tar_name" > "$offline_env_path/java/tarname.txt"
    
    green_echo "Successfully downloaded Java JRE ${JAVA_VERSION} for ${arch}"
}

function download_idmp_packages() {
    if [ "$IDMP" != "true" ]; then
        return 0
    fi
    
    yellow_echo "Downloading IDMP packages..."
    
    # Detect system architecture
    local arch
    arch=$(get_system_arch) || exit 1
    
    mkdir -p "$offline_env_path/idmp"
    
    # 1. Download Arthas
    yellow_echo "Downloading Arthas..."
    local arthas_file="$CACHE_DIR/arthas-boot.jar"
    if [ -f "$arthas_file" ]; then
        yellow_echo "Using cached Arthas from: $arthas_file"
    else
        if ! curl -fsSL --retry 3 -o "$arthas_file" https://arthas.aliyun.com/arthas-boot.jar; then
            red_echo "Failed to download Arthas"
            exit 1
        fi
        green_echo "Downloaded Arthas to cache"
    fi
    cp "$arthas_file" "$offline_env_path/idmp/arthas-boot.jar"
    
    # 2. Download Playwright packages based on architecture
    yellow_echo "Downloading Playwright packages for ${arch}..."
    
    if [ "$arch" = "x86_64" ]; then
        # x64 packages
        local chromium_url="https://cdn.playwright.dev/dbazure/download/playwright/builds/chromium/1194/chromium-headless-shell-linux.zip"
        local ffmpeg_url="https://cdn.playwright.dev/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux.zip"
        local chromium_file="$CACHE_DIR/chromium-headless-shell-linux.zip"
        local ffmpeg_file="$CACHE_DIR/ffmpeg-linux.zip"
    else
        # aarch64 packages
        local chromium_url="https://playwright.download.prss.microsoft.com/dbazure/download/playwright/builds/chromium/1194/chromium-headless-shell-linux-arm64.zip"
        local ffmpeg_url="https://cdn.playwright.dev/dbazure/download/playwright/builds/ffmpeg/1011/ffmpeg-linux-arm64.zip"
        local chromium_file="$CACHE_DIR/chromium-headless-shell-linux-arm64.zip"
        local ffmpeg_file="$CACHE_DIR/ffmpeg-linux-arm64.zip"
    fi
    
    # Download Chromium
    if [ -f "$chromium_file" ]; then
        yellow_echo "Using cached Chromium from: $chromium_file"
    else
        yellow_echo "Downloading Chromium from: $chromium_url"
        if ! curl -fsSL --retry 3 -o "$chromium_file" "$chromium_url"; then
            red_echo "Failed to download Chromium"
            exit 1
        fi
        green_echo "Downloaded Chromium to cache"
    fi
    cp "$chromium_file" "$offline_env_path/idmp/"
    
    # Download FFmpeg
    if [ -f "$ffmpeg_file" ]; then
        yellow_echo "Using cached FFmpeg from: $ffmpeg_file"
    else
        yellow_echo "Downloading FFmpeg from: $ffmpeg_url"
        if ! curl -fsSL --retry 3 -o "$ffmpeg_file" "$ffmpeg_url"; then
            red_echo "Failed to download FFmpeg"
            exit 1
        fi
        green_echo "Downloaded FFmpeg to cache"
    fi
    cp "$ffmpeg_file" "$offline_env_path/idmp/"
    
    # Save architecture info
    echo "$arch" > "$offline_env_path/idmp/arch.txt"
    
    green_echo "Successfully downloaded all IDMP packages for ${arch}"
}

function download_docker_compose() {
    if [ "$INSTALL_DOCKER_COMPOSE" != "true" ]; then
        return 0
    fi
    
    yellow_echo "Downloading Docker Compose..."
    
    # Detect system architecture
    local arch
    arch=$(get_system_arch) || exit 1
    
    mkdir -p "$offline_env_path/docker_compose"
    
    # Get latest version if not specified
    if [ "$DOCKER_COMPOSE_VERSION" = "latest" ]; then
        yellow_echo "Fetching latest Docker Compose version..."
        
        # Check if jq is available
        if ! command -v jq &> /dev/null; then
            red_echo "jq is required but not installed. Please install jq first:"
            red_echo "  - Ubuntu/Debian: apt-get install jq"
            red_echo "  - RHEL/CentOS: yum install jq"
            red_echo "  - SUSE: zypper install jq"
            exit 1
        fi
        
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
        if [ -z "$DOCKER_COMPOSE_VERSION" ] || [ "$DOCKER_COMPOSE_VERSION" = "null" ]; then
            red_echo "Failed to fetch latest Docker Compose version"
            exit 1
        fi
        yellow_echo "Latest Docker Compose version: $DOCKER_COMPOSE_VERSION"
    fi
    
    # Ensure version starts with 'v'
    if [[ ! "$DOCKER_COMPOSE_VERSION" =~ ^v ]]; then
        DOCKER_COMPOSE_VERSION="v${DOCKER_COMPOSE_VERSION}"
    fi
    
    local COMPOSE_URL="https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-${arch}"
    yellow_echo "Downloading from: $COMPOSE_URL"
    
    if ! wget -q "$COMPOSE_URL" -O "$offline_env_path/docker_compose/docker-compose"; then
        red_echo "Failed to download Docker Compose ${DOCKER_COMPOSE_VERSION}"
        exit 1
    fi
    
    chmod +x "$offline_env_path/docker_compose/docker-compose"
    
    # Save version info
    echo "$DOCKER_COMPOSE_VERSION" > "$offline_env_path/docker_compose/version.txt"
    echo "$arch" > "$offline_env_path/docker_compose/arch.txt"
    
    green_echo "Successfully downloaded Docker Compose ${DOCKER_COMPOSE_VERSION} for ${arch}"
}

function install_system_packages() {
    if [ -n "$SYSTEM_PACKAGES" ]; then
        yellow_echo "Downloading system packages: $SYSTEM_PACKAGES"
        # Source os-release first to get ID variable
        if [ -f /etc/os-release ]; then
            source /etc/os-release
        fi
        if [ -f /etc/redhat-release ] || [ -f /etc/kylin-release ] || [ "$ID" = "openEuler" ]; then
            # TODO Confirm
            if [ "$ID" = "centos" ] && [ "$VERSION_ID" = "7" ];then
                config_yum
            fi
            yellow_echo "$PKG_MGR updating"
            $PKG_MGR update -q -y
            if [ "$ID" = "centos" ] && [ "$VERSION_ID" = "7" ];then
                $PKG_MGR install -q -y yum-utils
            fi
            $PKG_MGR install -q -y wget gcc gcc-c++
            for pkg in "${formated_system_packages[@]}";
            do
                if [[ "$pkg" == "bpftrace" ]] && ([ "$ID" = "centos" ] || [ "$ID" = "openEuler" ]); then
                    download_bpftrace_binary "CentOS/RHEL/openEuler"
                    continue
                else
                    $PKG_MGR install -q -y dnf-plugins-core
                    # Escape special regex characters in package name for grep
                    escaped_pkg=$(echo "$pkg" | sed 's/[+]/\\&/g')
                    pkg_name=$(yum provides "$pkg" 2>/dev/null | grep -E "^(|[0-9]+:)[^/]*${escaped_pkg}-" | head -1 | awk '{print $1}')
                    format_name=$(echo "$pkg_name" | sed -E 's/^[0-9]+://; s/\.[^.]+$//')
                    
                    # If format_name is empty, try to use the original package name
                    if [ -z "$format_name" ]; then
                        yellow_echo "Warning: Could not resolve package name for '$pkg', trying direct download..."
                        format_name="$pkg"
                    fi
                    
                    yellow_echo "Downloading offline pkgs......"
                    if [ -f /etc/kylin-release ];then
                        repotrack --destdir "$system_packages_dir" "$format_name"
                    elif [ "$ID" = "openEuler" ];then
                        repotrack --downloaddir="$system_packages_dir" --resolve --alldeps "$format_name"
                    else
                        repotrack -p "$system_packages_dir" "$format_name"
                    fi
                fi
            done
            # # Why not use the following two methods?
            # * yumdownloader or downloadonly will not download already installed dependencies.
            # yum install -y $formated_system_packages --downloadonly --downloaddir="$system_packages_dir" --setopt=installonly=False
            # * repotrack must match the exact package name.
            # repotrack -p "$system_packages_dir" $formated_system_packages
        elif [ -f /etc/debian_version ]; then
            # TODO
            # apt-get install --download-only -y $formated_system_packages -o Dir::Cache::archives="$system_packages_dir"
            yellow_echo "$PKG_MGR updating"
            $PKG_MGR update -qq -y
            $PKG_MGR install -qq -y apt-offline wget curl openssh-client apt-rdepends build-essential
            
            # Use temp files in system_packages_dir for better organization
            raw_deps_file="$system_packages_dir/raw_deps.txt"
            dependencies_file="$system_packages_dir/dependencies.txt"
            
            if ! apt-rdepends "${formated_system_packages[@]}" | grep -v "^ " > "$raw_deps_file"; then
                red_echo "Failed to resolve dependencies with apt-rdepends"
                exit 1
            fi
            # echo $(cat raw_deps.txt) | xargs -n 5 apt-cache policy | awk '
            #     /^[^ ]/ { pkg=$0 }
            #     /Candidate:/ && $2 == "(none)" { print pkg >> dependencies.txt }
            # '
            cat "$raw_deps_file" | tr '\n' ' ' | xargs -n 20 apt-cache policy | awk -v depfile="$dependencies_file" '
                /^[^ ]/ {
                    current_pkg = $0;
                    sub(/:$/, "", current_pkg)
                }
                /Candidate:/ && $2 != "(none)" {
                    print current_pkg >> depfile
                }
            '
            chown -R _apt:root "$system_packages_dir"
            chmod -R 700 "$system_packages_dir"
            cd "$system_packages_dir" || exit
            yellow_echo "Downloading offline pkgs......"
            if ! apt-get download $(cat "$dependencies_file"); then
                red_echo "Failed to download packages with apt-get"
                exit 1
            fi
        elif [ -f /etc/SuSE-release ] || [ "$OS_ID" = "sles" ] || [ "$OS_ID" = "opensuse-leap" ] || [ "$OS_ID" = "suse" ]; then
            # SUSE/openSUSE systems using zypper
            yellow_echo "$PKG_MGR updating"
            $PKG_MGR refresh
            $PKG_MGR install -y wget curl gcc gcc-c++
            for pkg in "${formated_system_packages[@]}";
            do
                if [[ "$pkg" == "bpftrace" ]] && [ "$OS_ID" = "sles" ]; then
                    download_bpftrace_binary "SUSE/SLES"
                    continue
                else
                    yellow_echo "Downloading offline pkgs for $pkg......"
                    mkdir -p "$system_packages_dir"
                    temp_cache_dir="$system_packages_dir/temp_cache"
                    mkdir -p "$temp_cache_dir"
                    cd "$system_packages_dir" || exit
                    # Get complete dependency list using dry-run
                    yellow_echo "Resolving dependencies for $pkg..."
                    dep_list_file="$temp_cache_dir/dep_list.txt"

                    # Extract package names from dry-run output (handle both singular and plural cases)
                    $PKG_MGR --non-interactive install --dry-run "$pkg" 2>/dev/null | \
                        awk '/The following.*NEW package.*going to be installed:/{flag=1; next}
                             /^[[:space:]]*$/{if(flag) flag=0}
                             flag && /^[[:space:]]*[a-zA-Z0-9]/{
                                 gsub(/^[[:space:]]+/, ""); gsub(/[[:space:]]+$/, "");
                                 split($0, pkgs, /[[:space:]]+/);
                                 for(i in pkgs) {
                                     if(pkgs[i] && pkgs[i] !~ /^[[:space:]]*$/) print pkgs[i]
                                 }
                             }' > "$dep_list_file"

                    # If no packages found, add the original package
                    if [ ! -s "$dep_list_file" ]; then
                        echo "$pkg" > "$dep_list_file"
                    fi

                    # Download each package with dependencies
                    yellow_echo "Downloading packages: $(tr '\n' ' ' < "$dep_list_file")"
                    while IFS= read -r pkg_name; do
                        if [ -n "$pkg_name" ]; then
                            $PKG_MGR --non-interactive --no-gpg-checks --pkg-cache-dir="$temp_cache_dir" download "$pkg_name" 2>/dev/null || true
                        fi
                    done < "$dep_list_file"

                    # Also try install --download-only as backup
                    $PKG_MGR --non-interactive --no-gpg-checks --pkg-cache-dir="$temp_cache_dir" install --download-only "$pkg" 2>/dev/null || true
                    # Move all RPM files to the main system_packages directory
                    find "$temp_cache_dir" -name "*.rpm" -exec mv {} "$system_packages_dir/" \;
                    # Clean up temp cache directory structure
                    rm -rf "$temp_cache_dir"
                fi
            done
            # cat raw_deps.txt | tr '\n' ' ' | xargs -n 20 apt-cache policy | awk '
            #     /^[^ ]/ { current_pkg = $0 }
            #     /Candidate:/ && $2 = "(none)" {
            #         print current_pkg >> "dependencies.txt"
            #     }
            # '
            # cat raw_deps.txt | tr '\n' ' ' | xargs -n 20 apt-cache policy | awk '
            #     /^[^ ]/ { current_pkg = $0 }
            #     /Candidate:/ && $2 != "(none)" {
            #         print current_pkg
            #     }
            # '
            # for pkg in $(cat raw_deps.txt); do
            #     candidate=$(apt-cache policy $pkg | grep -i "Candidate" | awk '{print $2}')
            #     if [ "$candidate" != "(none)" ]; then
            #         echo "$pkg" >> dependencies.txt
            #     fi
            # done
            # valid_deps=$(while read pkg; do
            #     if apt-cache policy "$pkg" | grep Candidate | grep none  > /dev/null 2>&1; then
            #         echo "[Warning]: invalid pkg $pkg" >&2
            #     else
            #         echo "$pkg"
            #     fi
            # done < raw_deps.txt)

            # echo "$valid_deps" | sort -u > dependencies.txt
            # apt-offline set --update $system_packages_dir/download_list.sig --install-packages $(cat dependencies.txt)
            # apt-offline get $system_packages_dir/download_list.sig --bundle $tar_file
            # apt-offline get $system_packages_dir/download_list.sig -d $system_packages_dir
        else
            red_echo "Unsupported Linux distribution.. Please install the packages manually."
            exit 1
        fi
    else
        red_echo "No system packages to install."
    fi
}

function build_tdgpt_venvs() {
    if [ "$TDGPT" != "true" ]; then
        return 0
    fi

    # Base directory for TDgpt venvs (configurable via TDGPT_BASE_DIR)
    local tdgpt_base_dir="$TDGPT_BASE_DIR"
    mkdir -p "$tdgpt_base_dir"

    install_uv_cached

    # Determine Python version
    local python_ver="${PYTHON_VERSION:-3.10}"
    yellow_echo "Using Python version: $python_ver"
    uv python install "$python_ver"

    # --------------------------------------------------
    # Step 1: Always build the main venv (mirrors install_tdgpt.sh install_anode_venv)
    #   requirements_ess.txt includes -r requirements_docker.txt (basic deps),
    #   plus transformers==4.40.0, torch==2.3.1+cpu, tensorflow-cpu
    # --------------------------------------------------

    # Determine requirements file location: download from GitHub tag or use local fallback
    local req_dir
    if [ -n "$TDENGINE_TSDB_VER" ]; then
        req_dir=$(mktemp -d)
        local tdengine_tag="ver-${TDENGINE_TSDB_VER}"
        local base_url="https://raw.githubusercontent.com/taosdata/TDengine/${tdengine_tag}/tools/tdgpt"
        yellow_echo "Downloading requirements files from TDengine version: ${TDENGINE_TSDB_VER} (tag: ${tdengine_tag})"
        yellow_echo "  URL: ${base_url}/requirements_ess.txt"

        # Download requirements_docker.txt first (referenced by requirements_ess.txt via -r)
        if ! curl -fsSL "${base_url}/requirements_docker.txt" -o "${req_dir}/requirements_docker.txt"; then
            red_echo "Failed to download requirements_docker.txt from tag ver-${TDENGINE_TSDB_VER}"
            rm -rf "$req_dir"
            exit 1
        fi
        # Download requirements_ess.txt
        if ! curl -fsSL "${base_url}/requirements_ess.txt" -o "${req_dir}/requirements_ess.txt"; then
            red_echo "Failed to download requirements_ess.txt from tag ver-${TDENGINE_TSDB_VER}"
            rm -rf "$req_dir"
            exit 1
        fi
        green_echo "Successfully downloaded requirements files from tag ver-${TDENGINE_TSDB_VER}"
    else
        # Fallback to local files in script directory
        req_dir="$script_dir"
        if [ ! -f "$req_dir/requirements_ess.txt" ]; then
            red_echo "Local requirements_ess.txt not found and --tdengine-tsdb-ver not specified."
            red_echo "Please specify --tdengine-tsdb-ver=<ver> (e.g. --tdengine-tsdb-ver=3.4.0.8) to download from GitHub."
            exit 1
        fi
        yellow_echo "Using local requirements files from: $req_dir"
    fi

    yellow_echo "Building main venv for tdtsfm/timemoe (via requirements_ess.txt)..."
    local main_venv_path="${tdgpt_base_dir}/venv"
    uv venv --python "$python_ver" "$main_venv_path" --seed --clear
    source "$main_venv_path/bin/activate"

    # Strip all pytorch.org index/find-links directives from requirements files
    # so that our pytorch_index_args (aliyun CDN mirror) are the sole source for
    # torch wheels. Apply to both known files (requirements_ess.txt includes -r
    # requirements_docker.txt, so both need to be cleaned).
    # Note: avoid 'find' — it may not be on PATH in minimal containers.
    for _req_file in "${req_dir}/requirements_ess.txt" "${req_dir}/requirements_docker.txt"; do
        [ -f "$_req_file" ] && sed -i '/pytorch\.org/d' "$_req_file"
    done

    uv pip install -r "${req_dir}/requirements_ess.txt" \
        "${pip_index_args[@]}" "${pytorch_index_args[@]}"
    deactivate
    mv "$main_venv_path" "${py_venv_dir}/venv"
    green_echo "Main venv built successfully"

    # --------------------------------------------------
    # Step 2: Build extra model venvs only when --tdgpt-all is specified
    #         (mirrors install_tdgpt.sh install_extra_venvs called under -a flag)
    # --------------------------------------------------
    if [ "$TDGPT_ALL" != "true" ]; then
        yellow_echo "Skipping extra model venvs (use --tdgpt-all to build timesfm/moirai/chronos/moment)"
    else
        yellow_echo "Building extra model venvs (timesfm/moirai/chronos/moment)..."

        # timesfm venv
        yellow_echo "Building timesfm venv..."
        local venv_path="${tdgpt_base_dir}/timesfm_venv"
        uv venv --python "$python_ver" "$venv_path" --seed --clear
        source "$venv_path/bin/activate"
        uv pip install torch==2.3.1+cpu jax timesfm flask==3.0.3 \
            "${pip_index_args[@]}" "${pytorch_index_args[@]}"
        deactivate
        mv "$venv_path" "${py_venv_dir}/timesfm_venv"
        green_echo "timesfm venv built successfully"

        # moirai venv
        yellow_echo "Building moirai venv..."
        venv_path="${tdgpt_base_dir}/moirai_venv"
        uv venv --python "$python_ver" "$venv_path" --seed --clear
        source "$venv_path/bin/activate"
        uv pip install torch==2.3.1+cpu uni2ts flask \
            "${pip_index_args[@]}" "${pytorch_index_args[@]}"
        deactivate
        mv "$venv_path" "${py_venv_dir}/moirai_venv"
        green_echo "moirai venv built successfully"

        # chronos venv
        yellow_echo "Building chronos venv..."
        venv_path="${tdgpt_base_dir}/chronos_venv"
        uv venv --python "$python_ver" "$venv_path" --seed --clear
        source "$venv_path/bin/activate"
        uv pip install torch==2.3.1+cpu chronos-forecasting flask \
            "${pip_index_args[@]}" "${pytorch_index_args[@]}"
        deactivate
        mv "$venv_path" "${py_venv_dir}/chronos_venv"
        green_echo "chronos venv built successfully"

        # momentfm venv
        yellow_echo "Building momentfm venv..."
        venv_path="${tdgpt_base_dir}/momentfm_venv"
        uv venv --python "$python_ver" "$venv_path" --seed --clear
        source "$venv_path/bin/activate"
        uv pip install torch==2.3.1+cpu transformers==4.33.3 numpy==1.25.2 \
            matplotlib pandas==1.5 scikit-learn flask==3.0.3 momentfm \
            "${pip_index_args[@]}" "${pytorch_index_args[@]}"
        deactivate
        mv "$venv_path" "${py_venv_dir}/momentfm_venv"
        green_echo "momentfm venv built successfully"
    fi

    # Clean up downloaded requirements temp dir
    if [ -n "$TDENGINE_TSDB_VER" ] && [ -d "$req_dir" ] && [[ "$req_dir" == /tmp/* ]]; then
        rm -rf "$req_dir"
    fi

    # Copy .local directory for uv
    cp -r "$HOME/.local" "$py_venv_dir/"

    green_echo "TDgpt venvs built successfully"
}

function build_idmp_venvs() {
    if [ "$IDMP" != "true" ] || [ -z "$IDMP_VER" ]; then
        return 0
    fi

    # Validate GH_TOKEN is provided (TDasset is a private repository)
    if [ -z "$GH_TOKEN" ]; then
        red_echo "ERROR: --gh-token is required when using --idmp-ver (TDasset is a private repository)."
        red_echo "Usage: --idmp-ver=<ver> --gh-token=<your_github_token>"
        exit 1
    fi

    yellow_echo "Building IDMP Python venv from TDasset requirements..."

    install_uv_cached

    # Determine Python version
    local python_ver="${PYTHON_VERSION:-3.10}"
    yellow_echo "Using Python version: $python_ver"
    uv python install "$python_ver"

    # Download requirements.txt from TDasset private repo
    local req_dir
    req_dir=$(mktemp -d)
    local idmp_tag="ver-${IDMP_VER}"
    local raw_url="https://raw.githubusercontent.com/taosdata/TDasset/${idmp_tag}/ai-server/requirements.txt"
    yellow_echo "Downloading IDMP requirements from TDasset version: ${IDMP_VER} (tag: ${idmp_tag})"
    yellow_echo "  URL: ${raw_url}"

    if ! curl -fsSL -H "Authorization: token ${GH_TOKEN}" "${raw_url}" -o "${req_dir}/requirements.txt"; then
        red_echo "Failed to download requirements.txt from TDasset tag '${idmp_tag}'"
        red_echo "Please check: 1) --idmp-ver is a valid version (e.g. 1.0.12.10)  2) --gh-token has repo access"
        rm -rf "$req_dir"
        exit 1
    fi
    green_echo "Successfully downloaded requirements.txt from TDasset ${idmp_tag}"

    # Append extra packages from --python-packages if specified
    if [ -n "$PYTHON_PACKAGES" ]; then
        yellow_echo "Appending extra packages from --python-packages..."
        IFS=',' read -ra extra_pkgs <<< "$PYTHON_PACKAGES"
        for pkg in "${extra_pkgs[@]}"; do
            echo "$pkg" >> "${req_dir}/requirements.txt"
            yellow_echo "  + $pkg"
        done
    fi

    # Create venv and install packages
    local idmp_venv_path="${IDMP_VENV_DIR}"
    mkdir -p "$idmp_venv_path"
    uv venv --python "$python_ver" "$idmp_venv_path" --seed --clear
    source "$idmp_venv_path/bin/activate"

    yellow_echo "Installing IDMP packages from requirements.txt..."
    uv pip install -r "${req_dir}/requirements.txt" "${pip_index_args[@]}"
    deactivate

    # Move venv to offline package
    mv "$idmp_venv_path" "${py_venv_dir}/idmp_venv"
    green_echo "IDMP venv built successfully"

    # Clean up temp dir
    rm -rf "$req_dir"

    # Copy .local directory for uv
    cp -r "$HOME/.local" "$py_venv_dir/"

    green_echo "IDMP venvs built successfully"
}

function install_python_packages() {
    if [ -n "$PYTHON_PACKAGES" ] || [ -n "$PYTHON_REQUIREMENTS" ]; then
        # TDgpt mode: all venvs (main + model-specific) are fully managed by build_tdgpt_venvs
        if [ "$TDGPT" == "true" ]; then
            yellow_echo "TDgpt mode: Python venvs are managed by build_tdgpt_venvs, skipping install_python_packages."
            return 0
        fi
        # IDMP mode: venv is managed by build_idmp_venvs when --idmp-ver is set
        if [ "$IDMP" == "true" ] && [ -n "$IDMP_VER" ]; then
            yellow_echo "IDMP mode: Python venv is managed by build_idmp_venvs, skipping install_python_packages."
            return 0
        fi
        if [ -n "$PYTHON_REQUIREMENTS" ]; then
            yellow_echo "Installing uv and Python $PYTHON_VERSION from requirements file: $PYTHON_REQUIREMENTS"
        else
            yellow_echo "Installing uv and Python $PYTHON_VERSION and packages: $PYTHON_PACKAGES"
        fi

        # Install uv with setup_env.sh
        install_uv_cached

        if ! command -v uv &>/dev/null; then
            red_echo "Error: uv not found after installation. $HOME/.local/bin/env may be missing."
            exit 1
        fi

        if [ "$TDGPT" == "true" ];then
            python_venv_dir="${TDGPT_BASE_DIR}/venv"
            # Export TDGPT_MODELS for install.sh to use
            export TDGPT_MODELS
        elif [ "$IDMP" == "true" ];then
            python_venv_dir="$IDMP_VENV_DIR"
        else
            python_venv_dir="$HOME/.venv$PYTHON_VERSION"
        fi
        mkdir -p "$python_venv_dir"


        yellow_echo "Installing Python $PYTHON_VERSION using uv..."
        uv python install "$PYTHON_VERSION"
        uv venv --python "$PYTHON_VERSION" "$python_venv_dir" --seed --clear

        yellow_echo "Installing Python packages..."
        source "$python_venv_dir"/bin/activate
        
        if [ -n "$PYTHON_REQUIREMENTS" ]; then
            # Handle requirements file
            local req_file="$py_venv_dir/requirements.txt"
            
            # Convert GitHub blob URL to raw URL if needed
            local download_url="$PYTHON_REQUIREMENTS"
            if [[ "$download_url" == *"github.com"* ]] && [[ "$download_url" == *"/blob/"* ]]; then
                download_url=$(echo "$download_url" | sed 's|github.com|raw.githubusercontent.com|' | sed 's|/blob/|/|')
                yellow_echo "Converted GitHub URL to raw: $download_url"
            fi
            
            # Download or copy requirements file
            if [[ "$download_url" =~ ^https?:// ]]; then
                yellow_echo "Downloading requirements file from: $download_url"
                if ! curl -fsSL "$download_url" -o "$req_file"; then
                    red_echo "Failed to download requirements file"
                    exit 1
                fi
            elif [ -f "$download_url" ]; then
                yellow_echo "Using local requirements file: $download_url"
                cp "$download_url" "$req_file"
            else
                red_echo "Requirements file not found: $download_url"
                exit 1
            fi
            
            # Parse and install packages from requirements.txt
            yellow_echo "Installing packages from requirements.txt..."
            local current_index="${pip_index_args[*]}"
            local current_find_links=""
            
            # Install packages line by line, respecting index-url changes
            while IFS= read -r line || [ -n "$line" ]; do
                # Skip empty lines and comments
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                
                # Handle --find-links
                if [[ "$line" =~ ^--find-links[[:space:]]+(.*) ]] || [[ "$line" =~ ^--find-links=(.*) ]]; then
                    find_links="${BASH_REMATCH[1]}"
                    [[ -z "$find_links" ]] && find_links=$(echo "$line" | awk '{print $2}')
                    current_find_links=" --find-links $find_links"
                    yellow_echo "Switching to --find-links: $find_links"
                    continue
                fi
                
                # Handle --index-url (switch active index)
                if [[ "$line" =~ ^--index-url[[:space:]]+(.*) ]] || [[ "$line" =~ ^--index-url=(.*) ]]; then
                    index_url="${BASH_REMATCH[1]}"
                    [[ -z "$index_url" ]] && index_url=$(echo "$line" | awk '{print $2}')
                    current_index="-i $index_url"
                    current_find_links=""  # Clear find-links when switching index
                    yellow_echo "Switching to --index-url: $index_url"
                    continue
                fi
                
                # Skip other pip options
                [[ "$line" =~ ^-- ]] && continue
                
                # Install package with current active index/find-links
                echo "Installing: $line"
                uv pip install $current_find_links $current_index "$line"
            done < "$req_file"
        else
            # Original comma-separated packages logic
            IFS=',' read -ra pkg_array <<< "$PYTHON_PACKAGES"
            for pkg in "${pkg_array[@]}"
            do
                echo "installing: $pkg"
                if [[ $pkg == *"--index-url"* ]]; then
                    uv pip install "$pkg"
                else
                    uv pip install "$pkg" "${pip_index_args[@]}"
                fi
            done
        fi
        uv pip install --upgrade pip

        yellow_echo "Copying the installed environment to $py_venv_dir..."
        cp -r "$python_venv_dir" "$py_venv_dir"
        cp -r "$HOME/.local" "$py_venv_dir"
    else
        yellow_echo "No Python packages to install."
    fi
}

function summary() {
    cd "$parent_dir" || exit
    cp -f "$script_dir"/install.sh "$offline_env_dir"
    cp /etc/os-release "$offline_env_path"/os-release

    if [ "$TDGPT" == "true" ]; then
        if [ "$TDGPT_ALL" == "true" ]; then
            green_echo "TDgpt: built all model venvs (main + timesfm/moirai/chronos/momentfm)"
        else
            green_echo "TDgpt: built main venv only (tdtsfm/timemoe); use --tdgpt-all to build extra model venvs"
        fi
    fi

    tar zcf "$offline_env_dir.tar.gz" "$offline_env_dir"
    mv "$offline_env_dir.tar.gz" "$offline_env_path"
    green_echo "Offline env completed, please check $offline_env_path/$offline_env_dir.tar.gz"

    if [[ ${#BUILD_NOTES[@]} -gt 0 ]]; then
        echo ""
        yellow_echo "========== POST-BUILD NOTES =========="
        for note in "${BUILD_NOTES[@]}"; do
            yellow_echo "$note"
        done
        yellow_echo "======================================"
    fi
}

function build_pkgs() {
    install_system_packages
    install_python_packages
    build_tdgpt_venvs
    build_idmp_venvs
    download_docker
    download_docker_compose
    download_java
    download_idmp_packages
    summary
}

function check_python_pkgs() {
    # Python packages verification
    if [[ -n "$PYTHON_PACKAGES" ]]; then
        cp -r "$HOME"/"$offline_env_dir"/py_venv/.[!.]* "$HOME"
        source "$HOME/.venv$PYTHON_VERSION"/bin/activate
        failed_python_pkgs=()
        for pkg in $formated_python_packages;
        do
            if ! pip show "$pkg" &>/dev/null;then
                failed_python_pkgs+=("$pkg")
            fi
        done

        if [ ${#failed_python_pkgs[@]} -gt 0 ]; then
            result=$(printf "%s," "${failed_python_pkgs[@]}" | sed 's/,$//')
            red_echo "Failed verification for python package: $result"
            exit 1
        else
            green_echo "All python packages verified successfully"
        fi
    fi
}

function install_offline_pkgs() {
    yellow_echo "Installing offline pkgs"
    if [ -f /etc/redhat-release ] || [ -f /etc/kylin-release ] || [ "$OS_ID" = "openEuler" ]; then
        for i in "$HOME/$offline_env_dir/system_packages/"*.rpm;
        do
            rpm -ivh --nodeps "$i"  >/dev/null 2>&1
        done
        # rpm -Uvh --replacepkgs --nodeps "$HOME"/"$offline_env_dir"/system_packages/*.rpm >/dev/null 2>&1
#         local_repo_dir=/var/local-repo
#         repodata_dir="$local_repo_dir"/repodata
#         mkdir -p "$local_repo_dir"
#         mkdir -p "$repodata_dir"
#         cp -f "$HOME"/"$offline_env_dir"/system_packages/*.rpm "$local_repo_dir"
#         tee /etc/yum.repos.d/local.repo <<EOF
# [local]
# name=Local Repository
# baseurl=file:///var/local-repo
# enabled=1
# gpgcheck=0
# EOF
#         tee $repodata_dir/repomd.xml <<EOF
# <?xml version="1.0" encoding="UTF-8"?>
# <repomd xmlns="http://linux.duke.edu/metadata/repo">
#   <revision>$(date +%s)</revision>
# </repomd>
# EOF

#         yum clean all
#         for pkg in $formated_system_packages;
#         do
#             if printf '%s\n' "${BINARY_TOOLS[@]}" | grep -q -x "$pkg"; then
#                 continue
#             else
#                 yum install -y "$pkg"
#             fi
#         done
    elif [ -f /etc/debian_version ]; then
        DEBIAN_FRONTEND=noninteractive dpkg -i "$HOME"/"$offline_env_dir"/system_packages/*.deb >/dev/null 2>&1
    elif [ -f /etc/SuSE-release ] || [ "$OS_ID" = "sles" ] || [ "$OS_ID" = "opensuse-leap" ] || [ "$OS_ID" = "suse" ]; then
        # Install RPM packages on SUSE systems
        for i in "$HOME/$offline_env_dir/system_packages/"*.rpm;
        do
            rpm -ivh --nodeps "$i" >/dev/null 2>&1
        done
    else
        red_echo "Unsupported Linux distribution.. Please install the packages manually."
    fi
}

function install_binary_tools() {
    if [ -d "$HOME/$offline_env_dir/binary_tools" ];then
        yellow_echo "Installing binary_tools ..."
        binary_dir=/usr/bin
        for tool in "$HOME/$offline_env_dir/binary_tools"/*; do
            [ -e "$tool" ] || continue
            tool_name=$(basename "$tool")
            if [ -f "$binary_dir/$tool_name" ];then
                yellow_echo "Backing up existing $tool_name"
                mv "$binary_dir/$tool_name" "$binary_dir/$tool_name.bak"
            fi
            cp -rf "$tool" "$binary_dir"
            chmod +x "$binary_dir/$tool_name"
        done
        green_echo "Binary tools installed successfully"
    fi
}

function check_system_pkgs() {
    # System packages verification
    if [[ -n "$SYSTEM_PACKAGES" ]]; then
        failed_system_pkgs=()
        for pkg in "${formated_system_packages[@]}";
        do
            if printf '%s\n' "${BINARY_TOOLS[@]}" | grep -q -x "$pkg"; then
                if ! command -v "$pkg" >/dev/null 2>&1; then
                    failed_system_pkgs+=("$pkg")
                    red_echo "Failed verification for system package: $pkg"
                fi
            else
                if ! $PKG_CONFIRM "$pkg" &>/dev/null;then
                    failed_system_pkgs+=("$pkg")
                    red_echo "Failed verification for system package: $pkg"
                fi
            fi
        done

        if [ ${#failed_system_pkgs[@]} -gt 0 ]; then
            result=$(printf "%s," "${failed_system_pkgs[@]}" | sed 's/,$//')
            red_echo "Failed verification for system package: $result"
            exit 1
        else
            green_echo "All system packages verified successfully"
        fi
    fi
}

function run_test() {
    yellow_echo "[TEST] Starting test suite execution"
    yellow_echo "[TEST] OS type: $OS_ID $OS_VERSION"
    yellow_echo "[TEST] System packages: $SYSTEM_PACKAGES"
    yellow_echo "[TEST] Python version: $PYTHON_VERSION"
    yellow_echo "[TEST] Python dependencies: $PYTHON_PACKAGES"
    cd "$offline_env_path" || exit
    tar -xf "$offline_env_dir.tar.gz" -C $HOME
    install_offline_pkgs
    install_binary_tools
    check_system_pkgs
    check_python_pkgs
}

init

case "$MODE" in
    "build")
        yellow_echo "[INFO] Start Package Builder"
        build_pkgs
        ;;
    "test")
        yellow_echo "[INFO] Start tests"
        run_test
        ;;
    *)
        red_echo "[ERROR] unknown mode: $MODE"
        exit 1
        ;;
esac