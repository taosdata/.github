#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <monitor_ip> <monitor_port>"
    echo "Example:"
    echo "  $0 localhost 6041"
    exit 1
fi

# Input parameters
monitor_ip="$1"
monitor_port="$2"

# Install curl
script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$script_dir/install_via_apt.sh" curl

# Install grafanaplugin and config
cd /opt || exit
bash -c "$(curl -fsSL \
    https://raw.githubusercontent.com/taosdata/grafanaplugin/master/install.sh)" -- \
    -a http://"$monitor_ip":"$monitor_port" \
    -u root \
    -p taosdata

# Restart service
systemctl restart grafana-server.service