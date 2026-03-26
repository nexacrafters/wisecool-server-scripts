#!/bin/bash
# Check if Traefik can connect to Docker socket
# Restarts coolify-proxy if Docker socket connection is lost

LOG_FILE="/var/log/traefik-monitor.log"
MAX_ERRORS=3
ERROR_COUNT_FILE="/tmp/traefik-docker-errors"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# Check recent proxy logs for Docker socket errors
ERRORS=$(docker logs coolify-proxy --since 1m 2>&1 | grep -c "Cannot connect to the Docker daemon")

if [ "$ERRORS" -gt 0 ]; then
    # Increment error counter
    if [ -f "$ERROR_COUNT_FILE" ]; then
        COUNT=$(cat "$ERROR_COUNT_FILE")
    else
        COUNT=0
    fi
    COUNT=$((COUNT + 1))
    echo "$COUNT" > "$ERROR_COUNT_FILE"

    log "WARNING: Docker socket errors detected ($ERRORS in last minute). Count: $COUNT/$MAX_ERRORS"

    if [ "$COUNT" -ge "$MAX_ERRORS" ]; then
        log "ERROR: Max errors reached. Restarting coolify-proxy..."
        docker restart coolify-proxy
        rm -f "$ERROR_COUNT_FILE"
        log "INFO: coolify-proxy restarted"

        # Send alert (optional - uncomment if you have notification setup)
        # curl -X POST "YOUR_WEBHOOK_URL" -d "message=Traefik proxy restarted due to Docker socket issues"
    fi
else
    # Reset counter if no errors
    if [ -f "$ERROR_COUNT_FILE" ]; then
        rm -f "$ERROR_COUNT_FILE"
    fi
fi
