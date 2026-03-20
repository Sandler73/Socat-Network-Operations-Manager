# socat_manager.sh — Usage Guide

**Version 2.3.0**

This guide provides complete instructions for installing, configuring, and executing `socat_manager.sh` across three deployment models: direct script execution, system-wide command/utility installation, and isolated virtual environment setup. It covers all operational modes, protocol configurations, and traffic capture capabilities with step-by-step examples.

---

## Table of Contents

- [1. Installation](#1-installation)
  - [1.1 Prerequisites](#11-prerequisites)
  - [1.2 Downloading the Script](#12-downloading-the-script)
  - [1.3 Verifying the Installation](#13-verifying-the-installation)
- [2. Execution Methods](#2-execution-methods)
  - [2.1 Direct Bash Script Execution](#21-direct-bash-script-execution)
  - [2.2 System Command/Utility Installation](#22-system-commandutility-installation)
  - [2.3 Isolated Virtual Environment (venv) Setup](#23-isolated-virtual-environment-venv-setup)
- [3. Mode Reference](#3-mode-reference)
  - [3.1 listen — Single Port Listener](#31-listen--single-port-listener)
  - [3.2 batch — Multi-Port Listeners](#32-batch--multi-port-listeners)
  - [3.3 forward — Port Forwarding](#33-forward--port-forwarding)
  - [3.4 tunnel — Encrypted TLS Tunnel](#34-tunnel--encrypted-tls-tunnel)
  - [3.5 redirect — Traffic Redirection](#35-redirect--traffic-redirection)
  - [3.6 status — Session Status](#36-status--session-status)
  - [3.7 stop — Session Shutdown](#37-stop--session-shutdown)
- [4. Protocol Configuration](#4-protocol-configuration)
  - [4.1 Individual Protocol Selection (--proto)](#41-individual-protocol-selection---proto)
  - [4.2 Dual-Stack Operation (--dual-stack)](#42-dual-stack-operation---dual-stack)
  - [4.3 Protocol Interaction with Modes](#43-protocol-interaction-with-modes)
- [5. Traffic Capture](#5-traffic-capture)
  - [5.1 Enabling Capture](#51-enabling-capture)
  - [5.2 Capture Log Format](#52-capture-log-format)
  - [5.3 Capture with Dual-Stack](#53-capture-with-dual-stack)
  - [5.4 Analyzing Capture Logs](#54-analyzing-capture-logs)
- [6. Session Lifecycle](#6-session-lifecycle)
  - [6.1 Launch and Registration](#61-launch-and-registration)
  - [6.2 Monitoring](#62-monitoring)
  - [6.3 Stopping Sessions](#63-stopping-sessions)
  - [6.4 Cleanup and Maintenance](#64-cleanup-and-maintenance)
- [7. Watchdog Auto-Restart](#7-watchdog-auto-restart)
- [8. Operational Scenarios](#8-operational-scenarios)
  - [8.1 Honeypot Deployment](#81-honeypot-deployment)
  - [8.2 Traffic Interception and Analysis](#82-traffic-interception-and-analysis)
  - [8.3 Encrypted Relay](#83-encrypted-relay)
  - [8.4 DNS Proxy](#84-dns-proxy)
  - [8.5 Multi-Service Lab Environment](#85-multi-service-lab-environment)
- [9. Log Management](#9-log-management)
- [10. Troubleshooting](#10-troubleshooting)

---

## 1. Installation

### 1.1 Prerequisites

#### Required Packages

Install socat and core utilities (most Linux distributions have coreutils pre-installed):

```bash
# Debian/Ubuntu
sudo apt-get update
sudo apt-get install -y socat

# RHEL/CentOS/Fedora
sudo yum install -y socat
# or
sudo dnf install -y socat

# Arch Linux
sudo pacman -S socat
```

#### Optional Packages

These enhance functionality but are not required for core operations:

```bash
# Debian/Ubuntu
sudo apt-get install -y openssl iproute2 net-tools lsof psmisc

# RHEL/CentOS/Fedora
sudo yum install -y openssl iproute net-tools lsof psmisc
```

| Package | Purpose | Required By |
|---------|---------|-------------|
| `openssl` | TLS certificate generation | `tunnel` mode (auto-cert) |
| `iproute2` (provides `ss`) | Port status checking | `status`, `stop` verification |
| `net-tools` (provides `netstat`) | Fallback port checking | `status`, `stop` (if `ss` missing) |
| `lsof` | Fallback process-by-port discovery | `stop` (last-resort fallback) |
| `psmisc` (provides `pstree`) | Process tree display | `status` detail view |

#### System Requirements

- **Linux** kernel 3.x+ with `/proc/sys/kernel/random/uuid`
- **Bash** 4.4+ (verify: `bash --version`)
- **Root/sudo** access for privileged ports (<1024)

Verify bash version:

```bash
bash --version | head -1
# GNU bash, version 5.1.16(1)-release (x86_64-pc-linux-gnu)
```

If bash is below 4.4, update:

```bash
# Debian/Ubuntu
sudo apt-get install -y bash

# Build from source (if package is outdated)
wget https://ftp.gnu.org/gnu/bash/bash-5.2.tar.gz
tar xzf bash-5.2.tar.gz && cd bash-5.2
./configure && make && sudo make install
```

### 1.2 Downloading the Script

```bash
# Option A: Clone from repository (if hosted in Git)
git clone https://github.com/<your-org>/socat-manager.git
cd socat-manager

# Option B: Direct download
curl -O https://<your-host>/socat_manager.sh

# Option C: Copy from local source
cp /path/to/socat_manager.sh ./socat_manager.sh
```

Set executable permission:

```bash
chmod +x socat_manager.sh
```

### 1.3 Verifying the Installation

```bash
# Check version
./socat_manager.sh --version
# socat_manager.sh v2.3.0

# Check help
./socat_manager.sh --help

# Verify socat is available
./socat_manager.sh listen --help
# (should display listen mode help, not a "socat not found" error)

# Check that session/log directories can be created
./socat_manager.sh status
# (should display "No active sessions found" and create sessions/ and logs/ directories)
```

---

## 2. Execution Methods

### 2.1 Direct Bash Script Execution

The simplest method. Run the script directly from its location using `bash` or `./`:

#### From the Script Directory

```bash
cd /path/to/socat-manager/

# Using ./ (requires chmod +x)
./socat_manager.sh listen --port 8080

# Using bash explicitly (does not require chmod +x)
bash socat_manager.sh listen --port 8080

# With sudo for privileged ports
sudo ./socat_manager.sh listen --port 443
sudo bash socat_manager.sh listen --port 443
```

#### From Any Directory (Absolute Path)

```bash
/opt/tools/socat-manager/socat_manager.sh listen --port 8080
sudo /opt/tools/socat-manager/socat_manager.sh redirect --lport 443 --rhost internal.host --rport 8443
```

**Important:** The script creates its runtime directories (`sessions/`, `logs/`, `certs/`, `conf/`) relative to the script's own location, not the current working directory. This means you can run it from anywhere and the runtime data stays alongside the script.

#### Runtime Directory Layout After First Execution

```
/path/to/socat-manager/
├── socat_manager.sh
├── sessions/           # Created automatically (perms: 700)
├── logs/               # Created automatically
├── certs/              # Created automatically
└── conf/               # Created automatically
```

### 2.2 System Command/Utility Installation

Install `socat_manager.sh` as a system-wide command so it can be invoked as `socat-manager` from any directory by any user.

#### Method A: Symlink to /usr/local/bin (Recommended)

This method keeps the script in its project directory and creates a symbolic link in a directory on the system PATH. Updates to the script are immediately available.

```bash
# 1. Place the project in a permanent location
sudo mkdir -p /opt/tools/socat-manager
sudo cp socat_manager.sh /opt/tools/socat-manager/
sudo chmod +x /opt/tools/socat-manager/socat_manager.sh

# 2. Create a symlink in /usr/local/bin (on PATH for all users)
sudo ln -sf /opt/tools/socat-manager/socat_manager.sh /usr/local/bin/socat-manager

# 3. Verify
which socat-manager
# /usr/local/bin/socat-manager

socat-manager --version
# socat_manager.sh v2.3.0

# 4. Use from anywhere
socat-manager listen --port 8080
socat-manager status
socat-manager stop --all
```

**Runtime directories** will be created at `/opt/tools/socat-manager/sessions/`, `/opt/tools/socat-manager/logs/`, etc., since the script resolves its own location via the symlink.

#### Method B: Copy to /usr/local/bin

This places the script itself in `/usr/local/bin`. Simpler, but updates require re-copying.

```bash
# 1. Copy the script
sudo cp socat_manager.sh /usr/local/bin/socat-manager
sudo chmod +x /usr/local/bin/socat-manager

# 2. Verify
socat-manager --version

# 3. Use from anywhere
socat-manager listen --port 8080
```

**Note:** Runtime directories will be created at `/usr/local/bin/sessions/`, `/usr/local/bin/logs/`, etc., which is typically undesirable. Use Method A (symlink) or Method C (wrapper) instead.

#### Method C: Wrapper Script with Custom Runtime Directory

Create a wrapper that sets a custom runtime base directory, keeping runtime data out of system paths:

```bash
# 1. Create runtime directory
sudo mkdir -p /var/lib/socat-manager
sudo chmod 750 /var/lib/socat-manager

# 2. Place the script
sudo mkdir -p /opt/tools/socat-manager
sudo cp socat_manager.sh /opt/tools/socat-manager/
sudo chmod +x /opt/tools/socat-manager/socat_manager.sh

# 3. Create wrapper script
sudo tee /usr/local/bin/socat-manager << 'WRAPPER'
#!/usr/bin/env bash
# Wrapper for socat_manager.sh with custom runtime directory.
# Runtime data (sessions, logs, certs) stored in /var/lib/socat-manager/
# Script source located at /opt/tools/socat-manager/socat_manager.sh

SOCAT_MANAGER_HOME="/opt/tools/socat-manager"
cd "${SOCAT_MANAGER_HOME}" || { echo "Error: Cannot access ${SOCAT_MANAGER_HOME}" >&2; exit 1; }
exec "${SOCAT_MANAGER_HOME}/socat_manager.sh" "$@"
WRAPPER

sudo chmod +x /usr/local/bin/socat-manager

# 4. Verify
socat-manager --version
socat-manager status
```

#### Method D: User-Local Installation (No Root Required)

Install for the current user only using `~/.local/bin`:

```bash
# 1. Ensure ~/.local/bin exists and is on PATH
mkdir -p ~/.local/bin
echo 'export PATH="${HOME}/.local/bin:${PATH}"' >> ~/.bashrc
source ~/.bashrc

# 2. Create project directory
mkdir -p ~/tools/socat-manager
cp socat_manager.sh ~/tools/socat-manager/
chmod +x ~/tools/socat-manager/socat_manager.sh

# 3. Create symlink
ln -sf ~/tools/socat-manager/socat_manager.sh ~/.local/bin/socat-manager

# 4. Verify
socat-manager --version
```

#### Uninstallation

```bash
# Remove symlink or copy
sudo rm -f /usr/local/bin/socat-manager

# Remove project directory (includes all session data and logs)
sudo rm -rf /opt/tools/socat-manager

# Remove runtime data (if using wrapper Method C)
sudo rm -rf /var/lib/socat-manager

# User-local uninstall
rm -f ~/.local/bin/socat-manager
rm -rf ~/tools/socat-manager
```

### 2.3 Isolated Virtual Environment (venv) Setup

A virtual environment provides an isolated, self-contained deployment of `socat_manager.sh` with its own runtime directories, configuration, and logs. This is useful for:

- **Multi-tenant isolation**: Running separate instances for different projects, labs, or engagements
- **Testing and development**: Isolated sandbox that won't affect production sessions
- **Portable deployments**: Self-contained directory that can be archived, moved, or destroyed cleanly
- **Containerized operations**: Pre-staging a socat_manager deployment for Docker or LXC

#### Creating a Virtual Environment

```bash
# 1. Create the venv directory structure
mkdir -p /opt/engagements/project-alpha/socat-env
cd /opt/engagements/project-alpha/socat-env

# 2. Copy the script into the venv
cp /path/to/socat_manager.sh ./socat_manager.sh
chmod +x socat_manager.sh

# 3. Optionally create a port config for this engagement
mkdir -p conf
cat > conf/ports.conf << 'EOF'
# Project Alpha - service simulation ports
8080
8443
9090
9443
EOF

# 4. Create an activation script (similar to Python venv activate)
cat > activate.sh << 'ACTIVATE'
#!/usr/bin/env bash
# =============================================================================
# socat_manager virtual environment activation script
# =============================================================================
# Source this file to set up the isolated socat_manager environment.
# Usage: source activate.sh
#
# This script:
#   1. Sets SOCAT_MANAGER_HOME to this venv directory
#   2. Adds the venv to PATH (socat_manager.sh accessible as 'socat-manager')
#   3. Creates an alias for convenient invocation
#   4. Provides a 'deactivate_socat' function to restore the original environment
#   5. Displays activation confirmation
# =============================================================================

# Resolve the venv directory (where this script lives)
SOCAT_MANAGER_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SOCAT_MANAGER_HOME

# Save original PATH for deactivation
_SOCAT_OLD_PATH="${PATH}"

# Add venv to PATH
export PATH="${SOCAT_MANAGER_HOME}:${PATH}"

# Create convenient alias
alias socat-manager="${SOCAT_MANAGER_HOME}/socat_manager.sh"

# Deactivation function
deactivate_socat() {
    export PATH="${_SOCAT_OLD_PATH}"
    unset SOCAT_MANAGER_HOME
    unset _SOCAT_OLD_PATH
    unalias socat-manager 2>/dev/null
    unset -f deactivate_socat
    echo "[i] socat_manager venv deactivated"
}

# Change to venv directory so runtime dirs are created here
cd "${SOCAT_MANAGER_HOME}"

echo ""
echo "  socat_manager virtual environment activated"
echo "  Home: ${SOCAT_MANAGER_HOME}"
echo "  Run:  socat-manager <MODE> [OPTIONS]"
echo "  Exit: deactivate_socat"
echo ""
ACTIVATE

chmod +x activate.sh

# 5. The venv is ready
echo "Virtual environment created at: $(pwd)"
```

#### Activating the Virtual Environment

```bash
# Activate the venv (must use 'source' to affect current shell)
source /opt/engagements/project-alpha/socat-env/activate.sh

#   socat_manager virtual environment activated
#   Home: /opt/engagements/project-alpha/socat-env
#   Run:  socat-manager <MODE> [OPTIONS]
#   Exit: deactivate_socat
```

#### Using the Virtual Environment

Once activated, use `socat-manager` as a command. All runtime data (sessions, logs, certs) stays within the venv directory:

```bash
# Start listeners from the engagement's port config
socat-manager batch --config conf/ports.conf --capture

# Check sessions
socat-manager status

# Start a redirector
socat-manager redirect --lport 8443 --rhost target.internal --rport 443 --capture

# Check status of specific port
socat-manager status 8443

# Stop a specific session
socat-manager stop a1b2c3d4

# Stop all sessions in this venv
socat-manager stop --all
```

Runtime directory layout within the venv:

```
/opt/engagements/project-alpha/socat-env/
├── socat_manager.sh          # Script
├── activate.sh               # Activation script
├── conf/
│   └── ports.conf            # Engagement-specific port config
├── sessions/                 # Session files for THIS venv only
│   ├── a1b2c3d4.session
│   └── e5f67890.session
├── logs/                     # Logs for THIS venv only
│   ├── socat_manager-2026-03-20T14-30-00.log
│   ├── session-a1b2c3d4-2026-03-20T14-30-00.log
│   └── capture-tcp4-8443-target.internal-443-2026-03-20T14-30-00.log
└── certs/                    # Certs for THIS venv only
    ├── socat-tunnel-2026-03-20T14-30-00.pem
    └── socat-tunnel-2026-03-20T14-30-00.key
```

#### Deactivating the Virtual Environment

```bash
# Deactivate (restores original PATH and removes alias)
deactivate_socat
# [i] socat_manager venv deactivated
```

**Important:** Deactivating the venv does **not** stop running socat sessions. Sessions launched via `setsid` run independently of the shell. To stop sessions before deactivating:

```bash
socat-manager stop --all
deactivate_socat
```

#### Multiple Concurrent Virtual Environments

Each venv is fully independent. You can run multiple venvs simultaneously for different engagements, each with their own sessions, logs, and capture files:

```bash
# Terminal 1: Project Alpha
source /opt/engagements/project-alpha/socat-env/activate.sh
socat-manager listen --port 8080 --capture

# Terminal 2: Project Bravo
source /opt/engagements/project-bravo/socat-env/activate.sh
socat-manager listen --port 9090 --capture

# Each venv's sessions, logs, and captures are completely isolated
```

#### Archiving a Virtual Environment

Archive the entire venv for portability or evidence preservation:

```bash
# Stop all sessions first
source /opt/engagements/project-alpha/socat-env/activate.sh
socat-manager stop --all
deactivate_socat

# Archive (preserving permissions)
cd /opt/engagements/project-alpha
tar czpf socat-env-project-alpha-$(date +%Y%m%d).tar.gz socat-env/

# To restore on another host:
tar xzpf socat-env-project-alpha-20260320.tar.gz
source socat-env/activate.sh
```

#### Destroying a Virtual Environment

```bash
# Stop all sessions
source /opt/engagements/project-alpha/socat-env/activate.sh
socat-manager stop --all
deactivate_socat

# Remove the venv entirely
rm -rf /opt/engagements/project-alpha/socat-env
```

---

## 3. Mode Reference

### 3.1 listen — Single Port Listener

Starts a unidirectional listener that captures incoming data to a log file. Forks per connection for concurrent client handling.

**Synopsis:**

```
socat_manager.sh listen --port <PORT> [--proto <PROTO>] [--dual-stack] [--capture]
                        [--bind <ADDR>] [--name <n>] [--logfile <PATH>]
                        [--watchdog] [--socat-opts <OPTS>] [-v] [-h]
```

**Examples:**

```bash
# Basic TCP listener
socat-manager listen --port 8080

# UDP listener for DNS simulation
socat-manager listen --port 5353 --proto udp4

# Dual-stack with capture on a specific interface
socat-manager listen --port 8080 --dual-stack --capture --bind 192.168.1.100

# IPv6 listener with auto-restart
socat-manager listen --port 8080 --proto tcp6 --watchdog
```

**Data capture file:** `logs/listener-<proto>-<port>.log`
**Traffic capture file** (with `--capture`): `logs/capture-<proto>-<port>-<timestamp>.log`

### 3.2 batch — Multi-Port Listeners

Launches listeners on multiple ports simultaneously. Each port gets its own Session ID.

**Synopsis:**

```
socat_manager.sh batch --ports <LIST> | --range <START-END> | --config <FILE>
                       [--proto <PROTO>] [--dual-stack] [--capture]
                       [--watchdog] [-v] [-h]
```

**Examples:**

```bash
# Common service ports (requires root for <1024)
sudo socat-manager batch --ports "21,22,23,25,80,110,143,443,445,993,995"

# Port range with dual-stack and capture
socat-manager batch --range 8000-8010 --dual-stack --capture

# UDP-only batch
socat-manager batch --ports "5353,5354,5355" --proto udp4

# From config file with watchdog
socat-manager batch --config conf/ports.conf --watchdog --capture
```

**Config file format:**

```
# ports.conf - One port per line. Comments (#) and blank lines ignored.
8080
8443
9090
# 9999  ← commented out, skipped
```

### 3.3 forward — Port Forwarding

Creates a bidirectional port forwarder (full proxy) between a local port and a remote target.

**Synopsis:**

```
socat_manager.sh forward --lport <PORT> --rhost <HOST> --rport <PORT>
                         [--proto <PROTO>] [--remote-proto <PROTO>]
                         [--dual-stack] [--capture] [--logfile <PATH>]
                         [--name <n>] [--watchdog] [-v] [-h]
```

**Examples:**

```bash
# Forward HTTP traffic
socat-manager forward --lport 8080 --rhost 192.168.1.10 --rport 80

# Forward DNS (UDP)
socat-manager forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4

# Cross-protocol: TCP listener → UDP remote
socat-manager forward --lport 8080 --rhost 10.0.0.5 --rport 53 --proto tcp4 --remote-proto udp4

# Dual-stack with capture
socat-manager forward --lport 8080 --rhost 192.168.1.10 --rport 80 --dual-stack --capture
```

### 3.4 tunnel — Encrypted TLS Tunnel

Accepts TLS/SSL connections and forwards plaintext traffic to a remote target. Auto-generates self-signed certificates if not provided.

**Synopsis:**

```
socat_manager.sh tunnel --port <PORT> --rhost <HOST> --rport <PORT>
                        [--cert <PATH>] [--key <PATH>] [--cn <CN>]
                        [--proto <PROTO>] [--dual-stack] [--capture]
                        [--logfile <PATH>] [--name <n>] [--watchdog] [-v] [-h]
```

**Protocol note:** TLS tunnels are TCP-only. `--proto udp4` produces a clear error with guidance. `--dual-stack` adds a plaintext UDP forwarder (with a warning).

**Examples:**

```bash
# Basic tunnel with auto-cert
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22

# With custom certificate
socat-manager tunnel --port 8443 --rhost db.internal --rport 5432 \
    --cert /etc/ssl/cert.pem --key /etc/ssl/key.pem

# Tunnel + plaintext UDP forwarder with capture
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --dual-stack --capture
```

**Connecting to the tunnel from a client:**

```bash
socat - OPENSSL:localhost:4443,verify=0
```

### 3.5 redirect — Traffic Redirection

Bidirectional transparent proxy between a local port and a remote target with optional traffic capture.

**Synopsis:**

```
socat_manager.sh redirect --lport <PORT> --rhost <HOST> --rport <PORT>
                          [--proto <PROTO>] [--dual-stack] [--capture]
                          [--logfile <PATH>] [--name <n>] [--watchdog] [-v] [-h]
```

**Examples:**

```bash
# TCP redirect
socat-manager redirect --lport 8443 --rhost example.com --rport 443

# UDP redirect (DNS proxy)
socat-manager redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4

# Full dual-stack with capture
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --dual-stack --capture
```

### 3.6 status — Session Status

Display all active sessions or detailed information for a specific session.

**Synopsis:**

```
socat_manager.sh status [<SID> | <SESSION_NAME> | <PORT>]
                        [--cleanup] [--verbose] [-h]
```

**Examples:**

```bash
# All sessions overview
socat-manager status

# Detail by Session ID
socat-manager status a1b2c3d4

# Detail by session name
socat-manager status redir-tcp4-8443-example.com-443

# Detail by port (shows all protocols on that port)
socat-manager status 8443

# With system-level listener info (ss output)
socat-manager status --verbose

# Clean up dead session files
socat-manager status --cleanup
```

### 3.7 stop — Session Shutdown

Stop one or more sessions. Protocol-aware: stopping TCP does not affect UDP on the same port.

**Synopsis:**

```
socat_manager.sh stop <SID>
socat_manager.sh stop --all | --name <n> | --port <PORT> | --pid <PID>
```

**Examples:**

```bash
# By Session ID
socat-manager stop a1b2c3d4

# By session name
socat-manager stop --name redir-tcp4-8443-example.com-443

# All sessions on a port (both protocols)
socat-manager stop --port 8443

# By PID
socat-manager stop --pid 12345

# Everything
socat-manager stop --all
```

---

## 4. Protocol Configuration

### 4.1 Individual Protocol Selection (`--proto`)

Available on all operational modes. Default is `tcp4`.

| Value | Protocol | Address Family |
|-------|----------|----------------|
| `tcp` or `tcp4` | TCP | IPv4 |
| `tcp6` | TCP | IPv6 |
| `udp` or `udp4` | UDP | IPv4 |
| `udp6` | UDP | IPv6 |

```bash
# TCP4 (default - these are equivalent)
socat-manager listen --port 8080
socat-manager listen --port 8080 --proto tcp4

# UDP4
socat-manager listen --port 5353 --proto udp4

# TCP6 (IPv6)
socat-manager listen --port 8080 --proto tcp6
```

**Tunnel mode exception:** `--proto` only accepts TCP variants. UDP is rejected with a clear error message and guidance to use `forward --proto udp4` instead.

### 4.2 Dual-Stack Operation (`--dual-stack`)

Launches both TCP and UDP sessions on the same port. Each protocol gets its own Session ID for independent lifecycle management.

```bash
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --dual-stack
# Output:
#   [✓] Redirector active: tcp4:8443 → example.com:443 (SID a1b2c3d4)
#   [✓] Redirector active: udp4:8443 → example.com:443 (SID e5f67890)
```

**Protocol-aware stop:**

```bash
# Stop only TCP (UDP continues running)
socat-manager stop a1b2c3d4

# Stop only UDP (TCP continues running)
socat-manager stop e5f67890

# Stop both (all sessions on port 8443)
socat-manager stop --port 8443
```

### 4.3 Protocol Interaction with Modes

| Mode | `--proto` | `--dual-stack` | Notes |
|------|-----------|----------------|-------|
| listen | tcp4, tcp6, udp4, udp6 | TCP + UDP on same port | Each gets own data log |
| batch | tcp4, tcp6, udp4, udp6 | TCP + UDP per port | Independent session per port/proto |
| forward | tcp4, tcp6, udp4, udp6 | TCP + UDP on same port | `--remote-proto` for cross-protocol |
| tunnel | tcp4 only (udp rejected) | TLS(TCP) + plaintext UDP | UDP is NOT encrypted |
| redirect | tcp4, tcp6, udp4, udp6 | TCP + UDP on same port | Independent capture logs |

---

## 5. Traffic Capture

### 5.1 Enabling Capture

The `--capture` flag is available on **all** operational modes. It enables socat's `-v` (verbose) flag, which produces hex dump output of all traffic on stderr. The launcher redirects this stderr to a per-session capture log file.

```bash
socat-manager listen --port 8080 --capture
socat-manager batch --ports "8080,8443" --capture
socat-manager forward --lport 8080 --rhost 10.0.0.1 --rport 80 --capture
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --capture
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --capture
```

### 5.2 Capture Log Format

Capture logs contain socat's verbose hex dump output. Each data transfer shows direction, byte count, and hex/ASCII representation:

```
> 2026/03/20 14:30:00.123456  length=44 from=0 to=43
 47 45 54 20 2f 20 48 54 54 50 2f 31 2e 31 0d 0a  GET / HTTP/1.1..
 48 6f 73 74 3a 20 65 78 61 6d 70 6c 65 2e 63 6f  Host: example.co
 6d 0d 0a 0d 0a                                     m....
< 2026/03/20 14:30:00.234567  length=283 from=0 to=282
 48 54 54 50 2f 31 2e 31 20 32 30 30 20 4f 4b 0d  HTTP/1.1 200 OK.
 ...
```

`>` indicates data flowing from the client to the remote target. `<` indicates data flowing from the remote target back to the client.

**Capture log paths:**

| Mode | Path |
|------|------|
| listen | `logs/capture-<proto>-<port>-<timestamp>.log` |
| batch | `logs/capture-<proto>-<port>-<timestamp>.log` (per port) |
| forward | `logs/capture-<proto>-<lport>-<rhost>-<rport>-<timestamp>.log` |
| tunnel | `logs/capture-tls-<lport>-<rhost>-<rport>-<timestamp>.log` |
| redirect | `logs/capture-<proto>-<lport>-<rhost>-<rport>-<timestamp>.log` |

### 5.3 Capture with Dual-Stack

When `--capture` and `--dual-stack` are combined, each protocol gets its own capture log:

```bash
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --dual-stack --capture
# Creates:
#   logs/capture-tcp4-8443-example.com-443-2026-03-20T14-30-00.log
#   logs/capture-udp4-8443-example.com-443-2026-03-20T14-30-00.log
```

### 5.4 Analyzing Capture Logs

```bash
# View capture log in real-time
tail -f logs/capture-tcp4-8443-example.com-443-*.log

# Search for specific patterns
grep -i "password\|auth\|cookie" logs/capture-*.log

# Count connections
grep -c "^>" logs/capture-*.log

# Extract just the ASCII representation
awk '/^[<>]/{getline; print}' logs/capture-*.log
```

---

## 6. Session Lifecycle

### 6.1 Launch and Registration

When a session is launched, the following sequence occurs:

1. A unique 8-character hex **Session ID** is generated
2. A **PID staging file** is created (`sessions/<SID>.launching`)
3. The socat process is launched via `setsid bash -c 'echo $$ > pidfile; exec socat ...'`
4. The parent reads the real socat PID from the staging file
5. A **session file** is written (`sessions/<SID>.session`) with full metadata
6. The staging file is removed
7. The script returns to the prompt (non-blocking)

### 6.2 Monitoring

```bash
# Quick overview of all sessions
socat-manager status

# Detailed view of specific session
socat-manager status <SID>

# System-level verification
socat-manager status --verbose

# Direct system checks
ss -tlnp | grep socat        # TCP listeners
ss -ulnp | grep socat        # UDP listeners
ps aux | grep socat           # Process list
```

### 6.3 Stopping Sessions

```bash
# By Session ID (recommended - most precise)
socat-manager stop <SID>

# By session name
socat-manager stop --name <session-name>

# By port (stops all protocols on that port)
socat-manager stop --port <PORT>

# By PID
socat-manager stop --pid <PID>

# All sessions
socat-manager stop --all
```

The stop sequence is protocol-aware and verifies complete shutdown before removing the session file. See the README for the full 9-step stop sequence.

### 6.4 Cleanup and Maintenance

```bash
# Remove session files for dead processes
socat-manager status --cleanup

# Check for orphaned socat processes (reported by stop --all)
socat-manager stop --all

# Manual log rotation (no built-in rotation - use logrotate or manual)
find logs/ -name "*.log" -mtime +30 -delete

# Archive old logs
tar czf logs-archive-$(date +%Y%m%d).tar.gz logs/
rm -f logs/*.log
```

---

## 7. Watchdog Auto-Restart

The `--watchdog` flag enables automatic restart if the socat process crashes unexpectedly:

```bash
socat-manager listen --port 8080 --watchdog
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --watchdog
```

**Behavior:**

| Parameter | Value |
|-----------|-------|
| Initial restart delay | 1 second |
| Backoff pattern | Exponential: 1s, 2s, 4s, 8s, 16s, 32s, 60s |
| Maximum backoff | 60 seconds (capped) |
| Maximum restarts | 10 (default, configurable in source) |
| Graceful stop | Writes `.stop` signal file; watchdog checks between restarts |

**Checking watchdog status:**

The watchdog runs as a monitored subprocess. Check the session error log for restart events:

```bash
cat logs/session-<SID>-error.log
```

---

## 8. Operational Scenarios

### 8.1 Honeypot Deployment

Deploy listeners on common service ports to detect scanning and connection attempts:

```bash
# Deploy honeypot listeners with traffic capture
sudo socat-manager batch --ports "21,22,23,25,80,110,143,443,445,993,995,3389,5900" \
    --dual-stack --capture --watchdog

# Monitor in real-time
tail -f logs/capture-*.log

# Check which ports are receiving connections
ls -la logs/listener-*.log

# Status overview
socat-manager status
```

### 8.2 Traffic Interception and Analysis

Redirect traffic through a capture point for inspection:

```bash
# Redirect HTTPS traffic with capture
socat-manager redirect --lport 8443 --rhost target-server.internal --rport 443 --capture

# Redirect DNS traffic (UDP) with capture
socat-manager redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4 --capture

# Monitor capture logs
tail -f logs/capture-*.log
```

### 8.3 Encrypted Relay

Create a TLS-encrypted relay with traffic capture for analysis:

```bash
# TLS tunnel with decrypted traffic capture
socat-manager tunnel --port 4443 --rhost internal-db.local --rport 5432 --capture

# Connect from client
psql "host=relay-host port=4443 sslmode=verify-full ..."
```

### 8.4 DNS Proxy

Proxy DNS traffic through a local relay for monitoring or redirection:

```bash
# UDP DNS proxy with capture
socat-manager redirect --lport 53 --rhost 8.8.8.8 --rport 53 --proto udp4 --capture

# Or dual-stack (TCP + UDP) for full DNS coverage
sudo socat-manager redirect --lport 53 --rhost 8.8.8.8 --rport 53 --dual-stack --capture
```

### 8.5 Multi-Service Lab Environment

Set up a lab with multiple forwarding services:

```bash
# Web server relay
socat-manager forward --lport 8080 --rhost web-server.lab --rport 80 --capture

# Database relay with TLS
socat-manager tunnel --port 5433 --rhost db-server.lab --rport 5432 --capture

# SSH relay
socat-manager forward --lport 2222 --rhost ssh-server.lab --rport 22

# All running simultaneously with independent session IDs
socat-manager status
```

---

## 9. Log Management

### Log Directory Contents

| File Pattern | Description |
|-------------|-------------|
| `socat_manager-<timestamp>.log` | Master execution log for each script invocation |
| `session-<SID>-<timestamp>.log` | Per-session audit trail |
| `session-<SID>-error.log` | Socat stderr (errors, warnings, watchdog events) |
| `listener-<proto>-<port>.log` | Raw captured data (listen/batch modes) |
| `capture-<proto>-<details>-<timestamp>.log` | Verbose hex dump (when `--capture` enabled) |

### Log Format

Structured format compliant with OWASP Logging Cheat Sheet and NIST SP 800-92:

```
<ISO-8601 Timestamp> [<LEVEL>] [corr:<Correlation-ID>] [<Component>] <Message>
```

Example:

```
2026-03-20T14:30:00.123 [INFO] [corr:a1b2c3d4] [session] Session registered: name=redir-tcp4-8443 pid=12345 pgid=12345 mode=redirect proto=tcp4 port=8443
```

### Retention and Rotation

The script does not implement automatic log rotation. Recommended practices:

```bash
# Delete logs older than 30 days
find logs/ -name "*.log" -mtime +30 -delete

# Archive before deletion
tar czf logs-$(date +%Y%m%d).tar.gz logs/

# Use logrotate (create /etc/logrotate.d/socat-manager)
cat > /etc/logrotate.d/socat-manager << 'EOF'
/opt/tools/socat-manager/logs/*.log {
    weekly
    rotate 12
    compress
    missingok
    notifempty
    create 640 root root
}
EOF
```

---

## 10. Troubleshooting

### "socat is not installed or not in PATH"

Install socat:

```bash
sudo apt-get install -y socat    # Debian/Ubuntu
sudo yum install -y socat        # RHEL/CentOS
```

### "Port <PORT> is already in use"

Another process is bound to the port:

```bash
# Identify what's using the port
ss -tlnp | grep :<PORT>    # TCP
ss -ulnp | grep :<PORT>    # UDP

# If it's a stale socat_manager session
socat-manager status --cleanup
socat-manager status --verbose
```

### Session shows DEAD in status but port is still bound

The socat process was killed externally (not through `socat-manager stop`). Clean up:

```bash
socat-manager status --cleanup
# Then identify and kill the orphaned process
ss -tlnp | grep :<PORT>
kill <PID>
```

### Terminal blocked / script hangs

If using an older version (pre-2.1), upgrade to v2.3.0 which uses the PID-file handoff pattern. This was a bug in v2.0.0 caused by stdout file descriptor inheritance in `$()` subshells.

### Stop falls through to SIGKILL

This is expected behavior when socat child processes don't respond to SIGTERM within the 5-second grace period. The session is still stopped correctly. Verify:

```bash
socat-manager status <SID>    # Should show DEAD or not found
ss -tlnp | grep :<PORT>       # Should show no binding
```

### Capture log is empty

Verify that `--capture` was specified at launch time (it cannot be added to a running session). Check the session detail:

```bash
socat-manager status <SID>
# Look for "Traffic Capture: true" and "Capture Log: <path>"
```

### Dual-stack: stopping TCP kills UDP

Upgrade to v2.2.0+. This was a bug in v2.1.0 where `_stop_session` checked both protocols and `_kill_by_port` killed all socat processes on the port regardless of protocol. v2.2.0+ scopes all port checks and kills to the session's own protocol.

### Permission denied on privileged ports

Ports below 1024 require root/sudo:

```bash
sudo socat-manager listen --port 443
```

### "Neither ss nor netstat available"

Install iproute2 (provides `ss`) or net-tools (provides `netstat`):

```bash
sudo apt-get install -y iproute2
```

Without these tools, port availability checking is skipped with a warning. The session will still launch, but port conflict detection is disabled.
