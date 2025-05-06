#!/bin/bash

set -eo pipefail

# Input parameters
GRAFANA_URL="$1"
DASHBOARD_IDS="$2"
DASHBOARD_UIDS="$3"


# Ensure the correct number of input parameters
if [ "$#" -lt 3 ]; then
    echo "Usage: $0 <GRAFANA_URL> <DASHBOARD_IDS> <DASHBOARD_UIDS>"
    echo "Example:"
    echo "  $0 http://127.0.0.1:3000 18180,20631 td_ds_01,td_ds_02"
    exit 1
fi

# Install curl
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/install_via_apt.sh" curl

# Import Dashboards
IFS=',' read -ra id_array <<< "$DASHBOARD_IDS"
IFS=',' read -ra uid_array <<< "$DASHBOARD_UIDS"

length=${#id_array[@]}

for (( i=0; i<length; i++ )); do
    curl --retry 10 --retry-delay 5 --retry-max-time 120 \
      -s "https://grafana.com/api/dashboards/${id_array[i]}/revisions/latest/download" \
      -o tdengine-dashboard-"${id_array[i]}".json
    sed -i 's/"datasource": ".*"/"datasource": "TDengine"/g' tdengine-dashboard-"${id_array[i]}".json
    echo '{"dashboard": '"$(cat tdengine-dashboard-"${id_array[i]}".json)"', "overwrite": true}' > tdengine-formatted-"${id_array[i]}".json
    jq --arg uid "${uid_array[i]}" '.dashboard.uid = $uid' tdengine-formatted-"${id_array[i]}".json > tmp.json
    mv tmp.json tdengine-dashboard-"${id_array[i]}".json
    curl --retry 10 --retry-delay 5 --retry-max-time 120 \
      -X POST -H "Content-Type: application/json" \
      -u "admin:admin" \
      -d @tdengine-dashboard-"${id_array[i]}".json \
      "${GRAFANA_URL}/api/dashboards/db"
done