# Wisecool Server Scripts

Complete server hardening, monitoring, and maintenance scripts for Wisecool infrastructure.

## Fresh Server Setup (One Command)

On a fresh Ubuntu 22.04+ server:

```bash
curl -sSL https://raw.githubusercontent.com/nexacrafters/wisecool-server-scripts/main/bootstrap.sh | sudo bash
```

Or with custom SSH port and swap:
```bash
SSH_PORT=22222 SWAP_SIZE=8 curl -sSL https://raw.githubusercontent.com/nexacrafters/wisecool-server-scripts/main/bootstrap.sh | sudo bash
```

This installs **everything**: Docker, fail2ban, UFW, swap, all security configs, and monitoring scripts.

## Existing Server Install

```bash
git clone https://github.com/nexacrafters/wisecool-server-scripts.git
cd wisecool-server-scripts
sudo ./install.sh
```

Then configure:
```bash
sudo nano /etc/security-alerts/config      # Email alerts
sudo nano /etc/fail2ban/jail.local         # Whitelist IPs, SSH port
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf  # Review SSH settings
sudo sshd -t && sudo systemctl reload sshd  # Apply SSH changes
```

## What's Included

### Scripts (`/usr/local/bin/`)

| Script | Purpose | Schedule |
|--------|---------|----------|
| `check-traefik-docker.sh` | Auto-restart proxy on Docker socket loss | Every minute (cron) |
| `security-monitor.sh` | Full security monitoring with email alerts | Every 5 min (systemd) |
| `security-audit.sh` | Daily security audit report | Daily 6 AM (systemd) |
| `docker-auto-prune.sh` | Auto-prune Docker when disk > 50GB | On boot (systemd) |
| `docker-firewall.sh` | Block external access to DB ports | On boot (systemd) |
| `security-alert.sh` | Email alert helper via Resend API | Called by scripts |

### Systemd Services (`/etc/systemd/system/`)

- `docker-firewall.service` - Firewall rules on boot
- `docker-auto-prune.service` - Docker cleanup daemon
- `security-monitor.service` + `.timer` - 5-minute security checks
- `security-audit.service` + `.timer` - Daily audit at 6 AM

### Security Configs

- `fail2ban/jail.local` - SSH brute force protection
- `ssh/99-hardening.conf` - SSH hardening (strong ciphers, rate limiting)
- `sysctl/99-enterprise-security.conf` - Kernel hardening (network, memory protection)
- `ufw/setup-ufw.sh` - Firewall setup script
- `logrotate/enterprise-security` - Log retention (52 weeks auth logs)
- `scripts/setup-swap.sh` - Swap file setup (4GB default)

## Security Alerts

Email alerts via Resend API for:

- New SSH logins from unknown IPs
- Brute force attacks (>50 failed attempts)
- OOM kills
- Critical services down (docker, fail2ban, ufw, ssh)
- Disk space warnings (>80%) and critical (>90%)
- Coolify IP accidentally banned (auto-unbans)
- Suspicious processes (cryptominers)
- SSH authorized_keys modifications
- Traefik proxy Docker socket issues (auto-restarts)

## Configuration Files

### `/etc/security-alerts/config`
```bash
RESEND_API_KEY="re_xxxx"
ALERT_EMAILS="admin@example.com,devops@example.com"
FROM_EMAIL="security@yourdomain.com"
SERVER_NAME="Production Server"
COOLIFY_IP="x.x.x.x"
```

### `/etc/fail2ban/jail.local`
```ini
[DEFAULT]
ignoreip = 127.0.0.1/8 ::1 YOUR_IP COOLIFY_IP

[sshd]
port = YOUR_SSH_PORT
maxretry = 3
bantime = 24h
```

## Logs

| Log | Purpose |
|-----|---------|
| `/var/log/traefik-monitor.log` | Proxy health monitoring |
| `/var/log/security-alerts.log` | All alerts sent |
| `/var/log/security-audit.log` | Daily audit reports |
| `/var/log/security-monitor.log` | Monitor script output |

## Firewall Rules

The `docker-firewall.sh` blocks external access to:
- PostgreSQL: 5430, 5431, 5432, 5942, 5943
- PgBouncer: 6432
- Traefik dashboard: 8080

Only internal Docker containers can access these ports.

## Kernel Hardening (sysctl)

The `sysctl/99-enterprise-security.conf` includes:

- **Network security**: SYN flood protection, ICMP hardening, IP spoofing prevention
- **Memory protection**: ASLR, restricted kernel pointers, symlink protection
- **Performance tuning**: Optimized TCP buffers, connection limits, file handles
- **Docker optimization**: Increased inotify limits

## Swap Setup

```bash
sudo ./scripts/setup-swap.sh 4  # Creates 4GB swap
```

## Requirements

- Ubuntu 22.04+ / Debian 11+
- Docker with Coolify
- fail2ban
- ufw
- curl, python3
- Resend.com account

## Uninstall

```bash
sudo ./uninstall.sh
```

## License

MIT - nexacrafters
