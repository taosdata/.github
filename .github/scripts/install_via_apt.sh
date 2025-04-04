#!/bin/bash

install_packages() {
    local packages=("$@")

    for package in "${packages[@]}"; do
        if ! dpkg -l | grep -wq "$package"; then
            echo "Installing $package..."
            if ! apt-get install -y "$package"; then
                if ! apt-get install -y --fix-missing "$package"; then
                    echo "Attempting to update and install $package..."
                    apt-get update -qq && apt-get install -y "$package"
                fi
            fi
        else
            echo "$package is already installed."
        fi
    done
}

install_packages "$@"