#!/bin/bash
set -eo pipefail

if [[ $# -lt 1 ]]; then
  echo "::error::Missing required parameters"
  echo "Usage: $0 <ENTRIES>"
  exit 1
fi

ENTRIES="$1"

# Backup /etc/hosts
BACKUP_FILE="/etc/hosts-$(date +%s)"
cp "/etc/hosts" "$BACKUP_FILE"
echo "📦 Create Backup File: $BACKUP_FILE"

while IFS= read -r line; do
  [ -z "$line" ] || [[ "$line" =~ ^# ]] && continue

  if ! grep -Fxq "$line" "$HOSTS_FILE"; then
    echo "➕ Add: $line"
    echo "$line" >> "$HOSTS_FILE"
  else
    echo "⏩ Skip: $line"
  fi
done <<< "$ENTRIES"

echo "✅ Finished update /etc/hosts:"
cat /etc/hosts