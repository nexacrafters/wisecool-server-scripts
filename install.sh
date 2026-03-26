#!/bin/bash
# Wisecool Server Scripts Installer
# Full server hardening and monitoring setup

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
echo "[1/9] Creating directories..."
mkdir -p "$CONFIG_DIR"
mkdir -p /var/lib/security-monitor
mkdir -p /var/log

# Install scripts
echo "[2/9] Installing scripts to $INSTALL_DIR..."
cp "$SCRIPT_DIR/scripts/"*.sh "$INSTALL_DIR/"
chmod +x "$INSTALL_DIR/"*.sh

# Install config template if not exists
echo "[3/9] Setting up alert configuration..."
if [ ! -f "$CONFIG_DIR/config" ]; then
    cp "$SCRIPT_DIR/config/security-alerts.conf.example" "$CONFIG_DIR/config"
    chmod 600 "$CONFIG_DIR/config"
    echo "  -> Created $CONFIG_DIR/config (EDIT THIS FILE)"
else
    echo "  -> Config already exists, skipping"
fi

# Install systemd services
echo "[4/9] Installing systemd services..."
cp "$SCRIPT_DIR/systemd/"*.service /etc/systemd/system/
cp "$SCRIPT_DIR/systemd/"*.timer /etc/systemd/system/
systemctl daemon-reload

# Enable services
systemctl enable docker-firewall.service
systemctl enable docker-auto-prune.service
systemctl enable security-monitor.timer
systemctl enable security-audit.timer

# Start timers
systemctl start security-monitor.timer
systemctl start security-audit.timer

echo "  -> Systemd services installed and enabled"

# Install fail2ban config
echo "[5/9] Setting up fail2ban..."
if [ -d /etc/fail2ban ]; then
    if [ ! -f /etc/fail2ban/jail.local ]; then
        cp "$SCRIPT_DIR/fail2ban/jail.local" /etc/fail2ban/jail.local
        echo "  -> Installed jail.local (EDIT ignoreip AND port!)"
    else
        echo "  -> jail.local exists, skipping (check $SCRIPT_DIR/fail2ban/jail.local)"
    fi
    systemctl restart fail2ban
else
    echo "  -> fail2ban not installed, skipping"
fi

# Install SSH hardening
echo "[6/9] Setting up SSH hardening..."
if [ -d /etc/ssh/sshd_config.d ]; then
    if [ ! -f /etc/ssh/sshd_config.d/99-hardening.conf ]; then
        cp "$SCRIPT_DIR/ssh/99-hardening.conf" /etc/ssh/sshd_config.d/
        echo "  -> Installed SSH hardening config"
        echo "  -> WARNING: Review settings before restarting SSH!"
    else
        echo "  -> SSH hardening already exists, skipping"
    fi
else
    echo "  -> sshd_config.d not found, skipping"
fi

# Install logrotate config
echo "[7/9] Setting up log rotation..."
cp "$SCRIPT_DIR/logrotate/enterprise-security" /etc/logrotate.d/
echo "  -> Installed log rotation config"

# Setup cron for traefik monitor (runs every minute - too fast for systemd timer)
echo "[8/9] Setting up cron jobs..."
(crontab -l 2>/dev/null | grep -v "check-traefik-docker" ; \
echo "* * * * * $INSTALL_DIR/check-traefik-docker.sh") | crontab -
echo "  -> Traefik monitor cron installed (every minute)"

# Install sysctl hardening
echo "[9/11] Installing kernel security settings..."
if [ ! -f /etc/sysctl.d/99-enterprise-security.conf ]; then
    cp "$SCRIPT_DIR/sysctl/99-enterprise-security.conf" /etc/sysctl.d/
    sysctl --system > /dev/null 2>&1
    echo "  -> Kernel hardening applied"
else
    echo "  -> Sysctl config exists, skipping"
fi

# Setup swap if not exists
echo "[10/11] Checking swap..."
if ! swapon --show | grep -q "/swapfile"; then
    echo "  -> No swap found. Run: $SCRIPT_DIR/scripts/setup-swap.sh 4"
else
    echo "  -> Swap already configured"
fi

# Apply firewall rules now
echo "[11/11] Applying Docker firewall rules..."
"$INSTALL_DIR/docker-firewall.sh" 2>/dev/null || echo "  -> Warning: Run after Docker starts"

echo ""
echo "=========================================="
echo "  Installation Complete!"
echo "=========================================="
echo ""
echo "REQUIRED - Edit these files:"
echo ""
echo "1. $CONFIG_DIR/config"
echo "   - RESEND_API_KEY: Your Resend.com API key"
echo "   - ALERT_EMAILS: Email addresses for alerts"
echo "   - FROM_EMAIL: Verified sender email"
echo "   - SERVER_NAME: Friendly name for this server"
echo "   - COOLIFY_IP: Your Coolify management server IP"
echo ""
echo "2. /etc/fail2ban/jail.local"
echo "   - ignoreip: Add your IPs to whitelist"
echo "   - port: Change 49317 to your SSH port"
echo ""
echo "3. Review SSH settings before applying:"
echo "   cat /etc/ssh/sshd_config.d/99-hardening.conf"
echo "   sshd -t && systemctl reload sshd"
echo ""
echo "Services status:"
systemctl is-active docker-firewall.service || true
systemctl is-active docker-auto-prune.service || true
systemctl is-active security-monitor.timer || true
systemctl is-active security-audit.timer || true
echo ""
echo "Test: $INSTALL_DIR/security-monitor.sh"
echo ""
