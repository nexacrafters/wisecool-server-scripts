#!/bin/bash
# Wisecool Backup Restore Script
# Usage: ./backup-restore.sh <backup_name> [component]
#   component: all, postgres, redis (default: all)

set -e

BACKUP_DIR="/root/backups"
POSTGRES_CONTAINER="f8co488gcw4k0swk8wks0ckk"
REDIS_CONTAINERS=("lksksgk8s4o4gc0go8c0wk4w" "zw8ogk88c488w0okwkoo8kcw" "ugggwgw4cwk480owo44g480o")
REDIS_NAMES=("sessions" "api" "users")
PG_USER="wisecool"
PG_DB="wisecool"

BACKUP_NAME="${1:-}"
COMPONENT="${2:-all}"

if [ -z "$BACKUP_NAME" ]; then
    echo "Usage: $0 <backup_name> [component]"
    echo "Available backups:"
    ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | xargs -I{} basename {} .tar.gz || echo "  No backups found"
    exit 1
fi

ARCHIVE_FILE="$BACKUP_DIR/${BACKUP_NAME}.tar.gz"
BACKUP_FOLDER="$BACKUP_DIR/$BACKUP_NAME"

if [ ! -f "$ARCHIVE_FILE" ]; then
    echo "Backup not found: $ARCHIVE_FILE"
    exit 1
fi

echo "Restoring backup: $BACKUP_NAME"
echo "Component: $COMPONENT"
echo ""

# Extract archive if folder doesn't exist
if [ ! -d "$BACKUP_FOLDER" ]; then
    echo "Extracting archive..."
    tar -xzf "$ARCHIVE_FILE" -C "$BACKUP_DIR"
fi

restore_postgres() {
    local pg_file="$BACKUP_FOLDER/postgres_${PG_DB}.sql.gz"

    if [ ! -f "$pg_file" ]; then
        echo "PostgreSQL backup file not found: $pg_file"
        return 1
    fi

    echo "Restoring PostgreSQL database..."
    echo "WARNING: This will overwrite the current database!"
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        return 1
    fi

    # Restore database
    gunzip -c "$pg_file" | docker exec -i "$POSTGRES_CONTAINER" psql -U "$PG_USER" -d "$PG_DB"

    echo "PostgreSQL restore completed!"
}

restore_redis() {
    echo "Restoring Redis instances..."
    echo "WARNING: This will overwrite current Redis data!"
    read -p "Continue? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        echo "Aborted."
        return 1
    fi

    for i in "${!REDIS_CONTAINERS[@]}"; do
        local container="${REDIS_CONTAINERS[$i]}"
        local name="${REDIS_NAMES[$i]}"
        local redis_file="$BACKUP_FOLDER/redis_${name}.rdb"

        if [ ! -f "$redis_file" ]; then
            echo "  Redis $name backup not found, skipping..."
            continue
        fi

        echo "  Restoring Redis: $name"

        # Stop Redis, copy dump, restart
        docker stop "$container" > /dev/null 2>&1 || true
        docker cp "$redis_file" "$container:/data/dump.rdb"
        docker start "$container" > /dev/null 2>&1

        echo "  Redis $name restored!"
    done

    echo "Redis restore completed!"
}

case "$COMPONENT" in
    all)
        restore_postgres
        restore_redis
        ;;
    postgres|database|pg)
        restore_postgres
        ;;
    redis)
        restore_redis
        ;;
    *)
        echo "Unknown component: $COMPONENT"
        echo "Valid components: all, postgres, redis"
        exit 1
        ;;
esac

echo ""
echo "Restore completed!"
