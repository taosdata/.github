#!/bin/bash

#######################################
# IoTDB Installation Script (Enhanced)
# 
# Description: Enhanced script for downloading and installing Apache IoTDB
# Based on: https://iotdb.apache.org/UserGuide/latest/Deployment-and-Maintenance/Stand-Alone-Deployment_apache.html
# Author: Auto-generated script
# Date: $(date +%Y-%m-%d)
#######################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration
DEFAULT_VERSION="2.0.5"
DEFAULT_INSTALL_DIR="/opt/iotdb"
DEFAULT_DOWNLOAD_DIR="/tmp/iotdb-packages"
DEFAULT_CLUSTER_NAME="defaultCluster"
DEFAULT_RPC_PORT="6667"

# Script variables (will be set by command line arguments)
IOTDB_VERSION=""
INSTALL_DIR=""
DOWNLOAD_DIR=""
CLUSTER_NAME=""
DN_RPC_PORT=""
FORCE_INSTALL=false
SKIP_DOWNLOAD=false
UNINSTALL_ONLY=false
UNINSTALL_FORCE=false

# Global variables
IOTDB_PACKAGE_PATH=""

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" >&2
}

log_warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" >&2
}

log_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" >&2
}

log_info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" >&2
}

# Show help information
show_help() {
    echo "IoTDB Installation Script (Enhanced)"
    echo
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  -v, --version VERSION      IoTDB version (default: $DEFAULT_VERSION)"
    echo "  -i, --install-dir DIR      Installation directory (default: $DEFAULT_INSTALL_DIR)"
    echo "  -d, --download-dir DIR     Download directory (default: $DEFAULT_DOWNLOAD_DIR)"
    echo "  -c, --cluster-name NAME    Cluster name (default: $DEFAULT_CLUSTER_NAME)"
    echo "  -p, --rpc-port PORT        RPC port (default: $DEFAULT_RPC_PORT)"
    echo "  -f, --force                Force installation even if already installed"
    echo "  -s, --skip-download        Skip download if package exists"
    echo "      --uninstall            Uninstall existing IoTDB installation and exit
      --uninstall-force      Force uninstall without interactive prompts"
    echo "  -h, --help                 Show this help message"
    echo
    echo "Examples:"
    echo "  $0 -v 2.1.0 -d /opt/packages"
    echo "  $0 --version 2.0.5 --download-dir /tmp/iotdb --force"
    echo "  $0 --skip-download --download-dir /opt/packages"
    echo "  $0 --uninstall             # Uninstall existing installation"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--version)
                IOTDB_VERSION="$2"
                shift 2
                ;;
            -i|--install-dir)
                INSTALL_DIR="$2"
                shift 2
                ;;
            -d|--download-dir)
                DOWNLOAD_DIR="$2"
                shift 2
                ;;
            -c|--cluster-name)
                CLUSTER_NAME="$2"
                shift 2
                ;;
            -p|--rpc-port)
                DN_RPC_PORT="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_INSTALL=true
                shift
                ;;
            -s|--skip-download)
                SKIP_DOWNLOAD=true
                shift
                ;;
            --uninstall)
                UNINSTALL_ONLY=true
                shift
                ;;
            --uninstall-force)
                UNINSTALL_ONLY=true
                UNINSTALL_FORCE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # Set default values if not provided
    IOTDB_VERSION="${IOTDB_VERSION:-$DEFAULT_VERSION}"
    INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
    DOWNLOAD_DIR="${DOWNLOAD_DIR:-$DEFAULT_DOWNLOAD_DIR}"
    CLUSTER_NAME="${CLUSTER_NAME:-$DEFAULT_CLUSTER_NAME}"
    DN_RPC_PORT="${DN_RPC_PORT:-$DEFAULT_RPC_PORT}"
}

# Check if IoTDB is already installed
check_existing_installation() {
    log "Checking for existing IoTDB installation..."
    
    local installed=false
    local install_method=""
    local current_version=""
    local install_location=""
    
    # Check for IoTDB processes
    if pgrep -f "ConfigNode\|DataNode" > /dev/null; then
        installed=true
        install_method="Running Services"
        
        # Try to get version from running process
        if [ -f "$INSTALL_DIR/sbin/start-cli.sh" ]; then
            install_location="$INSTALL_DIR"
        fi
    fi
    
    # Check for installed binaries
    if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/sbin/start-confignode.sh" ]; then
        installed=true
        install_method="Local Installation"
        install_location="$INSTALL_DIR"
        
        # Try to extract version from jar files
        if [ -d "$INSTALL_DIR/lib" ]; then
            for jar_file in "$INSTALL_DIR/lib"/iotdb-server*.jar; do
                if [ -f "$jar_file" ]; then
                    current_version=$(basename "$jar_file" | sed 's/.*-\([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/' 2>/dev/null || echo "Unknown")
                    break
                fi
            done
        fi
    fi
    
    # Check for systemd services (only if they actually exist and are active)
    local service_files_exist=false
    if [ -f "/etc/systemd/system/iotdb-confignode.service" ] || [ -f "/etc/systemd/system/iotdb-datanode.service" ]; then
        service_files_exist=true
        installed=true
        if [ -z "$install_method" ]; then
            install_method="System Service"
        else
            install_method="$install_method + System Service"
        fi
    fi
    
    # If only service files exist but no processes or directories, it's likely a leftover
    if [ "$installed" = true ]; then
        local processes_running=false
        local directories_exist=false
        
        if pgrep -f "ConfigNode\|DataNode" > /dev/null; then
            processes_running=true
        fi
        
        if [ -d "$INSTALL_DIR" ] && [ -f "$INSTALL_DIR/sbin/start-confignode.sh" ]; then
            directories_exist=true
        fi
        
        # If only systemd services exist but no processes or directories, it's incomplete
        if [ "$service_files_exist" = true ] && [ "$processes_running" = false ] && [ "$directories_exist" = false ]; then
            log_warn "Found leftover systemd service files, but no actual IoTDB installation"
            log_info "Cleaning up leftover service files..."
            systemctl stop iotdb-datanode iotdb-confignode 2>/dev/null || true
            systemctl disable iotdb-datanode iotdb-confignode 2>/dev/null || true
            rm -f /etc/systemd/system/iotdb-confignode.service /etc/systemd/system/iotdb-datanode.service
            systemctl daemon-reload
            log_info "Leftover service files cleaned up, proceeding with installation..."
            return 0
        fi
        
        log_warn "Detected existing IoTDB installation"
        echo "  Installation method: $install_method"
        echo "  Current version: ${current_version:-Unknown}"
        echo "  Installation location: ${install_location:-Unknown}"
        echo "  Target version: $IOTDB_VERSION"
        echo "  Target location: $INSTALL_DIR"
        
        # Check if services are running
        if pgrep -f "ConfigNode" > /dev/null; then
            echo "  ConfigNode status: Running (PID: $(pgrep -f ConfigNode))"
        else
            echo "  ConfigNode status: Not running"
        fi
        
        if pgrep -f "DataNode" > /dev/null; then
            echo "  DataNode status: Running (PID: $(pgrep -f DataNode))"
        else
            echo "  DataNode status: Not running"
        fi
        
        if [ "$FORCE_INSTALL" = false ]; then
            echo
            log_info "Use --force option to proceed with installation anyway"
            log_info "Use --uninstall option to completely remove existing installation"
            log_info "Or use the following commands to manage existing installation:"
            echo "  Check status: systemctl status iotdb-confignode iotdb-datanode"
            echo "  View logs: journalctl -u iotdb-confignode -f"
            if [ -n "$install_location" ]; then
                echo "  Connect CLI: $install_location/sbin/start-cli.sh -h 127.0.0.1 -p 6667"
            fi
            exit 0
        else
            log_warn "Force installation mode: will overwrite existing installation"
            
            # Simply stop existing services if running
            if pgrep -f "ConfigNode\|DataNode" > /dev/null; then
                log_info "Stopping existing IoTDB services..."
                pkill -f "ConfigNode" 2>/dev/null || true
                pkill -f "DataNode" 2>/dev/null || true
                sleep 3
            fi
            
            return 0
        fi
    else
        log_info "No existing IoTDB installation detected"
        return 0
    fi
}

# Prepare download directory
prepare_download_directory() {
    log_info "Preparing download directory: $DOWNLOAD_DIR"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        mkdir -p "$DOWNLOAD_DIR"
        log_info "Created download directory: $DOWNLOAD_DIR"
    else
        log_info "Using existing download directory: $DOWNLOAD_DIR"
    fi
    
    # Check directory permissions
    if [ ! -w "$DOWNLOAD_DIR" ]; then
        log_error "No write permission for directory: $DOWNLOAD_DIR"
        exit 1
    fi
}

# Check if package already exists
check_package_exists() {
    local package_name="apache-iotdb-${IOTDB_VERSION}-all-bin.zip"
    local package_path="$DOWNLOAD_DIR/$package_name"
    
    if [ -f "$package_path" ]; then
        log_info "Found existing package: $package_path"
        local file_size
        file_size=$(du -h "$package_path" | cut -f1)
        log_info "Package size: $file_size"
        
        # Simple integrity check
        if [ -s "$package_path" ]; then
            log_info "Package integrity check passed"
            
            if [ "$SKIP_DOWNLOAD" = true ]; then
                log_info "Skipping download, using existing package"
                echo "$package_path"
                return 0
            else
                echo >&2
                read -p "Use existing package? (y/N): " -n 1 -r >&2
                echo >&2
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Using existing package: $package_path"
                    echo "$package_path"
                    return 0
                else
                    log_info "Will re-download package"
                    rm -f "$package_path"
                fi
            fi
        else
            log_warn "Existing package appears corrupted, will re-download"
            rm -f "$package_path"
        fi
    fi
    
    return 1
}

# Check if script is run as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (recommended for avoiding permission issues)"
        log_info "You can also run with a fixed non-root user, but ensure consistent user operations"
        exit 1
    fi
}

# Install system dependencies
install_dependencies() {
    log "Installing system dependencies..."
    
    # Detect OS and install dependencies
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        case "$ID" in
            "ubuntu"|"debian")
                log_info "Installing dependencies for Ubuntu/Debian..."
                apt-get update -y
                apt-get install -y lsof curl wget unzip procps net-tools
                ;;
            "centos"|"rhel"|"rocky"|"almalinux")
                log_info "Installing dependencies for CentOS/RHEL..."
                yum install -y lsof curl wget unzip procps-ng net-tools
                ;;
            "fedora")
                log_info "Installing dependencies for Fedora..."
                dnf install -y lsof curl wget unzip procps-ng net-tools
                ;;
            *)
                log_warn "Unknown OS: $ID. Attempting to install basic dependencies..."
                # Try different package managers
                if command -v apt-get &> /dev/null; then
                    apt-get update -y && apt-get install -y lsof curl wget unzip procps net-tools
                elif command -v yum &> /dev/null; then
                    yum install -y lsof curl wget unzip procps-ng net-tools
                elif command -v dnf &> /dev/null; then
                    dnf install -y lsof curl wget unzip procps-ng net-tools
                else
                    log_error "No supported package manager found"
                    exit 1
                fi
                ;;
        esac
    else
        log_error "Cannot detect OS. Please install lsof, curl, wget, unzip manually."
        exit 1
    fi
    
    log_info "Dependencies installed successfully"
}

# Check system requirements
check_system_requirements() {
    log "Checking system requirements..."
    
    # Check OS
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "Detected OS: $NAME $VERSION"
    else
        log_warn "Cannot detect OS version"
    fi
    
    # Check Java
    if command -v java &> /dev/null; then
        JAVA_VERSION=$(java -version 2>&1 | awk -F '"' '/version/ {print $2}')
        log_info "Java version: $JAVA_VERSION"
    else
        log_error "Java is not installed. Please install Java 8 or higher."
        exit 1
    fi
    
    # Check available memory
    TOTAL_MEM=$(free -m | awk 'NR==2{printf "%.0f", $2}')
    log_info "Total system memory: ${TOTAL_MEM}MB"
    
    if [[ $TOTAL_MEM -lt 2048 ]]; then
        log_warn "System has less than 2GB RAM. IoTDB may not perform optimally."
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df /opt 2>/dev/null | awk 'NR==2{print $4}' || df / | awk 'NR==2{print $4}')
    AVAILABLE_SPACE_GB=$((AVAILABLE_SPACE / 1024 / 1024))
    log_info "Available disk space: ${AVAILABLE_SPACE_GB}GB"
    
    if [[ $AVAILABLE_SPACE_GB -lt 5 ]]; then
        log_error "Insufficient disk space. At least 5GB is recommended."
        exit 1
    fi
}

# Check for port conflicts and clean up existing installations
check_and_cleanup_existing() {
    log "Checking for existing IoTDB installations and port conflicts..."
    
    # Define IoTDB ports
    local IOTDB_PORTS=(6667 8181 9003 10710 10720 10730 10740 10750 10760)
    local conflicts_found=false
    
    # Check for existing IoTDB processes
    local existing_pids=$(pgrep -f "iotdb\|ConfigNode\|DataNode" || true)
    if [ -n "$existing_pids" ]; then
        log_warn "Found existing IoTDB processes: $existing_pids"
        log_info "Stopping existing IoTDB processes..."
        
        # Try graceful shutdown first
        if [ -d "$INSTALL_DIR/sbin" ]; then
            cd "$INSTALL_DIR/sbin"
            log_info "Attempting graceful shutdown..."
            ./stop-datanode.sh 2>/dev/null || true
            ./stop-confignode.sh 2>/dev/null || true
            sleep 5
        fi
        
        # Force kill if still running
        existing_pids=$(pgrep -f "iotdb\|ConfigNode\|DataNode" || true)
        if [ -n "$existing_pids" ]; then
            log_warn "Force stopping remaining IoTDB processes..."
            pkill -f "iotdb\|ConfigNode\|DataNode" || true
            sleep 3
            pkill -9 -f "iotdb\|ConfigNode\|DataNode" || true
        fi
    fi
    
    # Check for port conflicts using lsof
    if command -v lsof &> /dev/null; then
        log_info "Checking for port conflicts..."
        for port in "${IOTDB_PORTS[@]}"; do
            if lsof -i ":$port" &> /dev/null; then
                local process_info=$(lsof -i ":$port" | tail -n +2)
                log_warn "Port $port is in use by:"
                echo "$process_info" >&2
                conflicts_found=true
            fi
        done
        
        if [ "$conflicts_found" = true ]; then
            log_error "Port conflicts detected. Please resolve conflicts before installation."
            log_info "You can try:"
            log_info "1. Stop other IoTDB instances"
            log_info "2. Kill processes using these ports"
            log_info "3. Change IoTDB configuration to use different ports"
            read -p "Do you want to force kill processes using IoTDB ports? (y/N): " -n 1 -r >&2
            echo >&2
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                for port in "${IOTDB_PORTS[@]}"; do
                    local pids=$(lsof -t -i ":$port" 2>/dev/null || true)
                    if [ -n "$pids" ]; then
                        log_warn "Killing processes on port $port: $pids"
                        kill -9 $pids 2>/dev/null || true
                    fi
                done
                sleep 2
            else
                log_error "Cannot proceed with port conflicts. Exiting."
                exit 1
            fi
        fi
    else
        log_warn "lsof not available, skipping detailed port check"
    fi
    
    # Clean up old data directories if they exist
    if [ -d "$INSTALL_DIR/data" ]; then
        log_warn "Found existing data directory: $INSTALL_DIR/data"
        read -p "Do you want to remove existing data? (y/N): " -n 1 -r >&2
        echo >&2
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Removing existing data directory..."
            rm -rf "$INSTALL_DIR/data"
        else
            log_warn "Keeping existing data. This may cause conflicts."
        fi
    fi
    
    log_info "Cleanup completed"
}

# Comprehensive uninstall function for --uninstall option
uninstall_iotdb() {
    log "Performing comprehensive IoTDB uninstall..."
    
    # Stop all IoTDB services first
    log_info "Stopping IoTDB systemd services..."
    systemctl stop iotdb-datanode 2>/dev/null || true
    systemctl stop iotdb-confignode 2>/dev/null || true
    systemctl disable iotdb-datanode 2>/dev/null || true
    systemctl disable iotdb-confignode 2>/dev/null || true
    
    # Stop using IoTDB scripts if available
    if [ -d "$INSTALL_DIR/sbin" ]; then
        log_info "Stopping IoTDB services using scripts..."
        cd "$INSTALL_DIR/sbin"
        ./stop-datanode.sh 2>/dev/null || true
        ./stop-confignode.sh 2>/dev/null || true
    fi
    
    # Kill all IoTDB processes
    log_info "Killing IoTDB processes..."
    pkill -f "iotdb\|ConfigNode\|DataNode" 2>/dev/null || true
    sleep 3
    pkill -9 -f "iotdb\|ConfigNode\|DataNode" 2>/dev/null || true
    
    # Remove systemd service files
    log_info "Removing systemd service files..."
    rm -f /etc/systemd/system/iotdb-confignode.service
    rm -f /etc/systemd/system/iotdb-datanode.service
    rm -f /etc/systemd/system/iotdb*.service
    systemctl daemon-reload
    
    # Remove installation directory
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removing installation directory: $INSTALL_DIR"
        rm -rf "$INSTALL_DIR"
    fi
    
    # Also check for other common installation paths
    local common_paths=("/opt/iotdb" "/usr/local/iotdb" "/home/iotdb")
    for path in "${common_paths[@]}"; do
        if [ -d "$path" ] && [ "$path" != "$INSTALL_DIR" ]; then
            log_warn "Found IoTDB installation at: $path"
            if [ "$UNINSTALL_FORCE" = true ]; then
                log_info "Force mode: Removing $path"
                rm -rf "$path"
            else
                read -p "Do you want to remove $path? (y/N): " -n 1 -r >&2
                echo >&2
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    log_info "Removing: $path"
                    rm -rf "$path"
                fi
            fi
        fi
    done
    
    # Remove IoTDB user if exists
    if id "iotdb" &>/dev/null; then
        log_info "Removing iotdb user..."
        userdel -r iotdb 2>/dev/null || true
    fi
    
    # Clean up temporary files (but preserve download packages)
    log_info "Cleaning up temporary files..."
    rm -rf /tmp/iotdb-extract-* 2>/dev/null || true
    rm -rf /tmp/test_iotdb.sh 2>/dev/null || true
    log_info "Note: Download packages in $DOWNLOAD_DIR are preserved"
    
    # Clean up any remaining iotdb-related files in /etc
    log_info "Cleaning up configuration files..."
    find /etc -name "*iotdb*" -type f 2>/dev/null | while read -r file; do
        log_warn "Found config file: $file"
        if [ "$UNINSTALL_FORCE" = true ]; then
            log_info "Force mode: Removing $file"
            rm -f "$file"
        else
            read -p "Do you want to remove $file? (y/N): " -n 1 -r >&2
            echo >&2
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                rm -f "$file"
            fi
        fi
    done
    
    log_info "IoTDB uninstall completed successfully!"
    log_info "You can now run the installation script again for a fresh installation."
}

# Configure system parameters
configure_system() {
    log "Configuring system parameters..."
    
    # Set somaxconn for high load scenarios
    log_info "Setting net.core.somaxconn to 65535"
    sysctl -w net.core.somaxconn=65535
    
    # Make the change persistent
    if ! grep -q "net.core.somaxconn" /etc/sysctl.conf; then
        echo "net.core.somaxconn = 65535" >> /etc/sysctl.conf
    fi
}

# Create IoTDB user (optional)
create_iotdb_user() {
    if [[ "$1" == "true" ]]; then
        log "Creating IoTDB user..."
        if ! id "$IOTDB_USER" &>/dev/null; then
            useradd -r -m -s /bin/bash "$IOTDB_USER"
            log_info "Created user: $IOTDB_USER"
        else
            log_info "User $IOTDB_USER already exists"
        fi
    fi
}

# Download IoTDB
download_iotdb() {
    log "Downloading IoTDB ${IOTDB_VERSION}..."
    
    # Prepare download directory
    prepare_download_directory
    
    # Check if package already exists
    local existing_package
    if existing_package=$(check_package_exists); then
        log_info "Using existing package for installation"
        IOTDB_PACKAGE_PATH="$existing_package"
        return 0
    fi
    
    # Download new package
    local package_name="apache-iotdb-${IOTDB_VERSION}-all-bin.zip"
    local download_url="https://dlcdn.apache.org/iotdb/${IOTDB_VERSION}/${package_name}"
    IOTDB_PACKAGE_PATH="$DOWNLOAD_DIR/$package_name"
    
    log_info "Download URL: $download_url"
    log_info "Save path: $IOTDB_PACKAGE_PATH"
    
    log_info "Starting download of IoTDB $IOTDB_VERSION..."
    if command -v wget &> /dev/null; then
        wget -O "$IOTDB_PACKAGE_PATH" "$download_url" || {
            log_error "Download failed"
            rm -f "$IOTDB_PACKAGE_PATH"
            exit 1
        }
    elif command -v curl &> /dev/null; then
        curl -L -o "$IOTDB_PACKAGE_PATH" "$download_url" || {
            log_error "Download failed"
            rm -f "$IOTDB_PACKAGE_PATH"
            exit 1
        }
    else
        log_error "Neither wget nor curl is available. Please install one of them."
        exit 1
    fi
    
    # Verify download
    if [[ ! -f "$IOTDB_PACKAGE_PATH" ]]; then
        log_error "Failed to download IoTDB package"
        exit 1
    fi
    
    local file_size
    file_size=$(du -h "$IOTDB_PACKAGE_PATH" | cut -f1)
    log_info "Package downloaded successfully: $file_size"
}

# Extract and install IoTDB
install_iotdb() {
    log "Installing IoTDB..."
    
    # Create temporary extraction directory
    local temp_extract_dir="/tmp/iotdb-extract-$$"
    mkdir -p "$temp_extract_dir"
    
    # Check if unzip is available
    if ! command -v unzip &> /dev/null; then
        log_error "unzip is not installed. Please install unzip package."
        exit 1
    fi
    
    # Extract package
    log_info "Extracting package: $IOTDB_PACKAGE_PATH"
    if ! unzip -q "$IOTDB_PACKAGE_PATH" -d "$temp_extract_dir"; then
        log_error "Failed to extract package"
        rm -rf "$temp_extract_dir"
        exit 1
    fi
    
    # Find extracted directory
    local extracted_dir
    extracted_dir=$(find "$temp_extract_dir" -maxdepth 1 -type d -name "apache-iotdb-*" | head -1)
    if [[ -z "$extracted_dir" ]]; then
        log_error "Failed to find extracted directory"
        rm -rf "$temp_extract_dir"
        exit 1
    fi
    
    # Remove existing installation if it exists
    if [ -d "$INSTALL_DIR" ]; then
        log_info "Removing existing installation directory"
        rm -rf "$INSTALL_DIR"
    fi
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    
    # Move files to installation directory
    log_info "Installing to $INSTALL_DIR..."
    if ! cp -r "$extracted_dir"/* "$INSTALL_DIR/"; then
        log_error "Failed to copy files to installation directory"
        rm -rf "$temp_extract_dir"
        exit 1
    fi
    
    # Set permissions
    chmod +x "$INSTALL_DIR"/sbin/*.sh
    
    # Clean up temporary directory
    rm -rf "$temp_extract_dir"
    
    log_info "IoTDB installed to: $INSTALL_DIR"
}

# Configure IoTDB
configure_iotdb() {
    log "Configuring IoTDB..."
    
    local config_file="$INSTALL_DIR/conf/iotdb-system.properties"
    
    # Check if config file exists
    if [[ ! -f "$config_file" ]]; then
        log_error "Configuration file not found: $config_file"
        exit 1
    fi
    
    # Backup original configuration
    if [[ ! -f "${config_file}.backup" ]]; then
        cp "$config_file" "${config_file}.backup"
        log_info "Backup created: ${config_file}.backup"
    fi
    
    log_info "Updating configuration file: $config_file"
    
    # Default configuration values (some from original script)
    local cn_internal_address="127.0.0.1"
    local cn_internal_port="10710"
    local cn_consensus_port="10720"
    local dn_rpc_address="0.0.0.0"
    local dn_internal_address="127.0.0.1"
    local dn_internal_port="10730"
    local dn_mpp_data_exchange_port="10740"
    local dn_data_region_consensus_port="10750"
    local dn_schema_region_consensus_port="10760"
    
    # System General Configuration
    sed -i "s/^#*cluster_name=.*/cluster_name=$CLUSTER_NAME/" "$config_file"
    sed -i "s/^#*schema_replication_factor=.*/schema_replication_factor=1/" "$config_file"
    sed -i "s/^#*data_replication_factor=.*/data_replication_factor=1/" "$config_file"
    
    # ConfigNode Configuration
    sed -i "s/^#*cn_internal_address=.*/cn_internal_address=$cn_internal_address/" "$config_file"
    sed -i "s/^#*cn_internal_port=.*/cn_internal_port=$cn_internal_port/" "$config_file"
    sed -i "s/^#*cn_consensus_port=.*/cn_consensus_port=$cn_consensus_port/" "$config_file"
    sed -i "s/^#*cn_seed_config_node=.*/cn_seed_config_node=${cn_internal_address}:${cn_internal_port}/" "$config_file"
    
    # DataNode Configuration
    sed -i "s/^#*dn_rpc_address=.*/dn_rpc_address=$dn_rpc_address/" "$config_file"
    sed -i "s/^#*dn_rpc_port=.*/dn_rpc_port=$DN_RPC_PORT/" "$config_file"
    sed -i "s/^#*dn_internal_address=.*/dn_internal_address=$dn_internal_address/" "$config_file"
    sed -i "s/^#*dn_internal_port=.*/dn_internal_port=$dn_internal_port/" "$config_file"
    sed -i "s/^#*dn_mpp_data_exchange_port=.*/dn_mpp_data_exchange_port=$dn_mpp_data_exchange_port/" "$config_file"
    sed -i "s/^#*dn_data_region_consensus_port=.*/dn_data_region_consensus_port=$dn_data_region_consensus_port/" "$config_file"
    sed -i "s/^#*dn_schema_region_consensus_port=.*/dn_schema_region_consensus_port=$dn_schema_region_consensus_port/" "$config_file"
    sed -i "s/^#*dn_seed_config_node=.*/dn_seed_config_node=${cn_internal_address}:${cn_internal_port}/" "$config_file"
    
    log_info "Configuration updated successfully"
    log_info "Cluster name: $CLUSTER_NAME"
    log_info "RPC port: $DN_RPC_PORT"
}

# Create systemd service files
create_service_files() {
    log "Creating systemd service files..."
    
    # ConfigNode service
    cat > /etc/systemd/system/iotdb-confignode.service << EOF
[Unit]
Description=Apache IoTDB ConfigNode
After=network.target
Wants=network.target

[Service]
Type=forking
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/sbin/start-confignode.sh -d
ExecStop=$INSTALL_DIR/sbin/stop-confignode.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # DataNode service
    cat > /etc/systemd/system/iotdb-datanode.service << EOF
[Unit]
Description=Apache IoTDB DataNode
After=network.target iotdb-confignode.service
Wants=network.target
Requires=iotdb-confignode.service

[Service]
Type=forking
User=root
Group=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/sbin/start-datanode.sh -d
ExecStop=$INSTALL_DIR/sbin/stop-datanode.sh
Restart=on-failure
RestartSec=10
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF

    # IoTDB combined service
    cat > /etc/systemd/system/iotdb.service << EOF
[Unit]
Description=Apache IoTDB Standalone
After=network.target
Wants=iotdb-confignode.service iotdb-datanode.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
ExecReload=/bin/true

[Install]
WantedBy=multi-user.target
Also=iotdb-confignode.service iotdb-datanode.service
EOF

    systemctl daemon-reload
    log_info "Systemd service files created"
}

# Start IoTDB services
start_iotdb() {
    log "Starting IoTDB services..."
    
    cd "$INSTALL_DIR/sbin"
    
    # Start ConfigNode
    log_info "Starting ConfigNode..."
    ./start-confignode.sh -d
    
    # Wait a moment for ConfigNode to initialize
    sleep 5
    
    # Start DataNode
    log_info "Starting DataNode..."
    ./start-datanode.sh -d
    
    # Give services time to start
    log_info "Waiting for services to start..."
    sleep 10
    
    log_info "IoTDB services started"
}

# Verify installation
verify_installation() {
    log "Verifying IoTDB installation..."
    
    # Simple check if processes are running
    if pgrep -f "ConfigNode" > /dev/null; then
        log_info "✓ ConfigNode is running"
    else
        log_warn "⚠ ConfigNode may not be running yet"
    fi
    
    if pgrep -f "DataNode" > /dev/null; then
        log_info "✓ DataNode is running"
    else
        log_warn "⚠ DataNode may not be running yet"
    fi
    
    log_info "Basic verification completed"
    log_info "Note: Services may take a few minutes to fully initialize"
    
    # Create a simple test script
    cat > /tmp/test_iotdb.sh << 'EOF'
#!/bin/bash
cd /opt/iotdb/sbin
echo "show cluster;" | timeout 30 ./start-cli.sh -h 127.0.0.1 -p 6667 2>/dev/null | grep -q "Activated"
EOF
    
    chmod +x /tmp/test_iotdb.sh
    
    if /tmp/test_iotdb.sh; then
        log_info "✓ IoTDB is responding to queries"
    else
        log_warn "⚠ IoTDB connection test failed, but services are running"
        log_info "You can manually verify using: $INSTALL_DIR/sbin/start-cli.sh -h 127.0.0.1 -p 6667"
    fi
    
    rm -f /tmp/test_iotdb.sh
}

# Print usage information
print_usage() {
    log_info "IoTDB $IOTDB_VERSION installation completed!"
    echo
    echo "====================================="
    echo "Installation Summary"
    echo "====================================="
    echo "Version: IoTDB $IOTDB_VERSION"
    echo "Installation directory: $INSTALL_DIR"
    echo "Download directory: $DOWNLOAD_DIR"
    echo "Cluster name: $CLUSTER_NAME"
    echo "RPC port: $DN_RPC_PORT"
    echo ""
    echo -e "${GREEN}Usage Information:${NC}"
    echo -e "${BLUE}1. Start IoTDB:${NC}"
    echo "   systemctl start iotdb-confignode"
    echo "   systemctl start iotdb-datanode"
    echo "   # Or use combined service:"
    echo "   systemctl start iotdb"
    echo
    echo -e "${BLUE}2. Stop IoTDB:${NC}"
    echo "   systemctl stop iotdb-datanode"
    echo "   systemctl stop iotdb-confignode"
    echo "   # Or use combined service:"
    echo "   systemctl stop iotdb"
    echo
    echo -e "${BLUE}3. Enable auto-start:${NC}"
    echo "   systemctl enable iotdb"
    echo
    echo -e "${BLUE}4. Connect to IoTDB:${NC}"
    echo "   $INSTALL_DIR/sbin/start-cli.sh -h 127.0.0.1 -p $DN_RPC_PORT"
    echo
    echo -e "${BLUE}5. Check cluster status:${NC}"
    echo "   In IoTDB CLI, run: show cluster;"
    echo
    echo -e "${BLUE}6. Configuration file:${NC}"
    echo "   $INSTALL_DIR/conf/iotdb-system.properties"
    echo
    echo -e "${BLUE}7. Log files:${NC}"
    echo "   $INSTALL_DIR/logs/"
    echo
    if [ -d "$DOWNLOAD_DIR" ] && [ "$(ls -A $DOWNLOAD_DIR 2>/dev/null)" ]; then
        echo -e "${BLUE}8. Downloaded packages:${NC}"
        echo "   $DOWNLOAD_DIR"
        echo "   $(ls -lh $DOWNLOAD_DIR/*.zip 2>/dev/null | wc -l) package(s) available"
    fi
    echo
    echo -e "${YELLOW}Note: For production use, consider configuring hostname-based addressing${NC}"
    echo -e "${YELLOW}and adjusting memory settings in *-env.sh files.${NC}"
}

# Main installation function
main() {
    log "IoTDB Installation Script (Enhanced)"
    echo "Target version: $IOTDB_VERSION"
    echo "Installation directory: $INSTALL_DIR"
    echo "Download directory: $DOWNLOAD_DIR"
    echo "Cluster name: $CLUSTER_NAME"
    echo "RPC port: $DN_RPC_PORT"
    echo ""
    
    # Handle uninstall-only mode
    if [ "$UNINSTALL_ONLY" = true ]; then
        check_root
        uninstall_iotdb
        exit 0
    fi
    
    # Check for existing installation
    check_existing_installation
    
    log "Starting IoTDB $IOTDB_VERSION installation..."
    
    # Execute installation steps
    check_root
    install_dependencies
    check_system_requirements
    configure_system
    download_iotdb
    install_iotdb
    configure_iotdb
    create_service_files
    start_iotdb
    verify_installation
    print_usage
    
    log "IoTDB $IOTDB_VERSION installation completed successfully!"
}

# Cleanup function
cleanup() {
    if [ $? -ne 0 ]; then
        log_error "Installation failed. Cleaning up..."
        # Clean up any temporary files
        rm -rf /tmp/iotdb-extract-*
    fi
}

# Main execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Set error handling
    trap cleanup EXIT
    
    # Parse command line arguments
    parse_arguments "$@"
    
    # Run main function
    main
fi
