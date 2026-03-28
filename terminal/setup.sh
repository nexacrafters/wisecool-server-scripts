#!/bin/bash
# Terminal Server Setup for Wisecool Admin
# This script sets up ttyd terminal server with nginx proxy for secure access

set -e

DOMAIN="${TERMINAL_DOMAIN:-terminal.wisecool.tn}"
TTYD_PORT="${TTYD_PORT:-7681}"
NGINX_PORT="${NGINX_PORT:-7680}"

echo "=== Wisecool Terminal Server Setup ==="
echo "Domain: $DOMAIN"
echo "ttyd port: $TTYD_PORT (localhost only)"
echo "Nginx proxy port: $NGINX_PORT"
echo ""

# Install ttyd
echo "[1/5] Installing ttyd..."
if ! command -v ttyd &> /dev/null; then
    apt-get update -qq
    apt-get install -y ttyd
    echo "ttyd installed"
else
    echo "ttyd already installed"
fi

# Install nginx if not present
echo "[2/5] Installing nginx..."
if ! command -v nginx &> /dev/null; then
    apt-get install -y nginx
    echo "nginx installed"
else
    echo "nginx already installed"
fi

# Configure ttyd
echo "[3/5] Configuring ttyd..."
cat > /etc/default/ttyd << EOF
# /etc/default/ttyd - Terminal server for wisecool-admin
# Runs on localhost:$TTYD_PORT, proxied through nginx

TTYD_OPTIONS="-i 127.0.0.1 -p $TTYD_PORT -O -t fontSize=14 -t fontFamily=Menlo,monospace bash"
EOF

# Configure nginx
echo "[4/5] Configuring nginx reverse proxy..."
cat > /etc/nginx/sites-available/wisecool-terminal << EOF
# Wisecool Terminal Proxy
# Proxies ttyd from localhost:$TTYD_PORT

upstream ttyd_backend {
    server 127.0.0.1:$TTYD_PORT;
}

server {
    listen $NGINX_PORT;
    listen [::]:$NGINX_PORT;
    server_name $DOMAIN;

    # WebSocket support
    location / {
        proxy_pass http://ttyd_backend;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Timeouts for long-running terminal sessions
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_connect_timeout 60s;

        # Buffer settings
        proxy_buffering off;
        proxy_buffer_size 4k;
    }

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
}
EOF

ln -sf /etc/nginx/sites-available/wisecool-terminal /etc/nginx/sites-enabled/

# Test nginx config
nginx -t

# Restart services
echo "[5/5] Starting services..."
systemctl enable ttyd
systemctl restart ttyd
systemctl enable nginx
systemctl restart nginx

# Add fail2ban exception for terminal (optional)
if [ -d /etc/fail2ban/jail.d ]; then
    echo "[Optional] Adding fail2ban ignore for terminal traffic..."
    cat > /etc/fail2ban/jail.d/wisecool-terminal.local << EOF
# Don't ban legitimate terminal WebSocket connections
[nginx-http-auth]
ignoreip = 127.0.0.1/8 ::1
EOF
    systemctl reload fail2ban 2>/dev/null || true
fi

echo ""
echo "=== Terminal Server Setup Complete ==="
echo ""
echo "ttyd is running on: http://127.0.0.1:$TTYD_PORT"
echo "Nginx proxy is running on: http://0.0.0.0:$NGINX_PORT"
echo ""
echo "For production, set up SSL through Coolify/Traefik by:"
echo "1. Create a service in Coolify pointing to port $NGINX_PORT"
echo "2. Or configure Traefik labels for the terminal domain"
echo ""
echo "In wisecool-admin terminal settings, use:"
echo "  https://$DOMAIN"
echo ""
