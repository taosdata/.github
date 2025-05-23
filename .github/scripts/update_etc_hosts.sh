#!/bin/bash
set -eo pipefail

if [[ $# -lt 1 ]]; then
  echo "::error::Missing required parameters"
  echo "Usage: $0 <ENTRIES>"
  exit 1
fi

ENTRIES="$1"

# Backup /etc/hosts
HOSTS_FILE="/etc/hosts"
BACKUP_FILE="$HOSTS_FILE-$(date +%s)"
cp "$HOSTS_FILE" "$BACKUP_FILE"
echo "📦 Create Backup File: $BACKUP_FILE"

DECODED_ECTRIES=$(echo "$ENTRIES" | base64 -d)

while IFS= read -r line; do
  [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue

  if ! grep -Fxq "$line" "$HOSTS_FILE"; then
    echo "➕ Add: $line"
    echo "$line" >> "$HOSTS_FILE"
  else
    echo "⏩ Skip: $line"
  fi
done <<< "$DECODED_ECTRIES"

echo "✅ Finished update $HOSTS_FILE:"
cat $HOSTS_FILE