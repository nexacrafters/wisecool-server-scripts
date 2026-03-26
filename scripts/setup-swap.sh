#!/bin/bash
# Setup swap file for server
# Usage: ./setup-swap.sh [SIZE_IN_GB]

set -e

SWAP_SIZE="${1:-4}"  # Default 4GB
SWAPFILE="/swapfile"

echo "Setting up ${SWAP_SIZE}GB swap..."

# Check if swap already exists
if swapon --show | grep -q "$SWAPFILE"; then
    echo "Swap already exists:"
    swapon --show
    exit 0
fi

# Create swap file
fallocate -l ${SWAP_SIZE}G $SWAPFILE
chmod 600 $SWAPFILE
mkswap $SWAPFILE
swapon $SWAPFILE

# Add to fstab if not already there
if ! grep -q "$SWAPFILE" /etc/fstab; then
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
fi

# Set swappiness
sysctl vm.swappiness=10
echo "vm.swappiness=10" >> /etc/sysctl.d/99-enterprise-security.conf 2>/dev/null || true

echo ""
echo "Swap configured:"
swapon --show
free -h
