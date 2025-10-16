#!/bin/bash

# Microsoft SQL Server Installation Script
# Supports CentOS 7.9 and Ubuntu 22.04
# Supports offline installation with custom version
# Author: Automated deployment script
# Version: 1.0

set -euo pipefail

# =============================================================================
# Configuration and Variables
# =============================================================================

# Default configuration
DEFAULT_VERSION="2022"
DEFAULT_INSTALL_DIR="/opt/mssql"
DEFAULT_DATA_DIR="/var/opt/mssql/data"
DEFAULT_PACKAGES_DIR="/tmp/mssql-packages"
DEFAULT_SA_PASSWORD="MyStr0ng!P@ssw0rd"
DEFAULT_EDITION="2"  # Developer edition

# Script options
MSSQL_VERSION="${MSSQL_VERSION:-$DEFAULT_VERSION}"
INSTALL_DIR="${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}"
DATA_DIR="${DATA_DIR:-$DEFAULT_DATA_DIR}"
PACKAGES_DIR="${PACKAGES_DIR:-$DEFAULT_PACKAGES_DIR}"
SA_PASSWORD="${SA_PASSWORD:-$DEFAULT_SA_PASSWORD}"
EDITION="${EDITION:-$DEFAULT_EDITION}"
SKIP_CONFIG="${SKIP_CONFIG:-false}"
UNINSTALL="${UNINSTALL:-false}"
FORCE_DOWNLOAD="${FORCE_DOWNLOAD:-false}"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# =============================================================================
# Helper Functions
# =============================================================================

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Print usage information
print_usage() {
    cat << EOF
Microsoft SQL Server Installation Script

Usage: $0 [OPTIONS]

Options:
    -v, --version VERSION       SQL Server version (2017, 2019, 2022) [default: 2022]
                                Note: Ubuntu 22.04 only supports 2022; CentOS 7 supports 2017 and 2019
    -i, --install-dir DIR       Installation directory [default: /opt/mssql]
    -d, --data-dir DIR          Data directory [default: /var/opt/mssql/data]
    -p, --packages-dir DIR      Local packages directory [default: /tmp/mssql-packages]
    -s, --sa-password PASSWORD  SA user password [default: MyStr0ng!P@ssw0rd]
    -e, --edition EDITION      Edition number (1=Evaluation, 2=Developer, 3=Express, 4=Web, 5=Standard, 6=Enterprise) [default: 2]
    -c, --skip-config          Skip SQL Server configuration
    -u, --uninstall            Uninstall SQL Server
    -f, --force-download       Force download even if package exists
    -h, --help                 Show this help message

Environment Variables:
    MSSQL_VERSION              SQL Server version
    INSTALL_DIR                Installation directory
    DATA_DIR                   Data directory
    PACKAGES_DIR               Local packages directory
    SA_PASSWORD                SA user password
    EDITION                    Edition number
    SKIP_CONFIG                Skip configuration (true/false)
    UNINSTALL                  Uninstall mode (true/false)
    FORCE_DOWNLOAD             Force download (true/false)

Examples:
    # Install SQL Server 2022 with default settings
    $0

    # Install SQL Server 2019 with custom directories
    $0 -v 2019 -i /opt/mssql2019 -d /data/mssql

    # Install from local packages (offline)
    $0 -p /path/to/local/packages

    # Uninstall SQL Server
    $0 --uninstall

EOF
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Detect operating system
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
        OS_VERSION_MAJOR=$(echo $VERSION_ID | cut -d. -f1)
    else
        log_error "Cannot detect operating system"
        exit 1
    fi

    log_info "Detected OS: $OS $OS_VERSION"
}

# Check system compatibility
check_compatibility() {
    log_info "Checking system compatibility..."

    # Check supported OS versions and SQL Server version compatibility
    case "$OS" in
        "centos")
            if [[ "$OS_VERSION_MAJOR" != "7" ]]; then
                log_error "CentOS $OS_VERSION is not supported. Only CentOS 7.x is supported."
                exit 1
            fi
            # CentOS 7 only supports SQL Server 2017 and 2019
            if [[ "$MSSQL_VERSION" != "2017" && "$MSSQL_VERSION" != "2019" ]]; then
                log_error "CentOS 7 only supports SQL Server 2017 and 2019."
                log_error "SQL Server $MSSQL_VERSION is not available for CentOS 7."
                log_error "Please use --version 2017 or --version 2019."
                exit 1
            fi
            ;;
        "ubuntu")
            if [[ "$OS_VERSION" != "22.04" ]]; then
                log_error "Ubuntu $OS_VERSION is not supported. Only Ubuntu 22.04 is supported."
                exit 1
            fi
            # Ubuntu 22.04 only supports SQL Server 2022
            if [[ "$MSSQL_VERSION" != "2022" ]]; then
                log_error "Ubuntu 22.04 only supports SQL Server 2022."
                log_error "SQL Server $MSSQL_VERSION is not available for Ubuntu 22.04."
                log_error "Please use --version 2022 or switch to CentOS 7 for versions 2017/2019."
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported operating system: $OS"
            exit 1
            ;;
    esac

    # Check memory (minimum 2GB)
    local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local total_mem_gb=$((total_mem_kb / 1024 / 1024))
    if [[ $total_mem_gb -lt 2 ]]; then
        log_warn "System has less than 2GB RAM. SQL Server may fail to start."
    fi

    # Check disk space (minimum 6GB for SQL Server)
    local available_space=$(df /var/opt/mssql 2>/dev/null | tail -1 | awk '{print $4}' || df / | tail -1 | awk '{print $4}')
    local available_gb=$((available_space / 1024 / 1024))
    if [[ $available_gb -lt 6 ]]; then
        log_warn "Available disk space is less than 6GB. This may not be sufficient for SQL Server."
    fi

    log_success "System compatibility check passed"
}

# Get version-specific configuration
get_version_config() {
    case "$MSSQL_VERSION" in
        "2017")
            PACKAGE_VERSION="14.0.3465.1"
            PACKAGE_RELEASE="1"
            REPO_PATH="mssql-server-2017"
            ;;
        "2019")
            PACKAGE_VERSION="15.0.4375.4"
            PACKAGE_RELEASE="1"
            REPO_PATH="mssql-server-2019"
            ;;
        "2022")
            PACKAGE_VERSION="16.0.4210.1"
            PACKAGE_RELEASE="1"
            REPO_PATH="mssql-server-2022"
            ;;
        *)
            log_error "Unsupported SQL Server version: $MSSQL_VERSION"
            log_error "Supported versions:"
            log_error "  - CentOS 7: SQL Server 2017, 2019"
            log_error "  - Ubuntu 22.04: SQL Server 2022"
            exit 1
            ;;
    esac

    log_info "Using SQL Server $MSSQL_VERSION (package version: $PACKAGE_VERSION)"
}

# Get platform-specific package information
get_platform_config() {
    case "$OS" in
        "ubuntu")
            if [[ "$MSSQL_VERSION" == "2022" ]]; then
                PKG_EXT="deb"
                PKG_NAME="mssql-server_${PACKAGE_VERSION}-${PACKAGE_RELEASE}_amd64.deb"
                BASE_URL="https://pmc-geofence.trafficmanager.net/ubuntu/22.04/mssql-server-2022/pool/main/m/mssql-server"
                INSTALL_CMD="dpkg -i"
                DEPS_CMD="apt-get install -f -y"
                SERVICE_NAME="mssql-server"
            else
                log_error "Ubuntu 22.04 only supports SQL Server 2022"
                exit 1
            fi
            ;;
        "centos")
            PKG_EXT="rpm"
            PKG_NAME="mssql-server-${PACKAGE_VERSION}-${PACKAGE_RELEASE}.x86_64.rpm"
            if [[ "$MSSQL_VERSION" == "2017" ]]; then
                BASE_URL="https://pmc-geofence.trafficmanager.net/rhel/7/mssql-server-2017/Packages/m"
            elif [[ "$MSSQL_VERSION" == "2019" ]]; then
                BASE_URL="https://pmc-geofence.trafficmanager.net/rhel/7/mssql-server-2019/Packages/m"
            else
                log_error "CentOS 7 only supports SQL Server 2017 and 2019"
                exit 1
            fi
            INSTALL_CMD="rpm -i"
            DEPS_CMD="yum install -y"
            SERVICE_NAME="mssql-server"
            ;;
    esac

    DOWNLOAD_URL="${BASE_URL}/${PKG_NAME}"
    PKG_PATH="${PACKAGES_DIR}/${PKG_NAME}"

    log_info "Package: $PKG_NAME"
    log_info "Download URL: $DOWNLOAD_URL"
}

# Create necessary directories
create_directories() {
    log_info "Creating directories..."
    
    mkdir -p "$PACKAGES_DIR"
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$DATA_DIR"
    mkdir -p "/var/log/mssql"
    mkdir -p "/var/opt/mssql"

    # Create mssql user if it doesn't exist
    if ! id "mssql" &>/dev/null; then
        useradd -r -s /bin/false mssql
        log_info "Created mssql user"
    fi

    # Set permissions
    chown -R mssql:mssql "$DATA_DIR" "/var/log/mssql" "/var/opt/mssql"
    chmod 755 "$DATA_DIR" "/var/log/mssql" "/var/opt/mssql"
}

# Check if SQL Server is already installed
check_existing_installation() {
    if command -v /opt/mssql/bin/sqlservr &> /dev/null; then
        log_info "SQL Server is already installed"
        return 0
    else
        log_info "SQL Server is not installed"
        return 1
    fi
}

# Install dependencies
install_dependencies() {
    log_info "Installing dependencies..."

    case "$OS" in
        "ubuntu")
            export DEBIAN_FRONTEND=noninteractive
            apt-get update
            apt-get install -y curl wget gnupg2 software-properties-common
            apt-get install -y libc++1 libsss-nss-idmap0 libsasl2-modules-gssapi-mit
            ;;
        "centos")
            yum install -y curl wget gnupg2
            yum install -y bash bzip2 cyrus-sasl cyrus-sasl-gssapi gawk gdb glibc \
                krb5-libs libatomic libsss_nss_idmap lsof numactl-libs openldap \
                openssl pam procps-ng python3 sed systemd tzdata
            ;;
    esac

    log_success "Dependencies installed successfully"
}

# Download SQL Server package
download_package() {
    local pkg_path="$1"
    
    if [[ -f "$pkg_path" && "$FORCE_DOWNLOAD" != "true" ]]; then
        log_info "Package already exists: $pkg_path"
        return 0
    fi

    log_info "Downloading SQL Server package..."
    log_info "URL: $DOWNLOAD_URL"
    log_info "Destination: $pkg_path"

    if ! curl -L -o "$pkg_path" "$DOWNLOAD_URL"; then
        log_error "Failed to download package from $DOWNLOAD_URL"
        return 1
    fi

    if [[ ! -f "$pkg_path" ]]; then
        log_error "Package download failed: $pkg_path does not exist"
        return 1
    fi

    log_success "Package downloaded successfully"
    return 0
}

# Verify package integrity
verify_package() {
    local pkg_path="$1"
    
    log_info "Verifying package integrity..."
    
    # Check file size (should be > 100MB for SQL Server)
    local file_size=$(stat -c%s "$pkg_path" 2>/dev/null || echo "0")
    local size_mb=$((file_size / 1024 / 1024))
    
    if [[ $size_mb -lt 100 ]]; then
        log_error "Package file seems too small: ${size_mb}MB (expected > 100MB)"
        log_error "This suggests the package file is corrupted or incomplete"
        return 1
    fi
    
    log_info "Package size: ${size_mb}MB"
    
    case "$OS" in
        "ubuntu")
            # Verify DEB package
            if ! dpkg --info "$pkg_path" > /dev/null 2>&1; then
                log_error "Invalid DEB package format"
                return 1
            fi
            ;;
        "centos")
            # Verify RPM package
            if ! rpm -qp "$pkg_path" > /dev/null 2>&1; then
                log_error "Invalid RPM package format"
                return 1
            fi
            
            # Check RPM signature (warning only, don't fail)
            if ! rpm --checksig "$pkg_path" > /dev/null 2>&1; then
                log_warn "RPM package signature verification failed (continuing anyway)"
            fi
            ;;
    esac
    
    log_success "Package verification completed"
    return 0
}

# Check system resources before installation
check_installation_requirements() {
    log_info "Checking installation requirements..."
    
    # Check available disk space in /opt and /var
    local opt_available=$(df /opt 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local var_available=$(df /var 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local opt_gb=$((opt_available / 1024 / 1024))
    local var_gb=$((var_available / 1024 / 1024))
    
    log_info "Available disk space: /opt: ${opt_gb}GB, /var: ${var_gb}GB"
    
    if [[ $opt_gb -lt 3 ]]; then
        log_error "Insufficient disk space in /opt: ${opt_gb}GB (required: 3GB)"
        exit 1
    fi
    
    if [[ $var_gb -lt 2 ]]; then
        log_error "Insufficient disk space in /var: ${var_gb}GB (required: 2GB)"
        exit 1
    fi
    
    # Check if /tmp has enough space for extraction
    local tmp_available=$(df /tmp 2>/dev/null | tail -1 | awk '{print $4}' || echo "0")
    local tmp_gb=$((tmp_available / 1024 / 1024))
    log_info "Available disk space in /tmp: ${tmp_gb}GB"
    
    if [[ $tmp_gb -lt 2 ]]; then
        log_warn "Low disk space in /tmp: ${tmp_gb}GB (recommended: 2GB)"
    fi
    
    # Check for existing SQL Server installation
    case "$OS" in
        "ubuntu")
            if dpkg -l | grep -q mssql-server 2>/dev/null; then
                log_warn "Existing SQL Server installation detected:"
                dpkg -l | grep mssql-server | awk '{print "  " $2 " " $3}'
                log_warn "This may cause conflicts. Consider uninstalling first."
            fi
            ;;
        "centos")
            if rpm -qa | grep -q mssql-server 2>/dev/null; then
                log_warn "Existing SQL Server installation detected:"
                rpm -qa | grep mssql-server | sed 's/^/  /'
                log_warn "This may cause conflicts. Consider uninstalling first."
            fi
            ;;
    esac
    
    log_success "Installation requirements check completed"
}

# Install SQL Server package
install_package() {
    local pkg_path="$1"

    if [[ ! -f "$pkg_path" ]]; then
        log_error "Package not found: $pkg_path"
        exit 1
    fi

    # Verify package before installation
    if ! verify_package "$pkg_path"; then
        log_error "Package verification failed. Please re-download the package."
        exit 1
    fi
    
    # Check system requirements
    check_installation_requirements

    log_info "Installing SQL Server package..."

    case "$OS" in
        "ubuntu")
            if ! $INSTALL_CMD "$pkg_path"; then
                log_warn "Initial package installation failed, fixing dependencies..."
                $DEPS_CMD
                if ! $INSTALL_CMD "$pkg_path"; then
                    log_error "Package installation failed"
                    exit 1
                fi
            fi
            ;;
        "centos")
            # Clean YUM cache first
            log_info "Cleaning YUM cache..."
            yum clean all > /dev/null 2>&1
            
            # Try YUM first for better dependency handling
            log_info "Attempting installation via YUM..."
            if yum localinstall -y --nogpgcheck "$pkg_path" 2>&1 | tee /tmp/yum_install.log; then
                log_success "Package installed successfully via YUM"
            else
                log_warn "YUM installation failed, checking error details..."
                
                # Check for specific error patterns
                if grep -q "unpacking of archive failed" /tmp/yum_install.log; then
                    log_error "RPM archive unpacking failed. This usually indicates:"
                    log_error "1. Corrupted package file"
                    log_error "2. Insufficient disk space"
                    log_error "3. File system errors"
                    
                    # Additional diagnostics
                    log_info "Running additional diagnostics..."
                    log_info "Disk space check:"
                    df -h /opt /var /tmp
                    
                    log_info "File system check for /opt:"
                    ls -la /opt/ || log_warn "Cannot access /opt directory"
                    
                    log_info "Package file details:"
                    ls -lh "$pkg_path"
                    file "$pkg_path"
                    
                elif grep -q "Header V4 RSA/SHA256 Signature" /tmp/yum_install.log; then
                    log_warn "Signature verification failed, trying with --nogpgcheck..."
                fi
                
                log_info "Attempting fallback RPM installation..."
                if rpm -ivh --force --nodeps --nogpgcheck "$pkg_path"; then
                    log_success "Package installed via RPM fallback"
                    # Install missing dependencies
                    log_info "Installing dependencies..."
                    $DEPS_CMD bash bzip2 cyrus-sasl cyrus-sasl-gssapi gawk gdb glibc \
                        krb5-libs libatomic libsss_nss_idmap lsof numactl-libs openldap \
                        openssl pam procps-ng python3 sed systemd tzdata
                else
                    log_error "Both YUM and RPM installation methods failed"
                    log_error "Package installation failed"
                    
                    # Cleanup any partial installation
                    log_info "Cleaning up partial installation..."
                    rpm -e mssql-server 2>/dev/null || true
                    
                    exit 1
                fi
            fi
            
            # Clean up log file
            rm -f /tmp/yum_install.log
            ;;
    esac

    log_success "SQL Server package installed successfully"
}

# Configure SQL Server
configure_sqlserver() {
    if [[ "$SKIP_CONFIG" == "true" ]]; then
        log_info "Skipping SQL Server configuration as requested"
        return 0
    fi

    log_info "Configuring SQL Server..."

    # Check if already configured
    if [[ -f /var/opt/mssql/mssql.conf ]] && [[ $(wc -l < /var/opt/mssql/mssql.conf) -gt 3 ]]; then
        log_info "SQL Server appears to be already configured"
        return 0
    fi

    # Set SA password and edition using environment variables
    export MSSQL_SA_PASSWORD="$SA_PASSWORD"
    export ACCEPT_EULA=Y
    
    # Map edition number to correct PID
    case "$EDITION" in
        "1") export MSSQL_PID="Evaluation" ;;
        "2") export MSSQL_PID="Developer" ;;
        "3") export MSSQL_PID="Express" ;;
        "4") export MSSQL_PID="Web" ;;
        "5") export MSSQL_PID="Standard" ;;
        "6") export MSSQL_PID="Enterprise" ;;
        *) 
            log_warn "Unknown edition: $EDITION, using Developer"
            export MSSQL_PID="Developer"
            ;;
    esac
    
    log_info "Configuring SQL Server with edition: $MSSQL_PID"

    if /opt/mssql/bin/mssql-conf -n setup accept-eula; then
        log_success "SQL Server configured successfully"
    else
        log_error "SQL Server configuration failed"
        exit 1
    fi
}

# Start and enable SQL Server service
start_service() {
    log_info "Starting SQL Server service..."

    systemctl daemon-reload
    
    if systemctl start mssql-server; then
        log_success "SQL Server service started"
    else
        log_error "Failed to start SQL Server service"
        log_info "Checking service status..."
        systemctl status mssql-server || true
        exit 1
    fi

    if systemctl enable mssql-server; then
        log_info "SQL Server service enabled for auto-start"
    else
        log_warn "Failed to enable SQL Server service for auto-start"
    fi
}

# Verify installation
verify_installation() {
    log_info "Verifying SQL Server installation..."

    # Check if SQL Server process is running
    if pgrep -f sqlservr > /dev/null; then
        log_success "SQL Server process is running"
    else
        log_error "SQL Server process is not running"
        return 1
    fi

    # Check service status
    if systemctl is-active --quiet mssql-server; then
        log_success "SQL Server service is active"
    else
        log_error "SQL Server service is not active"
        return 1
    fi

    # Check if SQL Server is listening on port 1433
    if command -v ss >/dev/null 2>&1; then
        if ss -tlnp | grep :1433 > /dev/null 2>&1; then
            log_success "SQL Server is listening on port 1433"
        else
            log_warn "SQL Server may not be listening on port 1433"
        fi
    elif command -v netstat >/dev/null 2>&1; then
        if netstat -tlnp | grep :1433 > /dev/null 2>&1; then
            log_success "SQL Server is listening on port 1433"
        else
            log_warn "SQL Server may not be listening on port 1433"
        fi
    else
        log_warn "Neither ss nor netstat available, skipping port check"
    fi

    log_success "SQL Server installation verification completed"
}

# Uninstall SQL Server
uninstall_sqlserver() {
    log_info "Uninstalling SQL Server..."

    # Stop service
    if systemctl is-active --quiet mssql-server; then
        systemctl stop mssql-server
        log_info "Stopped SQL Server service"
    fi

    # Disable service
    if systemctl is-enabled --quiet mssql-server; then
        systemctl disable mssql-server
        log_info "Disabled SQL Server service"
    fi

    # Remove package
    case "$OS" in
        "ubuntu")
            if dpkg -l | grep -q mssql-server; then
                dpkg -r mssql-server
                apt-get autoremove -y
                log_info "Removed SQL Server package (Ubuntu)"
            fi
            ;;
        "centos")
            if rpm -qa | grep -q mssql-server; then
                rpm -e mssql-server
                log_info "Removed SQL Server package (CentOS)"
            fi
            ;;
    esac

    # Remove data directories (with confirmation)
    read -p "Do you want to remove SQL Server data directories? [y/N]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf /var/opt/mssql
        rm -rf /opt/mssql
        log_info "Removed SQL Server data directories"
    fi

    log_success "SQL Server uninstalled successfully"
}

# Print installation summary
print_summary() {
    cat << EOF

${GREEN}=============================================================================
SQL Server Installation Summary
=============================================================================${NC}

${BLUE}Installation Details:${NC}
- SQL Server Version: $MSSQL_VERSION
- Package Version: $PACKAGE_VERSION
- Installation Directory: $INSTALL_DIR
- Data Directory: $DATA_DIR
- Service Name: $SERVICE_NAME

${BLUE}Service Information:${NC}
- Service Status: $(systemctl is-active mssql-server)
- Auto-start Enabled: $(systemctl is-enabled mssql-server)
- Process ID: $(pgrep -f sqlservr || echo "Not running")

${BLUE}Connection Information:${NC}
- Server: localhost
- Port: 1433
- SA Username: sa
- SA Password: $SA_PASSWORD

${BLUE}Useful Commands:${NC}
- Check service status: systemctl status mssql-server
- Start service: systemctl start mssql-server
- Stop service: systemctl stop mssql-server
- View logs: journalctl -u mssql-server
- Connect with sqlcmd: sqlcmd -S localhost -U sa -P '$SA_PASSWORD'

${YELLOW}Note: Install SQL Server command-line tools separately if needed:
- Ubuntu: apt-get install mssql-tools
- CentOS: yum install mssql-tools${NC}

EOF
}

# =============================================================================
# Main Installation Logic
# =============================================================================

main() {
    log_info "Starting Microsoft SQL Server installation..."
    log_info "Version: $MSSQL_VERSION"
    log_info "Target OS: CentOS 7.9 / Ubuntu 22.04"
    
    # Pre-installation checks
    check_root
    detect_os
    check_compatibility
    get_version_config
    get_platform_config

    # Handle uninstall
    if [[ "$UNINSTALL" == "true" ]]; then
        uninstall_sqlserver
        exit 0
    fi

    # Check if already installed
    if check_existing_installation; then
        log_warn "SQL Server is already installed. Use --uninstall to remove it first."
        exit 0
    fi

    # Installation process
    create_directories
    install_dependencies

    # Try to use local package first, then download if needed
    if [[ -f "$PKG_PATH" && "$FORCE_DOWNLOAD" != "true" ]]; then
        log_info "Using local package: $PKG_PATH"
    else
        if ! download_package "$PKG_PATH"; then
            log_error "Failed to download package. Please check:"
            log_error "1. Internet connectivity"
            log_error "2. Package availability for $OS $OS_VERSION"
            log_error "3. SQL Server $MSSQL_VERSION compatibility"
            exit 1
        fi
    fi

    install_package "$PKG_PATH"
    configure_sqlserver
    start_service
    verify_installation

    log_success "Microsoft SQL Server $MSSQL_VERSION installation completed successfully!"
    print_summary
}

# =============================================================================
# Command Line Argument Processing
# =============================================================================

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -v|--version)
            MSSQL_VERSION="$2"
            shift 2
            ;;
        -i|--install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        -d|--data-dir)
            DATA_DIR="$2"
            shift 2
            ;;
        -p|--packages-dir)
            PACKAGES_DIR="$2"
            shift 2
            ;;
        -s|--sa-password)
            SA_PASSWORD="$2"
            shift 2
            ;;
        -e|--edition)
            EDITION="$2"
            shift 2
            ;;
        -c|--skip-config)
            SKIP_CONFIG="true"
            shift
            ;;
        -u|--uninstall)
            UNINSTALL="true"
            shift
            ;;
        -f|--force-download)
            FORCE_DOWNLOAD="true"
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Validate SA password strength
if [[ ${#SA_PASSWORD} -lt 8 ]]; then
    log_error "SA password must be at least 8 characters long"
    exit 1
fi

# Run main installation
main

exit 0
