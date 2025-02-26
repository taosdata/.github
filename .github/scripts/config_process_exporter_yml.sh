#!/bin/bash

# Ensure the correct number of input parameters
if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <yml_file_path> <process_name1,process_name2,...>"
    echo "Example:"
    echo "  $0 /etc/process-exporter.yml taosd,taosadapter"
    exit 1
fi

# Input parameters
yml_file_path="$1"             # Path of the YAML file
process_names="$2"             # Comma-separated list of process names to monitor

# Convert process names into an array
IFS=',' read -r -a NAMES_ARRAY <<< "$process_names"

# Create the YAML file and write the content
echo "process_names:" > "$yml_file_path"
# Write each process name
for NAME in "${NAMES_ARRAY[@]}"; do
    echo "- cmdline:" >> "$yml_file_path"
    echo "  - $NAME" >> "$yml_file_path"
    echo "  name: '{{.Comm}}'" >> "$yml_file_path"
done
echo "YAML file updated: $yml_file_path"

# Restart process-exporter
echo "Restarting process-exporter..."
systemctl restart process_exporter

# Check process-exporter status
STATUS=$(systemctl is-active process_exporter)
if [ "$STATUS" != "active" ]; then
    echo "::error ::ERROR: process-exporter is in $STATUS state."
    exit 1
else
    echo "process-exporter is running successfully."
fi