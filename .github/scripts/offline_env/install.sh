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
taos_anode_dir=/var/lib/taos/taosanode
python_venv_dir="${taos_anode_dir}/venv"
venv_label=2
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
        if [ -d "$script_path/py_venv/venv" ];then
            mkdir -p "$taos_anode_dir"
            cp -r "$script_path/py_venv/venv" "$taos_anode_dir"
            venv_label=0
        else
            venv_label=1
        fi

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

function install_docker() {
    if [ -d "$script_path/docker" ]; then
        yellow_echo "Installing Docker..."
        
        # Read version and arch info
        if [ -f "$script_path/docker/version.txt" ]; then
            local docker_version
            docker_version=$(cat "$script_path/docker/version.txt")
            yellow_echo "Docker version: $docker_version"
        fi
        
        # Extract Docker binaries
        local docker_tgz
        docker_tgz=$(find "$script_path/docker" -name "docker-*.tgz" -print -quit)
        
        if [ -z "$docker_tgz" ]; then
            red_echo "Docker tarball not found"
            return 1
        fi
        
        # Extract to /tmp and move to /usr/bin
        local temp_dir="/tmp/docker_install_$$"
        mkdir -p "$temp_dir"
        tar -xzf "$docker_tgz" -C "$temp_dir"
        
        # Backup existing docker binaries if they exist
        for binary in "$temp_dir"/docker/*; do
            local binary_name
            binary_name=$(basename "$binary")
            if [ -f "/usr/bin/$binary_name" ]; then
                yellow_echo "Backing up existing $binary_name to /usr/bin/${binary_name}.bak"
                mv "/usr/bin/$binary_name" "/usr/bin/${binary_name}.bak"
            fi
        done
        
        # Install Docker binaries
        cp "$temp_dir"/docker/* /usr/bin/
        chmod +x /usr/bin/docker*
        
        # Cleanup
        rm -rf "$temp_dir"
        
        # Create docker systemd service if not exists
        if [ ! -f /etc/systemd/system/docker.service ]; then
            yellow_echo "Creating Docker systemd service..."
            cat > /etc/systemd/system/docker.service <<'EOF'
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service containerd.service
Wants=network-online.target
Requires=docker.socket containerd.service

[Service]
Type=notify
ExecStart=/usr/bin/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP $MAINPID
TimeoutSec=0
RestartSec=2
Restart=always
StartLimitBurst=3
StartLimitInterval=60s
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
Delegate=yes
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF

            cat > /etc/systemd/system/docker.socket <<'EOF'
[Unit]
Description=Docker Socket for the API

[Socket]
ListenStream=/var/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF

            cat > /etc/systemd/system/containerd.service <<'EOF'
[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=/usr/bin/containerd
Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
        fi
        
        # Create docker group if not exists
        if ! getent group docker > /dev/null; then
            groupadd docker
        fi
        
        # Reload systemd and enable docker
        systemctl daemon-reload
        systemctl enable docker.service
        systemctl enable containerd.service
        
        # Start Docker service (systemd will automatically start containerd due to dependency)
        yellow_echo "Starting Docker service..."
        if systemctl start docker.service; then
            green_echo "Docker service started successfully"
        else
            red_echo "Failed to start Docker service"
            yellow_echo "You can check logs with: journalctl -xu docker"
            return 1
        fi
        
        # Wait for Docker to be ready
        yellow_echo "Waiting for Docker to be ready..."
        local max_attempts=10
        local attempt=1
        while [ $attempt -le $max_attempts ]; do
            if docker info &>/dev/null; then
                green_echo "Docker is ready!"
                break
            fi
            if [ $attempt -eq $max_attempts ]; then
                red_echo "Docker is not responding after $max_attempts attempts"
                return 1
            fi
            echo "Waiting... (attempt $attempt/$max_attempts)"
            sleep 2
            ((attempt++))
        done
        
        # Show Docker version and status
        docker --version
        green_echo "Docker installed and started successfully"
    fi
}

function install_docker_compose() {
    if [ -d "$script_path/docker_compose" ]; then
        yellow_echo "Installing Docker Compose..."
        
        # Read version info
        if [ -f "$script_path/docker_compose/version.txt" ]; then
            local compose_version
            compose_version=$(cat "$script_path/docker_compose/version.txt")
            yellow_echo "Docker Compose version: $compose_version"
        fi
        
        # Backup existing docker-compose if it exists
        if [ -f /usr/local/bin/docker-compose ]; then
            yellow_echo "Backing up existing docker-compose to /usr/local/bin/docker-compose.bak"
            mv /usr/local/bin/docker-compose /usr/local/bin/docker-compose.bak
        fi
        
        # Install docker-compose
        mkdir -p /usr/local/bin
        cp "$script_path/docker_compose/docker-compose" /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        
        # Create symlink for docker compose plugin
        mkdir -p /usr/local/lib/docker/cli-plugins
        ln -sf /usr/local/bin/docker-compose /usr/local/lib/docker/cli-plugins/docker-compose
        
        green_echo "Docker Compose installed successfully at /usr/local/bin/docker-compose"
    fi
}

function install_system_packages() {
    if [ -d "$script_path/system_packages" ]; then
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
        elif [ -f /etc/SuSE-release ] || [ -f /etc/os-release ]; then
            # Check if it's a SUSE system
            if [ -f /etc/os-release ]; then
                OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
                if [ "$OS_ID" = "sles" ] || [ "$OS_ID" = "opensuse-leap" ] || [ "$OS_ID" = "suse" ]; then
                    compare_field "ID" || exit 1
                    compare_field "VERSION_ID" || exit 1
                    # Install RPM packages on SUSE systems
                    for i in "$script_path/system_packages/"*.rpm;
                    do
                        rpm -ivh --nodeps "$i" >/dev/null 2>&1
                    done
                else
                    red_echo "Unsupported Linux distribution.. Please install the packages manually."
                fi
            else
                red_echo "Unsupported Linux distribution.. Please install the packages manually."
            fi
        else
            red_echo "Unsupported Linux distribution.. Please install the packages manually."
        fi
    fi
}

function main() {
    if [ -f /etc/os-release ]; then
        install_venv
        install_binary_tools
        install_docker
        install_docker_compose
        install_system_packages
        green_echo "Install finished, please check your env"
        if [ $venv_label -eq 0 ];then
            green_echo "You can activate pyvenv via:\n\tsource $python_venv_dir/bin/activate"
        elif [ $venv_label -eq 1 ];then
            green_echo "You can activate pyvenv via:\n\tsource $HOME/$venv_name/bin/activate"
        else
            green_echo "No pyvenv activate"
        fi
    else
        red_echo "Cannot detect OS and set OS_ID and OS_VERSION to unknown"
    fi
}

main