#!/bin/bash

set -eo pipefail

# Input parameters
SERVICE_NAME="$1"

# Ensure the correct number of input parameters
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <SERVICE_NAME>"
    echo "Example:"
    echo "  $0 grafana-server.service"
    exit 1
fi

# Restart service
systemctl restart "$SERVICE_NAME"

MAX_WAIT=60
INTERVAL=5
elapsed=0

while [ $elapsed -lt $MAX_WAIT ]; do
    if systemctl is-active --quiet "$SERVICE_NAME"; then
        echo "$SERVICE_NAME start successfully"
        exit 0
    fi

    echo "Waiting $SERVICE_NAME start... ${elapsed}s"
    sleep $INTERVAL
    elapsed=$((elapsed + INTERVAL))
done

echo "Error: Start $SERVICE_NAME failed during ${MAX_WAIT}s"
exit 1