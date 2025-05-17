#!/bin/bash
if [ $# -ne 3 ]; then
    echo "::error::Missing required parameters"
    echo "Usage: $0 <json_file> <test_root> <exclude_components>"
    echo "Example:"
    echo "  $0 role_info.json /root/TestNG taosx,taoskeeper"
    exit 1
fi

JSON_FILE="$1"
TEST_ROOT="$2"
EXCLUDE_COMPONENTS="$3"

generate_json_compact_array() {
    local role="$1"
    jq -c --arg role "$role" '[.[$role][].hostname]' "$JSON_FILE"
}

generate_shell_literal_array() {
    local json_compact_array="$1"
    mapfile -t shell_array < <(echo "$json_compact_array" | jq -r '.[]')
    declare -p shell_array
}

filter_excluded_components() {
    local json_file="$1"
    if [ -n "$EXCLUDE_COMPONENTS" ]; then
        echo "$json_file" | jq --arg exclude "$EXCLUDE_COMPONENTS" '
            ($exclude | split(",")) as $exclude_list |
            with_entries(
                if .key as $k | $exclude_list | index($k) | not then
                    .
                else
                    empty
                end
            )
        '
    else
        echo "$json_file"
    fi
}

mqtt_json_array=$(generate_json_compact_array "mqtt")
eval "$(generate_shell_literal_array "$mqtt_json_array")"
mqtt_shell_array=("${shell_array[@]}")
echo "$mqtt_json_array"
echo "${mqtt_shell_array[0]}"
echo "${mqtt_shell_array[1]}"

flashmq_json_array=$(generate_json_compact_array "flashmq")
eval "$(generate_shell_literal_array "$flashmq_json_array")"
flashmq_shell_array=("${shell_array[@]}")
echo "$flashmq_json_array"
echo "${flashmq_shell_array[0]}"
echo "${flashmq_shell_array[1]}"

single_dnode_json_array=$(generate_json_compact_array "edge")
eval "$(generate_shell_literal_array "$single_dnode_json_array")"
single_dnode_shell_array=("${shell_array[@]}")
echo "$single_dnode_json_array"
echo "${single_dnode_shell_array[0]}"
echo "${single_dnode_shell_array[1]}"

cluster_dnode_json_array=$(generate_json_compact_array "center")
eval "$(generate_shell_literal_array "$cluster_dnode_json_array")"
cluster_dnode_shell_array=("${shell_array[@]}")
echo "$cluster_dnode_json_array"
echo "${cluster_dnode_shell_array[0]}"
echo "${cluster_dnode_shell_array[1]}"
echo "${cluster_dnode_shell_array[2]}"

client_json_array=$(generate_json_compact_array "client")
eval "$(generate_shell_literal_array "$client_json_array")"
client_shell_array=("${shell_array[@]}")
echo "$client_json_array"
echo "${client_shell_array[0]}"

kafka_json_array=$(generate_json_compact_array "kafka")
eval "$(generate_shell_literal_array "$kafka_json_array")"
kafka_shell_array=("${shell_array[@]}")
echo "$kafka_json_array"
echo "${kafka_shell_array[0]}"
echo "${kafka_shell_array[1]}"

hostname_info=(
    "${mqtt_shell_array[@]}"
    "${flashmq_shell_array[@]}"
    "${single_dnode_shell_array[@]}"
    "${client_shell_array[@]}"
    "${cluster_dnode_shell_array[@]}"
    "${kafka_shell_array[@]}"
)
hostname_info_str=$(IFS=,; echo "${hostname_info[*]}")

# Export results to environment variables
{
    echo "MQTT_HOSTS=$mqtt_json_array"
    echo "FLASHMQ_HOSTS=$flashmq_json_array"
    echo "SINGLE_DNODE_HOSTS=$single_dnode_json_array"
    echo "TAOS_BENCHMARK_HOSTS=$client_json_array"
    echo "CLUSTER_HOSTS=$cluster_dnode_json_array"
    echo "HOSTNAME_INFO=$hostname_info_str"
    echo "KAFKA_HOSTS=$kafka_json_array"
} >> "$GITHUB_OUTPUT"

# # Get the length of the first array (assuming both arrays are of the same length)
length=${#single_dnode_shell_array[@]}
# Iterate over indices
for ((i=0; i<length; i++)); do
    edge=${single_dnode_shell_array[$i]}
    mqtt=${mqtt_shell_array[$i]}
    flashmq=${flashmq_shell_array[$i]}
    full_json=$(cat <<EOF
{
    "taosd": {
        "fqdn": ["$edge"],
        "spec": {"firstEP": "$edge:6030"}
    },
    "mqtt-client": {
        "fqdn": ["$mqtt"],
        "spec": {}
    },
    "flashmq-client": {
        "fqdn": ["$flashmq"],
        "spec": {}
    },
    "taosadapter": {
        "fqdn": ["$edge"],
        "spec": {}
    },
    "taosBenchmark": {
        "fqdn": ["${client_shell_array[0]}"],
        "spec": {}
    },
    "taospy": {
        "fqdn": ["${client_shell_array[0]}"],
        "spec": {}
    },
    "taoskeeper": {
        "fqdn": ["$edge"],
        "spec": {"host": "${cluster_dnode_shell_array[0]}"}
    },
    "taosx": {
        "fqdn": ["$edge"],
        "spec": {}
    }
}
EOF
    )
    filtered_json=$(filter_excluded_components "$full_json")
    echo "$filtered_json" > "$TEST_ROOT/env/ems-edge-$((i+1)).json"
done

# Create JSON file for cluster node
cluster_fqdn=$(printf ',"%s"' "${cluster_dnode_shell_array[@]}")
cluster_fqdn="[${cluster_fqdn:1}]"

center_json=$(cat <<EOF
{
    "taosd": {
        "fqdn": ${cluster_fqdn},
        "spec": {"firstEP": "${cluster_dnode_shell_array[0]}:6030"}
    },
    "taosadapter": {
        "fqdn": ${cluster_fqdn},
        "spec": {}
    },
    "taosBenchmark": {
        "fqdn": ["${client_shell_array[0]}"],
        "spec": {}
    },
    "taospy": {
        "fqdn": ["${client_shell_array[0]}"],
        "spec": {}
    },
    "taoskeeper": {
        "fqdn": ${cluster_fqdn},
        "spec": {"host": "${cluster_dnode_shell_array[0]}"}
    },
    "taosx": {
        "fqdn": ${cluster_fqdn},
        "spec": {}
    }
}
EOF
)
filtered_json=$(filter_excluded_components "$center_json")
echo "$filtered_json" > "$TEST_ROOT/env/ems-center.json"

query_json=$(cat <<EOF
{
    "taosd": {
        "fqdn": ["${cluster_dnode_shell_array[0]}"],
        "spec": {"firstEP": "${cluster_dnode_shell_array[0]}:6030"}
    },
    "taosadapter": {
        "fqdn": ["${cluster_dnode_shell_array[0]}"],
        "spec": {}
    },
    "taosBenchmark": {
        "fqdn": ["${client_shell_array[0]}"],
        "spec": {"firstEP": "${cluster_dnode_shell_array[0]}:6030"}
    },
    "taospy": {
        "fqdn": ["${client_shell_array[0]}"],
        "spec": {}
    },
    "taoskeeper": {
        "fqdn": ${cluster_fqdn},
        "spec": {"host": "${cluster_dnode_shell_array[0]}"}
    },
    "taosx": {
        "fqdn": ${cluster_fqdn},
        "spec": {}
    }
}
EOF
)
filtered_json=$(filter_excluded_components "$query_json")
echo "$filtered_json" > "$TEST_ROOT/env/ems-query.json"