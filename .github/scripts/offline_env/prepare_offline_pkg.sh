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
DOCKER_VERSION="latest"
DOCKER_COMPOSE_VERSION="latest"
INSTALL_DOCKER=""
INSTALL_DOCKER_COMPOSE=""
JAVA_VERSION="21"
INSTALL_JAVA=""
IDMP=""
CACHE_DIR="/tmp/taos-packages"

function show_usage() {
    echo "Usage:"
    echo "  Option      Mode: $0 [--build|--test] --system-packages=<pkgs> --python-version=<ver> --python-packages=<pkgs> --pkg-label=<label>"
    echo "  Docker Options: [--install-docker] [--docker-version=<version>] [--install-docker-compose] [--docker-compose-version=<version>]"
    echo "  Java Options: [--install-java] [--java-version=<version>] (default: 21, supported: 8,11,17,21,23)"
    echo "  Python Options: [--python-requirements=<url_or_path>] (alternative to --python-packages)"
    echo "  Special Options: [--tdgpt=<true|false>] [--idmp=<true|false>]"
    echo "Example:"
    echo "  $0 --build --system-packages=vim,ntp --python-version=3.10 --python-packages=fabric2,requests --pkg-label=1.0.20250409"
    echo "  $0 --build --python-version=3.10 --python-requirements=https://github.com/user/repo/blob/main/requirements.txt --pkg-label=test"
    echo "  $0 --build --install-docker --docker-version=27.5.1 --install-docker-compose --docker-compose-version=v2.40.2 --pkg-label=test"
    echo "  $0 --build --install-java --java-version=21 --pkg-label=java-test"
    echo "  $0 --build --install-java --idmp=true --pkg-label=idmp-env"
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
        --tdgpt=*)
            TDGPT="${1#*=}"
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
    if [[ -z "$SYSTEM_PACKAGES" && -z "$PYTHON_PACKAGES" && -z "$PYTHON_REQUIREMENTS" && -z "$INSTALL_DOCKER" && -z "$INSTALL_DOCKER_COMPOSE" && -z "$INSTALL_JAVA" && -z "$IDMP" ]]; then
        package_error="At least one of **SYSTEM_PACKAGES**, **PYTHON_PACKAGES**, **PYTHON_REQUIREMENTS**, **INSTALL_DOCKER**, **INSTALL_DOCKER_COMPOSE**, **INSTALL_JAVA**, or **IDMP** must be provided."
    fi
    
    # Check if both python-packages and python-requirements are specified
    if [[ -n "$PYTHON_PACKAGES" && -n "$PYTHON_REQUIREMENTS" ]]; then
        package_error="Cannot specify both **PYTHON_PACKAGES** and **PYTHON_REQUIREMENTS** at the same time. Please use only one."
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
                    # Extract both SP version and code name from /etc/.productinfo
                    # Example line: "release V10 (SP3) /(Lance)-x86_64-Build23.02/20230324"
                    # Extract: SP3-Lance
                    if [ -f /etc/.productinfo ]; then
                        SUB_VERSION="$(sed -n '2p' /etc/.productinfo | sed -n 's/.*(\(SP[0-9]\+\)).*\/(\([^)]\+\)).*/\1-\2/p')-"
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

    formated_system_packages=$(echo "$SYSTEM_PACKAGES" | tr ',' ' ')
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
    offline_env_dir="offline-pkgs-$PKG_LABEL-$OS_ID-$OS_VERSION-${SUB_VERSION}$(arch)"
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
        if [[ -n "$PYTHON_PACKAGES" ]] || [[ -n "$PYTHON_REQUIREMENTS" ]]; then
            mkdir -p "$py_venv_dir"
        fi
    fi
}


function config_yum() {
    # Define the line to be added
    curl -o "$script_dir"/setup_env.sh https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh
    chmod +x "$script_dir"/setup_env.sh
    "$script_dir"/setup_env.sh replace_sources
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
    
    local BPFTRACE_URL="https://github.com/bpftrace/bpftrace/releases/download/v0.23.2/bpftrace"
    mkdir -p "$offline_env_path/binary_tools"
    
    if ! wget -q "$BPFTRACE_URL" -O "$offline_env_path/binary_tools/bpftrace"; then
        red_echo "Failed to download bpftrace binary"
        exit 1
    fi
    
    chmod +x "$offline_env_path/binary_tools/bpftrace"
    green_echo "Successfully downloaded bpftrace binary for ${os_type}"
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
    
    # Check if file exists in cache
    if [ -f "$cached_file" ]; then
        yellow_echo "Using cached Java JRE from: $cached_file"
    else
        yellow_echo "Downloading from: $download_url"
        if ! curl -fsSL "$download_url" -o "$cached_file"; then
            red_echo "Failed to download Java JRE ${JAVA_VERSION}"
            exit 1
        fi
        green_echo "Downloaded to cache: $cached_file"
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
        
        echo "${expected_sha256}  $cached_file" | sha256sum -c - || {
            red_echo "SHA256 checksum verification failed!"
            exit 1
        }
        green_echo "SHA256 checksum verified successfully"
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
        DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
        if [ -z "$DOCKER_COMPOSE_VERSION" ]; then
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
            for pkg in $formated_system_packages;
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
            
            apt-rdepends $formated_system_packages | grep -v "^ " > "$raw_deps_file"
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
            apt-get download $(cat "$dependencies_file")
        elif [ -f /etc/SuSE-release ] || [ "$OS_ID" = "sles" ] || [ "$OS_ID" = "opensuse-leap" ] || [ "$OS_ID" = "suse" ]; then
            # SUSE/openSUSE systems using zypper
            yellow_echo "$PKG_MGR updating"
            $PKG_MGR refresh
            $PKG_MGR install -y wget curl gcc gcc-c++
            for pkg in $formated_system_packages;
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

function install_python_packages() {
    if [ -n "$PYTHON_PACKAGES" ] || [ -n "$PYTHON_REQUIREMENTS" ]; then
        if [ -n "$PYTHON_REQUIREMENTS" ]; then
            yellow_echo "Installing uv and Python $PYTHON_VERSION from requirements file: $PYTHON_REQUIREMENTS"
        else
            yellow_echo "Installing uv and Python $PYTHON_VERSION and packages: $PYTHON_PACKAGES"
        fi

        # Install uv with setup_env.sh
        if ! command -v uv &> /dev/null; then
            if [ -f /etc/kylin-release ] || [ "$OS_ID" = "openEuler" ]; then
                curl -LsSf https://astral.sh/uv/install.sh | sh
            else
                curl -o "$script_dir"/setup_env.sh https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh
                chmod +x "$script_dir"/setup_env.sh
                "$script_dir"/setup_env.sh install_uv
            fi
        fi

        if [ -f "$HOME/.local/bin/env" ]; then
            source "$HOME/.local/bin/env"
        else
            red_echo "Error: $HOME/.local/bin/env not found."
            exit 1
        fi

        if [ "$TDGPT" == "true" ];then
            python_venv_dir="/var/lib/taos/taosanode/venv"
        elif [ "$IDMP" == "true" ];then
            python_venv_dir="/usr/local/taos/idmp/venv"
        else
            python_venv_dir="$HOME/.venv$PYTHON_VERSION"
        fi
        mkdir -p "$python_venv_dir"


        yellow_echo "Installing Python $PYTHON_VERSION using uv..."
        uv python install "$PYTHON_VERSION"
        uv venv --python "$PYTHON_VERSION" "$python_venv_dir"

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
            local current_index="-i https://pypi.tuna.tsinghua.edu.cn/simple"
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
                    uv pip install $pkg
                else
                    uv pip install $pkg -i https://pypi.tuna.tsinghua.edu.cn/simple
                fi
            done
        fi
        # uv pip install $formated_python_packages -i https://pypi.tuna.tsinghua.edu.cn/simple
        if [ "$TDGPT" == "true" ];then
            uv pip install numpy==1.26.4 -i https://pypi.tuna.tsinghua.edu.cn/simple
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
    tar zcf "$offline_env_dir.tar.gz" "$offline_env_dir"
    mv "$offline_env_dir.tar.gz" "$offline_env_path"
    green_echo "Offline env completed, please check $offline_env_path/$offline_env_dir.tar.gz"
    # cp -r .[!.]* ~
    # rpm -ivh --nodeps --force *.rpm
}

function build_pkgs() {
    install_system_packages
    install_python_packages
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
            tool_name=$(basename "$tool")
            if [ -f "$binary_dir/$tool_name" ];then
                mv "$binary_dir/$tool_name" "$binary_dir/$tool_name.bak"
            fi
            cp -rf "$tool" "$binary_dir"
        done
    fi
}

function check_system_pkgs() {
    # System packages verification
    if [[ -n "$SYSTEM_PACKAGES" ]]; then
        failed_system_pkgs=()
        for pkg in $formated_system_packages;
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