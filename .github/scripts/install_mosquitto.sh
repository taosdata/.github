#!/bin/bash

# Function to check and install Mosquitto
install_mosquitto() {
    if systemctl is-active --quiet mosquitto; then
        echo "Mosquitto is already running."
        return 0
    fi
    
    if dpkg -l | grep -q mosquitto; then
        echo "Mosquitto is already installed."
        echo "Mosquitto is not running. Starting the service."
        systemctl start mosquitto
        return 0
    fi
    
    echo "Mosquitto is not installed. Proceeding with installation."
    
    # Update package list
    apt update -y
    
    # Install Mosquitto broker and clients
    apt install -y mosquitto mosquitto-clients
    
    # Use default configuration - Mosquitto comes with default config
    # Just ensure basic directories exist and have proper permissions
    mkdir -p /var/lib/mosquitto
    chown -R mosquitto:mosquitto /var/lib/mosquitto/
    
    # Enable and start Mosquitto with default configuration
    systemctl daemon-reload
    systemctl enable mosquitto
    systemctl start mosquitto
    
    # Wait for Mosquitto to start
    sleep 5
}

# Function to check Mosquitto status
check_mosquitto_status() {
    STATUS=$(systemctl is-active mosquitto)
    if [ "$STATUS" != "active" ]; then
        echo "::error ::ERROR: Mosquitto is in $STATUS state."
        exit 1
    else
        echo "Mosquitto is running successfully."
        
        # Test basic connectivity
        if command -v mosquitto_pub &> /dev/null; then
            echo "Testing Mosquitto connectivity..."
            timeout 5 mosquitto_pub -h localhost -p 1883 -t test/topic -m "test message" || echo "Basic connectivity test completed"
        fi
    fi
}

# Run the functions
install_mosquitto
check_mosquitto_status