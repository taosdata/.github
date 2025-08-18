#!/bin/bash

# Function to check and install HiveMQ
install_hivemq() {
    if pgrep -f "hivemq.jar" > /dev/null; then
        echo "HiveMQ is already running."
        return 0
    fi
    
    if [ -d "/opt/hivemq" ]; then
        echo "HiveMQ is already installed."
        echo "HiveMQ is not running. Starting HiveMQ..."
        cd /opt/hivemq || exit 1
        nohup ./bin/run.sh > /var/log/hivemq.log 2>&1 &
        sleep 15
        return 0
    fi
    
    echo "HiveMQ is not installed. Proceeding with installation."
    
    # Install Java if not present
    if ! command -v java &> /dev/null; then
        echo "Installing Java..."
        apt update -y
        apt install -y openjdk-11-jdk
    fi
    
    # Download and install HiveMQ
    HIVEMQ_VERSION="2025.3"
    HIVEMQ_DIR="/opt/hivemq"
    
    cd /tmp || exit 1
    wget https://github.com/hivemq/hivemq-community-edition/releases/download/${HIVEMQ_VERSION}/hivemq-ce-${HIVEMQ_VERSION}.zip
    
    if [ ! -f "hivemq-ce-${HIVEMQ_VERSION}.zip" ]; then
        echo "::error ::Failed to download HiveMQ"
        exit 1
    fi
    
    unzip hivemq-ce-${HIVEMQ_VERSION}.zip
    mkdir -p ${HIVEMQ_DIR}
    mv hivemq-ce-${HIVEMQ_VERSION}/* ${HIVEMQ_DIR}/
    
    # Create HiveMQ user
    useradd -r -s /bin/false hivemq || true  # Don't fail if user already exists
    chown -R hivemq:hivemq ${HIVEMQ_DIR}
    
    # Make run.sh executable
    chmod +x ${HIVEMQ_DIR}/bin/run.sh
    
    # Use default configuration - HiveMQ comes with default config.xml
    
    # Start HiveMQ directly (no systemd service needed for simple usage)
    cd ${HIVEMQ_DIR} || exit 1
    nohup ./bin/run.sh > /var/log/hivemq.log 2>&1 &
    
    # Wait for HiveMQ to start
    echo "Waiting for HiveMQ to start..."
    sleep 15
    
    # Clean up
    rm -rf /tmp/hivemq-ce-${HIVEMQ_VERSION}*
}

# Function to check HiveMQ status
check_hivemq_status() {
    if pgrep -f "hivemq.jar" > /dev/null; then
        echo "HiveMQ is running successfully."
    else
        echo "::error ::ERROR: HiveMQ is not running."
        exit 1
    fi
}

# Run the functions
install_hivemq
check_hivemq_status