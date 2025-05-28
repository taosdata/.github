#!/bin/bash


# ==============================================
# Parameter Parsing Module
# ==============================================

MODE="build"
SYSTEM_PACKAGES=""
PYTHON_VERSION=""
PYTHON_PACKAGES=""
PKG_LABEL=""
BINARY_TOOLS=("bpftrace")
TDGPT=""

function show_usage() {
    echo "Usage:"
    echo "  Option      Mode: $0 [--build|--test] --system-packages=<pkgs> --python-version=<ver> --python-packages=<pkgs> --pkg-label=<label>"
    echo "Example:"
    echo "  $0 --build --system-packages=vim,ntp --python-version=3.10 --python-packages=fabric2,requests --pkg-label=1.0.20250409"
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
        --pkg-label=*)
            PKG_LABEL="${1#*=}"
            shift
            ;;
        --tdgpt=*)
            TDGPT="${1#*=}"
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
    if [[ -z "$SYSTEM_PACKAGES" && -z "$PYTHON_PACKAGES" ]]; then
        package_error="At least one of **SYSTEM_PACKAGES** or **PYTHON_PACKAGES** must be provided."
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

function init() {
    SUB_VERSION=""
    if [ -f /etc/os-release ]; then
        OS_ID=$(source /etc/os-release; echo $ID)
        case $OS_ID in
            ubuntu|debian)
                OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
                OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
                PKG_MGR="apt"
                PKG_CONFIRM="dpkg -l"
                ;;
            centos|rhel|rocky|kylin)
                OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
                OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
                if [ "$OS_ID" = "kylin" ];then
                    SUB_VERSION="$(cat /etc/.productinfo | awk '/SP2/ {split($0,a,"/"); gsub(/[()]/,"",a[2]); print "SP2-"a[3]} /SP3/ {split($0,a,"/"); gsub(/[()]/,"",a[2]); print "SP3-"a[3]}' | paste -sd '_')-"
                fi
                PKG_MGR="yum"
                PKG_CONFIRM="rpm -q"
                ;;
            *)
                red_echo "Unsupported OS and set OS_ID and OS_VERSION to unkown"
                OS_ID=unknown_os
                OS_VERSION=""
                PKG_MGR=""
                PKG_CONFIRM=""
        esac
    else
        red_echo "Cannot detect OS and set OS_ID and OS_VERSION to unkown"
        OS_ID=unknown_os
        OS_VERSION=""
    fi

    formated_system_packages=$(echo "$SYSTEM_PACKAGES" | tr ',' ' ')
    formated_python_packages=$(echo "$PYTHON_PACKAGES" | tr ',' ' ')
    if [[ -z "$PARENT_DIR" ]]; then
        parent_dir=/opt/offline-env
    else
        parent_dir=$PARENT_DIR
    fi
    mkdir -p "$parent_dir"
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
        if [[ -n "$PYTHON_PACKAGES" ]]; then
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

function install_system_packages() {
    if [ -n "$SYSTEM_PACKAGES" ]; then
        yellow_echo "Downloading system packages: $SYSTEM_PACKAGES"
        if [ -f /etc/redhat-release ] || [ -f /etc/kylin-release ]; then
            # TODO Confirm
            source /etc/os-release
            if [ "$ID" = "centos" ] && [ "$VERSION_ID" = "7" ];then
                config_yum
            fi
            yellow_echo "$PKG_MGR updating"
            $PKG_MGR update -q -y
            $PKG_MGR install -q -y yum-utils wget
            for pkg in $formated_system_packages;
            do
                if [[ "$pkg" == "bpftrace" ]] && [ "$ID" = "centos" ]; then
                    yellow_echo "Handling bpftrace specially for CentOS/RHEL..."
                    BPFTRACE_URL="https://github.com/bpftrace/bpftrace/releases/download/v0.23.2/bpftrace"
                    mkdir -p "$offline_env_path/binary_tools"
                    if ! wget -q "$BPFTRACE_URL" -O "$offline_env_path/binary_tools/bpftrace"; then
                        red_echo "Failed to download bpftrace binary"
                        exit 1
                    fi
                    chmod +x "$offline_env_path/binary_tools/bpftrace"
                    continue
                else
                    $PKG_MGR install -q -y dnf-plugins-core
                    pkg_name=$(yum provides "$pkg" 2>/dev/null | grep -E "^(|[0-9]+:)[^/]*${pkg}-" | head -1 | awk '{print $1}')
                    format_name=$(echo "$pkg_name" | sed -E 's/^[0-9]+://; s/\.[^.]+$//')
                    yellow_echo "Downloading offline pkgs......"
                    if [ -f /etc/kylin-release ];then
                        repotrack --destdir "$system_packages_dir" "$format_name"
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
            apt-rdepends $formated_system_packages | grep -v "^ " > raw_deps.txt
            # echo $(cat raw_deps.txt) | xargs -n 5 apt-cache policy | awk '
            #     /^[^ ]/ { pkg=$0 }
            #     /Candidate:/ && $2 == "(none)" { print pkg >> dependencies.txt }
            # '
            cat raw_deps.txt | tr '\n' ' ' | xargs -n 20 apt-cache policy | awk '
                /^[^ ]/ {
                    current_pkg = $0;
                    sub(/:$/, "", current_pkg)
                }
                /Candidate:/ && $2 != "(none)" {
                    print current_pkg >> "/dependencies.txt"
                }
            '
            chown -R _apt:root "$system_packages_dir"
            chmod -R 700 "$system_packages_dir"
            cd "$system_packages_dir" || exit
            yellow_echo "Downloading offline pkgs......"
            apt-get download $(cat /dependencies.txt)
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
        exit 1
    fi
}

function install_python_packages() {
    if [ -n "$PYTHON_PACKAGES" ]; then
        yellow_echo "Installing uv and Python $PYTHON_VERSION and packages: $PYTHON_PACKAGES"

        # Install uv with setup_env.sh
        if ! command -v uv &> /dev/null; then
            curl -o "$script_dir"/setup_env.sh https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh
            chmod +x "$script_dir"/setup_env.sh
            "$script_dir"/setup_env.sh install_uv
        fi

        if [ -f "$HOME/.local/bin/env" ]; then
            source "$HOME/.local/bin/env"
        else
            red_echo "Error: $HOME/.local/bin/env not found."
            exit 1
        fi

        if [ "$TDGPT" == "true" ];then
            python_venv_dir="/var/lib/taos/taosanode/venv"
        else
            python_venv_dir="$HOME/.venv$PYTHON_VERSION"
        fi
        mkdir -p "$python_venv_dir"


        yellow_echo "Installing Python $PYTHON_VERSION using uv..."
        uv python install "$PYTHON_VERSION"
        uv venv --python "$PYTHON_VERSION" "$python_venv_dir"

        yellow_echo "Installing Python packages..."
        source "$python_venv_dir"/bin/activate
        IFS=',' read -ra pkg_array <<< "$PYTHON_PACKAGES"
        for pkg in "${pkg_array[@]}"
        do
            echo "installing: $pkg"
            uv pip install $pkg
        done
        # uv pip install $formated_python_packages -i https://pypi.tuna.tsinghua.edu.cn/simple
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
    if [ -f /etc/redhat-release ] || [ -f /etc/kylin-release ]; then
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
        red_echo "[ERROR] Unkown mode: $MODE"
        exit 1
        ;;
esac