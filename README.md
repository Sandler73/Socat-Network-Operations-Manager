<p align="center">
  <img src="assets/images/header-socat.png" alt="Socat Network Operations Manager" width="50%" />
</p>

<p align="center">
  <h1 align="center">Socat Network Operations Manager</h1>
  <p align="center">
    <strong>Python Variant</strong><br>
    Production-grade socat session manager for network operations.<br>
    Listeners, bidirectional forwards, TLS tunnels, and transparent redirectors<br>
    with unique Session IDs, protocol-aware lifecycle management, and zero external dependencies.
  </p>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-0.9.0-blue?style=flat-square" alt="Version 0.9.0">
  <img src="https://img.shields.io/badge/python-3.12+-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python 3.12+">
  <img src="https://img.shields.io/badge/platform-linux-FCC624?style=flat-square&logo=linux&logoColor=black" alt="Linux">
  <img src="https://img.shields.io/badge/license-MIT-green?style=flat-square" alt="MIT License">
  <img src="https://img.shields.io/badge/maintained-yes-brightgreen?style=flat-square" alt="Maintained">
  <img src="https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square" alt="PRs Welcome">
  <img src="https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa?style=flat-square" alt="Code of Conduct">
</p>

<p align="center">
  <img src="https://img.shields.io/badge/ruff-passing-7B68EE?style=flat-square&logo=python&logoColor=white" alt="Ruff">
  <img src="https://img.shields.io/badge/pytest-510%20tests-blue?style=flat-square" alt="510 Tests">
  <img src="https://img.shields.io/badge/coverage-68%25-yellow?style=flat-square" alt="Coverage">
  <img src="https://img.shields.io/badge/dependencies-0%20runtime-brightgreen?style=flat-square" alt="Zero Dependencies">
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#operational-modes">Modes</a> ·
  <a href="docs/USAGE_GUIDE.md">Usage Guide</a> ·
  <a href="docs/CHANGELOG.md">Changelog</a> ·
  <a href="docs/SECURITY.md">Security</a> ·
  <a href="#testing">Testing</a> ·
  <a href="#contributing">Contributing</a>
</p>

---

**[Full Documentation Wiki](docs/wiki/)** — detailed guides, architecture with Mermaid diagrams, operational scenarios, and exhaustive developer reference.

---

## Table of Contents

- [Overview](#overview)
- [Key Highlights](#key-highlights)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
  - [Mode Examples](#mode-examples)
- [Operational Modes](#operational-modes)
  - [listen](#listen-mode)
  - [batch](#batch-mode)
  - [forward](#forward-mode)
  - [tunnel](#tunnel-mode)
  - [redirect](#redirect-mode)
  - [status](#status-mode)
  - [stop](#stop-mode)
- [Global Options](#global-options)
- [Session Management](#session-management)
- [Protocol Selection](#protocol-selection)
- [Traffic Capture](#traffic-capture)
- [Watchdog Auto-Restart](#watchdog-auto-restart)
- [Logging](#logging)
- [Directory Structure](#directory-structure)
- [Security Considerations](#security-considerations)
- [Troubleshooting](#troubleshooting)
- [Testing](#testing)
- [Contributing](#contributing)
- [Documentation](#documentation)
- [Version History](#version-history)
- [Acknowledgments](#acknowledgments)
- [License](#license)

---

## Overview

`socat-manager` provides a unified command-line interface and interactive menu for managing socat-based network operations. It wraps socat's complex syntax into seven structured operational modes, adding session tracking, process group isolation, protocol-aware lifecycle management, traffic capture, and automatic restart capabilities.

This is a complete Python 3.12+ reimplementation of [socat_manager.sh](https://github.com/Sandler73/Socat-Network-Operations-Manager) v2.3.0 (4,470 lines of bash, 91 functions) with full functional parity. The Python variant uses only the standard library at runtime — zero external PyPI dependencies.

Every launched socat process receives a unique 8-character hex **Session ID**, is placed in its own **process group** via `os.setsid()`, and is tracked in a persistent `.session` metadata file. This enables reliable status queries and clean shutdowns across terminal sessions and script invocations — you can launch a redirector in one terminal, check its status from another, and stop it from a third.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Key Highlights

| | Feature | Description |
|---|---------|-------------|
| 🔀 | **Seven Operational Modes** | listen, batch, forward, tunnel, redirect — plus status and stop for lifecycle management |
| 🔌 | **Protocol Flexibility** | TCP4, TCP6, UDP4, UDP6 individually (`--proto`) or both TCP+UDP simultaneously (`--dual-stack`) |
| 📡 | **Traffic Capture** | Verbose hex dump logging (`--capture`) on all modes — listen, batch, forward, tunnel, redirect |
| 🔖 | **Session Tracking** | Unique 8-char hex Session IDs with persistent `.session` metadata files |
| 🔒 | **Process Isolation** | Each socat process in its own process group via `os.setsid()` with direct PID access |
| 🛡️ | **Protocol-Aware Stop** | Stopping TCP does not affect UDP on the same port, and vice versa |
| 🖥️ | **Interactive Menu** | Run with no arguments for a guided, menu-driven interface with validation and cancel support |
| ⚡ | **Non-Blocking Launch** | Script returns to prompt immediately — no terminal blocking |
| 🔄 | **Watchdog Auto-Restart** | Monitor-first design with configurable exponential backoff and max restarts |
| 📦 | **Batch Operations** | Launch listeners on port lists, ranges, or config files in a single command |
| 📝 | **Structured Logging** | Dual-output (file + console) with correlation IDs and per-session audit trails |
| 🐍 | **Zero Dependencies** | Python standard library only — no pip packages required at runtime |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Features

### Core Capabilities

- **Seven operational modes**: listen, batch, forward, tunnel, redirect, status, stop
- **Protocol flexibility**: TCP4, TCP6, UDP4, UDP6 individually via `--proto`, or both TCP and UDP simultaneously via `--dual-stack`
- **Traffic capture**: Verbose hex dump logging (`--capture`) available on all operational modes (listen, batch, forward, tunnel, redirect)
- **Session management**: Unique 8-char hex Session IDs with `.session` metadata files for persistent tracking
- **Process group isolation**: Each socat process launched via `os.setsid()` in `subprocess.Popen` for reliable cross-invocation tracking
- **Protocol-aware stop**: Stopping a TCP session does not affect a UDP session on the same port, and vice versa
- **Non-blocking launch**: Script returns to prompt immediately after launching sessions — no terminal blocking
- **Watchdog auto-restart**: Monitor-first design (no duplicate launch), configurable exponential backoff (1s, 2s, 4s... 60s cap), configurable max restarts and initial backoff via `--max-restarts` and `--backoff`
- **Interactive menu**: No-args launches a full-featured menu with guided input, validation, dependency checking, socat-opts examples, configurable watchdog prompts, paired forward after listener, and cancel support at every prompt
- **Batch operations**: Launch listeners on port lists, ranges, or config files in a single command
- **Standalone runner**: `python3 socat-manager.py` — no pip install, no venv, no system modification
- **Cross-variant interoperability**: Session files use the same KEY=VALUE format as the bash variant — both can read each other's session files

### Input Validation and Security

- 9 whitelist-based validators at the trust boundary: ports, hostnames, protocols, file paths, socat options, session names, session IDs, port ranges, port lists
- Command injection prevention: `subprocess.Popen` with argument lists only — `shell=True` never appears in the 6,779-line codebase
- No `eval()`, `exec()`, `compile()`, or `__import__()` anywhere
- Shell metacharacters (`` ; | & $ ` ( ) { } [ ] < > ! # ``) blocked in hostnames and file paths
- Session directory permissions restricted to 0o700
- Session files restricted to 0o600
- Private key files restricted to 0o600
- Capture log files restricted to 0o600
- Only socat processes targeted during port-based fallback kill (process name verification via `/proc/{pid}/comm`)

See [SECURITY.md](docs/SECURITY.md) for the full STRIDE threat model, 7-layer defense-in-depth analysis, and secure deployment guidelines.

### Logging and Audit

- Structured master execution log with correlation IDs
- Per-session log files for independent audit trails
- Traffic capture logs (socat `-v` hex dumps) per session and protocol
- Console output with color-coded severity levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)
- Terminal-aware: ANSI colors gated on TTY detection (`sys.stderr.isatty()`)

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Architecture

### Process Launch Model

```
socat-manager (launcher)
    │
    ├── subprocess.Popen(cmd, preexec_fn=os.setsid, close_fds=True)
    │       │
    │       └── socat (PID == PGID, session leader)
    │               ├── socat fork (child for connection 1)
    │               ├── socat fork (child for connection 2)
    │               └── ...
    │
    ├── Popen.pid gives real socat PID directly
    ├── Registers session: SID, PID, PGID, protocol, port, command
    ├── Returns (sid, pid) tuple to caller
    └── Returns to prompt (non-blocking)
```

**Key design decisions:**

1. **`os.setsid` as `preexec_fn`** creates a new process group. Socat becomes the group leader (PID == PGID), so `os.killpg(pgid, signal)` terminates socat and all its `fork` children in one operation.

2. **Direct PID access via `Popen.pid`**: Unlike the bash variant which requires a PID-file handoff pattern (setsid wrapper PID problem), Python's `Popen.pid` gives the real socat PID directly. No staging files, no polling, no race conditions.

3. **`launch_socat_session()` returns `(sid, pid)` tuple**: The PID is passed to the watchdog for monitoring. This eliminates the critical bug where the watchdog would launch a duplicate socat on an already-bound port.

4. **`close_fds=True`** prevents file descriptor leakage from the management script to the socat process.

5. **`subprocess.Popen` with argument lists only**: The `cmd` parameter is always `list[str]`, never a shell string. `shell=True` is never used.

### Session File Format

```
SESSION_FILE_VERSION=v2.3
SESSION_ID=a1b2c3d4
SESSION_NAME=redir-tcp4-8443-example.com-443
PID=12345
PGID=12345
MODE=redirect
PROTOCOL=tcp4
LOCAL_PORT=8443
REMOTE_HOST=example.com
REMOTE_PORT=443
SOCAT_CMD=socat TCP4-LISTEN:8443,reuseaddr,fork,backlog=128,keepalive TCP4:example.com:443
STARTED=2026-03-30T14:30:00+00:00
CORRELATION=a1b2c3d4
LAUNCHER_PID=9999
```

### Stop Sequence

```
1. Read session metadata (PID, PGID, PROTOCOL, PORT)
2. Signal watchdog via .stop file (tells watchdog: do not restart)
3. SIGTERM entire process group: os.killpg(pgid, SIGTERM)
4. SIGTERM specific PID + children: os.kill(pid, SIGTERM); pkill -TERM -P pid
5. Wait grace period (5 seconds, checking every 0.5s)
6. SIGKILL if still alive: os.killpg + os.kill + pkill -KILL -P
7. Fallback: protocol-scoped port-based kill via ss (socat processes only)
8. Verify port freed (protocol-scoped, avoids cross-protocol interference)
9. Remove session file + .stop + .launching files after confirmed dead
```

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Prerequisites

### Required

| Dependency | Purpose | Install |
|------------|---------|---------|
| **Python** 3.12+ | Framework runtime | Pre-installed on Ubuntu 24.04+; `sudo apt-get install python3` |
| **socat** | Core network operations | `sudo apt-get install -y socat` |

### Optional

| Dependency | Purpose | Install |
|------------|---------|---------|
| **openssl** | TLS certificate generation (tunnel mode) | `sudo apt-get install -y openssl` |
| **ss** (iproute2) | Port status checking, session verification | `sudo apt-get install -y iproute2` |
| **pstree** (psmisc) | Process tree display in `status` detail view | `sudo apt-get install -y psmisc` |
| **flock** (util-linux) | Advisory file locking for session concurrency | Pre-installed on most Linux |

### System Requirements

- Linux kernel (any modern distribution)
- Python 3.12+ (uses `match/case`, `slots=True`, `from __future__ import annotations`)
- Root/sudo for privileged ports (<1024)
- Zero external PyPI packages at runtime (standard library only)

### Compatibility

Designed for the same 8 environments verified by the bash variant's CI pipeline:

| Distribution | Version | Python | Status | Notes |
|-------------|---------|--------|--------|-------|
| **Ubuntu** | 22.04 LTS | 3.12+ | ✅ Expected | May need `python3.12` package |
| **Ubuntu** | 24.04 LTS | 3.12 | ✅ Expected | Python 3.12 pre-installed |
| **Debian** | 12 (Bookworm) | 3.12+ | ✅ Expected | May need `python3.12` package |
| **Kali Linux** | Rolling | 3.12+ | ✅ Expected | socat typically pre-installed |
| **Rocky Linux** | 9 | 3.12+ | ✅ Expected | May need `python3.12` package |
| **AlmaLinux** | 9 | 3.12+ | ✅ Expected | May need `python3.12` package |
| **Arch Linux** | Rolling | 3.12+ | ✅ Expected | Python typically current |

**Also expected to work** on any Linux distribution with Python 3.12+ and socat, including Fedora, openSUSE, Amazon Linux 2023, and Raspberry Pi OS.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Quick Start

```bash
# 1. Install socat
sudo apt-get update && sudo apt-get install -y socat

# 2. Clone or download
git clone https://github.com/Sandler73/Socat-Network-Operations-Manager.git
cd Socat-Network-Operations-Manager

# 3. Run directly (no installation needed)
python3 socat-manager.py

# Or install system-wide:
pip install -e .
socat-manager

# 4. CLI mode:
socat-manager listen --port 8080    # Start a TCP listener
socat-manager status                # Check session status
socat-manager stop --all            # Stop everything
socat-manager help                  # Full help
socat-manager version               # Version info
```

**Interactive menu**: Running with no arguments launches a guided, menu-driven interface with validated input and cancel support (type `q` at any prompt to return to the main menu). Also accessible via `socat-manager menu`.

**Direct CLI**: All commands work exactly as shown — `socat-manager listen --port 8080`, `socat-manager status`, etc. Full CLI reference in the [Usage Guide](docs/USAGE_GUIDE.md).

**Standalone**: Run directly without installing — `python3 socat-manager.py`. No pip, no venv, no system modification.

### Mode Examples

Quick copy-paste examples for each operational mode. See the [Usage Guide](docs/USAGE_GUIDE.md) for complete options, dual-stack configuration, and operational scenarios.

**Listen** — Start a TCP/UDP listener that captures incoming data:

```bash
socat-manager listen --port 8080
socat-manager listen --port 5353 --proto udp4
socat-manager listen --port 8080 --dual-stack --capture
socat-manager listen --port 8080 --watchdog --max-restarts 5 --backoff 2
```

**Batch** — Launch listeners on multiple ports simultaneously:

```bash
socat-manager batch --ports 8080,8081,8082
socat-manager batch --range 9000-9010 --dual-stack
socat-manager batch --file conf/ports.conf --capture --watchdog
```

**Forward** — Relay traffic from a local port to a remote host:

```bash
socat-manager forward --lport 8080 --rhost 10.0.0.5 --rport 80
socat-manager forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4
socat-manager forward --lport 8080 --rhost 10.0.0.1 --rport 53 --remote-proto udp4
```

**Tunnel** — Create a TLS-encrypted tunnel (auto-generates certificates):

```bash
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --cn myhost.local
```

**Redirect** — Transparent port redirection with optional traffic capture:

```bash
socat-manager redirect --lport 8443 --rhost example.com --rport 443
socat-manager redirect --lport 53 --rhost 8.8.8.8 --rport 53 --proto udp4 --dual-stack
```

**Status** — View active sessions and session details:

```bash
socat-manager status
socat-manager status abcd1234     # Detail by session ID
socat-manager status 8080         # Detail by port
socat-manager status --cleanup    # Remove dead session files
```

**Stop** — Terminate sessions by ID, name, port, PID, or all at once:

```bash
socat-manager stop abcd1234
socat-manager stop --all
socat-manager stop --name tcp4-8080
socat-manager stop --port 8080
socat-manager stop --pid 12345
```

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Operational Modes

### listen Mode

Start a single TCP or UDP listener that captures incoming data to a log file.

```bash
# Basic TCP listener
socat-manager listen --port 8080

# UDP listener
socat-manager listen --port 5353 --proto udp4

# TCP + UDP simultaneously
socat-manager listen --port 8080 --dual-stack

# With traffic capture
socat-manager listen --port 8080 --capture

# Bind to specific interface
socat-manager listen --port 8080 --bind 192.168.1.100

# With auto-restart (configurable)
socat-manager listen --port 8080 --watchdog --max-restarts 20 --backoff 2

# With extra socat options
socat-manager listen --port 8080 --socat-opts "reuseaddr,nodelay"
```

**Options:**

| Option | Description |
|--------|-------------|
| `-p, --port <PORT>` | Port number to listen on (required) |
| `--proto <PROTO>` | Protocol: tcp, tcp4, tcp6, udp, udp4, udp6 (default: tcp4) |
| `--dual-stack` | Also start listener on alternate protocol |
| `--capture` | Enable verbose hex dump traffic logging |
| `--bind <ADDR>` | Bind to specific IP address |
| `--name <NAME>` | Custom session name |
| `--logfile <PATH>` | Custom data log file path |
| `--watchdog` | Enable auto-restart on crash |
| `--max-restarts <N>` | Maximum watchdog restart attempts (default: 10) |
| `--backoff <N>` | Initial watchdog backoff delay in seconds (default: 1) |
| `--socat-opts <OPTS>` | Additional socat address options |
| `-v, --verbose` | Enable debug logging |

### batch Mode

Start multiple listeners from port lists, ranges, or config files.

```bash
# Port list
socat-manager batch --ports "21,22,23,25,80,443"

# Port range
socat-manager batch --range 8000-8010

# Port range with dual-stack and capture
socat-manager batch --range 8000-8005 --dual-stack --capture

# UDP-only batch
socat-manager batch --ports "5353,5354,5355" --proto udp4

# From config file
socat-manager batch --file conf/ports.conf --watchdog
```

**Config file format** (`conf/ports.conf`):

```
# One port per line. Comments and blank lines are ignored.
8080
8443
9090
# 9999  ← commented out, skipped
```

**Options:**

| Option | Description |
|--------|-------------|
| `--ports <LIST>` | Comma-separated port list |
| `--range <START-END>` | Port range (max 1000 ports) |
| `--file <FILE>` | Config file (one port per line) |
| `--proto <PROTO>` | Protocol for all listeners (default: tcp4) |
| `--dual-stack` | Start both TCP and UDP per port |
| `--capture` | Enable traffic capture for all listeners |
| `--watchdog` | Enable auto-restart for all listeners |
| `--max-restarts <N>` | Maximum restart attempts per listener |
| `--backoff <N>` | Initial backoff delay in seconds |

### forward Mode

Create a bidirectional port forwarder between a local port and a remote target.

```bash
# TCP forwarder
socat-manager forward --lport 8080 --rhost 192.168.1.10 --rport 80

# UDP forwarder (e.g., DNS relay)
socat-manager forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4

# Dual-stack forwarder
socat-manager forward --lport 8080 --rhost 192.168.1.10 --rport 80 --dual-stack

# With traffic capture
socat-manager forward --lport 8080 --rhost 192.168.1.10 --rport 80 --capture

# Cross-protocol forwarding (TCP listen → UDP remote)
socat-manager forward --lport 8080 --rhost 10.0.0.5 --rport 53 --proto tcp4 --remote-proto udp4
```

**Options:**

| Option | Description |
|--------|-------------|
| `--lport <PORT>` | Local port to listen on (required) |
| `--rhost <HOST>` | Remote host to forward to (required) |
| `--rport <PORT>` | Remote port to forward to (required) |
| `--proto <PROTO>` | Listen protocol (default: tcp4) |
| `--remote-proto <PROTO>` | Remote protocol (default: matches `--proto`). Enables cross-protocol forwarding. |
| `--dual-stack` | Also start forwarder on alternate protocol |
| `--capture` | Enable traffic capture |
| `--name <NAME>` | Custom session name |
| `--watchdog` | Enable auto-restart |
| `--max-restarts <N>` | Maximum restart attempts |
| `--backoff <N>` | Initial backoff delay in seconds |

### tunnel Mode

Create an encrypted TLS/SSL tunnel. Accepts TLS connections on a local port and forwards plaintext traffic to a remote target. Auto-generates self-signed certificates if none provided.

```bash
# Basic tunnel (auto-generates self-signed cert)
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22

# With custom certificate
socat-manager tunnel --port 8443 --rhost db.internal --rport 5432 \
    --cert /etc/ssl/cert.pem --key /etc/ssl/key.pem

# Tunnel with plaintext UDP forwarder on same port
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --dual-stack

# With capture (logs decrypted traffic)
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --capture

# Custom Common Name for self-signed cert
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --cn myhost.local
```

> **Note:** TLS tunnels are TCP-only by design. `--proto udp4` will produce a clear error with guidance to use `forward --proto udp4` instead. `--dual-stack` adds a plaintext UDP forwarder with a warning that UDP traffic is not encrypted.

**Options:**

| Option | Description |
|--------|-------------|
| `-p, --port <PORT>` | Local TLS listen port (required) |
| `--rhost <HOST>` | Remote target host (required) |
| `--rport <PORT>` | Remote target port (required) |
| `--cert <PATH>` | Path to PEM certificate file |
| `--key <PATH>` | Path to PEM private key file |
| `--cn <CN>` | Common Name for self-signed cert (default: localhost) |
| `--dual-stack` | Also start plaintext UDP forwarder on same port |
| `--capture` | Enable capture of decrypted traffic |
| `--name <NAME>` | Custom session name |
| `--watchdog` | Enable auto-restart |

**Connecting to a tunnel:**

```bash
socat - OPENSSL:localhost:4443,verify=0
```

### redirect Mode

Redirect/proxy traffic transparently between a local port and a remote target. Optionally captures bidirectional traffic hex dumps.

```bash
# TCP redirect
socat-manager redirect --lport 8443 --rhost example.com --rport 443

# UDP redirect (e.g., DNS proxy)
socat-manager redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4

# Dual-stack redirect
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --dual-stack

# With traffic capture
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --capture
```

**Options:**

| Option | Description |
|--------|-------------|
| `--lport <PORT>` | Local listen port (required) |
| `--rhost <HOST>` | Remote target host (required) |
| `--rport <PORT>` | Remote target port (required) |
| `--proto <PROTO>` | Protocol: tcp, tcp4, tcp6, udp, udp4, udp6 (default: tcp4) |
| `--dual-stack` | Also start redirector on alternate protocol |
| `--capture` | Enable traffic capture (hex dump) |
| `--name <NAME>` | Custom session name |
| `--watchdog` | Enable auto-restart |

### status Mode

Display all active managed sessions or detailed information for a specific session.

```bash
# List all sessions
socat-manager status

# Detail by Session ID
socat-manager status a1b2c3d4

# Detail by session name
socat-manager status redir-tcp4-8443-example.com-443

# Detail by port (shows all protocols on that port)
socat-manager status 8443

# Include debug output
socat-manager status -v

# Clean up dead session files
socat-manager status --cleanup
```

**Detail view** (when querying by SID, name, or port) shows 5 sections: session metadata, process status with process tree (pstree/ps), port binding status per protocol (ss), socat command string, and associated log file paths.

### stop Mode

Stop one or more sessions by session ID, name, port, PID, or all.

```bash
# Stop by Session ID
socat-manager stop a1b2c3d4

# Stop by session name
socat-manager stop --name redir-tcp4-8443-example.com-443

# Stop all sessions on a port (both protocols if dual-stack)
socat-manager stop --port 8443

# Stop by PID
socat-manager stop --pid 12345

# Stop everything
socat-manager stop --all
```

> **Protocol isolation:** Stopping a TCP session on port 8443 does **not** affect a UDP session on the same port. Each protocol's stop operation is scoped to its own protocol only. The `--port` flag is the exception — it stops all sessions on that port across all protocols.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Global Options

These options are available on all operational modes:

| Option | Description |
|--------|-------------|
| `--proto <PROTOCOL>` | Select protocol: `tcp`, `tcp4`, `tcp6`, `udp`, `udp4`, `udp6`. Default: `tcp4`. Tunnel mode accepts TCP only. |
| `--dual-stack` | Launch sessions on both TCP and UDP simultaneously. Each gets its own Session ID. |
| `--capture` | Enable socat `-v` verbose hex dump traffic logging. Capture log per session/protocol. |
| `--watchdog` | Enable automatic restart with exponential backoff on process crash. |
| `--max-restarts <N>` | Maximum watchdog restart attempts (default: 10). |
| `--backoff <N>` | Initial watchdog backoff delay in seconds (default: 1). Doubles each restart up to 60s cap. |
| `--name <NAME>` | Custom session name (default: auto-generated from mode-proto-port). |
| `-v, --verbose` | Enable DEBUG-level console output. |
| `-h, --help` | Show context-sensitive help (per mode). |
| `--version` | Show version string and exit. |
| `help` | Show full help with examples, session management, protocol guide. |
| `version` | Show version number. |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Session Management

Every socat process launched by `socat-manager` receives:

1. A **unique 8-character hex Session ID** (e.g., `a1b2c3d4`) generated from `uuid.uuid4().hex[:8]` — the first 8 characters of a UUID4 hex string, with collision checking against existing session files (up to 100 attempts).
2. A **`.session` metadata file** in the `sessions/` directory (permissions 0o600) containing PID, PGID, mode, protocol, ports, timestamps, full socat command, correlation ID, and launcher PID.
3. An **isolated process group** via `os.setsid()`, making the socat process its own session leader and group leader. This enables `os.killpg(pgid, signal)` to terminate the entire process tree (parent + all forked children).

Sessions persist across terminal exits and script invocations. The `status` command reads session files to report on all managed processes. The `stop` command uses PID, PGID, and protocol-scoped port verification to ensure complete shutdown.

**Backward compatibility:** Legacy `.pid` session files from v1.x are automatically migrated to the v2.3 `.session` format on startup via `migrate_legacy_sessions()`.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Protocol Selection

### Individual Protocol (`--proto`)

Select a specific protocol for the session:

```bash
socat-manager listen --port 8080 --proto tcp4    # TCP4 (default)
socat-manager listen --port 5353 --proto udp4    # UDP4
socat-manager listen --port 8080 --proto tcp6    # TCP6 (IPv6)
socat-manager listen --port 5353 --proto udp6    # UDP6 (IPv6)
```

### Dual-Stack (`--dual-stack`)

Launch both TCP and UDP on the same port. Each protocol gets its own Session ID:

```bash
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --dual-stack
# Output:
#   [✓] Redirector active: tcp4:8443 → example.com:443 (SID a1b2c3d4)
#   [✓] Redirector active: udp4:8443 → example.com:443 (SID e5f67890)
```

Stop operations are protocol-aware:

```bash
socat-manager stop a1b2c3d4       # Stop only TCP (UDP remains active)
socat-manager stop e5f67890       # Stop only UDP
socat-manager stop --port 8443    # Stop both (all protocols on port)
```

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Traffic Capture

The `--capture` flag enables socat's `-v` (verbose) mode, which produces hex dump output of all traffic on stderr. The launcher redirects this stderr to a per-session capture log file:

```bash
# Capture on any mode
socat-manager listen --port 8080 --capture
socat-manager forward --lport 8080 --rhost 10.0.0.1 --rport 80 --capture
socat-manager tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --capture
socat-manager redirect --lport 8443 --rhost example.com --rport 443 --capture
socat-manager batch --ports "8080,8443" --capture
```

Capture log files are written to: `logs/capture-<proto>-<port>-<timestamp>.log`

For tunnel mode, capture logs contain **decrypted** traffic between the TLS termination point and the remote target.

For dual-stack with capture, each protocol gets its own capture log.

All capture logs are created with 0o600 permissions (owner read/write only).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Watchdog Auto-Restart

The `--watchdog` flag enables automatic restart if the socat process crashes:

```bash
socat-manager listen --port 8080 --watchdog
socat-manager listen --port 8080 --watchdog --max-restarts 20 --backoff 5
```

| Parameter | Default | CLI Flag | Description |
|-----------|---------|----------|-------------|
| Initial restart delay | 1 second | `--backoff` | Configurable initial delay |
| Backoff pattern | Exponential | — | 1s, 2s, 4s, 8s, 16s, 32s, 60s |
| Maximum backoff | 60 seconds | — | Capped |
| Maximum restarts | 10 | `--max-restarts` | Configurable |
| Graceful stop | `.stop` file | — | Watchdog checks between restarts |

**Monitor-first design:** The watchdog receives the PID of the already-running socat process and monitors it via `os.kill(pid, 0)` polling. It does NOT launch its own socat — only re-launches after confirmed process death. This eliminates the duplicate-launch bug class where the watchdog would bind an already-occupied port.

**Interactive menu:** When enabling watchdog in the menu, you're prompted for both max restart attempts and initial backoff delay.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Logging

### Log Types

| Log | Path | Description |
|-----|------|-------------|
| Master execution | `logs/socat-manager-<timestamp>.log` | All operations for this script invocation |
| Session-specific | `logs/session-<sid>.log` | Per-session audit trail |
| Listener data | `logs/listener-<proto>-<port>.log` | Raw incoming data (listen/batch modes) |
| Traffic capture | `logs/capture-<proto>-<port>-<timestamp>.log` | Hex dump traffic (when `--capture` enabled) |

### Log Format

Structured log entries include timestamp, level, correlation ID, component, and message:

```
2026-03-30 14:30:00 [INFO    ] [corr:a1b2c3d4] [session] Session active: PID=12345 PGID=12345
2026-03-30 14:30:01 [INFO    ] [corr:a1b2c3d4] [watchdog] Watchdog started for 'tcp4-8080' [a1b2c3d4] (max 10 restarts, backoff 1s)
```

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Directory Structure

```
socat-manager-python/                # Repository root
├── socat-manager.py                 # Standalone runner (no pip install needed)
├── LICENSE                          # MIT License with supplemental sections
├── Makefile                         # Build, test, install, package (14 targets)
├── pyproject.toml                   # Project metadata and tool configuration
├── .gitignore                       # Git ignore rules
├── src/socat_manager/
│   ├── __init__.py                  # Package version
│   ├── __main__.py                  # Entry point, signal handlers, dispatch
│   ├── cli.py                       # argparse with 10 subcommands
│   ├── menu.py                      # Interactive TUI with paired forward
│   ├── config.py                    # Constants, dataclasses, protocol maps
│   ├── logging_setup.py             # Dual-output structured logging
│   ├── validation.py                # 9 whitelist validators (trust boundary)
│   ├── session.py                   # CRUD, locking, migration, bulk reader
│   ├── commands.py                  # 4 socat command builders
│   ├── process.py                   # Launch (setsid), 9-step stop, port checks
│   ├── watchdog.py                  # Monitor-first auto-restart
│   ├── certs.py                     # TLS self-signed cert generation
│   └── modes/
│       ├── listen.py, batch.py      # Listener modes
│       ├── forward.py               # Bidirectional relay
│       ├── tunnel.py                # TLS-encrypted tunnel
│       ├── redirect.py              # Transparent redirection
│       ├── status.py                # Session status display
│       └── stop.py                  # Session termination
├── tests/
│   ├── conftest.py                  # Shared fixtures
│   ├── unit/                        # 355 unit tests (12 files)
│   ├── integration/                 # 155 integration tests (6 files)
│   └── stubs/                       # Mock socat, ss, openssl binaries
├── docs/
│   ├── README.md                    # Documentation index
│   ├── USAGE_GUIDE.md               # Full usage reference
│   ├── SETUP_GUIDE.md               # Installation and configuration
│   ├── SECURITY.md                  # STRIDE threat model, 7-layer defense
│   ├── CONTRIBUTING.md              # Contribution guidelines
│   ├── CHANGELOG.md                 # Version history
│   ├── CODE_OF_CONDUCT.md           # Community standards
│   ├── TROUBLESHOOTING.md           # Common issues and solutions
│   ├── Frequently_Asked_Questions_(FAQ).md
│   ├── DEVELOPMENT_GUIDE.md         # Development workflow
│   ├── DEVELOPER_GUIDE.md           # Exhaustive code reference (2,400+ lines)
│   └── wiki/                        # 15 standalone GitHub wiki pages
├── .github/
│   ├── workflows/test.yml           # CI: lint + pytest on push/PR
│   └── workflows/release.yml        # CD: build + publish on tag
├── conf/
│   └── ports.conf.example           # Example batch config
└── tasks/                           # Project tracking
    ├── todo.md, lessons.md
    ├── gap_analysis.md
    └── bug_report_session8.md
```

Runtime directories (`sessions/`, `logs/`, `certs/`) are created automatically on first run and excluded from version control by `.gitignore`.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Security Considerations

### Input Validation

- All ports validated as integers in range 1-65535
- All hostnames validated against IPv4, IPv6, and RFC 1123 patterns
- Shell metacharacters blocked in hostnames, file paths, and socat options
- Session IDs validated as exactly 8 lowercase hex characters
- Protocol strings validated against exact whitelist
- File paths validated for existence, readability, and absence of injection characters
- Socat options validated against character whitelist `[a-zA-Z0-9=,.:/_-]`

### Process Isolation

- Each socat process runs in its own process group (`os.setsid()`)
- Session files have restricted permissions (0o600)
- Session directory has restricted permissions (0o700)
- Private key files created with 0o600 permissions
- Capture logs created with 0o600 permissions
- Port-based fallback kill only targets processes with comm name `socat` (verified via `/proc/{pid}/comm`)
- `subprocess.Popen` with argument lists only — `shell=True` never used

### What This Tool Does NOT Do

- Does not encrypt traffic (except tunnel mode TLS)
- Does not authenticate connections to the listener/forwarder/redirector
- Does not implement rate limiting or connection throttling
- Does not filter or inspect traffic content (capture is passive hex dump)
- Self-signed certificates (tunnel mode default) are not trusted by clients unless explicitly configured

For the full STRIDE threat model, 7-layer defense analysis, attack surface analysis, and secure deployment guidelines, see [SECURITY.md](docs/SECURITY.md).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Troubleshooting

### Session appears DEAD in status but port is still bound

The original process may have been killed without going through `socat-manager stop`. Run:

```bash
socat-manager status --cleanup    # Remove stale session files
socat-manager status -v           # Show debug output
```

Then manually kill any orphaned socat processes:

```bash
ss -tlnp | grep :8443            # Find PID
kill <PID>                        # Or: kill -9 <PID>
```

### "Port already in use" when launching

Another process is bound to the port. Check with:

```bash
ss -tlnp | grep :<PORT>          # TCP
ss -ulnp | grep :<PORT>          # UDP
```

### Watchdog keeps restarting

Check the session log for the root cause:

```bash
socat-manager status <SID>        # Shows associated log files
cat logs/session-<SID>.log        # Check for errors
```

Common causes: invalid remote host (DNS failure), connection refused, certificate errors (tunnel mode).

### Stop falls through to SIGKILL

If SIGTERM doesn't work within the grace period (5 seconds), socat may have child processes not responding. This is expected behavior — SIGKILL is the fallback.

For additional troubleshooting, see [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Testing

The project includes a full test suite with 510 tests covering validation, session management, lifecycle operations, protocol-scoped stop, traffic capture, watchdog behavior, CLI parsing, and mode handler execution.

```bash
# Run the full test suite (lint + all tests)
make test

# Run unit tests only (fast, ~3 seconds)
make test-unit

# Run integration tests only
make test-integration

# Run tests with coverage report
make test-coverage

# Run ruff linting only
make lint

# Quick smoke test (import, help, version)
make test-smoke
```

| Test File | Tests | Coverage |
|-----------|-------|---------|
| `tests/unit/test_validation.py` | 70 | All 9 `validate_*` functions, injection attempts, edge cases |
| `tests/unit/test_session.py` | 49 | CRUD, exact-key matching, bulk reader, migration, cleanup |
| `tests/unit/test_config.py` | 44 | Constants, frozen dataclasses, protocol maps |
| `tests/unit/test_cli.py` | 43 | All 10 subcommands, flags, defaults, help/version |
| `tests/unit/test_commands.py` | 28 | All 4 command builders, protocol variants, capture |
| `tests/unit/test_logging.py` | 28 | Formatter, display helpers, session logging |
| `tests/unit/test_main.py` | 24 | Dispatch routing, signal handlers, check_socat |
| `tests/unit/test_process.py` | 15 | kill_by_port, _is_socat_process, check_port_freed |
| `tests/unit/test_watchdog.py` | 10 | Backoff, stop signal, max restarts, monitor-first |
| `tests/unit/test_certs.py` | 8 | OpenSSL subprocess, error handling |
| `tests/integration/test_menu.py` | 57 | Cancel detection, prompt validation, submenus |
| `tests/integration/test_mode_handlers.py` | 29 | All 5 mode handlers end-to-end |
| `tests/integration/test_lifecycle.py` | 22 | Launch→find→stop, max sessions, dual-stack |
| `tests/integration/test_modes.py` | 19 | mode_status, mode_stop with all selectors |
| `tests/integration/test_capture.py` | 15 | -v flag propagation, log permissions |
| `tests/integration/test_dual_stack.py` | 14 | Protocol independence, symmetric stop |

Tests use mock stubs for socat, ss, and openssl so they run without real network operations or dependencies. See [CONTRIBUTING.md](docs/CONTRIBUTING.md) for details on writing and running tests.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Contributing

Contributions are welcome and appreciated. To contribute:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/your-feature-name`)
3. **Commit** your changes with clear, descriptive messages
4. **Push** to your branch (`git push origin feature/your-feature-name`)
5. **Open** a Pull Request with a detailed description

### Guidelines

- Run `make test` before submitting — all 510 tests must pass
- Run `make lint` — ruff must report no errors
- Follow the existing code style: type hints, Google-style docstrings, thorough comments
- All user-supplied inputs must pass through the existing validation functions
- No `eval()`, `exec()`, or `shell=True` under any circumstances
- Update `docs/CHANGELOG.md` with your changes
- Read and follow the [Code of Conduct](docs/CODE_OF_CONDUCT.md)
- Report security vulnerabilities privately per [SECURITY.md](docs/SECURITY.md)

For the complete development guide including environment setup, test architecture, and PR process, see [CONTRIBUTING.md](docs/CONTRIBUTING.md).

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Documentation

| Document | Description |
|----------|-------------|
| [README.md](README.md) | Project overview, features, architecture, and quick reference (this file) |
| [docs/USAGE_GUIDE.md](docs/USAGE_GUIDE.md) | Complete usage for all modes with flag tables and behavioral details |
| [docs/SETUP_GUIDE.md](docs/SETUP_GUIDE.md) | Installation methods, dependency installation, environment configuration |
| [docs/SECURITY.md](docs/SECURITY.md) | STRIDE threat model, 7-layer defense analysis, attack surface, secure coding |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Development setup, coding standards, PR process, review checklist |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | Complete version history with detailed change descriptions |
| [docs/CODE_OF_CONDUCT.md](docs/CODE_OF_CONDUCT.md) | Contributor Covenant with responsible use policy |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | 12 common issues with causes, diagnostics, and solutions |
| [docs/DEVELOPER_GUIDE.md](docs/DEVELOPER_GUIDE.md) | Exhaustive API reference for every module, function, class, and constant |
| [docs/DEVELOPMENT_GUIDE.md](docs/DEVELOPMENT_GUIDE.md) | Development workflow, test organization, CI pipeline, release process |
| [docs/wiki/](docs/wiki/) | 15 standalone GitHub wiki pages with Mermaid diagrams and operational scenarios |

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| **0.1.0** | 2026-03-30 | Initial Python release. Full parity with bash v2.3.0. 510 tests. Watchdog rewrite (monitor-first). Configurable --max-restarts/--backoff. Paired forward. Interactive menu with socat-opts examples. |

See [CHANGELOG.md](docs/CHANGELOG.md) for complete details on every change.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## Acknowledgments

- **[socat](http://www.dest-unreach.org/socat/)** by Gerhard Rieger — the multipurpose relay utility that this manager wraps
- **[OpenSSL](https://www.openssl.org/)** — TLS/SSL implementation used for tunnel mode certificate generation
- **[socat_manager.sh](https://github.com/Sandler73/Socat-Network-Operations-Manager)** — the bash reference implementation (v2.3.0) that this Python variant reimplements
- **[Contributor Covenant](https://www.contributor-covenant.org/)** — code of conduct framework
- **[Keep a Changelog](https://keepachangelog.com/)** — changelog format standard
- **[Semantic Versioning](https://semver.org/)** — versioning scheme
- **OWASP** and **NIST** — security standards referenced (CWE-20, CWE-78, NIST SP 800-92)

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>

---

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for full terms including warranty disclaimer, liability limitation, authorized use notice, data handling notice, and cryptographic notice.

```
MIT License · Copyright (c) 2026 Socat Network Operations Manager Contributors
```

This software is intended for authorized network operations, security testing, research, and educational purposes only. Users are solely responsible for to confirm that their use complies with all applicable laws and regulations.

<p align="right">(<a href="#table-of-contents">back to top</a>)</p>
