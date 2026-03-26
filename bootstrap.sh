#!/bin/bash
# Wisecool Server Bootstrap
# Run this on a fresh Ubuntu 22.04+ server to set up everything
#
# Usage: curl -sSL https://raw.githubusercontent.com/nexacrafters/wisecool-server-scripts/main/bootstrap.sh | sudo bash

set -e

echo "=========================================="
echo "  Wisecool Server Bootstrap"
echo "=========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root"
    exit 1
fi

SSH_PORT="${SSH_PORT:-49317}"
SWAP_SIZE="${SWAP_SIZE:-4}"

echo "Configuration:"
echo "  SSH Port: $SSH_PORT (set SSH_PORT env to change)"
echo "  Swap Size: ${SWAP_SIZE}GB (set SWAP_SIZE env to change)"
echo ""

# ============================================
# 1. System Update
# ============================================
echo "[1/8] Updating system..."
apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -qq

# ============================================
# 2. Install Dependencies
# ============================================
echo "[2/8] Installing dependencies..."
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl \
    wget \
    git \
    fail2ban \
    ufw \
    python3 \
    jq \
    htop \
    ncdu \
    unzip \
    ca-certificates \
    gnupg \
    lsb-release

# ============================================
# 3. Install Docker (if not present)
# ============================================
echo "[3/8] Setting up Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "  -> Docker installed"
else
    echo "  -> Docker already installed"
fi

# ============================================
# 4. Setup Swap
# ============================================
echo "[4/8] Setting up swap..."
if ! swapon --show | grep -q "/swapfile"; then
    fallocate -l ${SWAP_SIZE}G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo "/swapfile none swap sw 0 0" >> /etc/fstab
    echo "  -> ${SWAP_SIZE}GB swap created"
else
    echo "  -> Swap already exists"
fi

# ============================================
# 5. Clone and Install Scripts
# ============================================
echo "[5/8] Installing Wisecool scripts..."
REPO_DIR="/opt/wisecool-server-scripts"
if [ -d "$REPO_DIR" ]; then
    cd "$REPO_DIR" && git pull -q
else
    git clone -q https://github.com/nexacrafters/wisecool-server-scripts.git "$REPO_DIR"
fi
cd "$REPO_DIR"

# Copy scripts
cp scripts/*.sh /usr/local/bin/
chmod +x /usr/local/bin/*.sh

# Copy systemd files
cp systemd/*.service /etc/systemd/system/
cp systemd/*.timer /etc/systemd/system/
systemctl daemon-reload

# Enable services
systemctl enable docker-firewall.service
systemctl enable docker-auto-prune.service
systemctl enable security-monitor.timer
systemctl enable security-audit.timer
systemctl start security-monitor.timer || true
systemctl start security-audit.timer || true

# Setup cron
(crontab -l 2>/dev/null | grep -v "check-traefik-docker" ; \
echo "* * * * * /usr/local/bin/check-traefik-docker.sh") | crontab -

echo "  -> Scripts installed"

# ============================================
# 6. Configure Security
# ============================================
echo "[6/8] Configuring security..."

# Sysctl
cp sysctl/99-enterprise-security.conf /etc/sysctl.d/
sysctl --system > /dev/null 2>&1

# SSH hardening
cp ssh/99-hardening.conf /etc/ssh/sshd_config.d/

# Change SSH port
if ! grep -q "^Port $SSH_PORT" /etc/ssh/sshd_config; then
    sed -i "s/^#*Port .*/Port $SSH_PORT/" /etc/ssh/sshd_config
fi

# Fail2ban
cp fail2ban/jail.local /etc/fail2ban/
sed -i "s/port = 49317/port = $SSH_PORT/" /etc/fail2ban/jail.local
systemctl restart fail2ban

# Logrotate
cp logrotate/enterprise-security /etc/logrotate.d/

echo "  -> Security configured"

# ============================================
# 7. Configure UFW
# ============================================
echo "[7/8] Configuring firewall..."
ufw --force reset > /dev/null
ufw default deny incoming > /dev/null
ufw default allow outgoing > /dev/null
ufw default allow routed > /dev/null

ufw allow 80/tcp comment 'HTTP' > /dev/null
ufw allow 443/tcp comment 'HTTPS' > /dev/null
ufw allow 443/udp comment 'HTTPS QUIC' > /dev/null
ufw allow ${SSH_PORT}/tcp comment 'SSH' > /dev/null

ufw --force enable > /dev/null
echo "  -> UFW configured"

# ============================================
# 8. Create Config Template
# ============================================
echo "[8/8] Setting up alert config..."
mkdir -p /etc/security-alerts
if [ ! -f /etc/security-alerts/config ]; then
    cp config/security-alerts.conf.example /etc/security-alerts/config
    chmod 600 /etc/security-alerts/config
fi

# Reload SSH
sshd -t && systemctl reload sshd

echo ""
echo "=========================================="
echo "  Bootstrap Complete!"
echo "=========================================="
echo ""
echo "IMPORTANT - Edit these files NOW:"
echo ""
echo "1. sudo nano /etc/security-alerts/config"
echo "   Add your Resend API key and email addresses"
echo ""
echo "2. sudo nano /etc/fail2ban/jail.local"
echo "   Add your IPs to ignoreip whitelist"
echo ""
echo "3. Add trusted IPs to firewall:"
echo "   sudo ufw allow from YOUR_IP to any port $SSH_PORT comment 'SSH - Your Name'"
echo "   sudo ufw allow from COOLIFY_IP to any port $SSH_PORT comment 'Coolify'"
echo ""
echo "SSH is now on port: $SSH_PORT"
echo ""
echo "Test connection in NEW terminal before closing this one!"
echo ""
