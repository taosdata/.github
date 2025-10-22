#!/bin/bash

################################################################################
# GitHub Self-Hosted Runner Management Script
# 
# This script provides a unified interface to install and remove GitHub 
# self-hosted runners using command-line arguments.
#
# Usage:
#   Install: ./manage-github-runner.sh install --owner OWNER --token TOKEN [OPTIONS]
#   Remove:  ./manage-github-runner.sh remove --owner OWNER --token TOKEN [OPTIONS]
#   Upgrade: ./manage-github-runner.sh upgrade --owner OWNER --token TOKEN [OPTIONS]
#
# Examples:
#   # Install organization-level runner
#   ./manage-github-runner.sh install --owner taosdata --token ghp_xxx
#
#   # Install batch runners
#   ./manage-github-runner.sh install --owner taosdata --token ghp_xxx \
#     --name "r1;r2;r3" --labels "gpu;cpu;test" --install-dir "/opt/r1;/opt/r2;/opt/r3"
#
#   # Remove a runner
#   ./manage-github-runner.sh remove --owner taosdata --token ghp_xxx \
#     --install-dir /opt/runner-01
#
#   # Batch remove runners
#   ./manage-github-runner.sh remove --owner taosdata --token ghp_xxx \
#     --install-dir "/opt/r1;/opt/r2;/opt/r3"
#
#   # Upgrade a runner
#   ./manage-github-runner.sh upgrade --owner taosdata --token ghp_xxx \
#     --install-dir /opt/runner-01
################################################################################

set -e  # Exit on error

################################################################################
# Color codes for output
################################################################################

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

################################################################################
# Output functions
################################################################################

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

################################################################################
# Default Configuration
################################################################################

# Command (install or remove)
COMMAND=""

# Required parameters (no defaults)
GITHUB_OWNER=""
GITHUB_TOKEN=""

# Optional parameters with defaults
GITHUB_REPO=""
RUNNER_NAME="$(hostname)"
RUNNER_LABELS=""  # System labels (self-hosted, OS, arch) are added automatically by the runner
RUNNER_GROUP=""
RUNNER_WORK_DIR="_work"
INSTALL_DIR="$HOME/actions-runner"
RUNNER_VERSION="2.329.0"
OS_TYPE="linux"
ARCH="x64"
TARGET_VERSION=""  # Empty means latest version
DISABLE_AUTO_UPDATE="true"  # Disable automatic updates by default

################################################################################
# Usage/Help function
################################################################################

show_usage() {
    cat << EOF
Usage: $0 <COMMAND> --owner OWNER --token TOKEN [OPTIONS]

Commands:
  install                Install/deploy runner(s)
  remove                 Remove/uninstall runner(s)
  upgrade                Upgrade existing runner(s)

Required Arguments:
  --owner OWNER          GitHub organization or user name
  --token TOKEN          GitHub Personal Access Token
                         Required scopes: 'admin:org' (org) or 'repo' (repo)

Optional Arguments:
  --repo REPO            Repository name (for repo-level runner)
  --name NAME            Runner name (default: hostname)
                         For multiple runners, use semicolon-separated: "runner-1;runner-2;runner-3"
  --labels LABELS        Custom labels to add (comma-separated)
                         System labels (self-hosted, OS, arch) are added automatically
                         (default: none, examples: gpu,cuda,docker)
                         For multiple runners, use semicolon-separated: "gpu,cuda;cpu,docker;test"
  --install-dir DIR      Installation directory
                         (default: \$HOME/actions-runner)
                         For multiple runners, use semicolon-separated: "/opt/r1;/opt/r2;/opt/r3"
  --group GROUP          Runner group for organization-level runners
                         (default: empty, uses GitHub default)
  --work-dir DIR         Runner work directory (default: _work)
  --version VERSION      Runner version (default: 2.329.0)
  --os OS                OS type: linux or osx (default: linux)
  --arch ARCH            Architecture: x64 or arm64 (default: x64)
  --target-version VER   Target version to upgrade to (default: latest)
  --enable-autoupdate    Enable GitHub automatic updates (default: disabled)
  -h, --help             Show this help message

Batch Deployment:
  To deploy multiple runners at once, use semicolon (;) to separate values:
  
  Example:
    $0 --owner taosdata --token ghp_xxx \\
      --name "runner-1;runner-2;runner-3" \\
      --labels "gpu,cuda;cpu,docker;test" \\
      --install-dir "/opt/r1;/opt/r2;/opt/r3"
  
  This will create 3 runners with different names, labels, and directories.
  If a parameter has fewer values than names, the last value is reused.

Environment Variables:
  GITHUB_TOKEN           Can be used instead of --token argument

User Requirements:
  Root User:             Works directly, but not recommended for production
                         (runner will run as root, security risk)
  Regular User:          Recommended for production (more secure)
                         Requires: sudo permissions for service management
                         Default install dir: \$HOME/actions-runner

Install Examples:
  # Single runner - Organization-level
  $0 install --owner taosdata --token ghp_xxx

  # Single runner - Repository-level
  $0 install --owner taosdata --repo TDengine --token ghp_xxx

  # Single runner - Custom configuration with labels
  $0 install --owner taosdata --token ghp_xxx \\
    --name gpu-runner-01 \\
    --labels gpu,cuda-12.0,nvidia \\
    --install-dir /opt/gpu-runner

  # Batch deployment - 3 runners with different configs
  $0 install --owner taosdata --token ghp_xxx \\
    --name "runner-1;runner-2;runner-3" \\
    --labels "gpu,cuda;cpu,docker;test" \\
    --install-dir "/opt/r1;/opt/r2;/opt/r3"

  # Batch deployment - 5 runners with same labels
  $0 install --owner taosdata --token ghp_xxx \\
    --name "worker-01;worker-02;worker-03;worker-04;worker-05" \\
    --labels "production,docker" \\
    --install-dir "/opt/runner-01;/opt/runner-02;/opt/runner-03;/opt/runner-04;/opt/runner-05"

Remove Examples:
  # Remove a single runner (removes from GitHub and deletes local files)
  $0 remove --owner taosdata --token ghp_xxx \\
    --install-dir /opt/runner-01

  # Batch remove - multiple runners
  $0 remove --owner taosdata --token ghp_xxx \\
    --install-dir "/opt/r1;/opt/r2;/opt/r3"

Upgrade Examples:
  # Upgrade a single runner to latest version
  $0 upgrade --owner taosdata --token ghp_xxx \\
    --install-dir /opt/runner-01

  # Upgrade to specific version
  $0 upgrade --owner taosdata --token ghp_xxx \\
    --install-dir /opt/runner-01 --target-version 2.330.0

  # Batch upgrade - multiple runners
  $0 upgrade --owner taosdata --token ghp_xxx \\
    --install-dir "/opt/r1;/opt/r2;/opt/r3"

EOF
}

################################################################################
# Parse command-line arguments
################################################################################

parse_arguments() {
    # First argument should be the command
    if [[ $# -gt 0 ]] && [[ ! "$1" =~ ^-- ]]; then
        COMMAND="$1"
        shift
    fi
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --owner)
                GITHUB_OWNER="$2"
                shift 2
                ;;
            --token)
                GITHUB_TOKEN="$2"
                shift 2
                ;;
            --repo)
                GITHUB_REPO="$2"
                shift 2
                ;;
            --name)
                RUNNER_NAME="$2"
                shift 2
                ;;
            --labels)
                RUNNER_LABELS="$2"
                shift 2
                ;;
            --group)
                RUNNER_GROUP="$2"
                shift 2
                ;;
            --work-dir)
                RUNNER_WORK_DIR="$2"
                shift 2
                ;;
            --install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            --version)
                RUNNER_VERSION="$2"
                shift 2
                ;;
            --os)
                OS_TYPE="$2"
                shift 2
                ;;
            --arch)
                ARCH="$2"
                shift 2
                ;;
            --target-version)
                TARGET_VERSION="$2"
                shift 2
                ;;
            --enable-autoupdate)
                DISABLE_AUTO_UPDATE="false"
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown argument: $1"
                echo ""
                show_usage
                exit 1
                ;;
        esac
    done
}

################################################################################
# Check sudo permissions
################################################################################

check_sudo_permission() {
    # Root user doesn't need to check sudo
    if [ "$EUID" -eq 0 ]; then
        return 0
    fi
    
    # Check if user can run sudo
    if ! sudo -n true 2>/dev/null; then
        print_warning "This script requires sudo permissions to install system services."
        print_info "Please make sure:"
        echo "  1. Your user is in the sudo group"
        echo "  2. You can run: sudo -v"
        echo ""
        print_info "Trying to authenticate with sudo..."
        if ! sudo -v; then
            print_error "Failed to get sudo permissions. Cannot continue."
            exit 1
        fi
    fi
}

################################################################################
# Validation
################################################################################

validate_parameters() {
    # Check command
    if [ -z "$COMMAND" ]; then
        print_error "Command is required. Use 'install' or 'remove'."
        echo ""
        show_usage
        exit 1
    fi
    
    if [[ "$COMMAND" != "install" && "$COMMAND" != "remove" && "$COMMAND" != "upgrade" ]]; then
        print_error "Invalid command: $COMMAND. Use 'install', 'remove', or 'upgrade'."
        echo ""
        show_usage
        exit 1
    fi
    
    # For remove command, install-dir, owner and token are required
    if [ "$COMMAND" = "remove" ]; then
        if [ -z "$INSTALL_DIR" ]; then
            print_error "For remove command, --install-dir is required and must be explicitly specified."
            echo ""
            show_usage
            exit 1
        fi
        if [ -z "$GITHUB_OWNER" ]; then
            print_error "For remove command, --owner is required."
            echo ""
            show_usage
            exit 1
        fi
        if [ -z "$GITHUB_TOKEN" ]; then
            print_error "For remove command, --token is required."
            echo ""
            show_usage
            exit 1
        fi
        return 0
    fi
    
    # For upgrade command, install-dir, owner and token are required
    if [ "$COMMAND" = "upgrade" ]; then
        if [ -z "$INSTALL_DIR" ]; then
            print_error "For upgrade command, --install-dir is required and must be explicitly specified."
            echo ""
            show_usage
            exit 1
        fi
        if [ -z "$GITHUB_OWNER" ]; then
            print_error "For upgrade command, --owner is required."
            echo ""
            show_usage
            exit 1
        fi
        if [ -z "$GITHUB_TOKEN" ]; then
            print_error "For upgrade command, --token is required."
            echo ""
            show_usage
            exit 1
        fi
        return 0
    fi
    
    # For install command, check required parameters
    if [ -z "$GITHUB_OWNER" ]; then
        print_error "GITHUB_OWNER is required for install. Use --owner argument."
        echo ""
        show_usage
        exit 1
    fi

    # Allow token from environment variable as fallback
    if [ -z "$GITHUB_TOKEN" ]; then
        if [ -n "${GH_TOKEN}" ]; then
            GITHUB_TOKEN="${GH_TOKEN}"
        else
            print_error "GITHUB_TOKEN is required for install. Use --token argument or set GH_TOKEN environment variable."
            echo ""
            show_usage
            exit 1
        fi
    fi

    # Validate OS type
    if [[ "$OS_TYPE" != "linux" && "$OS_TYPE" != "osx" ]]; then
        print_error "Invalid OS type: $OS_TYPE. Must be 'linux' or 'osx'."
        exit 1
    fi

    # Validate architecture
    if [[ "$ARCH" != "x64" && "$ARCH" != "arm64" ]]; then
        print_error "Invalid architecture: $ARCH. Must be 'x64' or 'arm64'."
        exit 1
    fi
}

################################################################################
# Functions
################################################################################

# Function to check if runner already exists on GitHub
check_runner_exists() {
    local api_url
    
    if [ -z "$GITHUB_REPO" ]; then
        # Organization-level runners
        api_url="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners"
    else
        # Repository-level runners
        api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners"
    fi
    
    print_info "Checking if runner '${RUNNER_NAME}' already exists on GitHub..."
    
    local response
    response=$(curl -sS \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${api_url}")
    
    # Check if runner with same name exists
    local exists=false
    if command -v jq >/dev/null 2>&1; then
        exists=$(echo "$response" | jq -r --arg name "$RUNNER_NAME" '.runners[] | select(.name == $name) | .name' | grep -q "." && echo "true" || echo "false")
    else
        exists=$(echo "$response" | grep -o "\"name\":\"${RUNNER_NAME}\"" | grep -q "." && echo "true" || echo "false")
    fi
    
    if [ "$exists" = "true" ]; then
        print_error "Runner '${RUNNER_NAME}' already exists on GitHub!"
        echo ""
        print_info "Please choose one of the following options:"
        echo "  1. Use a different runner name with --name parameter"
        echo "  2. Remove the existing runner from GitHub:"
        if [ -z "$GITHUB_REPO" ]; then
            echo "     https://github.com/organizations/${GITHUB_OWNER}/settings/actions/runners"
        else
            echo "     https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/actions/runners"
        fi
        echo ""
        exit 1
    fi
    
    print_info "✓ Runner name '${RUNNER_NAME}' is available"
}

# Function to get latest runner version from GitHub API
get_latest_runner_version() {
    print_info "Getting latest runner version from GitHub..." >&2
    
    local latest_version
    latest_version=$(curl -sS \
        -H "Accept: application/vnd.github+json" \
        https://api.github.com/repos/actions/runner/releases/latest | \
        jq -r '.tag_name // empty' 2>/dev/null)
    
    if [ -z "$latest_version" ]; then
        # Fallback to grep if jq is not available
        latest_version=$(curl -sS \
            -H "Accept: application/vnd.github+json" \
            https://api.github.com/repos/actions/runner/releases/latest | \
            grep -o '"tag_name":"[^"]*"' | \
            cut -d'"' -f4)
    fi
    
    if [ -z "$latest_version" ]; then
        print_error "Failed to get latest runner version from GitHub API" >&2
        return 1
    fi
    
    # Remove 'v' prefix if present
    latest_version=${latest_version#v}
    
    print_info "Latest runner version: $latest_version" >&2
    echo "$latest_version"
}

# Function to get current runner version from installation
get_current_runner_version() {
    local install_dir="$1"
    
    if [ ! -f "$install_dir/config.sh" ]; then
        print_error "Runner not found in: $install_dir" >&2
        return 1
    fi
    
    local current_version
    if [ "$EUID" -eq 0 ]; then
        # Running as root
        current_version=$(cd "$install_dir" && RUNNER_ALLOW_RUNASROOT=1 ./config.sh --version 2>/dev/null)
    else
        # Running as regular user
        current_version=$(cd "$install_dir" && ./config.sh --version 2>/dev/null)
    fi
    
    if [ -z "$current_version" ]; then
        print_error "Failed to get current runner version from: $install_dir" >&2
        return 1
    fi
    
    echo "$current_version"
}

# Function to compare versions (returns 0 if upgrade needed, 1 if not)
version_compare() {
    local current="$1"
    local target="$2"
    
    # Simple version comparison (assumes semantic versioning)
    if [ "$current" = "$target" ]; then
        return 1  # Same version, no upgrade needed
    fi
    
    # Use sort -V for version comparison if available
    if command -v sort >/dev/null 2>&1; then
        local newer
        newer=$(printf '%s\n%s\n' "$current" "$target" | sort -V | tail -n1)
        if [ "$newer" = "$target" ]; then
            return 0  # Upgrade needed
        else
            return 1  # Current is newer or same
        fi
    else
        # Fallback: assume upgrade is needed if versions differ
        return 0
    fi
}

# Function to get registration token from GitHub API
get_registration_token() {
    local api_url
    
    if [ -z "$GITHUB_REPO" ]; then
        # Organization-level runner
        api_url="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners/registration-token"
        print_info "Getting registration token for organization: ${GITHUB_OWNER}" >&2
    else
        # Repository-level runner
        api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/registration-token"
        print_info "Getting registration token for repository: ${GITHUB_OWNER}/${GITHUB_REPO}" >&2
    fi
    
    local response
    response=$(curl -sS -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${api_url}")
    
    local token
    # Try jq first, fallback to grep
    if command -v jq >/dev/null 2>&1; then
        token=$(echo "$response" | jq -r '.token // empty')
    else
        token=$(echo "$response" | tr -d '\n' | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    fi
    
    if [ -z "$token" ]; then
        print_error "Failed to get registration token" >&2
        echo "API Response: $response" >&2
        exit 1
    fi
    
    echo "$token"
}

# Function to download and extract runner
download_runner() {
    local package_name="actions-runner-${OS_TYPE}-${ARCH}-${RUNNER_VERSION}.tar.gz"
    local download_url="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${package_name}"
    local cache_dir="${HOME}/.cache/github-runner"
    local cached_package="${cache_dir}/${package_name}"
    
    print_info "Creating installation directory: ${INSTALL_DIR}"
    mkdir -p "${INSTALL_DIR}"
    cd "${INSTALL_DIR}"
    
    # Check if package is already cached
    if [ -f "${cached_package}" ]; then
        print_info "Found cached runner package: ${package_name}"
        print_info "Verifying cached package integrity..."
        
        # Try to verify it's a valid tar.gz file
        if tar -tzf "${cached_package}" >/dev/null 2>&1; then
            print_info "✓ Cached package is valid, using it"
            cp "${cached_package}" "./${package_name}"
        else
            print_warning "Cached package is corrupted, re-downloading..."
            rm -f "${cached_package}"
        fi
    fi
    
    # Download if not cached or cache was invalid
    if [ ! -f "./${package_name}" ]; then
        print_info "Downloading runner package: ${package_name}"
        if ! curl -o "${package_name}" -L "${download_url}"; then
            print_error "Failed to download runner package"
            exit 1
        fi
        
        # Cache the downloaded package for future use
        print_info "Caching package for future installations..."
        mkdir -p "${cache_dir}"
        cp "${package_name}" "${cached_package}"
    fi
    
    print_info "Extracting runner package"
    tar xzf "./${package_name}"
    
    print_info "Cleaning up installation directory"
    rm "./${package_name}"
}

# Function to configure runner
configure_runner() {
    local token=$1
    local github_url
    
    if [ -z "$GITHUB_REPO" ]; then
        github_url="https://github.com/${GITHUB_OWNER}"
    else
        github_url="https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
    fi
    
    print_info "Configuring runner"
    print_info "  URL: ${github_url}"
    print_info "  Name: ${RUNNER_NAME}"
    print_info "  Labels: ${RUNNER_LABELS}"
    print_info "  Work directory: ${RUNNER_WORK_DIR}"
    
    cd "${INSTALL_DIR}"
    
    print_info "Running configuration..."
    
    # Allow running as root (not recommended for production, but useful for testing)
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. Setting RUNNER_ALLOW_RUNASROOT=1"
        export RUNNER_ALLOW_RUNASROOT=1
    fi
    
    # Build configuration command with proper argument array
    local config_args=(
        "./config.sh"
        "--unattended"
        "--url" "${github_url}"
        "--token" "${token}"
        "--name" "${RUNNER_NAME}"
        "--labels" "${RUNNER_LABELS}"
        "--work" "${RUNNER_WORK_DIR}"
    )
    
    # Add runner group for organization-level runners
    if [ -z "$GITHUB_REPO" ] && [ -n "$RUNNER_GROUP" ]; then
        config_args+=("--runnergroup" "${RUNNER_GROUP}")
    fi
    
    # Disable automatic updates by default (unless --enable-autoupdate is specified)
    if [ "$DISABLE_AUTO_UPDATE" = "true" ]; then
        print_info "Disabling automatic updates (use --enable-autoupdate to enable)"
        config_args+=("--disableupdate")
    else
        print_info "Automatic updates enabled"
    fi
    
    if ! "${config_args[@]}"; then
        print_error "Failed to configure runner"
        exit 1
    fi
}

# Function to install and start service
install_service() {
    cd "${INSTALL_DIR}"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root. The service will be installed as root."
    fi
    
    print_info "Installing runner service"
    if ! sudo ./svc.sh install; then
        print_error "Failed to install service"
        exit 1
    fi
    
    print_info "Starting runner service"
    if ! sudo ./svc.sh start; then
        print_error "Failed to start service"
        exit 1
    fi
    
    print_info "Checking service status"
    sudo ./svc.sh status
}

# Function to check if local installation directory exists
check_local_installation() {
    if [ -d "${INSTALL_DIR}" ]; then
        print_error "Installation directory already exists: ${INSTALL_DIR}"
        echo ""
        print_info "Please choose one of the following options:"
        echo "  1. Remove the existing installation:"
        echo "     sudo rm -rf ${INSTALL_DIR}"
        echo "  2. Use a different installation directory with --install-dir parameter"
        echo ""
        exit 1
    fi
}

################################################################################
# Runner Removal Functions
################################################################################

# Get removal token from GitHub API
get_removal_token() {
    if [ -z "$GITHUB_TOKEN" ]; then
        print_warning "GITHUB_TOKEN not set. Skipping GitHub removal (local cleanup only)." >&2
        return 1
    fi
    
    if [ -z "$GITHUB_OWNER" ]; then
        print_warning "GITHUB_OWNER not set. Skipping GitHub removal (local cleanup only)." >&2
        return 1
    fi
    
    local api_url
    if [ -z "$GITHUB_REPO" ]; then
        api_url="https://api.github.com/orgs/${GITHUB_OWNER}/actions/runners/remove-token"
        print_info "Getting removal token for organization: ${GITHUB_OWNER}" >&2
    else
        api_url="https://api.github.com/repos/${GITHUB_OWNER}/${GITHUB_REPO}/actions/runners/remove-token"
        print_info "Getting removal token for repository: ${GITHUB_OWNER}/${GITHUB_REPO}" >&2
    fi
    
    local response
    response=$(curl -sS -X POST \
        -H "Accept: application/vnd.github+json" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        "${api_url}" 2>&1)
    
    local token
    if command -v jq >/dev/null 2>&1; then
        token=$(echo "$response" | jq -r '.token // empty')
    else
        token=$(echo "$response" | grep -o '"token":"[^"]*' | cut -d'"' -f4)
    fi
    
    if [ -z "$token" ]; then
        print_warning "Failed to get removal token. Will skip GitHub removal." >&2
        return 1
    fi
    
    echo "$token"
}

# Remove a single runner
remove_single_runner() {
    local single_dir="$1"
    
    print_info "=========================================="
    print_info "Removing Runner: ${single_dir}"
    print_info "=========================================="
    echo ""
    
    # Check if directory exists
    if [ ! -d "$single_dir" ]; then
        print_error "Installation directory not found: ${single_dir}"
        return 1
    fi
    
    cd "$single_dir"
    
    # Step 1: Stop service
    print_info "Step 1: Stopping runner service"
    if [ -f "./svc.sh" ]; then
        if sudo ./svc.sh status >/dev/null 2>&1; then
            sudo ./svc.sh stop || print_warning "Failed to stop service"
        else
            print_info "Service is not running"
        fi
    else
        print_warning "svc.sh not found, skipping service stop"
    fi
    
    # Step 2: Uninstall service
    print_info "Step 2: Uninstalling runner service"
    if [ -f "./svc.sh" ]; then
        sudo ./svc.sh uninstall || print_warning "Failed to uninstall service"
    else
        print_warning "svc.sh not found, skipping service uninstall"
    fi
    
    # Step 3: Remove from GitHub
    print_info "Step 3: Removing runner from GitHub"
    if [ -n "$GITHUB_TOKEN" ] && [ -n "$GITHUB_OWNER" ]; then
        local removal_token
        if removal_token=$(get_removal_token); then
            if [ -f "./config.sh" ]; then
                print_info "Running: ./config.sh remove --token ***"
                
                # Check if running as root and set environment variable
                if [ "$EUID" -eq 0 ]; then
                    export RUNNER_ALLOW_RUNASROOT=1
                    print_info "Running as root, setting RUNNER_ALLOW_RUNASROOT=1"
                fi
                
                if ./config.sh remove --token "$removal_token" 2>&1; then
                    print_info "✓ Successfully removed from GitHub"
                else
                    local exit_code=$?
                    print_warning "config.sh remove failed with exit code: $exit_code"
                    print_info "The runner may have already been removed from GitHub, or the token may have expired."
                    print_info "You can verify at:"
                    if [ -z "$GITHUB_REPO" ]; then
                        echo "  https://github.com/organizations/${GITHUB_OWNER}/settings/actions/runners"
                    else
                        echo "  https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/actions/runners"
                    fi
                fi
            else
                print_warning "config.sh not found, skipping GitHub removal"
            fi
        else
            print_warning "Could not get removal token, skipping GitHub removal"
        fi
    else
        print_warning "GITHUB_TOKEN or GITHUB_OWNER not set"
        print_info "Runner will be removed locally only. Please manually remove from GitHub UI:"
        if [ -n "$GITHUB_OWNER" ] && [ -z "$GITHUB_REPO" ]; then
            echo "  https://github.com/organizations/${GITHUB_OWNER}/settings/actions/runners"
        elif [ -n "$GITHUB_OWNER" ] && [ -n "$GITHUB_REPO" ]; then
            echo "  https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}/settings/actions/runners"
        fi
    fi
    
    # Step 4: Remove installation directory
    print_info "Step 4: Removing installation directory"
    cd ~
    if rm -rf "$single_dir"; then
        print_info "✓ Successfully removed: ${single_dir}"
        return 0
    else
        print_error "✗ Failed to remove directory: ${single_dir}"
        return 1
    fi
}

# Batch remove runners
batch_remove() {
    set +e  # Don't exit on error in batch mode
    
    # Split install dirs by semicolon
    IFS=';' read -ra DIRS <<< "$INSTALL_DIR"
    local count=${#DIRS[@]}
    
    print_info "=========================================="
    print_info "Batch Runner Removal"
    print_info "=========================================="
    echo ""
    print_info "Runners to be removed:"
    for ((i=0; i<count; i++)); do
        echo "  $((i+1)). ${DIRS[i]}"
    done
    echo ""
    
    print_warning "This will permanently remove ${count} runner(s)!"
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Removal cancelled"
        set -e
        return 0
    fi
    
    local successful=0
    local failed=0
    
    # Remove each runner
    for ((i=0; i<count; i++)); do
        local dir="${DIRS[i]}"
        
        echo ""
        if remove_single_runner "$dir"; then
            ((successful++))
        else
            ((failed++))
        fi
    done
    
    # Summary
    echo ""
    print_info "=========================================="
    print_info "Batch Removal Summary"
    print_info "=========================================="
    echo ""
    print_info "Successful: ${successful}"
    if [ $failed -gt 0 ]; then
        print_error "Failed: ${failed}"
    else
        print_info "Failed: ${failed}"
    fi
    echo ""
    
    set -e  # Re-enable exit on error
    
    if [ $failed -eq 0 ]; then
        print_info "All runners removed successfully!"
        return 0
    else
        print_warning "Some removals failed. Please check the logs above."
        return 1
    fi
}

# Check if batch removal is requested
is_batch_remove() {
    [[ "$INSTALL_DIR" == *";"* ]]
}

################################################################################
# Main Execution
################################################################################

################################################################################
# Batch deployment support
################################################################################

# Check if batch deployment is requested (semicolon in name)
is_batch_deployment() {
    [[ "$RUNNER_NAME" == *";"* ]]
}

# Deploy multiple runners
batch_deploy() {
    # Temporarily disable exit on error for batch deployment
    set +e
    
    # Split parameters by semicolon
    IFS=';' read -ra NAMES <<< "$RUNNER_NAME"
    IFS=';' read -ra LABELS_ARRAY <<< "$RUNNER_LABELS"
    IFS=';' read -ra DIRS <<< "$INSTALL_DIR"
    
    local count=${#NAMES[@]}
    
    print_info "=========================================="
    print_info "Batch Runner Deployment"
    print_info "=========================================="
    echo ""
    print_info "Configuration:"
    echo "  Owner: ${GITHUB_OWNER}"
    echo "  Repository: ${GITHUB_REPO:-<organization-level>}"
    echo "  Number of runners: ${count}"
    echo ""
    
    print_info "Runners to be created:"
    for ((i=0; i<count; i++)); do
        local name="${NAMES[i]}"
        local labels="${LABELS_ARRAY[i]:-${LABELS_ARRAY[-1]:-}}"
        local dir="${DIRS[i]:-${DIRS[-1]:-}}"
        echo "  $((i+1)). ${name} -> ${dir} [labels: ${labels:-<auto>}]"
    done
    echo ""
    
    local successful=0
    local failed=0
    
    # Deploy each runner
    for ((i=0; i<count; i++)); do
        local name="${NAMES[i]}"
        local labels="${LABELS_ARRAY[i]:-${LABELS_ARRAY[-1]:-}}"
        local dir="${DIRS[i]:-${DIRS[-1]:-}}"
        
        echo ""
        print_info "=========================================="
        print_info "Deploying Runner $((i+1))/${count}: ${name}"
        print_info "=========================================="
        
        # Call main deployment with single runner config
        if deploy_single_runner "$name" "$labels" "$dir"; then
            print_info "✓ Successfully deployed: ${name}"
            ((successful++))
        else
            print_error "✗ Failed to deploy: ${name}"
            ((failed++))
        fi
        
        # Delay between deployments (except last one)
        if [ $i -lt $((count - 1)) ]; then
            print_info "Waiting 3 seconds before next deployment..."
            sleep 3
        fi
    done
    
    # Summary
    echo ""
    print_info "=========================================="
    print_info "Batch Deployment Summary"
    print_info "=========================================="
    echo ""
    print_info "Successful: ${successful}"
    if [ $failed -gt 0 ]; then
        print_error "Failed: ${failed}"
    else
        print_info "Failed: ${failed}"
    fi
    echo ""
    
    # Re-enable exit on error
    set -e
    
    if [ $failed -eq 0 ]; then
        print_info "All runners deployed successfully! 🎉"
        return 0
    else
        print_warning "Some deployments failed. Please check the logs above."
        return 1
    fi
}

# Deploy a single runner (used by both single and batch mode)
deploy_single_runner() {
    local single_name="$1"
    local single_labels="$2"
    local single_dir="$3"
    
    # Temporarily override variables
    local orig_name="$RUNNER_NAME"
    local orig_labels="$RUNNER_LABELS"
    local orig_dir="$INSTALL_DIR"
    
    RUNNER_NAME="$single_name"
    RUNNER_LABELS="$single_labels"
    INSTALL_DIR="$single_dir"
    
    # Display configuration
    echo ""
    print_info "Configuration:"
    echo "  Owner: ${GITHUB_OWNER}"
    echo "  Repository: ${GITHUB_REPO:-<organization-level>}"
    echo "  Runner Name: ${RUNNER_NAME}"
    echo "  Runner Labels: ${RUNNER_LABELS:-<auto>}"
    echo "  Runner Group: ${RUNNER_GROUP:-<default>}"
    echo "  Install Directory: ${INSTALL_DIR}"
    echo "  Runner Version: ${RUNNER_VERSION}"
    echo "  OS/Arch: ${OS_TYPE}/${ARCH}"
    echo ""
    
    # Check if runner already exists on GitHub
    print_info "Step 1: Checking runner availability"
    if ! check_runner_exists; then
        RUNNER_NAME="$orig_name"
        RUNNER_LABELS="$orig_labels"
        INSTALL_DIR="$orig_dir"
        return 1
    fi
    
    # Check if local installation directory exists
    if ! check_local_installation; then
        RUNNER_NAME="$orig_name"
        RUNNER_LABELS="$orig_labels"
        INSTALL_DIR="$orig_dir"
        return 1
    fi
    
    # Get registration token
    print_info "Step 2: Getting registration token from GitHub"
    local token
    if ! token=$(get_registration_token); then
        RUNNER_NAME="$orig_name"
        RUNNER_LABELS="$orig_labels"
        INSTALL_DIR="$orig_dir"
        return 1
    fi
    print_info "Registration token obtained successfully"
    
    # Download runner
    print_info "Step 3: Downloading runner"
    if ! download_runner; then
        RUNNER_NAME="$orig_name"
        RUNNER_LABELS="$orig_labels"
        INSTALL_DIR="$orig_dir"
        return 1
    fi
    
    # Configure runner
    print_info "Step 4: Configuring runner"
    if ! configure_runner "$token"; then
        RUNNER_NAME="$orig_name"
        RUNNER_LABELS="$orig_labels"
        INSTALL_DIR="$orig_dir"
        return 1
    fi
    
    # Install and start service
    print_info "Step 5: Installing and starting service"
    if ! install_service; then
        RUNNER_NAME="$orig_name"
        RUNNER_LABELS="$orig_labels"
        INSTALL_DIR="$orig_dir"
        return 1
    fi
    
    echo ""
    print_info "=========================================="
    print_info "Runner setup completed successfully!"
    print_info "=========================================="
    
    # Restore original values
    RUNNER_NAME="$orig_name"
    RUNNER_LABELS="$orig_labels"
    INSTALL_DIR="$orig_dir"
    
    return 0
}

################################################################################
# Upgrade Functions
################################################################################

# Upgrade a single runner using in-place strategy
upgrade_single_runner_inplace() {
    local install_dir="$1"
    local target_version="$2"
    
    print_info "Starting in-place upgrade for: $install_dir"
    
    # Step 1: Get current version
    print_info "Step 1: Checking current runner version"
    local current_version
    current_version=$(get_current_runner_version "$install_dir")
    if [ $? -ne 0 ]; then
        print_error "Failed to get current version"
        return 1
    fi
    
    print_info "Current version: $current_version"
    print_info "Target version: $target_version"
    
    # Step 2: Check if upgrade is needed
    if ! version_compare "$current_version" "$target_version"; then
        print_info "✓ Runner is already up to date (current: $current_version, target: $target_version)"
        return 0
    fi
    
    # Step 3: Stop the service
    print_info "Step 2: Stopping runner service"
    if [ -f "$install_dir/svc.sh" ]; then
        if [ "$EUID" -eq 0 ]; then
            cd "$install_dir" && ./svc.sh stop || print_warning "Failed to stop service (may not be running)"
        else
            cd "$install_dir" && sudo ./svc.sh stop || print_warning "Failed to stop service (may not be running)"
        fi
    else
        print_warning "Service script not found, skipping service stop"
    fi
    
    # Step 4: Backup current installation
    print_info "Step 3: Creating backup"
    local backup_dir="${install_dir}.backup.$(date +%Y%m%d_%H%M%S)"
    cp -r "$install_dir" "$backup_dir"
    print_info "Backup created: $backup_dir"
    
    # Step 5: Download new version
    print_info "Step 4: Downloading runner version $target_version"
    local cache_dir="$HOME/.cache/github-runner"
    local package_name="actions-runner-${OS_TYPE}-${ARCH}-${target_version}.tar.gz"
    local package_path="$cache_dir/$package_name"
    
    mkdir -p "$cache_dir"
    
    if [ ! -f "$package_path" ]; then
        print_info "Downloading runner package..."
        local download_url="https://github.com/actions/runner/releases/download/v${target_version}/${package_name}"
        
        if ! curl -L -o "$package_path" "$download_url"; then
            print_error "Failed to download runner package"
            print_info "Restoring from backup..."
            rm -rf "$install_dir"
            mv "$backup_dir" "$install_dir"
            return 1
        fi
    else
        print_info "Using cached package: $package_name"
    fi
    
    # Step 6: Extract new version (preserve config files)
    print_info "Step 5: Extracting new runner version"
    
    # Save important config files
    local temp_config_dir="/tmp/runner_config_$$"
    mkdir -p "$temp_config_dir"
    
    if [ -f "$install_dir/.runner" ]; then
        cp "$install_dir/.runner" "$temp_config_dir/"
    fi
    if [ -f "$install_dir/.credentials" ]; then
        cp "$install_dir/.credentials" "$temp_config_dir/"
    fi
    if [ -f "$install_dir/.credentials_rsaparams" ]; then
        cp "$install_dir/.credentials_rsaparams" "$temp_config_dir/"
    fi
    
    # Extract new version
    cd "$install_dir"
    tar xzf "$package_path" --strip-components=0
    
    # Restore config files
    if [ -f "$temp_config_dir/.runner" ]; then
        cp "$temp_config_dir/.runner" "$install_dir/"
    fi
    if [ -f "$temp_config_dir/.credentials" ]; then
        cp "$temp_config_dir/.credentials" "$install_dir/"
    fi
    if [ -f "$temp_config_dir/.credentials_rsaparams" ]; then
        cp "$temp_config_dir/.credentials_rsaparams" "$install_dir/"
    fi
    
    # Cleanup temp config
    rm -rf "$temp_config_dir"
    
    # Step 7: Restart service
    print_info "Step 6: Restarting runner service"
    if [ -f "$install_dir/svc.sh" ]; then
        if [ "$EUID" -eq 0 ]; then
            cd "$install_dir" && ./svc.sh start
        else
            cd "$install_dir" && sudo ./svc.sh start
        fi
        
        # Wait a moment and check status
        sleep 2
        if [ "$EUID" -eq 0 ]; then
            cd "$install_dir" && ./svc.sh status
        else
            cd "$install_dir" && sudo ./svc.sh status
        fi
    else
        print_warning "Service script not found, please start manually"
    fi
    
    # Step 8: Verify upgrade
    print_info "Step 7: Verifying upgrade"
    local new_version
    new_version=$(get_current_runner_version "$install_dir")
    if [ $? -eq 0 ] && [ "$new_version" = "$target_version" ]; then
        print_info "✅ Upgrade successful! Version: $new_version"
        print_info "Backup available at: $backup_dir"
        return 0
    else
        print_error "Upgrade verification failed"
        print_info "Restoring from backup..."
        if [ "$EUID" -eq 0 ]; then
            cd "$install_dir" && ./svc.sh stop 2>/dev/null || true
        else
            cd "$install_dir" && sudo ./svc.sh stop 2>/dev/null || true
        fi
        rm -rf "$install_dir"
        mv "$backup_dir" "$install_dir"
        if [ "$EUID" -eq 0 ]; then
            cd "$install_dir" && ./svc.sh start
        else
            cd "$install_dir" && sudo ./svc.sh start
        fi
        return 1
    fi
}

# Main upgrade function (in-place with backup)
upgrade_single_runner() {
    local install_dir="$1"
    local target_version="$2"
    
    # Validate install directory
    if [ ! -d "$install_dir" ]; then
        print_error "Installation directory not found: $install_dir"
        return 1
    fi
    
    if [ ! -f "$install_dir/config.sh" ]; then
        print_error "Runner not found in: $install_dir"
        return 1
    fi
    
    # Get target version if not specified
    if [ -z "$target_version" ]; then
        target_version=$(get_latest_runner_version)
        if [ $? -ne 0 ] || [ -z "$target_version" ]; then
            print_error "Failed to get latest runner version"
            return 1
        fi
    fi
    
    print_info "Upgrading runner in: $install_dir"
    print_info "Target version: $target_version"
    
    # Call the in-place upgrade function
    upgrade_single_runner_inplace "$install_dir" "$target_version"
}

# Batch upgrade runners
batch_upgrade() {
    set +e  # Don't exit on error in batch mode
    
    # Split install dirs by semicolon
    IFS=';' read -ra DIRS <<< "$INSTALL_DIR"
    local count=${#DIRS[@]}
    
    print_info "Starting batch upgrade for $count runners..."
    
    local failed=0
    local i=1
    
    for dir in "${DIRS[@]}"; do
        # Trim whitespace
        dir=$(echo "$dir" | xargs)
        
        print_info "==========================================
[${i}/${count}] Upgrading runner: $dir
=========================================="
        
        if upgrade_single_runner "$dir" "$TARGET_VERSION"; then
            print_info "✅ Runner $i/$count upgraded successfully"
        else
            print_error "❌ Runner $i/$count upgrade failed"
            ((failed++))
        fi
        
        echo ""
        ((i++))
    done
    
    set -e  # Re-enable exit on error
    
    print_info "=========================================="
    print_info "Batch upgrade completed!"
    print_info "Total: $count, Success: $((count - failed)), Failed: $failed"
    print_info "=========================================="
    
    if [ $failed -eq 0 ]; then
        print_info "All runners upgraded successfully! 🎉"
        return 0
    else
        print_warning "Some upgrades failed. Please check the logs above."
        return 1
    fi
}

# Check if it's a batch upgrade
is_batch_upgrade() {
    [[ "$INSTALL_DIR" == *";"* ]]
}

################################################################################
# Main function
################################################################################

main() {
    # Parse command-line arguments
    parse_arguments "$@"
    
    # Validate parameters
    validate_parameters
    
    # Check sudo permissions (for both install and remove)
    check_sudo_permission
    
    # Route to appropriate command
    case "$COMMAND" in
        install)
            # Check if this is a batch deployment
            if is_batch_deployment; then
                batch_deploy
                return $?
            fi
            
            # Single runner deployment
            print_info "=========================================="
            print_info "GitHub Self-Hosted Runner Setup"
            print_info "=========================================="
            
            if deploy_single_runner "$RUNNER_NAME" "$RUNNER_LABELS" "$INSTALL_DIR"; then
                echo ""
                print_info "Useful commands:"
                echo "  Check status:  sudo ${INSTALL_DIR}/svc.sh status"
                echo "  Stop service:  sudo ${INSTALL_DIR}/svc.sh stop"
                echo "  Start service: sudo ${INSTALL_DIR}/svc.sh start"
                echo "  Uninstall:     sudo ${INSTALL_DIR}/svc.sh uninstall"
                return 0
            else
                return 1
            fi
            ;;
            
        remove)
            # Check if this is a batch removal
            if is_batch_remove; then
                batch_remove
                return $?
            fi
            
            # Single runner removal
            print_warning "This will remove the runner at: ${INSTALL_DIR}"
            read -p "Are you sure you want to continue? (y/n) " -n 1 -r
            echo
            
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_info "Removal cancelled"
                return 0
            fi
            
            remove_single_runner "$INSTALL_DIR"
            return $?
            ;;
            
        upgrade)
            # Check if this is a batch upgrade
            if is_batch_upgrade; then
                batch_upgrade
                return $?
            fi
            
            # Single runner upgrade
            print_info "=========================================="
            print_info "GitHub Self-Hosted Runner Upgrade"
            print_info "=========================================="
            
            upgrade_single_runner "$INSTALL_DIR" "$TARGET_VERSION"
            return $?
            ;;
            
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            return 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
