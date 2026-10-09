#!/bin/bash

################################################################################
# SessionWatch Universal Installer v4.0 (Hardened Auditd Kernel Monitor)
# Notification Options: Discord, Email, Microsoft Teams, Wall (local)
# Compatible with: Debian, Ubuntu, CentOS, RHEL, Rocky Linux, AlmaLinux
################################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "================================================================================"
echo "      SessionWatch Hardened Kernel Security Monitor v4.0 (Auditd)"
echo "           Discord | Email | Teams | Wall Notifications"
echo "================================================================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: Please run as root or with sudo${NC}"
    exit 1
fi

# Detect OS and package manager
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    else
        echo -e "${RED}Cannot detect OS. /etc/os-release not found.${NC}"
        exit 1
    fi
    
    case $OS in
        ubuntu|debian)
            PKG_MANAGER="apt-get"
            PKG_UPDATE="apt-get update"
            PKG_INSTALL="apt-get install -y"
            AUDIT_PKGS="auditd audispd-plugins xxd cron"
            ;;
        centos|rhel|rocky|almalinux|fedora)
            if command -v dnf &> /dev/null; then
                PKG_MANAGER="dnf"
                PKG_UPDATE="dnf check-update || true"
                PKG_INSTALL="dnf install -y"
            else
                PKG_MANAGER="yum"
                PKG_UPDATE="yum check-update || true"
                PKG_INSTALL="yum install -y"
            fi
            AUDIT_PKGS="audit vim-common crontabs"
            ;;
        *)
            echo -e "${RED}Unsupported OS: $OS${NC}"
            exit 1
            ;;
    esac
    
    echo -e "${GREEN}✓ Detected OS: $OS $OS_VERSION${NC}"
    echo -e "${GREEN}✓ Package manager: $PKG_MANAGER${NC}"
    echo ""
}

# Install dependencies
install_dependencies() {
    echo "[1/9] Installing dependencies (auditd, cron, utilities)..."
    
    $PKG_UPDATE > /dev/null 2>&1
    
    if ! command -v jq &> /dev/null; then
        echo "  Installing jq..."
        $PKG_INSTALL jq
    fi
    
    if ! command -v curl &> /dev/null; then
        echo "  Installing curl..."
        $PKG_INSTALL curl
    fi

    echo "  Installing auditd & cron..."
    $PKG_INSTALL $AUDIT_PKGS

    systemctl enable auditd 2>/dev/null || true
    systemctl start auditd 2>/dev/null || service auditd start 2>/dev/null || true
    systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null || true
    systemctl start cron 2>/dev/null || systemctl start crond 2>/dev/null || true

    echo -e "  ${GREEN}✓ All dependencies installed and services active${NC}"
    echo ""
}

# Create directories
create_directories() {
    echo "[2/9] Creating directories..."
    
    mkdir -p /var/log/sessionwatch
    mkdir -p /etc/sessionwatch
    chmod 750 /var/log/sessionwatch
    
    # Remove legacy profile hooks
    rm -f /etc/profile.d/sessionwatch.sh
    
    > /var/log/sessionwatch/alerts.log 2>/dev/null || true
    
    echo -e "${GREEN}✓ Directories prepared${NC}"
    echo ""
}

# Configure auditd rules
configure_auditd_rules() {
    echo "[3/9] Configuring auditd kernel rules..."

    mkdir -p /etc/audit/rules.d/

    cat > /etc/audit/rules.d/sessionwatch.rules << 'EOF'
# SessionWatch Audit Rules - Monitor execve calls for real users (auid >= 1000)
-D
-b 8192

-a always,exit -F arch=b64 -S execve -F auid>=1000 -F auid!=4294967295 -k user_commands
-a always,exit -F arch=b32 -S execve -F auid>=1000 -F auid!=4294967295 -k user_commands
EOF

    chmod 640 /etc/audit/rules.d/sessionwatch.rules

    if command -v augenrules &> /dev/null; then
        augenrules --load || true
    else
        auditctl -R /etc/audit/rules.d/sessionwatch.rules || true
    fi

    echo -e "${GREEN}✓ Auditd kernel monitoring rules loaded${NC}"
    echo ""
}

# Create alert patterns
create_alert_patterns() {
    echo "[4/9] Creating alert patterns (including Logins & Root Escalation)..."
    
    cat > /etc/sessionwatch/alert-patterns.txt << 'EOF'
# ==============================================================================
# SessionWatch Alert Patterns
# ==============================================================================

# --- INFO: System Login Events ---
/sshd
/login
pam_unix

# --- WARNING: Root Privilege Escalation ---
\bsudo\b
\bsu\b
\bdoas\b
\bpkexec\b
\brunuser\b

# --- CRITICAL: Filesystem Destruction ---
rm -rf /
rm -rf /\*
dd if=/dev/zero
mkfs\.
shred

# --- HIGH: System Access & Backdoors ---
/etc/shadow
/etc/passwd
nc -l
nc -e
bash -i
python.*pty\.spawn
socat.*exec

# --- MEDIUM: Suspicious Activity ---
chmod 777
chmod -R 777
wget.*http.*bash
wget.*http.*sh
curl.*\|.*bash
curl.*\|.*sh
/dev/tcp/
iptables -F
ufw disable
systemctl stop firewall
systemctl disable firewall
setenforce 0
history -c
history -w
unset HISTFILE
export HISTFILE=/dev/null
pkill -9
killall -9
python -c
python2 -c
python3 -c
perl -e
ruby -e
php -r
:\(\)\{.*:\|:.*\}
EOF
    
    chmod 644 /etc/sessionwatch/alert-patterns.txt
    echo -e "${GREEN}✓ Alert patterns created${NC}"
    echo ""
}

# Choose notification method
choose_notification_method() {
    echo "[5/9] Choosing notification method..."
    echo ""
    echo "How would you like to receive security alerts?"
    echo "  1) Discord webhook"
    echo "  2) Email (via SMTP)"
    echo "  3) Microsoft Teams webhook"
    echo "  4) Wall (local terminal broadcast to root)"
    echo ""
    echo -n "Enter choice (1-4): "
    read -r NOTIFY_CHOICE
    
    case $NOTIFY_CHOICE in
        1) NOTIFICATION_METHOD="discord" ;;
        2) NOTIFICATION_METHOD="email" ;;
        3) NOTIFICATION_METHOD="teams" ;;
        4) NOTIFICATION_METHOD="wall" ;;
        *) NOTIFICATION_METHOD="wall" ;;
    esac
    echo ""
}

configure_discord() {
    echo "Configuring Discord webhook..."
    echo -n "Enter your Discord Webhook URL: "
    read -r WEBHOOK_URL
    
    if [ -z "$WEBHOOK_URL" ]; then
        echo -e "${RED}ERROR: Webhook URL cannot be empty${NC}"
        exit 1
    fi
    
    cat > /etc/sessionwatch/notification.conf << EOF
NOTIFICATION_METHOD=discord
DISCORD_WEBHOOK=${WEBHOOK_URL}
EOF
    chmod 600 /etc/sessionwatch/notification.conf
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -X POST \
        -d '{"content": "✓ SessionWatch webhook test successful"}' \
        "$WEBHOOK_URL")
    
    if [ "$HTTP_CODE" = "204" ] || [ "$HTTP_CODE" = "200" ]; then
        echo -e "${GREEN}✓ Webhook test successful!${NC}"
    else
        echo -e "${RED}✗ Webhook test failed (HTTP $HTTP_CODE)${NC}"
        exit 1
    fi
}

configure_email() {
    echo "Configuring Email notifications..."
    $PKG_INSTALL esmtp
    
    echo -n "SMTP Server (e.g., smtp.gmail.com): "
    read -r SMTP_SERVER
    echo -n "SMTP Port (e.g. 587): "
    read -r SMTP_PORT
    echo -n "Your email address (from): "
    read -r SMTP_FROM
    echo -n "Alert recipient email (to): "
    read -r SMTP_TO
    echo -n "SMTP Username: "
    read -r SMTP_USER
    echo -n "SMTP Password: "
    read -rs SMTP_PASS
    echo ""
    
    cat > /etc/esmtprc << EOF
identity = "${SMTP_FROM}"
hostname = ${SMTP_SERVER}:${SMTP_PORT}
username = "${SMTP_USER}"
password = "${SMTP_PASS}"
starttls = yes
EOF
    chmod 600 /etc/esmtprc
    
    cat > /etc/sessionwatch/notification.conf << EOF
NOTIFICATION_METHOD=email
SMTP_FROM=${SMTP_FROM}
SMTP_TO=${SMTP_TO}
EOF
    chmod 600 /etc/sessionwatch/notification.conf
}

configure_teams() {
    echo "Configuring Microsoft Teams webhook..."
    echo -n "Enter your Microsoft Teams Webhook URL: "
    read -r WEBHOOK_URL
    
    cat > /etc/sessionwatch/notification.conf << EOF
NOTIFICATION_METHOD=teams
TEAMS_WEBHOOK=${WEBHOOK_URL}
EOF
    chmod 600 /etc/sessionwatch/notification.conf
}

configure_wall() {
    cat > /etc/sessionwatch/notification.conf << EOF
NOTIFICATION_METHOD=wall
EOF
    chmod 600 /etc/sessionwatch/notification.conf
}

configure_notifications() {
    case "$NOTIFICATION_METHOD" in
        discord) configure_discord ;;
        email)   configure_email ;;
        teams)   configure_teams ;;
        wall)    configure_wall ;;
    esac
}

# Create monitoring script
create_monitor_script() {
    echo "[6/9] Creating auditd monitoring script..."
    
    cat > /usr/local/bin/sessionwatch-monitor.sh << 'MONITOR_SCRIPT'
#!/bin/bash

LOG_DIR="/var/log/sessionwatch"
ALERT_PATTERNS="/etc/sessionwatch/alert-patterns.txt"
NOTIFICATION_CONF="/etc/sessionwatch/notification.conf"
AUDIT_LOG="/var/log/audit/audit.log"

if [ ! -f "${NOTIFICATION_CONF}" ]; then
    echo "ERROR: Notification configuration not found!"
    exit 1
fi

source ${NOTIFICATION_CONF}

send_discord_alert() {
    local message="$1" severity="$2" user_info="$3" command="$4"
    case "$severity" in
        "CRITICAL") COLOR="15158332" ;; # Red
        "HIGH")     COLOR="16776960" ;; # Orange
        "WARNING")  COLOR="16705372" ;; # Yellow
        "MEDIUM")   COLOR="16705372" ;; # Yellow
        "INFO")     COLOR="3447003"  ;; # Blue
        *)          COLOR="3447003"  ;;
    esac
    
    TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    HOSTNAME=$(hostname)
    
    COMMAND_JSON=$(echo -n "$command" | jq -Rs . 2>/dev/null || echo '"[encoding error]"')
    USER_JSON=$(echo -n "$user_info" | jq -Rs . 2>/dev/null || echo '"[encoding error]"')
    MESSAGE_JSON=$(echo -n "$message" | jq -Rs . 2>/dev/null || echo '"[encoding error]"')
    
    PAYLOAD=$(jq -n \
        --argjson color "$COLOR" \
        --arg title "🚨 SessionWatch Security Alert" \
        --argjson description "$MESSAGE_JSON" \
        --arg severity "$severity" \
        --arg hostname "$HOSTNAME" \
        --argjson userinfo "$USER_JSON" \
        --argjson command "$COMMAND_JSON" \
        --arg timestamp "$TIMESTAMP" \
        '{
            embeds: [{
                title: $title,
                description: $description,
                color: $color,
                fields: [
                    { name: "⚠️ Severity", value: $severity, inline: true },
                    { name: "🖥️ Server", value: $hostname, inline: true },
                    { name: "👤 User Info", value: $userinfo, inline: false },
                    { name: "💻 Command Executed", value: ("```bash\n" + $command + "\n```"), inline: false }
                ],
                timestamp: $timestamp,
                footer: { text: "SessionWatch v4.0 (Auditd Hardened)" }
            }]
        }' 2>/dev/null)
    
    curl -s -o /dev/null -H "Content-Type: application/json" -X POST -d "$PAYLOAD" "${DISCORD_WEBHOOK}" 2>/dev/null
}

send_email_alert() {
    local message="$1" severity="$2" user_info="$3" command="$4"
    HOSTNAME=$(hostname)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
    
    EMAIL_BODY="SessionWatch Security Alert
================================================================================
Alert Type: ${message}
Severity: ${severity}
Server: ${HOSTNAME}
Timestamp: ${TIMESTAMP}
User Information: ${user_info}
Command Executed: ${command}
================================================================================"

    echo "Subject: [SessionWatch ${severity}] Alert on ${HOSTNAME}
From: ${SMTP_FROM}
To: ${SMTP_TO}

${EMAIL_BODY}" | esmtp -f "${SMTP_FROM}" "${SMTP_TO}" 2>/dev/null
}

send_teams_alert() {
    local message="$1" severity="$2" user_info="$3" command="$4"
    HOSTNAME=$(hostname)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
    
    case "$severity" in
        "CRITICAL") THEME_COLOR="FF0000" ;;
        "HIGH")     THEME_COLOR="FFA500" ;;
        "WARNING")  THEME_COLOR="FFFF00" ;;
        "MEDIUM")   THEME_COLOR="FFFF00" ;;
        "INFO")     THEME_COLOR="0078D4" ;;
        *)          THEME_COLOR="0078D4" ;;
    esac
    
    COMMAND_ESCAPED=$(echo -n "$command" | jq -Rs . 2>/dev/null || echo '"[encoding error]"')
    USER_ESCAPED=$(echo -n "$user_info" | jq -Rs . 2>/dev/null || echo '"[encoding error]"')
    MESSAGE_ESCAPED=$(echo -n "$message" | jq -Rs . 2>/dev/null || echo '"[encoding error]"')
    
    PAYLOAD=$(jq -n \
        --arg color "$THEME_COLOR" \
        --argjson title "\"🚨 SessionWatch Alert\"" \
        --argjson summary "$MESSAGE_ESCAPED" \
        --arg severity "$severity" \
        --arg hostname "$HOSTNAME" \
        --arg timestamp "$TIMESTAMP" \
        --argjson userinfo "$USER_ESCAPED" \
        --argjson command "$COMMAND_ESCAPED" \
        '{
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "themeColor": $color,
            "summary": $summary,
            "sections": [{
                "activityTitle": $title,
                "activitySubtitle": $summary,
                "facts": [
                    { "name": "Severity:", "value": $severity },
                    { "name": "Server:", "value": $hostname },
                    { "name": "Time:", "value": $timestamp },
                    { "name": "User:", "value": $userinfo },
                    { "name": "Command:", "value": $command }
                ],
                "markdown": true
            }]
        }' 2>/dev/null)
    
    curl -s -o /dev/null -H "Content-Type: application/json" -X POST -d "$PAYLOAD" "${TEAMS_WEBHOOK}" 2>/dev/null
}

send_wall_alert() {
    local message="$1" severity="$2" user_info="$3" command="$4"
    HOSTNAME=$(hostname)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    
    WALL_MESSAGE="
╔════════════════════════════════════════════════════════════════════╗
║              🚨 SessionWatch Security Alert                        ║
╠════════════════════════════════════════════════════════════════════╣
║  Severity: ${severity}
║  Server: ${HOSTNAME} | Time: ${TIMESTAMP}
║  User: ${user_info}
║  Command: ${command:0:60}
╚════════════════════════════════════════════════════════════════════╝
"
    echo "$WALL_MESSAGE" | wall 2>/dev/null
}

send_alert() {
    local message="$1" severity="$2" user_info="$3" command="$4"
    echo "[$(date)] [${severity}] ${user_info}: ${command}" >> ${LOG_DIR}/alerts.log
    
    case "$NOTIFICATION_METHOD" in
        discord) send_discord_alert "$message" "$severity" "$user_info" "$command" ;;
        email)   send_email_alert "$message" "$severity" "$user_info" "$command" ;;
        teams)   send_teams_alert "$message" "$severity" "$user_info" "$command" ;;
        wall)    send_wall_alert "$message" "$severity" "$user_info" "$command" ;;
    esac
}

send_alert "SessionWatch monitoring service started (Auditd Kernel Mode)" "INFO" "system@$(hostname)" "systemctl start sessionwatch"

echo "SessionWatch kernel monitoring active."

declare -A USER_MAP

tail -n 0 -F "${AUDIT_LOG}" 2>/dev/null | while read -r line; do
    [ -z "$line" ] && continue
    
    # 1. Map SYSCALL event to user
    if echo "$line" | grep -q 'type=SYSCALL.*key="user_commands"'; then
        EVENT_ID=$(echo "$line" | grep -oP 'msg=audit\([^:]+:\K[0-9]+')
        AUID=$(echo "$line" | grep -oP '\bauid=\K[0-9]+')
        
        if [ -n "$EVENT_ID" ] && [ -n "$AUID" ]; then
            UNAME=$(getent passwd "$AUID" 2>/dev/null | cut -d: -f1)
            [ -z "$UNAME" ] && UNAME="uid:$AUID"
            USER_MAP["$EVENT_ID"]="$UNAME"
        fi

    # 2. Capture EXECVE event and arguments
    elif echo "$line" | grep -q 'type=EXECVE'; then
        EVENT_ID=$(echo "$line" | grep -oP 'msg=audit\([^:]+:\K[0-9]+')
        [ -z "$EVENT_ID" ] && continue
        
        USER_INFO="${USER_MAP[$EVENT_ID]}"
        [ -z "$USER_INFO" ] && continue
        unset USER_MAP["$EVENT_ID"]
        
        RAW_ARGS=$(echo "$line" | grep -oP '\ba[0-9]+=\S+' | sort -V | cut -d= -f2-)
        
        COMMAND=""
        for arg in $RAW_ARGS; do
            if [[ "$arg" =~ ^\"(.*)\"$ ]]; then
                decoded="${BASH_REMATCH[1]}"
            elif [[ "$arg" =~ ^[0-9A-Fa-f]+$ ]]; then
                decoded=$(echo "$arg" | xxd -r -p 2>/dev/null || echo "$arg")
            else
                decoded="$arg"
            fi
            COMMAND="${COMMAND}${decoded} "
        done
        
        COMMAND=$(echo "$COMMAND" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -z "$COMMAND" ] && continue
        
        # Filter internal sessionwatch calls
        case "$COMMAND" in
            *sessionwatch*|*auditctl*|*augenrules*) continue ;;
        esac

        COMMAND_SHORT="${COMMAND:0:80}"
        [ ${#COMMAND} -gt 80 ] && COMMAND_SHORT="${COMMAND_SHORT}..."

        # Match against patterns
        MATCHED=0
        while IFS= read -r pattern; do
            [ -z "$pattern" ] && continue
            [ "${pattern:0:1}" = "#" ] && continue

            if echo "$COMMAND" | grep -qiE "$pattern"; then
                echo "[$(date '+%H:%M:%S')] ⚠️ MATCH! Pattern: $pattern"

                # Categorize Severity
                if echo "$COMMAND" | grep -qE "rm -rf|mkfs|dd if=|shred"; then
                    SEVERITY="CRITICAL"
                    MSG="Critical destruction command detected!"
                elif echo "$COMMAND" | grep -qE "shadow|passwd|nc -|nc -e|bash -i|pty\.spawn"; then
                    SEVERITY="HIGH"
                    MSG="High-risk backdoor or access command detected!"
                elif echo "$COMMAND" | grep -qE "(^|[[:space:]])(sudo|su|doas|pkexec|runuser)($|[[:space:]])"; then
                    SEVERITY="WARNING"
                    MSG="Root privilege escalation attempted/executed!"
                elif echo "$COMMAND" | grep -qE "sshd|login|pam_unix"; then
                    SEVERITY="INFO"
                    MSG="System login activity detected"
                else
                    SEVERITY="MEDIUM"
                    MSG="Suspicious command pattern detected!"
                fi

                send_alert \
                    "$MSG" \
                    "$SEVERITY" \
                    "${USER_INFO}@$(hostname)" \
                    "$COMMAND"

                MATCHED=1
                break
            fi
        done < "${ALERT_PATTERNS}"

        [ $MATCHED -eq 0 ] && echo "[$(date '+%H:%M:%S')] ✓ Command safe"
    fi
done
MONITOR_SCRIPT
    
    chmod +x /usr/local/bin/sessionwatch-monitor.sh
    echo -e "${GREEN}✓ Monitor script created${NC}"
    echo ""
}

# Create Cron Watchdog
create_watchdog_cron() {
    echo "[7/9] Creating Watchdog cron job..."
    
    cat > /etc/cron.d/sessionwatch-watchdog << 'EOF'
* * * * * root /bin/chmod +x /usr/local/bin/sessionwatch-monitor.sh 2>/dev/null; /bin/systemctl is-active --quiet sessionwatch || (/bin/systemctl enable sessionwatch --now 2>/dev/null)
EOF
    chmod 644 /etc/cron.d/sessionwatch-watchdog
    echo -e "${GREEN}✓ Watchdog cron created${NC}"
    echo ""
}

# Create and lock hardened systemd service
create_service() {
    echo "[8/9] Creating hardened systemd service & applying file immutability..."
    
    cat > /etc/systemd/system/sessionwatch.service << 'SERVICE'
[Unit]
Description=SessionWatch Security Monitoring Service (Auditd Kernel Mode)
After=network.target auditd.service
RefuseManualStop=yes

[Service]
Type=simple
ExecStartPre=-/bin/chmod +x /usr/local/bin/sessionwatch-monitor.sh
ExecStart=/usr/local/bin/sessionwatch-monitor.sh
Restart=always
RestartSec=1
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE
    
    systemctl daemon-reload
    systemctl enable sessionwatch
    systemctl start sessionwatch
    
    # Apply immutable flag (+i) to prevent deletion, edit, or chmod -x by root/users
    chattr +i /usr/local/bin/sessionwatch-monitor.sh 2>/dev/null || true
    chattr +i /etc/systemd/system/sessionwatch.service 2>/dev/null || true
    chattr +i /etc/audit/rules.d/sessionwatch.rules 2>/dev/null || true
    chattr +i /etc/cron.d/sessionwatch-watchdog 2>/dev/null || true
    chattr +i /etc/sessionwatch/alert-patterns.txt 2>/dev/null || true
    
    sleep 2
    if systemctl is-active --quiet sessionwatch; then
        echo -e "${GREEN}✓ Hardened service started successfully${NC}"
    else
        echo -e "${RED}✗ Service failed to start${NC}"
        echo "Check logs with: journalctl -u sessionwatch -n 50"
        exit 1
    fi
    echo ""
}

# Create uninstall script
create_uninstall_script() {
    echo "[9/9] Creating uninstaller..."
    cat > /usr/local/bin/uninstall-sessionwatch.sh << 'UNINSTALL_SCRIPT'
#!/bin/bash

if [ "$EUID" -ne 0 ]; then
    echo "ERROR: Please run as root"
    exit 1
fi

echo "================================================================================"
echo "                    SessionWatch Uninstaller"
echo "================================================================================"
echo -n "Are you sure you want to completely uninstall SessionWatch? (yes/NO): "
read -r CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo "Removing file immutability flags (+i)..."
chattr -i /usr/local/bin/sessionwatch-monitor.sh 2>/dev/null || true
chattr -i /etc/systemd/system/sessionwatch.service 2>/dev/null || true
chattr -i /etc/audit/rules.d/sessionwatch.rules 2>/dev/null || true
chattr -i /etc/cron.d/sessionwatch-watchdog 2>/dev/null || true
chattr -i /etc/sessionwatch/alert-patterns.txt 2>/dev/null || true

echo "Removing watchdog cron..."
rm -f /etc/cron.d/sessionwatch-watchdog

echo "Disabling RefuseManualStop to allow service shutdown..."
sed -i '/RefuseManualStop/d' /etc/systemd/system/sessionwatch.service 2>/dev/null || true
systemctl daemon-reload

echo "Stopping service..."
systemctl stop sessionwatch 2>/dev/null || true
systemctl disable sessionwatch 2>/dev/null || true
rm -f /etc/systemd/system/sessionwatch.service
systemctl daemon-reload

echo "Removing auditd rules..."
rm -f /etc/audit/rules.d/sessionwatch.rules
if command -v augenrules &> /dev/null; then
    augenrules --load || true
fi

echo "Removing files and logs..."
rm -f /usr/local/bin/sessionwatch-monitor.sh
rm -f /etc/profile.d/sessionwatch.sh
rm -rf /etc/sessionwatch
rm -rf /var/log/sessionwatch

echo "✓ SessionWatch uninstalled successfully!"
UNINSTALL_SCRIPT

    chmod +x /usr/local/bin/uninstall-sessionwatch.sh
    echo -e "${GREEN}✓ Uninstaller created${NC}"
    echo ""
}

display_summary() {
    echo "================================================================================"
    echo -e "${GREEN}      ✓ SessionWatch Installed & Hardened Successfully!${NC}"
    echo "================================================================================"
    echo ""
    echo "Notification Method: ${NOTIFICATION_METHOD^^}"
    echo "Monitoring Engine:   Linux Kernel Auditd (execve tracking)"
    echo "Anti-Tamper Status:  Active (chattr +i, RefuseManualStop, Cron Watchdog)"
    echo ""
    echo "Configured Alert Severity Levels:"
    echo "  • INFO:    System Logins (sshd, login)"
    echo "  • WARNING: Root Privilege Escalation (sudo, su, doas, pkexec)"
    echo "  • MEDIUM:  Suspicious commands (chmod 777, wget|bash, etc.)"
    echo "  • HIGH:    Backdoors & shadow access"
    echo "  • CRITICAL: Filesystem destruction (rm -rf /, dd, mkfs)"
    echo ""
    echo "How to test:"
    echo "  1. Test Root Escalation (WARNING): sudo whoami"
    echo "  2. Test Critical Alert (CRITICAL): rm -rf /tmp/fake_dir"
    echo ""
    echo "Useful commands:"
    echo "  • Service status:     systemctl status sessionwatch"
    echo "  • Live alerts log:    tail -f /var/log/sessionwatch/alerts.log"
    echo "  • Uninstall:          sudo /usr/local/bin/uninstall-sessionwatch.sh"
    echo ""
    echo "================================================================================"
}

main() {
    detect_os
    install_dependencies
    create_directories
    configure_auditd_rules
    create_alert_patterns
    choose_notification_method
    configure_notifications
    create_monitor_script
    create_watchdog_cron
    create_service
    create_uninstall_script
    display_summary
}

main