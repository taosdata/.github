#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <target_hosts> <password>"
    echo
    echo "Parameters:"
    echo "  target_hosts  Comma-separated list of target hosts"
    echo "  password      SSH login password"
    echo
    echo "Example:"
    echo "  $0 host1,host2,host3 your_password"
    exit 1
fi

# Input parameters
TARGET_HOSTS="$1"  # List of target hosts
PASSWORD="$2"      # SSH login password

# Check if sshpass is already installed
if ! command -v sshpass &> /dev/null; then
    echo "Installing sshpass..."
    apt-get update
    apt-get install -y sshpass
else
    echo "sshpass is already installed."
fi

# Generate SSH key (ed25519)
echo "Generating SSH key (ed25519)..."
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N "" || echo "SSH key already exists"

# Copy SSH key to target hosts
IFS=',' read -r -a hosts <<< "$TARGET_HOSTS"
for host in "${hosts[@]}"; do
    echo "Copying SSH key to $host"
    sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null root@"$host" "grep -qxF \"$(cat ~/.ssh/id_ed25519.pub)\" ~/.ssh/authorized_keys || echo \"$(cat ~/.ssh/id_ed25519.pub)\" >> ~/.ssh/authorized_keys"
done

echo "SSH key copied to all target hosts."