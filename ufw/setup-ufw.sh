#!/bin/bash
# UFW Firewall Setup for Wisecool Server
# Run this after installing UFW

set -e

SSH_PORT="${1:-49317}"  # Pass SSH port as argument or use default

echo "Setting up UFW firewall..."
echo "SSH Port: $SSH_PORT"
echo ""

# Reset UFW
ufw --force reset

# Default policies
ufw default deny incoming
ufw default allow outgoing
ufw default allow routed  # For Docker

# Essential ports
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 443/udp comment 'HTTPS QUIC'
ufw allow ${SSH_PORT}/tcp comment 'SSH'

# Enable logging
ufw logging on

# Enable UFW
ufw --force enable

echo ""
echo "UFW configured with basic rules."
echo ""
echo "Add specific IP access with:"
echo "  ufw allow from YOUR_IP to any port ${SSH_PORT} comment 'SSH - Your Name'"
echo "  ufw allow from COOLIFY_IP to any port ${SSH_PORT} comment 'Coolify'"
echo ""
echo "For database access (only allow specific IPs!):"
echo "  ufw allow from TRUSTED_IP to any port 5430,5431,5432 proto tcp comment 'Redis'"
echo "  ufw allow from TRUSTED_IP to any port 5942,5943 proto tcp comment 'PostgreSQL'"
echo ""

ufw status verbose
