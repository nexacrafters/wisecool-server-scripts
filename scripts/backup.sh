#!/bin/bash
# Wisecool Backup Script
# Creates backups of PostgreSQL database and Redis data
# Usage: ./backup.sh [type] [name]
#   type: full, database, redis (default: full)
#   name: optional backup name (default: auto-generated)

set -e

# Configuration
BACKUP_DIR="/root/backups"
RETENTION_DAYS=30
POSTGRES_CONTAINER="f8co488gcw4k0swk8wks0ckk"
REDIS_CONTAINERS=("lksksgk8s4o4gc0go8c0wk4w" "zw8ogk88c488w0okwkoo8kcw" "ugggwgw4cwk480owo44g480o")
REDIS_NAMES=("sessions" "api" "users")

# PostgreSQL credentials
PG_USER="wisecool"
PG_DB="wisecool"

# Parse arguments
BACKUP_TYPE="${1:-full}"
BACKUP_NAME="${2:-}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

if [ -z "$BACKUP_NAME" ]; then
    BACKUP_NAME="${BACKUP_TYPE}_${TIMESTAMP}"
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"
CURRENT_BACKUP_DIR="$BACKUP_DIR/$BACKUP_NAME"
mkdir -p "$CURRENT_BACKUP_DIR"

# Metadata file
METADATA_FILE="$CURRENT_BACKUP_DIR/metadata.json"

echo "Starting $BACKUP_TYPE backup: $BACKUP_NAME"
echo "Backup directory: $CURRENT_BACKUP_DIR"

# Initialize metadata
cat > "$METADATA_FILE" << EOF
{
  "name": "$BACKUP_NAME",
  "type": "$BACKUP_TYPE",
  "timestamp": "$(date -Iseconds)",
  "status": "in_progress",
  "components": {}
}
EOF

backup_postgres() {
    echo "Backing up PostgreSQL database..."
    local pg_file="$CURRENT_BACKUP_DIR/postgres_${PG_DB}.sql.gz"

    if docker exec "$POSTGRES_CONTAINER" pg_dump -U "$PG_USER" "$PG_DB" | gzip > "$pg_file"; then
        local size=$(stat -c%s "$pg_file" 2>/dev/null || stat -f%z "$pg_file")
        echo "PostgreSQL backup completed: $pg_file ($size bytes)"

        # Update metadata
        python3 << PYEOF
import json
with open("$METADATA_FILE", "r") as f:
    data = json.load(f)
data["components"]["postgres"] = {
    "file": "postgres_${PG_DB}.sql.gz",
    "size": $size,
    "database": "$PG_DB",
    "status": "completed"
}
with open("$METADATA_FILE", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
        return 0
    else
        echo "PostgreSQL backup failed!"
        return 1
    fi
}

backup_redis() {
    echo "Backing up Redis instances..."

    for i in "${!REDIS_CONTAINERS[@]}"; do
        local container="${REDIS_CONTAINERS[$i]}"
        local name="${REDIS_NAMES[$i]}"
        local redis_file="$CURRENT_BACKUP_DIR/redis_${name}.rdb"

        echo "  Backing up Redis: $name ($container)"

        # Trigger BGSAVE and wait
        docker exec "$container" redis-cli BGSAVE > /dev/null 2>&1 || true
        sleep 2

        # Copy the dump file
        if docker cp "$container:/data/dump.rdb" "$redis_file" 2>/dev/null; then
            local size=$(stat -c%s "$redis_file" 2>/dev/null || stat -f%z "$redis_file")
            echo "  Redis $name backup completed: $redis_file ($size bytes)"

            # Update metadata
            python3 << PYEOF
import json
with open("$METADATA_FILE", "r") as f:
    data = json.load(f)
if "redis" not in data["components"]:
    data["components"]["redis"] = {}
data["components"]["redis"]["$name"] = {
    "file": "redis_${name}.rdb",
    "size": $size,
    "container": "$container",
    "status": "completed"
}
with open("$METADATA_FILE", "w") as f:
    json.dump(data, f, indent=2)
PYEOF
        else
            echo "  Redis $name backup skipped (no dump file)"
        fi
    done
}

# Run backups based on type
case "$BACKUP_TYPE" in
    full)
        backup_postgres
        backup_redis
        ;;
    database|postgres|pg)
        backup_postgres
        ;;
    redis)
        backup_redis
        ;;
    *)
        echo "Unknown backup type: $BACKUP_TYPE"
        echo "Valid types: full, database, redis"
        exit 1
        ;;
esac

# Calculate total size
TOTAL_SIZE=$(du -sb "$CURRENT_BACKUP_DIR" | cut -f1)

# Create archive
echo "Creating archive..."
ARCHIVE_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
tar -czf "$ARCHIVE_FILE" -C "$BACKUP_DIR" "$BACKUP_NAME"
ARCHIVE_SIZE=$(stat -c%s "$ARCHIVE_FILE" 2>/dev/null || stat -f%z "$ARCHIVE_FILE")

# Update final metadata
python3 << PYEOF
import json
with open("$METADATA_FILE", "r") as f:
    data = json.load(f)
data["status"] = "completed"
data["total_size"] = $TOTAL_SIZE
data["archive_size"] = $ARCHIVE_SIZE
data["archive_file"] = "${BACKUP_NAME}.tar.gz"
data["completed_at"] = "$(date -Iseconds)"
with open("$METADATA_FILE", "w") as f:
    json.dump(data, f, indent=2)
PYEOF

# Cleanup old backups
echo "Cleaning up old backups (older than $RETENTION_DAYS days)..."
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +$RETENTION_DAYS -delete 2>/dev/null || true
find "$BACKUP_DIR" -type d -empty -mtime +$RETENTION_DAYS -delete 2>/dev/null || true

echo ""
echo "Backup completed successfully!"
echo "Archive: $ARCHIVE_FILE"
echo "Size: $(numfmt --to=iec $ARCHIVE_SIZE 2>/dev/null || echo "$ARCHIVE_SIZE bytes")"
echo ""

# Output JSON for API consumption
echo "BACKUP_JSON:$(cat "$METADATA_FILE")"
