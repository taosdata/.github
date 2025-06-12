#!/bin/bash

# Function to update nginx configuration dynamically
config_nginx() {
    local nginx_config_path="/etc/nginx/nginx.conf"
    local dbserver_hosts="$1"       # Comma-separated list of dbserver hosts
    local keeper_hosts="$2"         # Comma-separated list of keeper hosts
    local explorer_hosts="$3"       # Comma-separated list of explorer hosts

    mkdir -p "$(dirname "$nginx_config_path")"

    # 写入新的 Nginx 配置
    cat > "$nginx_config_path" <<EOF
user root;
worker_processes auto;
worker_rlimit_nofile 900000;
error_log /var/log/nginx/nginx_error.log;
pid /run/nginx.pid;

events {
    use epoll;
    worker_connections 65535;
    multi_accept on;
}

http {

    access_log off;
    client_max_body_size 20M;
    map \$http_upgrade \$connection_upgrade {
        default upgrade;
        ''      close;
    }

    server {
        listen 6041;
        location ~* {
            proxy_pass http://dbserver;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            proxy_connect_timeout 600s;
            proxy_next_upstream error http_502 non_idempotent;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection \$connection_upgrade;
        }
    }
    server {
        listen 6043;
        location ~* {
            proxy_pass http://keeper;
            proxy_read_timeout 60s;
            proxy_next_upstream error http_502 non_idempotent;
        }
    }

    server {
        listen 6060;
        location ~* {
            proxy_pass http://explorer;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            proxy_connect_timeout 600s;
            proxy_next_upstream error http_502 non_idempotent;
        }
    }
    upstream dbserver {
        random;
EOF

    # 动态添加 dbserver hosts
    IFS=',' read -r -a DBSERVER_ARRAY <<< "$dbserver_hosts"
    for HOST in "${DBSERVER_ARRAY[@]}"; do
        echo "        server $HOST max_fails=0;" >> "$nginx_config_path"
    done

    cat >> "$nginx_config_path" <<EOF
    }
    upstream keeper {
        ip_hash;
EOF

    # 动态添加 keeper hosts
    IFS=',' read -r -a KEEPER_ARRAY <<< "$keeper_hosts"
    for HOST in "${KEEPER_ARRAY[@]}"; do
        echo "        server $HOST;" >> "$nginx_config_path"
    done

    cat >> "$nginx_config_path" <<EOF
    }
    upstream explorer {
        ip_hash;
EOF

    # 动态添加 explorer hosts
    IFS=',' read -r -a EXPLORER_ARRAY <<< "$explorer_hosts"
    for HOST in "${EXPLORER_ARRAY[@]}"; do
        echo "        server $HOST;" >> "$nginx_config_path"
    done

    cat >> "$nginx_config_path" <<EOF
    }
}
EOF

    echo "Nginx configuration has been updated at $nginx_config_path"
}

restart_nginx() {
    echo "Restarting nginx..."
    systemctl restart nginx.service

    # Check nginx status
    local STATUS
    STATUS=$(systemctl is-active nginx.service)
    if [ "$STATUS" != "active" ]; then
        echo "::error ::ERROR: nginx is in $STATUS state."
        exit 1
    else
        echo "nginx is running successfully."
    fi
}

# Main script execution
if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <adapter_hosts> <keeper_hosts> <explorer_hosts>"
    echo "Example:"
    echo "  $0 192.168.2.145:6041,192.168.2.142:6041 192.168.2.145:6043,192.168.2.142:6043 192.168.2.145:6060,192.168.2.142:6060"
    exit 1
fi

# Call the function with provided arguments
config_nginx "$1" "$2" "$3"
restart_nginx