#!/bin/bash

set -eo pipefail

# Input parameters
MONITOR_IP="$1"
MONITOR_PORT="$2"

# Ensure the correct number of input parameters
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <MONITOR_IP> <MONITOR_PORT>"
    echo "Example:"
    echo "  $0 localhost 6041"
    exit 1
fi



# Install curl
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/install_via_apt.sh" curl

# Install grafanaplugin and config
cd /opt || exit
bash -c "$(curl -fsSL \
    https://raw.githubusercontent.com/taosdata/grafanaplugin/master/install.sh)" -- \
    -a http://"$MONITOR_IP":"$MONITOR_PORT" \
    -u root \
    -p taosdata

# Restart service
"$script_dir/restart_service.sh" grafana-server.service