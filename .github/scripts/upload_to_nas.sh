#!/bin/bash
# =============================================================================
# upload_to_nas.sh — Upload a single file to NAS via SCP
#
# Usage:
#   upload_to_nas.sh <file> <ssh-key> <host> <port> <username> <nas-dir>
#
# Arguments:
#   file        Absolute path to the local file to upload
#   ssh-key     EITHER a path to an existing SSH private key file
#               OR the raw PEM content of the key (e.g. a GitHub Actions secret)
#   host        NAS hostname or IP address
#   port        NAS SSH port (default: 22)
#   username    NAS SSH username
#   nas-dir     Remote directory on NAS (must already exist)
#
# Outputs (written to GITHUB_OUTPUT when available):
#   nas_path        Full remote path: <nas-dir>/<filename>
#   filename        Basename of the uploaded file
# =============================================================================

set -euo pipefail

FILE="${1:-}"
SSH_KEY_ARG="${2:-}"
NAS_HOST="${3:-}"
NAS_PORT="${4:-22}"
NAS_USER="${5:-}"
NAS_DIR="${6:-}"

# ---- Validate required arguments ----
if [[ -z "$FILE" || -z "$SSH_KEY_ARG" || -z "$NAS_HOST" || -z "$NAS_USER" || -z "$NAS_DIR" ]]; then
    echo "Usage: $0 <file> <ssh-key> <host> <port> <username> <nas-dir>" >&2
    echo "  ssh-key: path to a key file (e.g. ~/.ssh/nas_key) or raw PEM content" >&2
    exit 1
fi

if [[ ! -f "$FILE" ]]; then
    echo "::error::File not found: $FILE" >&2
    exit 1
fi

FILENAME=$(basename "$FILE")
NAS_DEST="${NAS_DIR}/${FILENAME}"

# ---- Resolve SSH key: accept a file path OR raw PEM content ----
KEY_FILE=$(mktemp)
trap "rm -f ${KEY_FILE}" EXIT
chmod 600 "$KEY_FILE"

if [[ -f "$SSH_KEY_ARG" ]]; then
    # Caller passed an existing key file path (e.g. ~/.ssh/nas_key)
    cp "$SSH_KEY_ARG" "$KEY_FILE"
    echo "Using SSH key file : ${SSH_KEY_ARG}"
elif [[ "$SSH_KEY_ARG" == *"PRIVATE KEY"* ]]; then
    # Caller passed raw PEM content (typical GitHub Actions secret)
    printf '%s\n' "$SSH_KEY_ARG" > "$KEY_FILE"
    echo "Using SSH key from : <secret content>"
else
    echo "::error::SSH key not found as a file and does not look like PEM content." >&2
    echo "  Pass either a file path (e.g. ~/.ssh/nas_key) or the raw PEM key content." >&2
    exit 1
fi

echo "Uploading : ${FILENAME}"
echo "Target    : ${NAS_USER}@${NAS_HOST}:${NAS_DEST}  (port ${NAS_PORT})"

scp -i "$KEY_FILE" \
    -P "${NAS_PORT}" \
    -o StrictHostKeyChecking=no \
    -o BatchMode=yes \
    "$FILE" \
    "${NAS_USER}@${NAS_HOST}:${NAS_DEST}"

echo "✅ Upload complete: ${NAS_DEST}"

# ---- Write outputs for GitHub Actions (no-op when run locally) ----
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "nas_path=${NAS_DEST}" >> "$GITHUB_OUTPUT"
    echo "filename=${FILENAME}"  >> "$GITHUB_OUTPUT"
fi
