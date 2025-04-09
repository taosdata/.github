#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <system_packages> <python_version> <python_packages> <env_version>"
    echo "Example:"
    echo "  $0 vim,ntp 3.10 fabric2,requests 1.0.20250409"
    exit 1
fi

# Input parameters
system_packages="$1"     # yum/apt packages
python_version="$2"      # python version
python_packages="$3"     # python packages
env_version="$4"         # offline env version

formated_system_packages=$(echo "$system_packages" | tr ',' ' ')
formated_python_packages=$(echo "$python_packages" | tr ',' ' ')


offline_env_dir="offline-env-$env_version"
offline_env_path="$HOME/offline-env-$env_version"
system_packages_dir="$offline_env_path/system_packages"
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

if [ -n "$system_packages" ]; then
    echo "Downloading system packages: $system_packages"
    if [ -f /etc/redhat-release ]; then
        # TODO
        yum install -y yum-utils
        # yum install -y $formated_system_packages --downloadonly --downloaddir="$system_packages_dir" --setopt=installonly=False
        repotrack $formated_system_packages --download-path="$system_packages_dir"
    elif [ -f /etc/debian_version ]; then
        # TODO
        apt-get install --download-only -y $formated_system_packages -o Dir::Cache::archives="$system_packages_dir"
    else
        echo "Unsupported Linux distribution.. Please install the packages manually."
    fi
else
    echo "No system packages to install."
fi

if [ -n "$python_packages" ]; then
    echo "Installing uv and Python $python_version and packages: $python_packages"

    # Install uv with setup_env.sh
    if ! command -v uv &> /dev/null; then
        wget -O "$script_dir"/setup_env.sh https://raw.githubusercontent.com/taosdata/TDengine/main/packaging/setup_env.sh
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

tar zcf "$offline_env_dir.tar.gz" "$offline_env_dir"
mv "$offline_env_dir.tar.gz" "$offline_env_path"
echo "Offline env completed, please check $offline_env_path/$offline_env_dir.tar.gz"