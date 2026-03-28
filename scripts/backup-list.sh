#!/bin/bash
# List all backups with metadata
# Outputs JSON for API consumption

BACKUP_DIR="/root/backups"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Build JSON array of backups
echo "["

first=true
for metadata_file in "$BACKUP_DIR"/*/metadata.json; do
    [ -f "$metadata_file" ] || continue

    if [ "$first" = true ]; then
        first=false
    else
        echo ","
    fi

    cat "$metadata_file"
done

echo "]"
