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
    if [ ! -d "/opt/kafka/kafka_2.13-3.7.2" ]; then
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
}

start_zookeeper() {
    if ! pgrep -f zookeeper &> /dev/null; then
        echo "Starting Zookeeper..."
        /opt/kafka/bin/zookeeper-server-start.sh -daemon /opt/kafka/config/zookeeper.properties
        sleep 5  # Wait for Zookeeper to initialize

        # Check if Zookeeper started successfully
        if ! pgrep -f zookeeper &> /dev/null; then
            echo "Failed to start Zookeeper."
            exit 1
        fi
        echo "Zookeeper started successfully."
    else
        echo "Zookeeper is already running."
    fi
}

start_kafka() {
    if ! pgrep -f kafka.Kafka &> /dev/null; then
        echo "Starting Kafka..."
        /opt/kafka/bin/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
        sleep 5  # Wait for Kafka to initialize

        # Check if Kafka started successfully
        if ! pgrep -f kafka.Kafka &> /dev/null; then
            echo "Failed to start Kafka."
            exit 1
        fi
        echo "Kafka started successfully."
    else
        echo "Kafka is already running."
    fi
}

# Run the functions
check_java
install_kafka
start_zookeeper
start_kafka