#!/bin/bash

# Function to update Prometheus YAML and restart the service
config_prometheus_yaml() {
    local yml_file_path="$1"                # Path of the YAML file
    local node_exporter_hosts="$2"          # Comma-separated list of node exporter hosts
    local process_exporter_hosts="$3"       # Comma-separated list of process exporter hosts
    mkdir -p "$(dirname "$yml_file_path")"
    # Reset the Prometheus YAML file
    echo "scrape_configs:" > "$yml_file_path"
    echo "  - job_name: 'prometheus_monitor'" >> "$yml_file_path"
    echo "    file_sd_configs:" >> "$yml_file_path"
    echo "      - files:" >> "$yml_file_path"
    echo "        - 'targets.json'" >> "$yml_file_path"
    echo "        refresh_interval: 5m" >> "$yml_file_path"

    # Initialize the target JSON file path

    local target_json="/etc/prometheus/targets.json"

    # Check inputs
    if [ -z "$node_exporter_hosts" ] && [ -z "$process_exporter_hosts" ]; then
        echo "No hosts provided"
        exit 1
    fi

    # Initialize an array for targets
    local TARGETS=()

    # Process node exporter hosts
    IFS=',' read -r -a NODE_HOSTS <<< "$node_exporter_hosts"
    for HOST in "${NODE_HOSTS[@]}"; do
        TARGETS+=("{\"targets\": [\"$HOST:9100\"], \"labels\": {\"instance\": \"${HOST}\"}}")
    done

    # Process process exporter hosts
    IFS=',' read -r -a PROCESS_HOSTS <<< "$process_exporter_hosts"
    for HOST in "${PROCESS_HOSTS[@]}"; do
        TARGETS+=("{\"targets\": [\"$HOST:9256\"], \"labels\": {\"instance\": \"${HOST}\"}}")
    done

    # Create targets.json
    echo "[" > "$target_json"
    for TARGET in "${TARGETS[@]}"; do
        echo "  $TARGET," >> "$target_json"
    done
    # Remove the last comma and close the JSON array
    sed -i '$ s/,$//' "$target_json"
    echo "]" >> "$target_json"

    echo "targets.json created at $target_json"
}

restart_prometheus() {
    echo "Restarting Prometheus..."
    systemctl restart prometheus

    # Check Prometheus status
    local STATUS
    STATUS=$(systemctl is-active prometheus)
    if [ "$STATUS" != "active" ]; then
        echo "::error ::ERROR: Prometheus is in $STATUS state."
        exit 1
    else
        echo "Prometheus is running successfully."
    fi
}

# Main script execution
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <yml_file_path> <node_exporter_hosts> <process_exporter_hosts>"
    echo "Example:"
    echo "  $0 /etc/prometheus/prometheus.yml host1,host2 host3,host4"
    exit 1
fi

# Call the function with provided arguments
config_prometheus_yaml "$1" "$2" "$3"
restart_prometheus