# 🛡️ SessionWatch v4.2 — Hardened Kernel Security Monitor & Multi-Channel Alerts

**SessionWatch** is a lightweight, real-time security monitoring tool for Linux servers. It operates at the kernel level using `auditd` to capture system command executions (`execve`), evaluating them against customizable security patterns and instantly delivering rich alerts to **multiple channels at once** — **Discord, Microsoft Teams, Email, and local terminals (`wall`)**.

Built with an **anti-tamper, self-healing architecture**, SessionWatch is resilient against process termination (`kill -9`), service stops (`systemctl stop`), executable permission stripping (`chmod -x`), **log destruction / DoS attempts against auditd**, and — crucially — **it detects and alerts you when someone tries to tamper with it, with `auditd`, or with the audit log itself**.

---

## 🆕 What's New in v4.2 (vs. v4.1-1)

### 📢 Multi-Channel Notifications

You can now notify **any combination** of Discord, Email, Teams and Wall simultaneously. Every alert fans out to all configured channels.

- Installer prompt accepts multiple selections: `1`, `1,3`, `1 3`, `1,2,3,4`, etc.
- New config format in `/etc/sessionwatch/notification.conf`:

  ```ini
  DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
  TEAMS_WEBHOOK="https://..."
  SMTP_FROM="you@example.com"
  SMTP_TO="you@example.com"
  NOTIFICATION_METHODS="discord teams wall"
  ```

- Only the channels listed in `NOTIFICATION_METHODS` are used. Empty channels are silently skipped (e.g., if you enter nothing for the Discord webhook, Discord is dropped from the list).
- The startup banner prints the configured channel list for easy verification.
- `send_alert()` iterates the list and calls each channel's sender with `|| true` so a failing channel never blocks the others.

### 🔁 Backwards Compatibility

The monitor script **still honours the old `NOTIFICATION_METHOD` (singular)** variable:

```bash
if [ -z "${NOTIFICATION_METHODS:-}" ] && [ -n "${NOTIFICATION_METHOD:-}" ]; then
    NOTIFICATION_METHODS="${NOTIFICATION_METHOD}"
fi
```

Any v4.1-1 installation will keep working without reinstalling — but to use multi-channel, run the v4.2 installer.

### ✅ Teams webhook now tested

The installer now performs a live test against the Teams webhook and reports the HTTP status (legacy webhooks often return `200`, newer ones may return `202`). Misconfigurations are visible immediately, not at first alert time.

### 🔧 Carried over from v4.1-1

- **msmtp** replaces `esmtp`; SMTP account named `sessionwatch` (fixes exit code 78).
- **Automatic TLS mode** — port 465 = implicit TLS, 587/25 = STARTTLS.
- **Wall** broadcasts directly to `/dev/pts/*` (fixes Debian 13 silent failure).
- **Discord** webhook test uses real `||` (fixes v4.0 `\vert{}` escaping).

---

## 🆕 What's New in v4.1-1 (vs. v4.0 / v4.1)

### 📧 Email: `msmtp`, automatic TLS mode, `sessionwatch` account

- **Fix: `account default was already defined` (exit 78)** — the account is now named `sessionwatch` instead of `default`. This avoids a collision with msmtp's `account default : <name>` directive. All sends use `msmtp -a sessionwatch <recipient>`.
- **Fix: implicit TLS on port 465** — `tls_starttls` is now set from the port number:

  | Port | TLS mode | `tls_starttls` |
  | :--- | :--- | :--- |
  | `465` | Implicit TLS (SMTPS) | `off` |
  | `587`, `25`, `2525` | STARTTLS | `on` |
  | other | STARTTLS (assumed) | `on` |

- CA bundle auto-detection (`ca-certificates.crt` on Debian, `ca-bundle.crt` on RHEL).
- `/var/log/msmtp.log` is pre-created with mode `640`.
- Live test now prints msmtp's real stderr instead of swallowing it; the installer continues on failure and tells you how to fix it.

### 🔧 Wall: direct pty broadcast

`wall(1)` on Debian 13 / util-linux 2.40+ no longer delivers to interactive ptys reliably (utmp is empty). `send_wall_alert()` now writes directly:

```bash
for pts in /dev/pts/[0-9]*; do
    [[ -w "$pts" ]] || continue
    printf '\r\n%s\r\n' "$WALL_MESSAGE" > "$pts" 2>/dev/null || true
done
```

### 🐛 Discord: `\vert{}` escaping fix

v4.0 shipped Markdown-escaped pipe characters (`\vert{}` instead of `|`) in the `configure_discord()` HTTP test, causing **every valid Discord webhook (HTTP 204) to be reported as a failure and abort the installer**. Same artefact broke the monitor's parser and privilege-escalation regex. All instances now use real `|` / `||`.

---

## 🆕 What's New in v4.1 (vs. v4.0)

v4.1 added the **Log Shield** layer.

- **Binary Stream Sanitization** — `tail -F audit.log` is piped through `tr -cd '\11\12\15\40-\176'` to strip NUL bytes and binary junk before parsing.
- **New CRITICAL log-tampering patterns** — `/dev/random`, `/dev/urandom`, `/dev/zero`, `> audit.log`, `truncate audit.log`, `rm audit.log`. Log tampering is now evaluated **before** the service-tampering branch and is always escalated to **CRITICAL**.
- **Auditd rotation hardening** — `/etc/audit/auditd.conf` gets `max_log_file=20`, `num_logs=5`, `max_log_file_action=ROTATE`, `space_left_action=SYSLOG`, `admin_space_left_action=SUSPEND`.
- **`/var/log/audit`** is now created with `chmod 700`.

---

## ✨ Features

- **Kernel-Level Tracking (`auditd`)** — Monitors `execve` calls inside the kernel for all real users (`auid >= 1000`). Bypasses shell-level anti-forensics (`trap - DEBUG`, `HISTFILE=/dev/null`, shell swaps, etc.).
- **Multi-Channel Alerts** — Send the same alert to Discord, Teams, Email and Wall at once. Each channel is independent — a failing channel never blocks the others.
- **Log Shield** — Binary-stream sanitization (`tr -cd`) plus pre-execution CRITICAL alerts for commands targeting the audit log.
- **Tamper Alerts** — Attempts to `stop`, `disable`, `mask`, `kill`, or otherwise interfere with SessionWatch or auditd are alerted as **HIGH**. Kill-resurrect produces a "resurrected daemon" alert.
- **Auditd Lifecycle Monitoring** — `type=DAEMON_END` → **CRITICAL**; `type=DAEMON_START` → **HIGH**.
- **Immutable Audit Kernel Lock** — Rules loaded with `-e 2` (kernel-level lock until reboot).
- **Auditd Rotation Limits** — 20 MB × 5 rotations cap, prevents `/dev/urandom` disk-fill DoS.
- **Anti-Tamper Hardening** — `chattr +i` on 7 critical files; dual `RefuseManualStop=yes` (sessionwatch + auditd); `RestartSec=1`; dual cron watchdog (re-asserts `+x`, restarts either service if down).
- **Categorized Threat Detection** — INFO / WARNING / MEDIUM / HIGH / CRITICAL with sensible defaults.
- **Universal Linux** — Debian, Ubuntu, RHEL, CentOS, Rocky, AlmaLinux, Fedora.

---

## 🚨 Alert Severity Levels

| Severity | Color | Example Triggers & Events |
| :--- | :--- | :--- |
| ℹ️ **INFO** | 🔵 Blue | System logins (`sshd`, `/bin/login`, PAM); SessionWatch daemon started |
| ⚠️ **WARNING** | 🟡 Yellow | Root privilege escalation: `sudo`, `su`, `doas`, `pkexec`, `runuser` |
| 🟡 **MEDIUM** | 🟡 Yellow | `chmod 777`, `wget \| bash`, disabling firewalls, clearing history, inline `python -c` / `perl -e` / `php -r`, fork bombs |
| 🟠 **HIGH** | 🟠 Orange | `/etc/shadow` access, reverse shells (`nc -e`, `pty.spawn`), tamper attempts on `sessionwatch`/`auditd`, process resurrection, `DAEMON_START` |
| 🔴 **CRITICAL** | 🔴 Red | `rm -rf /`, `dd if=/dev/zero`, `mkfs`, `shred`; `DAEMON_END`; log tampering / DoS (`/dev/random`, `/dev/urandom`, `/dev/zero`, `> audit.log`, `truncate audit.log`, `rm audit.log`) |

---

## 🐧 Supported Operating Systems

- **Debian / Ubuntu** (including **Debian 13 "Trixie"**)
- **RHEL / CentOS / Rocky Linux / AlmaLinux / Fedora**

---

## 📦 Installation

```bash
git clone https://github.com/sgozdzicki-sgkomp/sessionwatch.git
cd sessionwatch
chmod +x setup.sh
sudo ./setup.sh
```

### Installer flow

1. Detects OS, installs `auditd`, `jq`, `curl`, `xxd`, `cron` (and `msmtp`+`msmtp-mta` if Email is chosen).
2. Creates `/etc/sessionwatch`, `/var/log/sessionwatch`, `/var/log/audit` (mode 700).
3. Loads kernel audit rules (`-e 2`), hardens `auditd.conf` rotation, drops in `auditd.service.d/override.conf` (`RefuseManualStop=yes`, `Restart=always`, `RestartSec=1`).
4. Deploys alert patterns.
5. **Asks for notification channels** (multi-select) and configures each.
6. Deploys `/usr/local/bin/sessionwatch-monitor.sh`.
7. Installs `/etc/cron.d/sessionwatch-watchdog`.
8. Starts hardened `sessionwatch.service`, applies `chattr +i` to critical files.
9. Creates `/usr/local/bin/uninstall-sessionwatch.sh`.

### Choosing notification channels

```
How would you like to receive security alerts?
You can select MULTIPLE channels (space- or comma-separated).

  1) Discord webhook
  2) Email (via msmtp)
  3) Microsoft Teams webhook
  4) Wall (broadcast to all active ptys in /dev/pts)

Examples:   1     1,3     1 3     1,2,3,4
Enter choice(s):
```

Each selected channel is configured and live-tested. If a channel is skipped (empty input), it is removed from the list. If all channels are skipped, `wall` is used as a fallback.

---

## 📧 Email Configuration (msmtp)

When **Email** is selected, the installer writes `/etc/msmtprc`, then sends a live test.

### Config structure

```ini
# /etc/msmtprc
defaults
auth           on
tls            on
tls_starttls   off                    # on for 587/STARTTLS, off for 465/SMTPS
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

# SessionWatch SMTP account
account        sessionwatch
host           mailhost.example.com
port           465
from           you@example.com
user           you@example.com
password       ••••••••

# Make sessionwatch the default account
account default : sessionwatch
```

> ⚠️ The account is named **`sessionwatch`**, not `default`. Naming it `default` collides with msmtp's `account default : <name>` directive and makes msmtp exit with code 78 (`EX_CONFIG`). All sends use `msmtp -a sessionwatch <recipient>`.

### Port → TLS mapping

| Your SMTP port | TLS mode | Typical provider |
| :--- | :--- | :--- |
| **465** | Implicit TLS (SMTPS) | Many dedicated mail servers, some Office365 setups |
| **587** | STARTTLS | Gmail, Office365, Fastmail, most modern hosts |
| **25 / 2525** | STARTTLS | Internal relays |

### Gmail

1. Enable 2-Step Verification.
2. Generate an **App Password** (Google Account → Security → App passwords → Mail → Other).
3. Use the 16-character App Password during install.
4. Host: `smtp.gmail.com`, Port: `587`.

### Verify the config

```bash
cat /etc/msmtprc
echo -e "Subject: test\r\nFrom: you@example.com\r\nTo: you@example.com\r\n\r\nhello" \
  | msmtp -a sessionwatch you@example.com
tail -f /var/log/msmtp.log
```

### Common msmtp exit codes

| Code | Meaning | Typical cause |
| :--- | :--- | :--- |
| `0` | Success | — |
| `1` | Network error | Wrong host/port, firewall |
| `4` | Authentication failure | Wrong password, Gmail password instead of App Password |
| `77` | TLS error | `tls_starttls` mismatch (465 vs 587), untrusted cert |
| `78` | Config error (`EX_CONFIG`) | `/etc/msmtprc` syntax problem — e.g., account name collision |

---

## 📄 `notification.conf` — Multi-Channel Format

```ini
# /etc/sessionwatch/notification.conf (mode 600)
DISCORD_WEBHOOK="https://discord.com/api/webhooks/..."
TEAMS_WEBHOOK="https://..."
SMTP_FROM="you@example.com"
SMTP_TO="you@example.com"
NOTIFICATION_METHODS="discord teams wall"
```

The monitor `source`s this file at startup. Only channels in `NOTIFICATION_METHODS` are dispatched. Empty variables are tolerated (the corresponding sender is a no-op).

To change channels later:

```bash
sudo chattr -i /etc/sessionwatch/notification.conf 2>/dev/null || true
sudo nano /etc/sessionwatch/notification.conf
sudo systemctl restart sessionwatch
```

---

## 🔒 Anti-Tamper Architecture

```
[ User/Attacker Command ]
           │
           ▼
[ Kernel Auditd (execve) ] ──▶ Unbypassable (ignores trap - DEBUG & HISTFILE)
           │                    Rules locked with `-e 2`
           │                    Rotation capped at 20MB × 5
           ▼
[ SessionWatch Daemon ]   ──▶ chattr +i (blocks chmod -x & rm)
           │                    DAEMON_START / DAEMON_END detection
           │                    "Resurrected" alert after kill -9
           │                    tr -cd binary stream sanitization
           │                    CRITICAL on log tampering patterns
           ▼
[ Systemd Service ]       ──▶ RefuseManualStop=yes + RestartSec=1
           ▲                    (applies to BOTH sessionwatch AND auditd)
           │ (60s tick)
[ Watchdog Cron ]         ──▶ re-chmod +x; restart either service if down
```

---

## 🧪 Testing Alerts

```bash
# 1. WARNING — root escalation
sudo whoami

# 2. CRITICAL — filesystem hazard pattern
rm -rf /tmp/fake_test_directory

# 3. HIGH — tamper / stop attempt on auditd
sudo systemctl stop auditd
#   → RefuseManualStop blocks it AND a HIGH alert fans out to all channels

# 4. HIGH — process resurrection
sudo pkill -9 -f sessionwatch-monitor.sh
#   → systemd restarts within 1s AND a "resurrected daemon" HIGH alert is sent

# 5. CRITICAL — auditd lifecycle
#   Stop auditd forcibly (bypassing systemd) to see a DAEMON_END CRITICAL alert

# 6. CRITICAL — log tampering / DoS
cat /dev/urandom > /var/log/audit/audit.log
#   → Instant CRITICAL on every configured channel

# 7. Multi-channel verification
#   Watch Discord/Teams/Email/Wall at the same time — all should light up
#   for the same alert within a second.
```

Check each configured channel to confirm receipt. Local alert history is always available:

```bash
tail -f /var/log/sessionwatch/alerts.log
```

---

## ⚙️ File Locations & Commands

| Component | Path |
| :--- | :--- |
| Monitor binary | `/usr/local/bin/sessionwatch-monitor.sh` |
| Uninstaller | `/usr/local/bin/uninstall-sessionwatch.sh` |
| SessionWatch service | `/etc/systemd/system/sessionwatch.service` |
| Auditd hardening override | `/etc/systemd/system/auditd.service.d/override.conf` |
| Audit rules | `/etc/audit/rules.d/sessionwatch.rules` |
| Auditd config (locked) | `/etc/audit/auditd.conf` |
| Alert patterns | `/etc/sessionwatch/alert-patterns.txt` |
| **Notification config (multi-channel)** | `/etc/sessionwatch/notification.conf` |
| Local alert log | `/var/log/sessionwatch/alerts.log` |
| Service state file | `/var/log/sessionwatch/service.state` |
| Audit log directory (locked) | `/var/log/audit` (mode 700) |
| msmtp config | `/etc/msmtprc` (mode 600) |
| msmtp log | `/var/log/msmtp.log` (mode 640) |
| msmtp account name | `sessionwatch` |
| Watchdog cron | `/etc/cron.d/sessionwatch-watchdog` |

### Files locked with `chattr +i`

- `/usr/local/bin/sessionwatch-monitor.sh`
- `/etc/systemd/system/sessionwatch.service`
- `/etc/systemd/system/auditd.service.d/override.conf`
- `/etc/audit/rules.d/sessionwatch.rules`
- `/etc/audit/auditd.conf`
- `/etc/cron.d/sessionwatch-watchdog`
- `/etc/sessionwatch/alert-patterns.txt`

### Useful commands

```bash
# Service status
systemctl status sessionwatch auditd

# Live monitor logs
journalctl -u sessionwatch -f

# Local alert history
tail -f /var/log/sessionwatch/alerts.log

# Show configured channels
cat /etc/sessionwatch/notification.conf

# Verify audit rules
auditctl -l
auditctl -s | grep enabled   # should show "enabled 2"

# Verify immutability
lsattr /usr/local/bin/sessionwatch-monitor.sh

# Verify auditd rotation caps
grep -E 'max_log_file|num_logs|max_log_file_action' /etc/audit/auditd.conf

# Verify audit log dir perms
stat -c '%a %n' /var/log/audit   # 700

# Active ptys (Wall target)
ls -l /dev/pts/

# Email debug
cat /etc/msmtprc
tail -f /var/log/msmtp.log
```

---

## 🔄 Changing Channels After Install

The config is not immutable — only `alert-patterns.txt` and the monitor binary are. Edit safely:

```bash
sudo nano /etc/sessionwatch/notification.conf
# Adjust NOTIFICATION_METHODS and the relevant per-channel values
sudo systemctl restart sessionwatch
```

Example — add Teams to an existing Discord + Wall setup:

```ini
NOTIFICATION_METHODS="discord teams wall"
TEAMS_WEBHOOK="https://outlook.office.com/webhook/..."
```

No reinstall needed.

---

## 🗑️ Uninstallation

```bash
sudo /usr/local/bin/uninstall-sessionwatch.sh
```

The uninstaller strips `chattr +i`, removes the watchdog cron, auditd override, SessionWatch unit, audit rules, binaries, configs and logs.

> ⚠️ The kernel audit lock (`-e 2`) persists until the next **reboot**.
>
> ⚠️ The uninstaller does **not** revert `auditd.conf` rotation hardening. To restore pristine defaults: `apt install --reinstall auditd` (Debian) / `dnf reinstall audit` (RHEL family).

---

## 📜 License

This project is licensed under the **MIT License**.