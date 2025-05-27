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
EXPECTED_OS_RELEASE="$script_path"/os-release
CURRENT_OS_RELEASE="/etc/os-release"

compare_field() {
    local field=$1
    local expected_val
    expected_val=$(grep "^$field=" "$EXPECTED_OS_RELEASE" | cut -d= -f2 | tr -d '"')
    local current_val
    current_val=$(grep "^$field=" "$CURRENT_OS_RELEASE" | cut -d= -f2 | tr -d '"')

    if [ "$expected_val" != "$current_val" ]; then
        echo "Unmatched $field in os-release file: ./os-release='$expected_val', /etc/os-release='$current_val'" >&2
        return 1
    fi
    return 0
}

compare_field "ID" || exit 1
compare_field "VERSION_ID" || exit 1

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
    yellow_echo "Installing offline pkgs ..."
    if [ -f /etc/redhat-release ] || [ -f /etc/kylin-release ]; then
        compare_field "ID" || exit 1
        compare_field "VERSION_ID" || exit 1
        for i in "$script_path/system_packages/"*.rpm;
        do
            rpm -ivh --nodeps "$i"  >/dev/null 2>&1
        done
        # rpm -Uvh --replacepkgs --nodeps "$script_path/system_packages/"*.rpm >/dev/null 2>&1
        # yum localinstall -y "$script_path"/py_venv/system_packages/*.rpm >/dev/null 2>&1
    elif [ -f /etc/debian_version ]; then
        DEBIAN_FRONTEND=noninteractive dpkg -i "$script_path/system_packages/"*.deb >/dev/null 2>&1
    else
        red_echo "Unsupported Linux distribution.. Please install the packages manually."
    fi
}

function main() {
    if [ -f /etc/os-release ]; then
        install_venv
        install_binary_tools
        install_system_packages
        green_echo "Install finished, please check your env"
    else
        red_echo "Cannot detect OS and set OS_ID and OS_VERSION to unkown"
    fi
}

main