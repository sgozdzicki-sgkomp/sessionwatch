# 🛡️ SessionWatch v4.1-1 — Hardened Kernel Security Monitor & Log Shield

**SessionWatch** is a lightweight, real-time security monitoring tool for Linux servers. It operates at the kernel level using `auditd` to capture system command executions (`execve`), evaluating them against customizable security patterns and instantly delivering rich alerts to **Discord, Microsoft Teams, Email, or local terminals (`wall`)**.

Built with an **anti-tamper, self-healing architecture**, SessionWatch is resilient against process termination (`kill -9`), service stops (`systemctl stop`), executable permission stripping (`chmod -x`), **log destruction / DoS attempts against auditd**, and — crucially — **it detects and alerts you when someone tries to tamper with it, with `auditd`, or with the audit log itself**.

---

## 🆕 What's New in v4.1-1 (vs. v4.0 / v4.1)

v4.1-1 is a **maintenance release** addressing three long-standing runtime issues on modern Linux distributions.

### 📧 Fix: msmtp — `account default was already defined` (exit code 78)

The first v4.1-1 email build generated an `/etc/msmtprc` that named the SMTP account `default`:

```
account        default       ← definition of an account called "default"
...
account default : default    ← try to set "default" as the default account
```

`account default : <name>` is msmtp's directive for *selecting* which of the defined accounts is the default. Naming the account itself `default` makes msmtp parse the second line as **a second definition** of the same account and abort with:

```
msmtp: /etc/msmtprc: line 18: account default was already defined
msmtp exit code 78 (EX_CONFIG)
```

**v4.1-1 now names the account `sessionwatch`** and refers to it consistently:

```
account        sessionwatch
...
account default : sessionwatch
```

All `msmtp` invocations (installer test, `send_email_alert()`, documentation) use `msmtp -a sessionwatch`. The summary banner in `setup.sh` also reports the account name for easier debugging.

If you already deployed a broken build, you can either re-run `setup.sh` or patch in place:

```bash
sudo chattr -i /usr/local/bin/sessionwatch-monitor.sh
sudo sed -i 's/^account        default$/account        sessionwatch/' /etc/msmtprc
sudo sed -i 's|^account default : default$|account default : sessionwatch|' /etc/msmtprc
sudo sed -i 's/msmtp -a default/msmtp -a sessionwatch/g' /usr/local/bin/sessionwatch-monitor.sh
sudo chattr +i /usr/local/bin/sessionwatch-monitor.sh
```

### 📧 Fix: Email notifications — automatic TLS mode detection

The initial `msmtp` rollout failed silently on **port 465 (implicit TLS / SMTPS)** because the generated `/etc/msmtprc` only had `tls on`, which in `msmtp` defaults to **STARTTLS** (plaintext first, then upgrade). Servers listening on 465 expect TLS from the first byte and never send a `STARTTLS` capability — the connection dies before `msmtp` even opens the log file. That is why `/var/log/msmtp.log` was missing entirely.

**v4.1-1 auto-detects the TLS mode from the port number:**

| Port | TLS Mode | `tls_starttls` |
| :--- | :--- | :--- |
| `465` | Implicit TLS (SMTPS) | `off` |
| `587`, `25`, `2525` | STARTTLS | `on` |
| anything else | STARTTLS (assumed) | `on` |

Additional improvements:

- **CA bundle auto-detection** — uses `/etc/ssl/certs/ca-certificates.crt` on Debian/Ubuntu and `/etc/pki/tls/certs/ca-bundle.crt` on RHEL/CentOS, with a `tls_trust_file system` fallback.
- **`/var/log/msmtp.log` is pre-created** with mode `640` before the live test, so it always exists for debugging.
- **Live test now shows the real error** — stderr from `msmtp` is captured (previously swallowed by `2>/dev/null`), printed, followed by the last 10 lines of the log and concrete hints (port/TLS mismatch, Gmail App Password, manual test command).
- **Installer no longer aborts on email failure** — it prints a warning and continues, so you can fix `/etc/msmtprc` after install and `systemctl restart sessionwatch`.

### 📧 Fix: Email notifications rewritten for msmtp (vs. `esmtp`)

The original `esmtp`-based delivery silently failed on Gmail, Office365, and most modern SMTP servers because:

- `esmtp` does not correctly negotiate **STARTTLS** with servers that require it.
- It has no built-in TLS certificate validation.
- Errors were swallowed by `2>/dev/null`, making it impossible to debug.

**v4.1-1 uses `msmtp`** — a modern, actively maintained SMTP client with full TLS/STARTTLS support.

- Config: **`/etc/msmtprc`** (mode 600).
- Log: **`/var/log/msmtp.log`** (mode 640).
- `send_email_alert()` uses `msmtp -a sessionwatch <recipient>`.

### 🔧 Fix: `wall` notification rewritten for modern Linux

Debian 13 (Trixie) ships a `wall(1)` that no longer reliably delivers to interactive ptys — it still targets the legacy `utmp` database, which is typically empty on modern systemd hosts. Users selecting **option 4 (Wall)** during install were getting **silent failures**.

`send_wall_alert()` now broadcasts **directly to every writable pty** in `/dev/pts/*`:

```bash
for pts in /dev/pts/[0-9]*; do
    [[ -w "$pts" ]] || continue
    printf '\r\n%s\r\n' "$WALL_MESSAGE" > "$pts" 2>/dev/null || true
done
```

- No dependency on `wall(1)` or `utmp`.
- Works on Debian 13, Ubuntu 24.04+, RHEL 10, and any host with a standard `/dev/pts` mount.
- Silently skips ptys that are not writable.

### 🔁 Backwards Compatibility

- **No breaking changes vs. v4.1.** Drop-in replacement.
- If you are on v4.0 or v4.1, run the uninstaller and reinstall:
  ```bash
  sudo /usr/local/bin/uninstall-sessionwatch.sh   # type "yes"
  git pull && sudo ./setup.sh
  ```

---

## 🆕 What's New in v4.1 (vs. v4.0)

v4.1 was a **hardening + bug-fix release** on top of the v4.0 stable branch. It added an active **Log Shield** layer and fixed a critical escaping bug that broke Discord webhook verification.

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

---

## ✨ Features

- **Kernel-Level Tracking (`auditd`)** — Monitors binary executions (`execve`) directly inside the Linux kernel for all users (`auid >= 1000`). Bypasses shell-level anti-forensics (e.g., `trap - DEBUG`, `HISTFILE=/dev/null`, or switching from `bash` to `zsh`/`python`).
- **Log Shield** — Binary-stream sanitization (`tr -cd`) plus pre-execution CRITICAL alerts on any command that targets the audit log directly (`/dev/random`, `> audit.log`, `truncate audit.log`, `rm audit.log`).
- **Tamper Alerts** — Every attempt to `stop`, `disable`, `mask`, `kill`, or otherwise interfere with **SessionWatch** or **auditd** is detected and sent as a **HIGH** severity alert. Even successful kills trigger a "resurrected" notification on restart.
- **Auditd Lifecycle Monitoring** — `type=DAEMON_START` and `type=DAEMON_END` events in the audit log trigger alerts:
  - `DAEMON_END` → **CRITICAL** (auditd was stopped or crashed)
  - `DAEMON_START` → **HIGH** (auditd started or auto-recovered)
- **Immutable Audit Kernel Lock** — Audit rules are loaded with the `-e 2` flag, which locks the kernel audit configuration until reboot. Even `root` cannot unload or modify audit rules at runtime.
- **Auditd Rotation Limits** — `/etc/audit/auditd.conf` hard-capped at 20 MB × 5 rotations to prevent disk-fill DoS via `/dev/urandom`.
- **Anti-Tamper & Hardening**
  - **File Immutability (`chattr +i`)** — Locks the monitor binary, systemd unit, auditd override, audit rules, `auditd.conf`, cron watchdog, and alert patterns against modification, deletion, or permission changes.
  - **Dual Systemd Stop Protection (`RefuseManualStop=yes`)** — Applied to **both** `sessionwatch.service` **and** `auditd.service` (via drop-in override).
  - **Instant Process Recovery** — Restarts in less than 1 second (`RestartSec=1`) if forcefully killed.
  - **Dual Cron Watchdog** — Every minute: restores `+x` on the monitor binary, re-enables/restarts `auditd` if down, and re-enables/restarts `sessionwatch` if down.
- **Categorized Threat Detection** — Alerts on system logins, privilege escalations, suspicious scripts, backdoors, and destructive commands.
- **Multi-Channel Notifications** — Rich Discord Embeds, Microsoft Teams MessageCards, Formatted SMTP Emails via **msmtp** (auto-detected TLS mode, dedicated `sessionwatch` account), Local Terminal Broadcasts (**direct pty write — no `wall(1)` dependency**).
- **Universal Linux Compatibility** — Automated installation for Debian, Ubuntu, RHEL, CentOS, Rocky Linux, AlmaLinux, and Fedora.

---

## 🚨 Alert Severity Levels

| Severity | Color | Example Triggers & Events |
| :--- | :--- | :--- |
| ℹ️ **INFO** | 🔵 Blue | **System Logins**: `sshd`, `/bin/login`, PAM authentication; **Service start**: SessionWatch daemon started |
| ⚠️ **WARNING** | 🟡 Yellow | **Root Privilege Escalation**: `sudo`, `su`, `doas`, `pkexec`, `runuser` |
| 🟡 **MEDIUM** | 🟡 Yellow | **Suspicious Activity**: `chmod 777`, `wget \| bash`, disabling firewalls, clearing history, inline `python -c` / `perl -e` / `php -r`, fork bombs |
| 🟠 **HIGH** | 🟠 Orange | **Tamper & Backdoors**: `/etc/shadow` access, reverse shells (`nc -e`, `pty.spawn`), **any attempt to stop/kill/mask `sessionwatch` or `auditd`**, process resurrection after `kill -9`, `DAEMON_START` events |
| 🔴 **CRITICAL** | 🔴 Red | **Filesystem Destruction**: `rm -rf /`, `dd if=/dev/zero`, `mkfs`, `shred`; **`auditd` daemon termination** (`DAEMON_END`); **Log tampering / DoS** (`/dev/random`, `/dev/urandom`, `/dev/zero`, `> audit.log`, `truncate audit.log`, `rm audit.log`) |

---

## 🐧 Supported Operating Systems

- **Debian / Ubuntu** (including **Debian 13 "Trixie"** — `wall` fix landed in v4.1-1)
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

1. Detects OS and installs dependencies (`auditd`, `jq`, `curl`, `xxd`, `cron`, and optionally `msmtp` + `msmtp-mta` for email).
2. Creates directories (`/etc/sessionwatch`, `/var/log/sessionwatch`, `/var/log/audit` with `chmod 700`) and removes legacy profile hooks.
3. Configures kernel audit rules (`/etc/audit/rules.d/sessionwatch.rules`) and locks them with **`-e 2`**. Hardens `/etc/audit/auditd.conf` with rotation limits.
4. Hardens the `auditd` systemd unit with a drop-in (`RefuseManualStop=yes`, `Restart=always`, `RestartSec=1`).
5. Deploys threat patterns (`/etc/sessionwatch/alert-patterns.txt`) — including **service tampering** and **log destruction / DoS** patterns.
6. Guides you through notification setup (Discord / Email via msmtp / Teams / Wall) with a **live test that shows the real error**.
7. Deploys the audit parser daemon with **self-healing / resurrection detection**, **auditd lifecycle monitoring**, **binary stream sanitization** (`tr -cd`), and **direct pty broadcast** for Wall.
8. Installs the **dual watchdog cron job** (`/etc/cron.d/sessionwatch-watchdog`).
9. Enables the hardened `sessionwatch.service` and applies **`chattr +i`** to all critical files.
10. Creates the uninstaller at `/usr/local/bin/uninstall-sessionwatch.sh`.

---

## 📧 Email Configuration (msmtp)

When you choose **option 2) Email** during installation, SessionWatch configures `msmtp`, writes `/etc/msmtprc`, and sends a live test email. TLS mode is **auto-detected from the port**.

### How the config is structured

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

> ⚠️ The account is named **`sessionwatch`**, not `default`. Naming it `default` collides with the `account default : <name>` directive and makes msmtp exit with code 78 (`EX_CONFIG`). All calls use `msmtp -a sessionwatch <recipient>`.

### Port → TLS mapping

| Your SMTP port | TLS mode used | Typical provider |
| :--- | :--- | :--- |
| **465** | Implicit TLS (SMTPS) | Many dedicated mail servers, some Office365 setups |
| **587** | STARTTLS | Gmail, Office365, Fastmail, most modern hosts |
| **25 / 2525** | STARTTLS | Internal relays |

### Gmail

1. Enable 2-Step Verification on your Google account.
2. Generate an **App Password** (Google Account → Security → App passwords → "Mail" → "Other").
3. Use the 16-character App Password during install (not your regular Gmail password).
4. SMTP host: `smtp.gmail.com`, Port: `587`.

### Custom SMTP (e.g., `mailhost.example.com:465`)

- Just enter the host and port — the installer picks implicit TLS automatically.
- After install, verify: `cat /etc/msmtprc` should contain `tls_starttls off` and `account sessionwatch`.

### Verify the config

```bash
# Show what the installer generated
cat /etc/msmtprc

# Manual test send (note the -a sessionwatch account selector)
echo -e "Subject: test\r\nFrom: you@example.com\r\nTo: you@example.com\r\n\r\nhello" \
  | msmtp -a sessionwatch you@example.com

# Watch the debug log (all attempts are logged)
tail -f /var/log/msmtp.log
```

### If your server uses a self-signed certificate

Edit `/etc/msmtprc` and replace the `tls_trust_file` line with:

```
tls_trust_file /path/to/your/ca.pem
```

or, as a last resort on trusted internal networks only:

```
tls_trust_file system   # uses system trust store (msmtp ≥ 1.8.20)
# or disable verification entirely:
# tls_trust_file /dev/null
```

Then `systemctl restart sessionwatch`.

### Common msmtp exit codes

| Code | Meaning | Typical cause |
| :--- | :--- | :--- |
| `0` | Success | — |
| `1` | Network / connection error | Wrong host/port, firewall |
| `4` | Authentication failure | Wrong password, Gmail password instead of App Password |
| `77` | TLS error | `tls_starttls` mismatch (465 vs 587), untrusted certificate |
| `78` | Config error (`EX_CONFIG`) | `/etc/msmtprc` syntax problem — e.g. account name collision |

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

- **Kernel Level Monitoring** — `auditd` captures executions at the system call level.
- **Immutable Audit Rules (`-e 2`)** — Once loaded, the kernel rejects any further audit rule changes until reboot.
- **Log Shield** — Audit log stream is sanitized of binary junk (`tr -cd`) and `/var/log/audit` is `chmod 700`.
- **File Immutability** — Key files are locked with `chattr +i`.
- **Dual Service Shielding** — `RefuseManualStop=yes` blocks `systemctl stop` on both `sessionwatch` **and** `auditd`.
- **Self-Healing + Alerts** — If SessionWatch is killed, systemd restarts it in ≤1s and it sends a **HIGH** alert.
- **Dual Cron Watchdog** — Every minute the cron re-asserts `+x` on the monitor binary and verifies both services.

---

## 🧪 Testing Alerts

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

# 6. Test CRITICAL Alert (Log Tampering / DoS)
cat /dev/urandom > /var/log/audit/audit.log
#   → Instant CRITICAL: "Log tampering / DoS attempt detected!"

# 7. Test Wall Notification (Debian 13+)
#   After installing with notification method "4) Wall", run any of the above
#   commands in one terminal and watch a *second* open terminal receive the banner.

# 8. Test Email Notification (msmtp)
echo -e "Subject: test\r\nFrom: you@example.com\r\nTo: you@example.com\r\n\r\nhello" \
  | msmtp -a sessionwatch you@example.com
#   If it fails:
tail -f /var/log/msmtp.log
cat /etc/msmtprc
```

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
| Audit Log Directory (locked) | `/var/log/audit` (chmod 700) |
| msmtp Config | `/etc/msmtprc` (mode 600) |
| msmtp Log | `/var/log/msmtp.log` (mode 640) |
| msmtp Account Name | `sessionwatch` (used with `msmtp -a sessionwatch`) |
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

# Verify auditd rotation settings
grep -E 'max_log_file|num_logs|max_log_file_action|space_left_action|admin_space_left_action' /etc/audit/auditd.conf

# Verify /var/log/audit is locked down
stat -c '%a %n' /var/log/audit   # should show "700 /var/log/audit"

# Check active ptys (Wall notifications)
ls -l /dev/pts/

# Email debug
cat /etc/msmtprc
tail -f /var/log/msmtp.log
msmtp --version
```

---

## 🗑️ Uninstallation

```bash
sudo /usr/local/bin/uninstall-sessionwatch.sh
```

The uninstaller removes `chattr +i`, the watchdog cron, the auditd override, the SessionWatch unit, audit rules, binaries, configs, and logs.

> ⚠️ The kernel audit lock (`-e 2`) persists until the next **reboot**.
>
> ⚠️ The uninstaller does **not** revert `auditd.conf` rotation hardening. If you want pristine defaults, restore it from your distro package (`apt install --reinstall auditd` or `dnf reinstall audit`).

---

## 📜 License

This project is licensed under the **MIT License**.