#!/bin/bash
# Enterprise Security Alert System
# Sends alerts via Resend API

source /etc/security-alerts/config

send_alert() {
    local subject="$1"
    local body="$2"
    local priority="${3:-normal}"

    # Add priority indicator
    if [ "$priority" = "critical" ]; then
        subject="[CRITICAL] $subject"
    elif [ "$priority" = "warning" ]; then
        subject="[WARNING] $subject"
    fi

    # Build email body with server info
    local full_body="Server: $SERVER_NAME
Time: $(date '+%Y-%m-%d %H:%M:%S %Z')
Priority: $priority

$body

---
This is an automated security alert from your server monitoring system."

    # Send to each recipient
    IFS=',' read -ra EMAILS <<< "$ALERT_EMAILS"
    for email in "${EMAILS[@]}"; do
        curl -s -X POST 'https://api.resend.com/emails' \
            -H "Authorization: Bearer $RESEND_API_KEY" \
            -H 'Content-Type: application/json' \
            -d "{
                \"from\": \"Server Security <$FROM_EMAIL>\",
                \"to\": [\"$email\"],
                \"subject\": \"$subject\",
                \"text\": \"$full_body\"
            }" > /dev/null 2>&1
    done

    # Log the alert
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$priority] $subject" >> /var/log/security-alerts.log
}

# Export function for use by other scripts
export -f send_alert
