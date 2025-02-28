#!/bin/bash

# Function to display help
usage() {
  echo "Usage: $0 MINIO_ROOT_USER MINIO_ROOT_PASSWORD MINIO_ACCESS_KEY MINIO_SECRET_KEY"
  echo "Eg: $0 test_user test_passwd test_access_key test_access_secret"
  echo
  echo "Arguments:"
  echo "  MINIO_ROOT_USER     The root user for MinIO (length at least 3)."
  echo "  MINIO_ROOT_PASSWORD The root password for MinIO (length at least 8 characters)."
  echo "  MINIO_ACCESS_KEY    The access key for MinIO (length between 3 and 20)."
  echo "  MINIO_SECRET_KEY    The secret key for MinIO (length between 8 and 40)."
  echo
  echo "This script installs MinIO server and client, sets up the environment, and creates a bucket and access key."
  exit 1
}

# Function to check parameter validity
check_parameters() {
  if [[ -z "$MINIO_ROOT_USER" ]]; then
    echo "Error: MINIO_ROOT_USER is not defined."
    exit 1
  fi
  if [[ -z "$MINIO_ROOT_PASSWORD" ]]; then
    echo "Error: MINIO_ROOT_PASSWORD is not defined."
    exit 1
  fi
  if [[ -z "$MINIO_ACCESS_KEY" ]]; then
    echo "Error: MINIO_ACCESS_KEY is not defined."
    exit 1
  fi
  if [[ -z "$MINIO_SECRET_KEY" ]]; then
    echo "Error: MINIO_SECRET_KEY is not defined."
    exit 1
  fi
}

# Function to install MinIO Server
install_minio_server() {
  if [ ! -f /usr/local/bin/minio ]; then
    wget https://dl.min.io/server/minio/release/linux-amd64/minio
    chmod +x minio
    mv minio /usr/local/bin/
  fi
}

# Function to install MinIO Client
install_minio_client() {
  if [ ! -f /usr/local/bin/mc ]; then
    wget https://dl.min.io/client/mc/release/linux-amd64/mc
    chmod +x mc
    mv mc /usr/local/bin/
  fi
}

# Function to start MinIO Server
start_minio_server() {
  mkdir -p /mnt/data
  export MINIO_ROOT_USER=${MINIO_ROOT_USER}
  export MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

  if ! curl -s http://localhost:9000/minio/health/live; then
    echo "Starting MinIO Server..."
    nohup env MINIO_ROOT_USER="${MINIO_ROOT_USER}" MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" minio server /mnt/data --console-address ":9001" > /var/log/minio.log 2>&1 &
  else
    echo "MinIO is already running."
  fi

  # Check if MinIO Server is up
  until curl -s http://localhost:9000/minio/health/live; do
    echo 'Waiting for MinIO to start...'
    sleep 5
  done
  echo "MinIO is running."
}

# Function to create bucket and access key
setup_minio() {
  mc alias set myminio http://127.0.0.1:9000 "${MINIO_ROOT_USER}" "${MINIO_ROOT_PASSWORD}"

  if mc ls myminio | grep -q 'td-bucket'; then
    echo "Bucket 'td-bucket' already exists."
  else
    mc mb myminio/td-bucket
    echo "Bucket 'td-bucket' created."
  fi

  if mc admin accesskey ls myminio "$MINIO_ROOT_USER" | grep "${MINIO_ACCESS_KEY}"; then
    echo "Access key ${MINIO_ACCESS_KEY} already exists."
  else
    mc admin accesskey create myminio/ "$MINIO_ROOT_USER" --access-key "${MINIO_ACCESS_KEY}" --secret-key "${MINIO_SECRET_KEY}"
    echo "Access key created."
  fi
}

# Main script execution

# Check if the correct number of arguments is provided
if [ "$#" -ne 4 ]; then
  usage
fi

# Get parameters
MINIO_ROOT_USER="$1"
MINIO_ROOT_PASSWORD="$2"
MINIO_ACCESS_KEY="$3"
MINIO_SECRET_KEY="$4"

# Check parameters
check_parameters

# Install MinIO Server and Client
install_minio_server
install_minio_client

# Start MinIO Server
start_minio_server

# Set up MinIO (create bucket and access key)
setup_minio