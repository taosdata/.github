#!/bin/bash
set -euo pipefail

# Function to display help
usage() {
  echo "Usage: $0 MINIO_ROOT_USER MINIO_ROOT_PASSWORD MINIO_ACCESS_KEY MINIO_SECRET_KEY"
  echo "Eg: $0 test_user test_passwd test_access_key test_access_scret"
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

# Check if the correct number of arguments is provided
if [ "$#" -ne 4 ]; then
  usage
fi

# Get parameters
MINIO_ROOT_USER="$1"
MINIO_ROOT_PASSWORD="$2"
MINIO_ACCESS_KEY="$3"
MINIO_SECRET_KEY="$4"

# Parameter checks
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

# Install MinIO Server
if [ ! -f /usr/local/bin/minio ]; then
  wget https://dl.min.io/server/minio/release/linux-amd64/minio
  chmod +x minio
  mv minio /usr/local/bin/
fi

# Install MinIO Client
if [ ! -f /usr/local/bin/mc ]; then
  wget https://dl.min.io/client/mc/release/linux-amd64/mc
  chmod +x mc
  mv mc /usr/local/bin/
fi

# Create data directory
mkdir -p /mnt/data

# Set environment variables
export MINIO_ROOT_USER=${MINIO_ROOT_USER}
export MINIO_ROOT_PASSWORD=${MINIO_ROOT_PASSWORD}

# Check if MinIO is running
if curl -s http://localhost:9000/minio/health/live; then
  echo "MinIO is already running."
  running=true
else
  echo "MinIO is not running."
  running=false
fi

# Start MinIO Server
if [ $running == "false" ]; then
  nohup env MINIO_ROOT_USER="${MINIO_ROOT_USER}" MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD}" minio server /mnt/data --console-address ":9001" > /var/log/minio.log 2>&1 &
fi

# Check if MinIO Server is up
until curl -s http://localhost:9000/minio/health/live; do
  echo 'Waiting for MinIO to start...'
  sleep 5
done
echo "MinIO is running."

# Create Bucket and Access Key
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