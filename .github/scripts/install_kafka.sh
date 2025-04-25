#!/bin/bash

# Function to check and install Kafka
install_kafka() {
    if ! command -v kafka-server-start.sh &> /dev/null; then
        echo "Kafka is not installed. Installing Kafka..."
        wget https://downloads.apache.org/kafka/3.5.0/kafka_2.13-3.5.0.tgz -O /tmp/kafka.tgz
        tar -xzf /tmp/kafka.tgz -C /opt
        mv /opt/kafka_2.13-3.5.0 /opt/kafka
        echo "Kafka installed successfully."
    else
        echo "Kafka is already installed."
    fi
}

start_kafka() {
    if ! pgrep -f kafka.Kafka &> /dev/null; then
        echo "Starting Kafka..."
        /opt/kafka/bin/kafka-server-start.sh -daemon /opt/kafka/config/server.properties
        echo "Kafka started successfully."
    else
        echo "Kafka is already running."
    fi
}

# Function to check Kafka status
check_kafka_status() {
    if pgrep -f kafka.Kafka &> /dev/null; then
        echo "Kafka is running."
    else
        echo "Kafka is not running."
    fi
}

# Run the functions
install_kafka
check_kafka_status