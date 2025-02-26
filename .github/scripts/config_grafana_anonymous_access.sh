#!/bin/bash

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <path_to_grafana.ini>"
    exit 1
fi

GRAFANA_INI="$1"

# Function to enable anonymous access in Grafana
enable_anonymous_access() {
    echo "Enabling anonymous access in Grafana configuration at $GRAFANA_INI..."
    # Enable anonymous access
    sed -i 's/;enabled = false/enabled = true/' "$GRAFANA_INI"
    systemctl restart grafana-server
}

# Function to check Grafana status
check_grafana_status() {
    STATUS=$(systemctl is-active grafana-server)
    if [ "$STATUS" != "active" ]; then
        echo "::error ::ERROR: Grafana is in $STATUS state."
        exit 1
    else
        echo "Grafana is running successfully."
    fi
}

# Run the functions
enable_anonymous_access
check_grafana_status
