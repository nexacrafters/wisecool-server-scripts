#!/bin/bash
# Wisecool Server Scripts Installer
# Installs monitoring and security scripts for Wisecool infrastructure

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="/etc/security-alerts"

echo "=========================================="
echo "  Wisecool Server Scripts Installer"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root (sudo ./install.sh)"
    exit 1
fi

# Create directories
echo "[1/6] Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p /var/lib/security-monitor
mkdir -p /var/log

# Install scripts
echo "[2/6] Installing scripts to $INSTALL_DIR..."
cp "$SCRIPT_DIR/scripts/"*.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/"*.sh

# Install config template if not exists
echo "[3/6] Setting up configuration..."
if [ ! -f "$CONFIG_DIR/config" ]; then
    cp "$SCRIPT_DIR/config/security-alerts.conf.example" "$CONFIG_DIR/config"
    echo "  -> Created $CONFIG_DIR/config (EDIT THIS FILE WITH YOUR VALUES)"
else
    echo "  -> Config already exists, skipping"
fi

# Setup cron jobs
echo "[4/6] Setting up cron jobs..."

# Remove old entries and add new ones
(crontab -l 2>/dev/null | grep -v "check-traefik-docker\|security-monitor\|security-audit\|docker-auto-prune" ; \
echo "* * * * * $INSTALL_DIR/check-traefik-docker.sh" ; \
echo "*/5 * * * * $INSTALL_DIR/security-monitor.sh" ; \
echo "0 6 * * * $INSTALL_DIR/security-audit.sh" ; \
echo "0 */4 * * * $INSTALL_DIR/docker-auto-prune.sh") | crontab -

echo "  -> Cron jobs installed:"
echo "     - Traefik monitor: every minute"
echo "     - Security monitor: every 5 minutes"
echo "     - Security audit: daily at 6 AM"
echo "     - Docker prune: every 4 hours"

# Apply firewall rules
echo "[5/6] Applying Docker firewall rules..."
"$INSTALL_DIR/docker-firewall.sh" || echo "  -> Warning: Firewall rules may need Docker running"

# Setup firewall on boot
echo "[6/6] Setting up firewall on boot..."
if [ ! -f /etc/systemd/system/docker-firewall.service ]; then
    cat > /etc/systemd/system/docker-firewall.service << 'EOF'
[Unit]
Description=Docker Firewall Rules
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/docker-firewall.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable docker-firewall.service
    echo "  -> Firewall service enabled"
else
    echo "  -> Firewall service already exists"
fi

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT: Edit the configuration file:"
echo "  nano $CONFIG_DIR/config"
echo ""
echo "Required settings:"
echo "  - RESEND_API_KEY: Your Resend.com API key"
echo "  - ALERT_EMAILS: Email addresses for alerts"
echo "  - FROM_EMAIL: Verified sender email"
echo "  - SERVER_NAME: Friendly name for this server"
echo "  - COOLIFY_IP: Your Coolify management server IP"
echo ""
echo "Logs location:"
echo "  - /var/log/traefik-monitor.log"
echo "  - /var/log/security-alerts.log"
echo "  - /var/log/security-audit.log"
echo ""
echo "Test the installation:"
echo "  $INSTALL_DIR/security-monitor.sh"
echo ""
