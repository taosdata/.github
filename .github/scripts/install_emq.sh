#!/bin/bash

# Function to check and install EMQX
install_emq() {
    if systemctl is-active --quiet emqx; then
        echo "EMQX is already running."
        return 0
    fi
    
    if dpkg -l | grep -q emqx; then
        echo "EMQX is already installed."
        echo "EMQX is not running. Starting the service."
        systemctl start emqx
        return 0
    fi
    
    echo "EMQX is not installed. Proceeding with installation."
    
    # Install required packages
    apt update -y
    apt install -y curl gnupg2 software-properties-common
    
    # Add EMQX repository
    curl -s https://assets.emqx.com/scripts/install-emqx-deb.sh | bash
    
    # Install EMQX
    apt update -y
    apt install -y emqx
    
    # Use default configuration - no custom config needed for basic anonymous access
    
    # Enable and start EMQX
    systemctl daemon-reload
    systemctl enable emqx
    systemctl start emqx
    
    # Wait for EMQX to start properly
    echo "Waiting for EMQX to fully start..."
    for i in {1..30}; do
        if systemctl is-active --quiet emqx; then
            echo "EMQX started successfully"
            break
        fi
        echo "Waiting for EMQX to start... ($i/30)"
        sleep 2
    done
}

# Function to check EMQX status
check_emq_status() {
    STATUS=$(systemctl is-active emqx)
    if [ "$STATUS" != "active" ]; then
        echo "::error ::ERROR: EMQX is in $STATUS state."
        exit 1
    else
        echo "EMQX is running successfully."
    fi
}

# Run the functions
install_emq
check_emq_status