#!/bin/bash

# Function to check and install FlashMQ
install_flashmq() {
    if dpkg -l | grep -q flashmq; then
        echo "FlashMQ is already installed."
        # Check if FlashMQ is running
        if systemctl is-active --quiet flashmq; then
            echo "FlashMQ is already running."
        else
            echo "FlashMQ is not running. Starting the service."
            systemctl start flashmq
        fi
    else
        echo "FlashMQ is not installed. Proceeding with installation."
        # Add FlashMQ GPG Key
        curl -fsSL https://www.flashmq.org/wp-content/uploads/2021/10/flashmq-repo.gpg -o /usr/share/keyrings/flashmq-repo.gpg

        # Add FlashMQ APT Repository
        echo "deb [signed-by=/usr/share/keyrings/flashmq-repo.gpg] http://repo.flashmq.org/apt $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/flashmq.list

        # Update Package List and Install FlashMQ
        apt update -y && apt install -y flashmq

        # Start FlashMQ and Enable on Startup
        systemctl start flashmq
        systemctl enable flashmq
    fi

    # Append allow_anonymous true to FlashMQ configuration file
    echo "allow_anonymous true" >> /etc/flashmq/flashmq.conf
    systemctl restart flashmq
}

# Function to check FlashMQ status
check_flashmq_status() {
    STATUS=$(systemctl is-active flashmq)
    if [ "$STATUS" != "active" ]; then
        echo "::error ::ERROR: FlashMQ is in $STATUS state."
        exit 1
    else
        echo "FlashMQ is running successfully."
    fi
}

# Run the functions
install_flashmq
check_flashmq_status
