# Wisecool Terminal Server

Secure web-based terminal access for wisecool-admin.

## Architecture

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│  wisecool-admin │ --> │  Traefik/nginx  │ --> │      ttyd       │
│   (Frontend)    │     │   (SSL Proxy)   │     │  (localhost)    │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │
        ▼
┌─────────────────┐
│  wisecool-api   │
│ (Auth/Password) │
└─────────────────┘
```

## Security

1. **Password Gate**: Daily password set by admin (ID 1) via wisecool-api
2. **Session Tokens**: 1-hour sessions stored in database
3. **Granular Permissions**: Users can be restricted to specific tools (POSTGRES, REDIS, etc.)
4. **ttyd on localhost**: Terminal server only accessible via proxy

## Quick Setup

### Option 1: Direct Setup (Recommended)

```bash
chmod +x setup.sh
./setup.sh
```

### Option 2: Docker + Coolify

1. Deploy via Coolify using `docker-compose.yml`
2. Configure domain: `terminal.wisecool.tn`
3. Enable HTTPS

## Configuration

### ttyd Options

Edit `/etc/default/ttyd`:

```bash
# Basic (default)
TTYD_OPTIONS="-i 127.0.0.1 -p 7681 -O bash"

# With custom shell
TTYD_OPTIONS="-i 127.0.0.1 -p 7681 -O /bin/zsh"

# Read-only mode (view only)
TTYD_OPTIONS="-i 127.0.0.1 -p 7681 -O -R bash"
```

### Environment Variables

```bash
export TERMINAL_DOMAIN="terminal.wisecool.tn"
export TTYD_PORT="7681"
export NGINX_PORT="7680"
```

## Permission Types

| Type | Description | Access |
|------|-------------|--------|
| FULL_SHELL | Complete bash access | Full server control |
| POSTGRES | PostgreSQL only | `psql` commands |
| REDIS | Redis CLI only | `redis-cli` commands |
| DOCKER | Docker/Compose | Container management |
| LOGS | View logs | `journalctl`, `docker logs` |
| CLAUDE_CODE | Claude CLI | AI assistant |
| GIT | Git operations | Repository management |
| SYSTEM_INFO | System monitoring | `htop`, `df`, `free` |

## API Endpoints

All endpoints require authentication via wisecool-admin:

```
GET  /security/terminal/status/           - Check if password is set
POST /security/terminal/set-password/     - Set password (admin only)
POST /security/terminal/verify/           - Verify password, get session
GET  /security/terminal/check-session/    - Check session validity
POST /security/terminal/logout/           - End session

GET  /security/terminal/permissions/      - List all permissions (admin)
POST /security/terminal/permissions/set/  - Set user permissions (admin)
POST /security/terminal/permissions/revoke/ - Revoke access (admin)
GET  /security/terminal/my-permissions/   - Get own permissions
```

## Troubleshooting

### ttyd not starting
```bash
systemctl status ttyd
journalctl -u ttyd -f
```

### WebSocket connection failed
- Check nginx/Traefik logs
- Ensure `Upgrade` header is passed through proxy
- Verify port 7681 is accessible from proxy

### Session expired immediately
- Check server time sync: `timedatectl`
- Verify wisecool-api database connectivity

## Files

- `setup.sh` - Installation script
- `docker-compose.yml` - Docker deployment for Coolify
- `nginx.conf` - Nginx config for Docker container
- `/etc/default/ttyd` - ttyd configuration
- `/etc/nginx/sites-available/wisecool-terminal` - Nginx site config
