#!/bin/bash
# Enterprise Security Monitor - Wisecool TN
# Monitors for security events and sends alerts

source /etc/security-alerts/config

STATE_DIR="/var/lib/security-monitor"
mkdir -p "$STATE_DIR"

# Get server IP to sanitize it from outputs (never expose in emails)
SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "")
SERVER_IP6=$(curl -s -6 ifconfig.me 2>/dev/null || echo "")
SERVER_HOSTNAME=$(hostname)

# Sanitize function - removes server IP from text
sanitize() {
    local text="$1"
    if [ -n "$SERVER_IP" ]; then
        text=$(echo "$text" | sed "s/$SERVER_IP/[REDACTED]/g")
    fi
    if [ -n "$SERVER_IP6" ]; then
        text=$(echo "$text" | sed "s/$SERVER_IP6/[REDACTED]/g")
    fi
    echo "$text"
}

# JSON escape function
json_escape() {
    printf '%s' "$1" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'
}

send_alert() {
    local subject="$1"
    local body="$2"
    local priority="${3:-normal}"

    if [ "$priority" = "critical" ]; then
        subject="[CRITICAL] $subject"
    elif [ "$priority" = "warning" ]; then
        subject="[WARNING] $subject"
    fi

    # Sanitize body to remove server IP
    body=$(sanitize "$body")

    local full_body="Server: $SERVER_NAME
Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
Priority: $priority

$body

---
Automated Security Alert - Wisecool TN"

    # Escape for JSON
    local escaped_body=$(json_escape "$full_body")

    IFS=',' read -ra EMAILS <<< "$ALERT_EMAILS"
    for email in "${EMAILS[@]}"; do
        sleep 1  # Rate limiting
        curl -s -X POST 'https://api.resend.com/emails' \
            -H "Authorization: Bearer $RESEND_API_KEY" \
            -H 'Content-Type: application/json' \
            -d "{
                \"from\": \"Security Alert <$FROM_EMAIL>\",
                \"to\": [\"$email\"],
                \"subject\": \"$subject\",
                \"text\": $escaped_body
            }" >> /var/log/security-alerts-api.log 2>&1
    done

    echo "$(date '+%Y-%m-%d %H:%M:%S') [$priority] $subject" >> /var/log/security-alerts.log
}

# ============================================
# CHECK 1: New SSH Login Detection
# ============================================
check_ssh_logins() {
    local known_ips_file="$STATE_DIR/known_ssh_ips"
    touch "$known_ips_file"

    local recent_logins=$(grep "Accepted" /var/log/auth.log 2>/dev/null | tail -20)

    while IFS= read -r line; do
        local ip=$(echo "$line" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        local user=$(echo "$line" | grep -oP 'for \K\w+' | head -1)

        if [ -n "$ip" ] && ! grep -q "^$ip$" "$known_ips_file"; then
            echo "$ip" >> "$known_ips_file"

            # Skip Coolify management server
            if [ "$ip" = "194.163.185.133" ]; then
                continue
            fi

            local geo=$(curl -s "http://ip-api.com/line/$ip?fields=country,city" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

            send_alert "New SSH Login Detected" \
"A successful SSH login was detected from a new IP address.

User: $user
IP Address: $ip
Location: $geo

If this was not you, immediately:
1. Change your SSH keys
2. Check for unauthorized changes
3. Review running processes" "warning"
        fi
    done <<< "$recent_logins"
}

# ============================================
# CHECK 2: Brute Force Detection
# ============================================
check_brute_force() {
    local alert_file="$STATE_DIR/last_bruteforce_alert"
    local current_time=$(date +%s)
    local last_alert=0

    [ -f "$alert_file" ] && last_alert=$(cat "$alert_file")

    if [ $((current_time - last_alert)) -lt 3600 ]; then
        return
    fi

    local failed_count=$(grep "Failed password" /var/log/auth.log 2>/dev/null | \
        grep "$(date '+%b %_d')" | wc -l)

    if [ "$failed_count" -gt 50 ]; then
        echo "$current_time" > "$alert_file"

        local top_attackers=$(grep "Failed password" /var/log/auth.log 2>/dev/null | \
            grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -5)

        local banned_count=$(fail2ban-client status sshd 2>/dev/null | grep "Currently banned" | awk '{print $4}')

        send_alert "High Brute Force Activity" \
"Elevated brute force attack activity detected.

Failed attempts today: $failed_count
Currently banned IPs: $banned_count

Top attacking IPs:
$top_attackers

Fail2ban is actively blocking attackers." "warning"
    fi
}

# ============================================
# CHECK 3: OOM Kill Detection
# ============================================
check_oom_kills() {
    local last_check_file="$STATE_DIR/last_oom_time"
    local current_time=$(date +%s)
    local last_check=0

    [ -f "$last_check_file" ] && last_check=$(cat "$last_check_file")

    # Only alert once per hour for OOM
    if [ $((current_time - last_check)) -lt 3600 ]; then
        return
    fi

    local recent_oom=$(dmesg -T 2>/dev/null | grep -i "oom-kill" | tail -1)

    if [ -n "$recent_oom" ]; then
        # Check if it's from today
        if echo "$recent_oom" | grep -q "$(date '+%a %b %_d')"; then
            echo "$current_time" > "$last_check_file"

            local mem_info=$(free -h)

            send_alert "OOM Kill Detected" \
"The system killed a process due to memory exhaustion.

Memory status:
$mem_info

Action: Check for memory leaks or increase resources." "critical"
        fi
    fi
}

# ============================================
# CHECK 4: Service Down Detection
# ============================================
check_services() {
    local services=("docker" "fail2ban" "ufw" "ssh")
    local down_services=""

    for svc in "${services[@]}"; do
        if ! systemctl is-active --quiet "$svc"; then
            down_services="$down_services $svc"
        fi
    done

    if [ -n "$down_services" ]; then
        # Try to restart
        for svc in $down_services; do
            systemctl restart "$svc" 2>/dev/null
        done

        send_alert "Critical Services Down" \
"Services not running: $down_services

Restart attempted. Please verify." "critical"
    fi
}

# ============================================
# CHECK 5: Disk Space Alert
# ============================================
check_disk_space() {
    local usage=$(df / | tail -1 | awk '{print $5}' | tr -d '%')
    local alert_file="$STATE_DIR/last_disk_alert"
    local current_time=$(date +%s)
    local last_alert=0

    [ -f "$alert_file" ] && last_alert=$(cat "$alert_file")

    if [ "$usage" -gt 90 ]; then
        if [ $((current_time - last_alert)) -gt 3600 ]; then
            echo "$current_time" > "$alert_file"
            send_alert "Disk Space Critical (${usage}%)" \
"Root partition is ${usage}% full. Immediate action required." "critical"
        fi
    elif [ "$usage" -gt 80 ]; then
        if [ $((current_time - last_alert)) -gt 86400 ]; then
            echo "$current_time" > "$alert_file"
            send_alert "Disk Space Warning (${usage}%)" \
"Root partition is ${usage}% full. Consider cleanup." "warning"
        fi
    fi
}

# ============================================
# CHECK 6: Coolify Connectivity
# ============================================
check_coolify() {
    local coolify_ip="194.163.185.133"
    local alert_file="$STATE_DIR/coolify_status"
    local last_status="ok"

    [ -f "$alert_file" ] && last_status=$(cat "$alert_file")

    # Check if Coolify IP has connected recently (last 30 min)
    local last_coolify=$(grep "Accepted.*$coolify_ip" /var/log/auth.log 2>/dev/null | tail -1)

    # Check if Coolify IP is accidentally banned
    local is_banned=$(fail2ban-client status sshd 2>/dev/null | grep "$coolify_ip")

    if [ -n "$is_banned" ]; then
        if [ "$last_status" != "banned" ]; then
            echo "banned" > "$alert_file"

            # Auto-unban Coolify
            fail2ban-client set sshd unbanip "$coolify_ip" 2>/dev/null

            send_alert "Coolify IP Was Banned - Auto Fixed" \
"The Coolify management server IP ($coolify_ip) was accidentally banned by fail2ban.

Action taken: IP has been automatically unbanned.

This could happen if:
- Coolify had connection issues causing multiple retries
- Network problems caused failed handshakes

Coolify should reconnect shortly." "warning"
        fi
    else
        echo "ok" > "$alert_file"
    fi
}

# ============================================
# CHECK 7: Suspicious Process Detection
# ============================================
check_suspicious_processes() {
    local alert_file="$STATE_DIR/last_process_alert"
    local current_time=$(date +%s)
    local last_alert=0

    [ -f "$alert_file" ] && last_alert=$(cat "$alert_file")

    # Only check once per hour
    if [ $((current_time - last_alert)) -lt 3600 ]; then
        return
    fi

    # Look for common cryptominer/malware process names
    local suspicious=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|cgminer|kworker.*mining|\.hidden|/tmp/\." | grep -v grep)

    if [ -n "$suspicious" ]; then
        echo "$current_time" > "$alert_file"

        send_alert "Suspicious Process Detected" \
"Potentially malicious process found running on server.

Suspicious processes:
$suspicious

Immediate investigation required:
1. Kill suspicious process: kill -9 <PID>
2. Check how it started: check crontab, systemd, rc.local
3. Look for persistence mechanisms
4. Check for unauthorized SSH keys

Recent crontab entries:
$(crontab -l 2>/dev/null | tail -5 || echo 'None')

This could indicate a server compromise." "critical"
    fi
}

# ============================================
# CHECK 8: Unauthorized SSH Key Detection
# ============================================
check_ssh_keys() {
    local keys_file="/root/.ssh/authorized_keys"
    local hash_file="$STATE_DIR/ssh_keys_hash"

    if [ ! -f "$keys_file" ]; then
        return
    fi

    local current_hash=$(md5sum "$keys_file" 2>/dev/null | awk '{print $1}')
    local stored_hash=""

    [ -f "$hash_file" ] && stored_hash=$(cat "$hash_file")

    # First run - store hash
    if [ -z "$stored_hash" ]; then
        echo "$current_hash" > "$hash_file"
        return
    fi

    # Check if keys changed
    if [ "$current_hash" != "$stored_hash" ]; then
        echo "$current_hash" > "$hash_file"

        local key_count=$(wc -l < "$keys_file")

        send_alert "SSH Authorized Keys Modified" \
"The SSH authorized_keys file has been modified.

File: $keys_file
Current key count: $key_count

If you did not add a new key, this could indicate:
- Unauthorized access
- Backdoor installation
- Compromised credentials

Review immediately:
cat /root/.ssh/authorized_keys

Recent logins:
$(last -5)" "critical"
    fi
}

# ============================================
# RUN ALL CHECKS
# ============================================
main() {
    check_services
    check_coolify
    check_disk_space
    check_brute_force
    check_oom_kills
    check_ssh_logins
    check_suspicious_processes
    check_ssh_keys
}

main
