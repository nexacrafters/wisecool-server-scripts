#!/bin/bash
# Wisecool Server Scripts Uninstaller

set -e

INSTALL_DIR="/usr/local/bin"

echo "Removing Wisecool Server Scripts..."

# Remove cron jobs
(crontab -l 2>/dev/null | grep -v "check-traefik-docker\|security-monitor\|security-audit\|docker-auto-prune") | crontab -

# Remove scripts
rm -f "$INSTALL_DIR/check-traefik-docker.sh"
rm -f "$INSTALL_DIR/docker-auto-prune.sh"
rm -f "$INSTALL_DIR/docker-firewall.sh"
rm -f "$INSTALL_DIR/security-alert.sh"
rm -f "$INSTALL_DIR/security-audit.sh"
rm -f "$INSTALL_DIR/security-monitor.sh"

# Remove systemd service
systemctl disable docker-firewall.service 2>/dev/null || true
rm -f /etc/systemd/system/docker-firewall.service
systemctl daemon-reload

echo ""
echo "Uninstall complete."
echo ""
echo "Note: Configuration and logs were NOT removed:"
echo "  - /etc/security-alerts/config"
echo "  - /var/log/traefik-monitor.log"
echo "  - /var/log/security-alerts.log"
echo "  - /var/log/security-audit.log"
echo "  - /var/lib/security-monitor/"
echo ""
echo "Remove manually if needed."
