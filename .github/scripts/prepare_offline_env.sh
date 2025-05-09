#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <system_packages> <python_version> <python_packages> <pkg_label>"
    echo "Example:"
    echo "  $0 vim,ntp 3.10 fabric2,requests 1.0.20250409"
    exit 1
fi

if [ -f /etc/os-release ]; then
    OS_ID=$(source /etc/os-release; echo $ID)
    case $OS_ID in
        ubuntu)
            OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
            OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
            ;;
        centos)
            OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
            OS_VERSION=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
            ;;
        *)
            echo "Unsupported OS and set OS_ID and OS_VERSION to unkown"
            OS_ID=unknown_os
            OS_VERSION=""
    esac
else
    echo "Cannot detect OS and set OS_ID and OS_VERSION to unkown"
    OS_ID=unknown_os
    OS_VERSION=""
fi

PACKAGE_NAME="package_${OS_ID}${OS_VERSION}_$(date +%Y%m%d).tar.gz"
echo $PACKAGE_NAME

# Input parameters
system_packages="$1"     # yum/apt packages
python_version="$2"      # python version
python_packages="$3"     # python packages
pkg_label="$4"           # offline pkg label

formated_system_packages=$(echo "$system_packages" | tr ',' ' ')
formated_python_packages=$(echo "$python_packages" | tr ',' ' ')


offline_env_dir="offline-pkg-$OS_ID-$OS_VERSION-$pkg_label"
offline_env_path="$HOME/$offline_env_dir"
system_packages_dir="$offline_env_path/system_packages"
tar_file="$system_packages_dir/system_packages.tar"
py_venv_dir="$offline_env_path/py_venv"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Force clean and create dir
rm -rf "$offline_env_path"
mkdir -p "$system_packages_dir"
mkdir -p "$py_venv_dir"

if [ -z "$system_packages" ] && [ -z "$python_packages" ]; then
    echo "No system packages specified."
    exit 1
fi


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
            echo "The line already exists in /etc/yum.conf."
        else
            # Append the line after the [main] section
            sed -i "/^\[main\]/a $EXCLUDE_LINE" /etc/yum.conf
            echo "Successfully added '$EXCLUDE_LINE' to /etc/yum.conf."
        fi
    else
        echo "/etc/yum.conf file does not exist."
    fi
}

function install_system_packages() {
    if [ -n "$system_packages" ]; then
        echo "Downloading system packages: $system_packages"
        if [ -f /etc/redhat-release ]; then
            # TODO Confirm
            config_yum
            yum update -y
            yum install -y yum-utils wget
            for pkg in $formated_system_packages;
            do
                pkg_name=$(yum provides "$pkg" 2>/dev/null | grep -E "^(|[0-9]+:)[^/]*${pkg}-" | head -1 | awk '{print $1}')
                format_name=$(echo "$pkg_name" | sed -E 's/^[0-9]+://; s/\.[^.]+$//')
                repotrack -p "$system_packages_dir" "$format_name"
            done
            # # Why not use the following two methods?
            # * yumdownloader or downloadonly will not download already installed dependencies.
            # yum install -y $formated_system_packages --downloadonly --downloaddir="$system_packages_dir" --setopt=installonly=False
            # * repotrack must match the exact package name.
            # repotrack -p "$system_packages_dir" $formated_system_packages
        elif [ -f /etc/debian_version ]; then
            # TODO
            # apt-get install --download-only -y $formated_system_packages -o Dir::Cache::archives="$system_packages_dir"
            apt update -y
            apt install -y apt-offline wget curl openssh-client apt-rdepends
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
            echo "Unsupported Linux distribution.. Please install the packages manually."
        fi
    else
        echo "No system packages to install."
    fi
}

function install_python_packages() {
    if [ -n "$python_packages" ]; then
        echo "Installing uv and Python $python_version and packages: $python_packages"

        # Install uv with setup_env.sh
        if ! command -v uv &> /dev/null; then
            curl -o "$script_dir"/setup_env.sh https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh
            chmod +x "$script_dir"/setup_env.sh
            "$script_dir"/setup_env.sh install_uv
        fi

        if [ -f "$HOME/.local/bin/env" ]; then
            source "$HOME/.local/bin/env"
        else
            echo "Error: $HOME/.local/bin/env not found."
            exit 1
        fi

        echo "Installing Python $python_version using uv..."
        uv python install "$python_version"
        uv venv --python "$python_version" "$HOME/.venv$python_version"

        echo "Installing Python packages..."
        source "$HOME/.venv$python_version"/bin/activate
        uv pip install $formated_python_packages -i https://pypi.tuna.tsinghua.edu.cn/simple

        echo "Copying the installed environment to $py_venv_dir..."
        cp -r "$HOME/.venv$python_version" "$py_venv_dir"
        cp -r "$HOME/.local" "$py_venv_dir"
    else
        echo "No Python packages to install."
    fi
}

function summary() {
    cd "$HOME" || exit
    tar zcf "$offline_env_dir.tar.gz" "$offline_env_dir"
    mv "$offline_env_dir.tar.gz" "$offline_env_path"
    echo "Offline env completed, please check $offline_env_path/$offline_env_dir.tar.gz"
    # cp -r .[!.]* ~
    # rpm -ivh --nodeps --force *.rpm
}

install_system_packages
install_python_packages
summary
