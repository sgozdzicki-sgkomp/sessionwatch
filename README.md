# 🛡️ SessionWatch v4.1 — Hardened Kernel Security Monitor & Log Shield

**SessionWatch** is a lightweight, real-time security monitoring tool for Linux servers. It operates at the kernel level using `auditd` to capture system command executions (`execve`), evaluating them against customizable security patterns and instantly delivering rich alerts to **Discord, Microsoft Teams, Email, or local terminals (`wall`)**.

Built with an **anti-tamper, self-healing architecture**, SessionWatch is resilient against process termination (`kill -9`), service stops (`systemctl stop`), executable permission stripping (`chmod -x`), **log destruction / DoS attempts against auditd**, and — crucially — **it detects and alerts you when someone tries to tamper with it, with `auditd`, or with the audit log itself**.

---

## 🆕 What's New in v4.1 (vs. v4.0)

v4.1 is a **hardening + bug-fix release** on top of the v4.0 stable branch. It adds an active **Log Shield** layer and fixes a critical escaping bug that broke Discord webhook verification and could silently disable parts of the monitor parser.

### 🐛 Critical Fixes

- **Fixed `\vert{}` escaping bug** — v4.0 shipped with Markdown/JSON-escaped pipe characters (`\vert{}` instead of `|`, `\vert{}\vert{}` instead of `||`) in several places:
  - `configure_discord()` HTTP test → condition was always false, so a **valid Discord webhook (HTTP 204) was reported as a failure and aborted the installer**.
  - Inside the generated `sessionwatch-monitor.sh` heredoc → the decoded command pipeline (`| xxd`, `| sed`, `| grep`) and the privilege-escalation regex would have failed at runtime.
  - All occurrences replaced with real `|` / `||`. Verified with `grep -n 'vert{}' setup.sh` (should return nothing).

### 🛡️ New: Log Shield (Anti-Tamper for Audit Logs)

- **Binary Stream Sanitization** — `tail -F audit.log` output is now piped through `tr -cd '\11\12\15\40-\176'` before parsing. This strips NUL bytes and other binary junk that could corrupt Bash `read`, desynchronize the SYSCALL ↔ EXECVE event map, or crash the parser when an attacker writes binary garbage into the audit stream.
- **New CRITICAL patterns** targeting log destruction & DoS:
  - `/dev/random`, `/dev/urandom`, `/dev/zero` (log-flooding / entropy drain)
  - `>.*audit\.log`, `>>.*audit\.log`, `truncate.*audit\.log`, `rm.*audit\.log` (truncation / deletion)
- **New severity branch** — Log tampering / DoS is evaluated **first**, before the sessionwatch/auditd tamper branch, and is always escalated to **CRITICAL** with the message `Log tampering / DoS attempt detected!`.

### ⚙️ New: Auditd Rotation & DoS Prevention

`configure_auditd_rules()` now hardens `/etc/audit/auditd.conf` against disk saturation (e.g. attacker spamming `/dev/urandom` into `audit.log`):

| Directive | v4.0 | v4.1 |
| :--- | :--- | :--- |
| `max_log_file` | *(default)* | **`20`** MB |
| `num_logs` | *(default)* | **`5`** |
| `max_log_file_action` | *(default)* | **`ROTATE`** |
| `space_left_action` | *(default)* | **`SYSLOG`** |
| `admin_space_left_action` | *(default)* | **`SUSPEND`** |

### 📁 New: `/var/log/audit` Directory Lock

`create_directories()` now also creates `/var/log/audit` and locks it down:

```bash
mkdir -p /var/log/audit
chmod 700 /var/log/audit
```

### 📊 Updated Installer Summary

The post-install banner now reports a **Log Shield Status** line, e.g.:

```
Notification Method: DISCORD
Monitoring Engine:   Linux Kernel Auditd (execve tracking)
Log Shield Status:   Active (tr -cd sanitization + execve pre-detection)

Log Tampering Protections:
  • Stream Sanitization:  Binary characters (\0, etc.) filtered out instantly
  • Pre-Execution Alert:  Commands using /dev/random or > audit.log trigger CRITICAL
  • Auditd Auto-Rotation: max_log_file = 20MB, ROTATE action enforced
  • Directory Lock:       /var/log/audit restricted to chmod 700
```

### 🔁 Backwards Compatibility

- **No breaking changes.** v4.1 is a drop-in replacement for v4.0.
- If you already installed v4.0 and only want the fixes, re-running `sudo ./setup.sh` from the v4.1 tree is safe — `chattr +i` on the v4.0 files will be re-asserted on the new versions after the installer overwrites them (the installer strips and re-applies immutability internally via the uninstaller-friendly paths).
- To upgrade cleanly:
  ```bash
  sudo /usr/local/bin/uninstall-sessionwatch.sh   # type "yes"
  git pull && sudo ./setup.sh
  ```

---

## ✨ Features

- **Kernel-Level Tracking (`auditd`)** — Monitors binary executions (`execve`) directly inside the Linux kernel for all users (`auid >= 1000`). Bypasses shell-level anti-forensics (e.g., `trap - DEBUG`, `HISTFILE=/dev/null`, or switching from `bash` to `zsh`/`python`).
- **Log Shield (NEW in 4.1)** — Binary-stream sanitization (`tr -cd`) plus pre-execution CRITICAL alerts on any command that targets the audit log directly (`/dev/random`, `> audit.log`, `truncate audit.log`, `rm audit.log`).
- **Tamper Alerts** — Every attempt to `stop`, `disable`, `mask`, `kill`, or otherwise interfere with **SessionWatch** or **auditd** is detected and sent as a **HIGH** severity alert. Even successful kills trigger a "resurrected" notification on restart.
- **Auditd Lifecycle Monitoring** — `type=DAEMON_START` and `type=DAEMON_END` events in the audit log trigger alerts:
  - `DAEMON_END` → **CRITICAL** (auditd was stopped or crashed)
  - `DAEMON_START` → **HIGH** (auditd started or auto-recovered)
- **Immutable Audit Kernel Lock** — Audit rules are loaded with the `-e 2` flag, which locks the kernel audit configuration until reboot. Even `root` cannot unload or modify audit rules at runtime.
- **Auditd Rotation Limits (NEW in 4.1)** — `/etc/audit/auditd.conf` hard-capped at 20 MB × 5 rotations to prevent disk-fill DoS via `/dev/urandom`.
- **Anti-Tamper & Hardening**
  - **File Immutability (`chattr +i`)** — Locks the monitor binary, systemd unit, auditd override, audit rules, `auditd.conf`, cron watchdog, and alert patterns against modification, deletion, or permission changes.
  - **Dual Systemd Stop Protection (`RefuseManualStop=yes`)** — Applied to **both** `sessionwatch.service` **and** `auditd.service` (via drop-in override).
  - **Instant Process Recovery** — Restarts in less than 1 second (`RestartSec=1`) if forcefully killed.
  - **Dual Cron Watchdog** — Every minute: restores `+x` on the monitor binary, re-enables/restarts `auditd` if down, and re-enables/restarts `sessionwatch` if down.
- **Categorized Threat Detection** — Alerts on system logins, privilege escalations, suspicious scripts, backdoors, and destructive commands.
- **Multi-Channel Notifications** — Rich Discord Embeds, Microsoft Teams MessageCards, Formatted SMTP Emails, Local Terminal Broadcasts (`wall`).
- **Universal Linux Compatibility** — Automated installation for Debian, Ubuntu, RHEL, CentOS, Rocky Linux, AlmaLinux, and Fedora.

---

## 🚨 Alert Severity Levels

| Severity | Color | Example Triggers & Events |
| :--- | :--- | :--- |
| ℹ️ **INFO** | 🔵 Blue | **System Logins**: `sshd`, `/bin/login`, PAM authentication; **Service start**: SessionWatch daemon started |
| ⚠️ **WARNING** | 🟡 Yellow | **Root Privilege Escalation**: `sudo`, `su`, `doas`, `pkexec`, `runuser` |
| 🟡 **MEDIUM** | 🟡 Yellow | **Suspicious Activity**: `chmod 777`, `wget \| bash`, disabling firewalls, clearing history, inline `python -c` / `perl -e` / `php -r`, fork bombs |
| 🟠 **HIGH** | 🟠 Orange | **Tamper & Backdoors**: `/etc/shadow` access, reverse shells (`nc -e`, `pty.spawn`), **any attempt to stop/kill/mask `sessionwatch` or `auditd`**, process resurrection after `kill -9`, `DAEMON_START` events |
| 🔴 **CRITICAL** | 🔴 Red | **Filesystem Destruction**: `rm -rf /`, `dd if=/dev/zero`, `mkfs`, `shred`; **`auditd` daemon termination** (`DAEMON_END`); **Log tampering / DoS** (`/dev/random`, `/dev/urandom`, `/dev/zero`, `> audit.log`, `truncate audit.log`, `rm audit.log`) — *new in v4.1* |

---

## 🐧 Supported Operating Systems

- **Debian / Ubuntu**
- **RHEL / CentOS / Rocky Linux / AlmaLinux / Fedora**

---

## 📦 Installation

Run `setup.sh` as `root` (or via `sudo`) on your server:

```bash
git clone https://github.com/sgozdzicki-sgkomp/sessionwatch.git
cd sessionwatch
chmod +x setup.sh
sudo ./setup.sh
```

### What `setup.sh` does automatically

1. Detects OS and installs dependencies (`auditd`, `jq`, `curl`, `xxd`, `cron`, and optionally `esmtp` for email).
2. Creates directories (`/etc/sessionwatch`, `/var/log/sessionwatch`, **`/var/log/audit` with `chmod 700`**) and removes legacy profile hooks.
3. Configures kernel audit rules (`/etc/audit/rules.d/sessionwatch.rules`) and locks them with **`-e 2`** (immutable until reboot). **Hardens `/etc/audit/auditd.conf`** with rotation limits (`max_log_file=20`, `num_logs=5`, `ROTATE`, `SYSLOG`, `SUSPEND`).
4. Hardens the `auditd` systemd unit with a drop-in (`RefuseManualStop=yes`, `Restart=always`, `RestartSec=1`).
5. Deploys threat patterns (`/etc/sessionwatch/alert-patterns.txt`) — including **service tampering** and **log destruction / DoS** patterns.
6. Guides you through notification setup (Discord / Teams / Email / Wall) with a live webhook test.
7. Deploys the audit parser daemon (`/usr/local/bin/sessionwatch-monitor.sh`) with **self-healing / resurrection detection**, **auditd lifecycle monitoring**, and **binary stream sanitization** (`tr -cd`).
8. Installs the **dual watchdog cron job** (`/etc/cron.d/sessionwatch-watchdog`) that keeps both `sessionwatch` and `auditd` alive.
9. Enables the hardened `sessionwatch.service` and applies **`chattr +i`** to all critical files.
10. Creates the uninstaller at `/usr/local/bin/uninstall-sessionwatch.sh`.

---

## 🔒 Anti-Tamper Security Architecture

SessionWatch implements a **multi-layer defense mechanism** against local tampering, log destruction, and service evasion:

```
[ User/Attacker Command ]
           │
           ▼
[ Kernel Auditd (execve) ] ──▶ Unbypassable tracking (ignores trap - DEBUG & HISTFILE)
           │                    Rules locked in-kernel with `-e 2`
           │                    Rotation capped at 20MB × 5 (DoS shield)
           ▼
[ SessionWatch Daemon ]   ──▶ Locked with chattr +i (prevents chmod -x & rm)
           │                    Detects auditd DAEMON_START / DAEMON_END
           │                    Emits "resurrected" alert after kill -9
           │                    Sanitizes binary stream with `tr -cd`
           │                    CRITICAL alerts on log tampering patterns
           ▼
[ Systemd Service ]       ──▶ Protected by RefuseManualStop=yes & RestartSec=1
           ▲                    (applied to BOTH sessionwatch AND auditd)
           │ (Checks status every 60s)
[ Watchdog Cron Job ]     ──▶ Re-chmod +x, restarts sessionwatch or auditd if down
```

- **Kernel Level Monitoring** — `auditd` captures executions at the system call level, meaning users cannot hide commands by clearing shell variables or changing subshells.
- **Immutable Audit Rules (`-e 2`)** — Once loaded, the kernel rejects any further audit rule changes until reboot. An attacker cannot disable or reconfigure auditing at runtime.
- **Log Shield (v4.1)** — Audit log stream is sanitized of binary junk (`tr -cd`) and `/var/log/audit` is `chmod 700`. Attempts to `> audit.log`, `truncate`, `rm`, or flood with `/dev/urandom` trigger CRITICAL alerts and are rate-limited by auditd's own rotation policy.
- **File Immutability** — Key files are locked with `chattr +i`. Even `root` cannot edit or delete them without first stripping the attribute.
- **Dual Service Shielding** — `RefuseManualStop=yes` blocks `systemctl stop` on both `sessionwatch` **and** `auditd`.
- **Self-Healing + Alerts** — If SessionWatch is killed, systemd restarts it in ≤1s and it detects the resurrection on startup (via a state file) and sends a **HIGH** alert.
- **Dual Cron Watchdog** — Every minute the cron re-asserts `+x` on the monitor binary and verifies that both `sessionwatch` and `auditd` are active, restarting them if needed.

---

## 🧪 Testing Alerts

Once installed, open any shell session and trigger test events:

```bash
# 1. Test WARNING Alert (Root Escalation)
sudo whoami

# 2. Test CRITICAL Alert (Filesystem Hazard Pattern)
rm -rf /tmp/fake_test_directory

# 3. Test HIGH Alert (Tamper / Stop Attempt on auditd)
sudo systemctl stop auditd
#   → RefuseManualStop blocks it AND a HIGH alert is sent

# 4. Test HIGH Alert (Process Resurrection)
sudo pkill -9 -f sessionwatch-monitor.sh
#   → systemd restarts it within 1s AND a "resurrected daemon" HIGH alert is sent

# 5. Test CRITICAL Alert (Auditd Lifecycle)
#   Stop auditd forcibly (bypassing systemd) to see a DAEMON_END CRITICAL alert

# 6. Test CRITICAL Alert (Log Tampering / DoS) — NEW in v4.1
cat /dev/urandom > /var/log/audit/audit.log
#   → Instant CRITICAL: "Log tampering / DoS attempt detected!"
#   (Tip: run against a dummy file first to avoid actually corrupting the log)
```

Check your configured notification channel (Discord / Teams / Email / Terminal) to confirm alert receipt.

---

## ⚙️ File Locations & Commands

### System Paths

| Component | Path |
| :--- | :--- |
| Monitor Binary | `/usr/local/bin/sessionwatch-monitor.sh` |
| Uninstaller | `/usr/local/bin/uninstall-sessionwatch.sh` |
| SessionWatch Service | `/etc/systemd/system/sessionwatch.service` |
| Auditd Hardening Override | `/etc/systemd/system/auditd.service.d/override.conf` |
| Audit Rules | `/etc/audit/rules.d/sessionwatch.rules` |
| Auditd Config (locked) | `/etc/audit/auditd.conf` |
| Alert Patterns | `/etc/sessionwatch/alert-patterns.txt` |
| Notification Config | `/etc/sessionwatch/notification.conf` |
| Local Alert Log | `/var/log/sessionwatch/alerts.log` |
| Service State File | `/var/log/sessionwatch/service.state` |
| Audit Log Directory (locked) | `/var/log/audit` (chmod 700) — *new in v4.1* |
| Watchdog Cron | `/etc/cron.d/sessionwatch-watchdog` |

### Files Locked with `chattr +i`

- `/usr/local/bin/sessionwatch-monitor.sh`
- `/etc/systemd/system/sessionwatch.service`
- `/etc/systemd/system/auditd.service.d/override.conf`
- `/etc/audit/rules.d/sessionwatch.rules`
- `/etc/audit/auditd.conf`
- `/etc/cron.d/sessionwatch-watchdog`
- `/etc/sessionwatch/alert-patterns.txt`

### Useful Management Commands

```bash
# Check service status (both)
systemctl status sessionwatch auditd

# View live monitoring logs
journalctl -u sessionwatch -f

# View local alert history
tail -f /var/log/sessionwatch/alerts.log

# Verify active audit rules
auditctl -l

# Verify kernel-level audit lock
auditctl -s | grep enabled   # should show "enabled 2" (immutable)

# Verify file immutability
lsattr /usr/local/bin/sessionwatch-monitor.sh

# Verify auditd rotation settings (v4.1)
grep -E 'max_log_file|num_logs|max_log_file_action|space_left_action|admin_space_left_action' /etc/audit/auditd.conf

# Verify /var/log/audit is locked down (v4.1)
stat -c '%a %n' /var/log/audit   # should show "700 /var/log/audit"
```

---

## 🗑️ Uninstallation

Due to the anti-tamper locks (`chattr +i`, auditd `-e 2` lock, and systemd stop protection), standard `systemctl stop` or `rm` commands will fail. Use the included uninstaller script:

```bash
sudo /usr/local/bin/uninstall-sessionwatch.sh
```

The uninstaller:

1. Removes `chattr +i` from all locked files.
2. Removes the watchdog cron job.
3. Removes the `auditd.service.d` hardening override.
4. Patches out `RefuseManualStop=yes` from the SessionWatch unit and reloads systemd.
5. Stops and disables `sessionwatch.service`.
6. Removes the audit rules.
7. Removes binaries, configs, and logs.

> ⚠️ **Note:** The kernel audit lock (`-e 2`) persists until the next **reboot**. Audit rules remain active until then — this is by design.
>
> ⚠️ **Note (v4.1):** The uninstaller does **not** revert the `auditd.conf` rotation hardening to upstream defaults. If you want a pristine `auditd.conf` back, restore it from your distro package (`apt install --reinstall auditd` or `dnf reinstall audit`).

---

## 📜 License

This project is licensed under the **MIT License**.