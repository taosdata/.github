#!/bin/bash

install_java() {
    if ! command -v java &> /dev/null; then
        echo "Java is not installed. Installing Java..."
        apt-get update
        apt-get install -y openjdk-11-jdk
    else
        echo "Java is already installed."
    fi
}

# Function to check if Java is installed
check_java() {
    if ! command -v java &> /dev/null; then
        echo "Java is not installed. Please install Java (e.g., OpenJDK 11) and try again."
        install_java
        if [ $? -ne 0 ]; then
            echo "Failed to install Java. Exiting."
            exit 1
        fi
    fi
}

# Function to determine if the network is domestic or international
is_domestic() {
    # Test connectivity to a domestic server (e.g., Tsinghua mirror)
    ping -c 1 mirrors.tuna.tsinghua.edu.cn &> /dev/null
    if [ $? -eq 0 ]; then
        return 0  # Domestic
    else
        return 1  # International
    fi
}

# Function to check and install Kafka
install_kafka() {
    if [ ! -d "/opt/kafka" ]; then
        echo "Kafka is not installed. Installing Kafka..."

        # Choose the appropriate mirror based on network environment
        if is_domestic; then
            echo "Using domestic mirror for Kafka download."
            wget https://mirrors.tuna.tsinghua.edu.cn/apache/kafka/3.7.2/kafka_2.13-3.7.2.tgz -O /tmp/kafka.tgz
        else
            echo "Using international mirror for Kafka download."
            wget https://downloads.apache.org/kafka/3.7.2/kafka_2.13-3.7.2.tgz -O /tmp/kafka.tgz
        fi

        if [ $? -ne 0 ]; then
            echo "Failed to download Kafka. Exiting."
            exit 1
        fi

        tar -xzf /tmp/kafka.tgz -C /opt
        if [ $? -ne 0 ]; then
            echo "Failed to extract Kafka. Exiting."
            exit 1
        fi

        mv /opt/kafka_2.13-3.7.2 /opt/kafka
        if [ $? -ne 0 ]; then
            echo "Failed to move Kafka directory. Exiting."
            exit 1
        fi

        echo "Kafka installed successfully."
    else
        echo "Kafka is already installed."
    fi

    # configure Kafka
    echo "Configuring Kafka..."
    mkdir -p /opt/kafka/logs
    cp /opt/kafka/config/server.properties /opt/kafka/config/server.properties.bak
    sed -i "s|^log.dirs=.*|log.dirs=/opt/kafka/logs|" /opt/kafka/config/server.properties
    sed -i "s|^zookeeper.connect=.*|zookeeper.connect=localhost:2181|" /opt/kafka/config/server.properties
    sed -i "s|^listeners=.*|listeners=PLAINTEXT://:9092|" /opt/kafka/config/server.properties
    sed -i "s|^advertised.listeners=.*|advertised.listeners=PLAINTEXT://${serverIP}:9092|" /opt/kafka/config/server.properties
    sed -i "s|^log.retention.hours=.*|log.retention.hours=1|" /opt/kafka/config/server.properties
}

create_service_files() {
    echo "Creating Zookeeper systemd service file..."
    cat <<EOF > /etc/systemd/system/zookeeper.service
[Unit]
Description=Apache Zookeeper Service
After=network.target

[Service]
Type=simple
ExecStart=/opt/kafka/bin/zookeeper-server-start.sh /opt/kafka/config/zookeeper.properties
ExecStop=/opt/kafka/bin/zookeeper-server-stop.sh
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    echo "Creating Kafka systemd service file..."
    cat <<EOF > /etc/systemd/system/kafka.service
[Unit]
Description=Apache Kafka Service
After=zookeeper.service

[Service]
Type=simple
ExecStart=/opt/kafka/bin/kafka-server-start.sh /opt/kafka/config/server.properties
ExecStop=/opt/kafka/bin/kafka-server-stop.sh
Restart=on-failure
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

    echo "Reloading systemd daemon and enabling services..."
    systemctl daemon-reload
    systemctl enable zookeeper
    systemctl enable kafka
}

start_service() {
    systemctl stop kafka
    systemctl stop zookeeper

    echo "Starting Zookeeper service..."
    systemctl start zookeeper
    # Check if Zookeeper started successfully
    if ! systemctl is-active --quiet zookeeper; then
        echo "Failed to start Zookeeper service."
        exit 1
    fi
    echo "Zookeeper service started successfully."

    echo "Starting Kafka service..."
    systemctl start kafka
    # Check if Kafka started successfully
    if ! systemctl is-active --quiet kafka; then
        echo "Failed to start Kafka service."
        exit 1
    fi
    echo "Kafka service started successfully."
}

# Check if the correct number of arguments is provided
if [ "$#" -ne 1 ]; then
  usage
fi

# Get parameters
serverIP="$1"
# Run the functions
check_java
install_kafka $serverIP
create_service_files
start_service