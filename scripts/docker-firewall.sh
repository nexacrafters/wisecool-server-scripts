#!/bin/bash
# Enterprise Docker Firewall Rules
# Blocks external access to sensitive Docker ports
# Applied: 2026-03-01

set -e

# Wait for Docker to create DOCKER-USER chain
sleep 5

# Function to add rule if it doesn't exist
add_rule() {
    if ! iptables -C DOCKER-USER "$@" 2>/dev/null; then
        iptables -I DOCKER-USER "$@"
    fi
}

# Block external access to database ports (PostgreSQL, PgBouncer, Redis proxies)
add_rule -i eth0 -p tcp --dport 5430 -j DROP
add_rule -i eth0 -p tcp --dport 5431 -j DROP
add_rule -i eth0 -p tcp --dport 5432 -j DROP
add_rule -i eth0 -p tcp --dport 5942 -j DROP
add_rule -i eth0 -p tcp --dport 5943 -j DROP
add_rule -i eth0 -p tcp --dport 6432 -j DROP

# Block Traefik dashboard from external access
add_rule -i eth0 -p tcp --dport 8080 -j DROP

echo "Docker firewall rules applied successfully"
