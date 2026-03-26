#!/bin/bash
# Enterprise Security Daily Audit Script
# Applied: 2026-03-01

LOG_FILE="/var/log/security-audit.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

echo "========================================" >> $LOG_FILE
echo "Security Audit - $DATE" >> $LOG_FILE
echo "========================================" >> $LOG_FILE

# Check for failed login attempts
echo "" >> $LOG_FILE
echo "--- Failed Login Attempts (Last 24h) ---" >> $LOG_FILE
grep "Failed password" /var/log/auth.log | tail -20 >> $LOG_FILE

# Check fail2ban status
echo "" >> $LOG_FILE
echo "--- Fail2Ban Status ---" >> $LOG_FILE
fail2ban-client status >> $LOG_FILE 2>&1

# Check for currently banned IPs
echo "" >> $LOG_FILE
echo "--- Currently Banned IPs ---" >> $LOG_FILE
fail2ban-client status sshd 2>/dev/null | grep "Banned IP" >> $LOG_FILE

# Check disk usage
echo "" >> $LOG_FILE
echo "--- Disk Usage ---" >> $LOG_FILE
df -h / >> $LOG_FILE

# Check memory/swap usage
echo "" >> $LOG_FILE
echo "--- Memory Usage ---" >> $LOG_FILE
free -h >> $LOG_FILE

# Check Docker container status
echo "" >> $LOG_FILE
echo "--- Docker Containers ---" >> $LOG_FILE
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" >> $LOG_FILE 2>&1

# Check for listening ports
echo "" >> $LOG_FILE
echo "--- Listening Ports ---" >> $LOG_FILE
ss -tlnp | grep LISTEN >> $LOG_FILE

# Check system load
echo "" >> $LOG_FILE
echo "--- System Load ---" >> $LOG_FILE
uptime >> $LOG_FILE

# Check for recent OOM kills
echo "" >> $LOG_FILE
echo "--- OOM Kills (Last 24h) ---" >> $LOG_FILE
dmesg -T 2>/dev/null | grep -i "oom\|killed process" | tail -5 >> $LOG_FILE

echo "" >> $LOG_FILE
echo "Audit complete." >> $LOG_FILE
