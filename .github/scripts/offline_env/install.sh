#!/bin/bash

RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RESET='\033[0m'
red_echo() { echo -e "${RED}$*${RESET}"; }
green_echo() { echo -e "${GREEN}$*${RESET}"; }
yellow_echo() { echo -e "${YELLOW}$*${RESET}"; }

script_path=$(dirname "$(readlink -f "$0")")
binary_dir=/usr/bin

function install_venv() {
    if [ -d "$script_path/py_venv" ];then
        yellow_echo "Installing pyvenv ..."
        cp -r "$script_path"/py_venv/.[!.]* "$HOME"
        venv_dir=$(find . -type d -name ".venv*" -print -quit)
        venv_name=$(basename "$venv_dir")
        green_echo "You can activate pyvenv via:\n\tsource $HOME/$venv_name/bin/activate"
    fi
}

function install_binary_tools() {
    if [ -d "$script_path/binary_tools" ];then
        yellow_echo "Installing binary_tools ..."
        for tool in "$script_path/binary_tools"/*; do
            tool_name=$(basename "$tool")
            if [ -f "$binary_dir/$tool_name" ];then
                mv "$binary_dir/$tool_name" "$binary_dir/$tool_name.bak"
            fi
            cp -rf "$script_path/binary_tools/$tool_name" "$binary_dir"
        done
    fi
}

function install_system_packages() {
    yellow_echo "Installing offline pkgs"
    if [ -f /etc/redhat-release ]; then
        rpm -Uvh --replacepkgs --nodeps "$script_path"/py_venv/system_packages/*.rpm >/dev/null 2>&1
        # yum localinstall -y "$script_path"/py_venv/system_packages/*.rpm >/dev/null 2>&1
    elif [ -f /etc/debian_version ]; then
        DEBIAN_FRONTEND=noninteractive dpkg -i "$script_path"/py_venv/system_packages/*.deb >/dev/null 2>&1
    else
        red_echo "Unsupported Linux distribution.. Please install the packages manually."
    fi
}

function main() {
    if [ -f /etc/os-release ]; then
        install_venv
        install_binary_tools
        install_system_packages
    else
        red_echo "Cannot detect OS and set OS_ID and OS_VERSION to unkown"
    fi
}
