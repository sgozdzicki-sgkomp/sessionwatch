# 🛡️ SessionWatch v4.0 — Hardened Kernel Security Monitor

**SessionWatch** is a lightweight, real-time security monitoring tool for Linux servers. It operates at the kernel level using `auditd` to capture system command executions (`execve`), evaluating them against customizable security patterns and instantly delivering rich alerts to **Discord, Microsoft Teams, Email, or local terminals (`wall`)**.

Built with an **anti-tamper architecture**, SessionWatch is resilient against process termination (`kill -9`), service stops (`systemctl stop`), and executable permission stripping (`chmod -x`).

---

## ✨ Features

- **Kernel-Level Tracking (`auditd`)** — Monitors binary executions (`execve`) directly inside the Linux kernel for all users (`auid >= 1000`). Bypasses shell-level anti-forensics (e.g., `trap - DEBUG`, `HISTFILE=/dev/null`, or switching from `bash` to `zsh`/`python`).
- **Anti-Tamper & Hardening**
  - **File Immutability (`chattr +i`)** — Locks binaries, configuration files, audit rules, and cron jobs against modification, deletion, or permission changes.
  - **Systemd Stop Protection (`RefuseManualStop=yes`)** — Rejects manual `systemctl stop` requests.
  - **Instant Process Recovery** — Restarts in less than 1 second (`RestartSec=1`) if forcefully killed.
  - **Cron Watchdog** — Automatically restores executable flags and ensures service persistence every minute.
- **Categorized Threat Detection** — Alerts on system logins, privilege escalations, suspicious scripts, backdoors, and destructive commands.
- **Multi-Channel Notifications**
  - Rich Discord Embeds
  - Microsoft Teams MessageCards
  - Formatted SMTP Emails
  - Local Terminal Broadcasts (`wall`)
- **Universal Linux Compatibility** — Automated installation for Debian, Ubuntu, RHEL, CentOS, Rocky Linux, AlmaLinux, and Fedora.

---

## 🚨 Alert Severity Levels

| Severity | Color | Example Triggers & Events |
| :--- | :--- | :--- |
| ℹ️ **INFO** | 🔵 Blue | **System Logins**: `sshd`, `/bin/login`, PAM authentication |
| ⚠️ **WARNING** | 🟡 Yellow | **Root Privilege Escalation**: `sudo`, `su`, `doas`, `pkexec`, `runuser` |
| 🟡 **MEDIUM** | 🟡 Yellow | **Suspicious Activity**: `chmod 777`, `wget \| bash`, disabling firewalls, clearing history |
| 🟠 **HIGH** | 🟠 Orange | **Backdoors & Sensitive Files**: `/etc/shadow` access, reverse shells (`nc -e`, `pty.spawn`) |
| 🔴 **CRITICAL** | 🔴 Red | **Filesystem Destruction**: `rm -rf /`, `dd if=/dev/zero`, `mkfs`, `shred` |

---

## 🐧 Supported Operating Systems

- **Debian / Ubuntu**
- **RHEL / CentOS / Rocky Linux / AlmaLinux / Fedora**

---

## 📦 Installation

Run `setup.sh` as `root` (or via `sudo`) on your server:

```bash
git clone https://github.com/your-username/sessionwatch.git
cd sessionwatch
chmod +x setup.sh
sudo ./setup.sh
```

### What `setup.sh` does automatically

1. Detects OS and installs dependencies (`auditd`, `jq`, `curl`, `xxd`, `cron`, `esmtp`).
2. Configures kernel audit rules (`/etc/audit/rules.d/sessionwatch.rules`).
3. Deploys threat patterns (`/etc/sessionwatch/alert-patterns.txt`).
4. Guides you through notification setup (Discord / Teams / Email / Wall).
5. Deploys the audit parser daemon (`/usr/local/bin/sessionwatch-monitor.sh`).
6. Configures systemd hardened unit and watchdog cron job.
7. Locks key files using `chattr +i`.

---

## 🔒 Anti-Tamper Security Architecture

SessionWatch implements a **4-layer defense mechanism** against local tampering and service evasion:

```
[ User/Attacker Command ]
           │
           ▼
[ Kernel Auditd (execve) ] ──▶ Unbypassable tracking (ignores trap - DEBUG & HISTFILE)
           │
           ▼
[ SessionWatch Daemon ]   ──▶ Locked with chattr +i (prevents chmod -x & rm)
           │
           ▼
[ Systemd Service ]       ──▶ Protected by RefuseManualStop=yes & RestartSec=1
           ▲
           │ (Checks status every 60s)
[ Watchdog Cron Job ]     ──▶ Enforces chmod +x and auto-restarts if disabled
```

- **Kernel Level Monitoring** — `auditd` captures executions at the system call level, meaning users cannot hide commands by clearing shell variables or changing subshells.
- **File Immutability** — Key files are locked with `chattr +i`. Even `root` cannot edit or delete them without explicitly stripping the attribute first.
- **Service Shielding** — `RefuseManualStop=yes` stops users from running `systemctl stop sessionwatch`.
- **Cron Watchdog** — Re-enables the service and restores execution flags if tampered with.

---

## 🧪 Testing Alerts

Once installed, open any shell session and trigger test events:

```bash
# 1. Test WARNING Alert (Root Escalation)
sudo whoami

# 2. Test CRITICAL Alert (Filesystem Hazard Pattern)
rm -rf /tmp/fake_test_directory
```

Check your configured notification channel (Discord / Teams / Email / Terminal) to confirm alert receipt.

---

## ⚙️ File Locations & Commands

### System Paths

| Component | Path |
| :--- | :--- |
| Monitor Binary | `/usr/local/bin/sessionwatch-monitor.sh` |
| Audit Rules | `/etc/audit/rules.d/sessionwatch.rules` |
| Alert Patterns | `/etc/sessionwatch/alert-patterns.txt` |
| Notification Config | `/etc/sessionwatch/notification.conf` |
| Local Alert Log | `/var/log/sessionwatch/alerts.log` |
| Watchdog Cron | `/etc/cron.d/sessionwatch-watchdog` |

### Useful Management Commands

```bash
# Check service status
systemctl status sessionwatch

# View live monitoring logs
journalctl -u sessionwatch -f

# View local alert history
tail -f /var/log/sessionwatch/alerts.log

# Verify active audit rules
auditctl -l
```

---

## 🗑️ Uninstallation

Due to the anti-tamper locks (`chattr +i` and systemd stop protection), standard `systemctl stop` or `rm` commands will fail. Use the included uninstaller script:

```bash
sudo /usr/local/bin/uninstall-sessionwatch.sh
```

The uninstaller safely removes immutable attributes, disables systemd stop protection, cleans up cron jobs and audit rules, and removes all installed binaries.

---

## 📜 License

This project is licensed under the **MIT License**.