#!/bin/bash
# Monitor Docker and auto-prune when it gets too big

MAX_DOCKER_GB=50  # Prune when Docker uses more than this

while true; do
    # Get Docker disk usage in GB
    DOCKER_SIZE=$(docker system df --format '{{.Size}}' | head -1 | grep -oE '[0-9.]+' | head -1)
    DOCKER_UNIT=$(docker system df --format '{{.Size}}' | head -1 | grep -oE 'GB|MB|TB' | head -1)

    # Convert to GB for comparison
    if [ "$DOCKER_UNIT" = "TB" ]; then
        DOCKER_GB=$(echo "$DOCKER_SIZE * 1000" | bc)
    elif [ "$DOCKER_UNIT" = "MB" ]; then
        DOCKER_GB=$(echo "$DOCKER_SIZE / 1000" | bc)
    else
        DOCKER_GB=${DOCKER_SIZE%.*}
    fi

    if [ "$DOCKER_GB" -gt "$MAX_DOCKER_GB" ] 2>/dev/null; then
        echo "$(date): Docker at ${DOCKER_SIZE}${DOCKER_UNIT}, exceeds ${MAX_DOCKER_GB}GB. Pruning..."
        docker system prune -af
        echo "$(date): Prune complete"
    fi

    sleep 3600  # Check every 5 minutes
done
