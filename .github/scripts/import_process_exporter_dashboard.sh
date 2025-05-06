#!/bin/bash
set -eo pipefail

# Grafana API configuration
GRAFANA_URL="$1"                # Grafana URL as the first argument
PROMETHEUS_URL="$2"             # Prometheus URL as the first argument
USERNAME="$3"                   # Grafana username as the second argument
PASSWORD="$4"                   # Grafana password as the third argument
DATASOURCE_NAME="$5"            # Data source name as the fourth argument

# Validate mandatory parameters
if [[ $# -lt 5 ]]; then
  echo "::error::Missing required parameters"
  echo "Usage: $0 <GRAFANA_URL> <PROMETHEUS_URL> <USERNAME> <PASSWORD> <DATASOURCE_NAME>"
  echo "Example:"
  echo "$0 http://192.168.9.99:3000 http://192.168.9.98:9090 admin admin process_exporter_dashboard"
  exit 1
fi

# Query existing data sources
response=$(curl -s -u "$USERNAME:$PASSWORD" "$GRAFANA_URL/api/datasources")

# Check if the data source exists
if echo "$response" | jq -e ".[] | select(.name == \"$DATASOURCE_NAME\")" > /dev/null; then
    echo "Data source '$DATASOURCE_NAME' already exists, skipping creation."
else
    echo "Data source '$DATASOURCE_NAME' does not exist, creating a new data source."

    # Create a new data source
    curl -X POST \
      -u "$USERNAME:$PASSWORD" \
      -H "Content-Type: application/json" \
      -d '{
            "name": "'"$DATASOURCE_NAME"'",
            "type": "prometheus",
            "url": "'"$PROMETHEUS_URL"'",
            "access": "proxy",
            "basicAuth": false,
            "jsonData": {
              "timeInterval": "10s"
            }
          }' \
      "$GRAFANA_URL/api/datasources"

    echo "Data source '$DATASOURCE_NAME' created successfully."
fi

wget -O tdengine_process_exporter.json https://platform.tdengine.net:8090/download/config/tdengine_process_exporter_template.json
sed -i "s/to_replace/$DATASOURCE_NAME/g" tdengine_process_exporter.json

# Import the dashboard
import_response=$(curl -s -X POST \
  -u "$USERNAME:$PASSWORD" \
  -H "Content-Type: application/json" \
  -d "{\"dashboard\": $(jq 'del(.id)' tdengine_process_exporter.json), \"overwrite\": true}" \
  "$GRAFANA_URL/api/dashboards/db")

# Check if the dashboard import was successful
if echo "$import_response" | jq -e '.status == "success"' > /dev/null; then
    echo "Dashboard imported successfully."
else
    echo "Failed to import the dashboard. Response: $import_response"
    exit 1
fi
