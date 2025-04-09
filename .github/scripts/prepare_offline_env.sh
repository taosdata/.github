#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <pub_dl_url> <test_root> <pip_source>"
    echo "or"
    echo "Usage: $0 <pub_dl_url>"
    echo "Example:"
    echo "  $0 https:****/download /root/tests https://pypi.tuna.tsinghua.edu.cn/simple"
    exit 1
fi

# Input parameters
system_packages="$1"     # yum/apt packages
python_version="$2:-3.8" # python version
python_packages="$3"     # python packages
env_version="$4:3.0.0.0" # offline env version

offline_env_dir="$HOME/offline-env-$env_version"
system_packages_dir="$offline_env_dir/system_packages"
py_venv_dir="$offline_env_dir/py_venv"
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Force clean and create dir
rm -rf "$offline_env_dir"
mkdir -p "$system_packages_dir"
mkdir -p "$py_venv_dir"

if [ -n "$system_packages" ]; then
    echo "Downloading system packages: $system_packages"
    if [ -f /etc/redhat-release ]; then
        # TODO
        yum install -y "$system_packages" --downloadonly --downloaddir="$system_packages_dir"
    elif [ -f /etc/debian_version ]; then
        # TODO
        apt-get install --download-only -y "$system_packages" -o Dir::Cache::archives="$system_packages_dir"
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
        "$script_dir"/setup_env.sh uv
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
    uv pip install "$python_packages"

    echo "Copying the installed environment to $py_venv_dir..."
    cp -r "$HOME/.venv$python_version" "$py_venv_dir"
    cp -r "$HOME/.local" "$py_venv_dir"
else
    echo "No Python packages to install."
fi

echo "Offline env download completed."