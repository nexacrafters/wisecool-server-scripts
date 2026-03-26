# Wisecool Server Scripts

Monitoring, security, and maintenance scripts for Wisecool infrastructure servers.

## Features

- **Traefik/Proxy Monitoring** - Auto-restarts proxy when Docker socket connection is lost
- **Security Monitoring** - Detects brute force attacks, unauthorized SSH access, suspicious processes
- **Docker Firewall** - Blocks external access to database ports
- **Auto Prune** - Keeps Docker disk usage under control
- **Security Audits** - Daily security status reports

## Quick Install

```bash
git clone https://github.com/wisecool-tn/server-scripts.git
cd server-scripts
sudo ./install.sh
```

Then edit the configuration:
```bash
sudo nano /etc/security-alerts/config
```

## Scripts

| Script | Description | Schedule |
|--------|-------------|----------|
| `check-traefik-docker.sh` | Monitors Traefik proxy Docker socket connectivity | Every minute |
| `security-monitor.sh` | Comprehensive security monitoring with email alerts | Every 5 minutes |
| `security-audit.sh` | Daily security audit report | Daily 6 AM |
| `docker-auto-prune.sh` | Auto-prunes Docker when disk usage exceeds threshold | Every 4 hours |
| `docker-firewall.sh` | Applies firewall rules to protect Docker ports | On boot |
| `security-alert.sh` | Helper for sending security alerts via Resend API | Called by other scripts |

## Configuration

Copy `config/security-alerts.conf.example` to `/etc/security-alerts/config` and configure:

```bash
RESEND_API_KEY="your_resend_api_key"
ALERT_EMAILS="admin@example.com"
FROM_EMAIL="security@yourdomain.com"
SERVER_NAME="Production Server"
COOLIFY_IP="your_coolify_ip"
```

## Alerts

The system sends email alerts for:

- New SSH logins from unknown IPs
- Brute force attack detection (>50 failed attempts)
- OOM kills
- Critical services down (docker, fail2ban, ufw, ssh)
- Disk space warnings (>80%) and critical (>90%)
- Coolify IP accidentally banned
- Suspicious processes (cryptominers, etc.)
- SSH authorized_keys modifications
- Traefik proxy Docker socket issues

## Logs

- `/var/log/traefik-monitor.log` - Traefik monitoring
- `/var/log/security-alerts.log` - All security alerts sent
- `/var/log/security-audit.log` - Daily audit reports

## Uninstall

```bash
sudo ./uninstall.sh
```

## Requirements

- Ubuntu/Debian server
- Docker with Coolify
- fail2ban
- ufw
- curl
- Resend.com account for email alerts

## License

MIT - Wisecool TN
