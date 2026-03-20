# Socat Network Operations Manager

# socat_manager.sh

**A socat-based network listener, forwarder, tunneler, and traffic redirector with reliability and multi-session management.**

> Version 2.3.0 · Bash 4.4+ · Linux

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
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
- [Version History](#version-history)
- [License](#license)

---

## Overview

`socat_manager.sh` provides a unified command-line interface for managing socat-based network operations. It wraps socat's powerful but complex syntax into six intuitive operational modes, adding session tracking, process group isolation, protocol-aware lifecycle management, traffic capture, and automatic restart capabilities.

Every launched socat process receives a unique 8-character hex **Session ID**, is placed in its own **process group** via `setsid`, and is tracked in a persistent `.session` metadata file. This enables reliable status queries and clean shutdowns across terminal sessions and script invocations — you can launch a redirector in one terminal, check its status from another, and stop it from a third.

---

## Features

### Core Capabilities

- **Six operational modes**: listen, batch, forward, tunnel, redirect, status, stop
- **Protocol flexibility**: TCP4, TCP6, UDP4, UDP6 individually via `--proto`, or both TCP and UDP simultaneously via `--dual-stack`
- **Traffic capture**: Verbose hex dump logging (`--capture`) available on all operational modes (listen, batch, forward, tunnel, redirect)
- **Session management**: Unique 8-char hex Session IDs with `.session` metadata files for persistent tracking
- **Process group isolation**: Each socat process launched via `setsid` with PID-file handoff for reliable cross-invocation tracking
- **Protocol-aware stop**: Stopping a TCP session does not affect a UDP session on the same port, and vice versa
- **Non-blocking launch**: Script returns to prompt immediately after launching sessions — no terminal blocking
- **Watchdog auto-restart**: Exponential backoff (1s, 2s, 4s... 60s cap) with configurable max restarts
- **Batch operations**: Launch listeners on port lists, ranges, or config files in a single command

### Input Validation and Security

- Whitelist-based port, hostname, protocol, file path, and session ID validation
- Command injection prevention on all user-supplied inputs (hostnames, paths)
- Path traversal protection on file path parameters
- Session directory permissions restricted to 700
- Session files restricted to 600
- Private key files restricted to 600
- Only socat processes targeted during port-based fallback kill (process name verification)
- No shell metacharacters permitted in hostname or path parameters

### Logging and Audit

- Structured master execution log with correlation IDs (OWASP/NIST SP 800-92 compliant format)
- Per-session log files for independent audit trails
- Per-session error logs for stderr capture
- Traffic capture logs (socat `-v` hex dumps) per session and protocol
- Console output with color-coded severity levels (DEBUG, INFO, WARNING, ERROR, CRITICAL)

---

## Architecture

### Process Launch Model

```
socat_manager.sh (launcher)
    │
    ├── setsid bash -c 'echo $$ > pidfile; exec socat ...' &>/dev/null &
    │       │
    │       └── socat (PID == PGID, session leader)
    │               ├── socat fork (child for connection 1)
    │               ├── socat fork (child for connection 2)
    │               └── ...
    │
    ├── Reads real socat PID from pidfile
    ├── Registers session: SID, PID, PGID, protocol, port, command
    └── Returns to prompt (non-blocking)
```

**Key design decisions:**

1. **`setsid`** creates a new process group. Socat becomes the group leader (PID == PGID), so `kill -TERM -${PGID}` terminates socat and all its `fork` children in one operation.

2. **PID-file handoff**: The inner `bash -c` writes `$$` to a staging file before `exec socat`. Since `exec` preserves the PID, the parent reads the actual socat PID (not a dead wrapper PID).

3. **No `$()` subshell**: Session IDs are returned via a global variable (`LAUNCH_SID`) rather than command substitution, preventing stdout file descriptor inheritance that would block the terminal.

4. **`disown` equivalent**: All stdout/stderr are redirected before `exec`, so no file descriptors leak back to the launching terminal.

### Session File Format

```
# socat_manager session file v2.2
SESSION_ID=a1b2c3d4
SESSION_NAME=redir-tcp4-8443-example.com-443
PID=12345
PGID=12345
MODE=redirect
PROTOCOL=tcp4
LOCAL_PORT=8443
REMOTE_HOST=example.com
REMOTE_PORT=443
SOCAT_CMD=socat -v TCP4-LISTEN:8443,reuseaddr,fork,backlog=128 TCP4:example.com:443
STARTED=2026-03-20T14:30:00
CORRELATION=a1b2c3d4
LAUNCHER_PID=9999
```

### Stop Sequence

```
1. Read session metadata (PID, PGID, PROTOCOL)
2. Signal watchdog via .stop file (if applicable)
3. SIGTERM entire process group: kill -TERM -${PGID}
4. SIGTERM specific PID + children: kill -TERM ${PID}; pkill -TERM -P ${PID}
5. Wait grace period (5 seconds, checking every 0.5s)
6. SIGKILL if still alive: kill -KILL -${PGID}
7. Fallback: protocol-scoped port-based kill via ss/lsof (socat processes only)
8. Verify port freed (protocol-scoped, avoids cross-protocol interference)
9. Remove session file after confirmed dead
```

---

## Prerequisites

### Required

| Dependency | Purpose | Install |
|------------|---------|---------|
| **socat** | Core network operations | `sudo apt-get install -y socat` |
| **bash** 4.4+ | Script execution (associative arrays, `setsid`) | Pre-installed on most Linux |
| **coreutils** | `setsid`, `kill`, `sleep`, `date`, `sha256sum` | Pre-installed on most Linux |

### Optional

| Dependency | Purpose | Install |
|------------|---------|---------|
| **openssl** | TLS certificate generation (tunnel mode) | `sudo apt-get install -y openssl` |
| **ss** (iproute2) | Port status checking, session verification | `sudo apt-get install -y iproute2` |
| **netstat** (net-tools) | Fallback port status checking | `sudo apt-get install -y net-tools` |
| **lsof** | Fallback process-by-port discovery | `sudo apt-get install -y lsof` |
| **pstree** (psmisc) | Process tree display in `status` detail view | `sudo apt-get install -y psmisc` |

### System Requirements

- Linux kernel with `/proc/sys/kernel/random/uuid` (session ID generation)
- Root/sudo for privileged ports (<1024)
- Bash 4.4+ for associative arrays and `${var,,}` lowercase expansion

---

## Quick Start

```bash
# Install socat
sudo apt-get update && sudo apt-get install -y socat

# Clone or download socat_manager.sh
chmod +x socat_manager.sh

# Start a TCP listener on port 8080
./socat_manager.sh listen --port 8080

# Check session status
./socat_manager.sh status

# Stop everything
./socat_manager.sh stop --all
```

---

## Operational Modes

### listen Mode

Start a single TCP or UDP listener that captures incoming data to a log file.

```bash
# Basic TCP listener
./socat_manager.sh listen --port 8080

# UDP listener
./socat_manager.sh listen --port 5353 --proto udp4

# TCP + UDP simultaneously
./socat_manager.sh listen --port 8080 --dual-stack

# With traffic capture
./socat_manager.sh listen --port 8080 --capture

# Bind to specific interface
./socat_manager.sh listen --port 8080 --bind 192.168.1.100

# With auto-restart
./socat_manager.sh listen --port 8080 --watchdog
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
| `--socat-opts <OPTS>` | Additional socat address options |

### batch Mode

Start multiple listeners from port lists, ranges, or config files.

```bash
# Port list
sudo ./socat_manager.sh batch --ports "21,22,23,25,80,443"

# Port range
./socat_manager.sh batch --range 8000-8010

# Port range with dual-stack and capture
./socat_manager.sh batch --range 8000-8005 --dual-stack --capture

# UDP-only batch
./socat_manager.sh batch --ports "5353,5354,5355" --proto udp4

# From config file
./socat_manager.sh batch --config ./ports.conf
```

**Config file format** (`ports.conf`):

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
| `--config <FILE>` | Config file (one port per line) |
| `--proto <PROTO>` | Protocol for all listeners (default: tcp4) |
| `--dual-stack` | Start both TCP and UDP per port |
| `--capture` | Enable traffic capture for all listeners |
| `--watchdog` | Enable auto-restart for all listeners |

### forward Mode

Create a bidirectional port forwarder between a local port and a remote target.

```bash
# TCP forwarder
./socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80

# UDP forwarder (e.g., DNS relay)
./socat_manager.sh forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4

# Dual-stack forwarder
./socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80 --dual-stack

# With traffic capture
./socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80 --capture

# Cross-protocol forwarding (TCP listen → UDP remote)
./socat_manager.sh forward --lport 8080 --rhost 10.0.0.5 --rport 53 --proto tcp4 --remote-proto udp4
```

**Options:**

| Option | Description |
|--------|-------------|
| `--lport <PORT>` | Local port to listen on (required) |
| `--rhost <HOST>` | Remote host to forward to (required) |
| `--rport <PORT>` | Remote port to forward to (required) |
| `--proto <PROTO>` | Listen protocol (default: tcp4) |
| `--remote-proto <PROTO>` | Remote protocol (default: matches `--proto`) |
| `--dual-stack` | Also start forwarder on alternate protocol |
| `--capture` | Enable traffic capture |
| `--logfile <PATH>` | Custom capture log file |
| `--name <NAME>` | Custom session name |
| `--watchdog` | Enable auto-restart |

### tunnel Mode

Create an encrypted TLS/SSL tunnel. Accepts TLS connections on a local port and forwards plaintext traffic to a remote target. Auto-generates self-signed certificates if none provided.

```bash
# Basic tunnel (auto-generates self-signed cert)
./socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22

# With custom certificate
./socat_manager.sh tunnel --port 8443 --rhost db.internal --rport 5432 \
    --cert /etc/ssl/cert.pem --key /etc/ssl/key.pem

# Tunnel with plaintext UDP forwarder on same port
./socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --dual-stack

# With capture (logs decrypted traffic)
./socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --capture

# Custom Common Name for self-signed cert
./socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --cn myhost.local
```

**Protocol note:** TLS tunnels are TCP-only by design. Using `--proto udp4` will produce a clear error with guidance to use `forward --proto udp4` instead. `--dual-stack` adds a plaintext UDP forwarder with a warning that UDP traffic is not encrypted.

**Options:**

| Option | Description |
|--------|-------------|
| `-p, --port <PORT>` | Local TLS listen port (required) |
| `--rhost <HOST>` | Remote target host (required) |
| `--rport <PORT>` | Remote target port (required) |
| `--cert <PATH>` | Path to PEM certificate file |
| `--key <PATH>` | Path to PEM private key file |
| `--cn <CN>` | Common Name for self-signed cert (default: localhost) |
| `--proto <PROTO>` | Validates protocol (tcp accepted; udp rejected with guidance) |
| `--dual-stack` | Also start plaintext UDP forwarder on same port |
| `--capture` | Enable capture of decrypted traffic |
| `--logfile <PATH>` | Custom capture log file |
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
./socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443

# UDP redirect (e.g., DNS proxy)
./socat_manager.sh redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4

# Dual-stack redirect
./socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack

# With traffic capture
./socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --capture

# Full dual-stack with capture
./socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack --capture
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
| `--logfile <PATH>` | Custom capture log file |
| `--name <NAME>` | Custom session name |
| `--watchdog` | Enable auto-restart |

### status Mode

Display all active managed sessions or detailed information for a specific session.

```bash
# List all sessions
./socat_manager.sh status

# Detail by Session ID
./socat_manager.sh status a1b2c3d4

# Detail by session name
./socat_manager.sh status redir-tcp4-8443-example.com-443

# Detail by port (shows all protocols on that port)
./socat_manager.sh status 8443

# Include system-level listener info
./socat_manager.sh status --verbose

# Clean up dead session files
./socat_manager.sh status --cleanup
```

**Status table output:**

```
  ─── Active Sessions ───

  SID        SESSION                      PID      PGID     MODE       PROTO  LPORT  REMOTE                 STATUS
  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────
  a1b2c3d4   redir-tcp4-8443-example.com  12345    12345    redirect   tcp4   8443   example.com:443        ALIVE
  e5f67890   redir-udp4-8443-example.com  12346    12346    redirect   udp4   8443   example.com:443        ALIVE

  Sessions: 2 alive, 0 dead, 2 total
```

**Detail view** (when querying by SID, name, or port) includes: all session metadata fields, process tree (via `pstree`), port binding status per protocol, socat command string, and associated log file paths.

### stop Mode

Stop one or more sessions by session ID, name, port, PID, or all.

```bash
# Stop by Session ID
./socat_manager.sh stop a1b2c3d4

# Stop by session name
./socat_manager.sh stop --name redir-tcp4-8443-example.com-443

# Stop all sessions on a port (both protocols if dual-stack)
./socat_manager.sh stop --port 8443

# Stop by PID
./socat_manager.sh stop --pid 12345

# Stop everything
./socat_manager.sh stop --all
```

**Protocol isolation:** Stopping a TCP session on port 8443 does **not** affect a UDP session on the same port. Each protocol's stop operation is scoped to its own protocol only. The `--port` flag is the exception — it stops all sessions on that port across all protocols.

---

## Global Options

These options are available on all operational modes:

| Option | Description |
|--------|-------------|
| `--proto <PROTOCOL>` | Select protocol: `tcp`, `tcp4`, `tcp6`, `udp`, `udp4`, `udp6`. Default: `tcp4`. Tunnel mode accepts TCP only. |
| `--dual-stack` | Launch sessions on both TCP and UDP simultaneously. Each gets its own Session ID. |
| `--capture` | Enable socat `-v` verbose hex dump traffic logging. Capture log per session/protocol. |
| `--watchdog` | Enable automatic restart with exponential backoff on process crash. |
| `-v, --verbose` | Enable DEBUG-level console output. |
| `-h, --help` | Show context-sensitive help (per mode). |
| `--version` | Show version string and exit. |

---

## Session Management

Every socat process launched by `socat_manager.sh` receives:

1. A **unique 8-character hex Session ID** (e.g., `a1b2c3d4`) generated from `/proc/sys/kernel/random/uuid` with collision checking.

2. A **`.session` metadata file** in the `sessions/` directory (permissions 600) containing PID, PGID, mode, protocol, ports, timestamps, full socat command, correlation ID, and launcher PID.

3. An **isolated process group** via `setsid`, making the socat process its own session leader and group leader. This enables `kill -TERM -${PGID}` to terminate the entire process tree (parent + all forked children).

Sessions persist across terminal exits and script invocations. The `status` command reads session files to report on all managed processes. The `stop` command uses PID, PGID, and protocol-scoped port verification to ensure complete shutdown.

**Backward compatibility:** If legacy `.pid` session files from v1.x are detected, they are automatically migrated to the v2.x `.session` format on startup.

---

## Protocol Selection

### Individual Protocol (`--proto`)

Select a specific protocol for the session:

```bash
# TCP4 (default)
./socat_manager.sh listen --port 8080 --proto tcp4

# UDP4
./socat_manager.sh listen --port 5353 --proto udp4

# TCP6 (IPv6)
./socat_manager.sh listen --port 8080 --proto tcp6

# UDP6 (IPv6)
./socat_manager.sh listen --port 5353 --proto udp6
```

### Dual-Stack (`--dual-stack`)

Launch both TCP and UDP on the same port. Each protocol gets its own Session ID:

```bash
./socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack
# Output:
#   [✓] Redirector active: tcp4:8443 → example.com:443 (SID a1b2c3d4)
#   [✓] Redirector active: udp4:8443 → example.com:443 (SID e5f67890)
```

Stop operations are protocol-aware:

```bash
# Stop only TCP (UDP remains active)
./socat_manager.sh stop a1b2c3d4

# Stop only UDP
./socat_manager.sh stop e5f67890

# Stop both (all sessions on port)
./socat_manager.sh stop --port 8443
```

---

## Traffic Capture

The `--capture` flag enables socat's `-v` (verbose) mode, which produces hex dump output of all traffic on stderr. The launcher redirects this stderr to a per-session capture log file:

```bash
# Capture on any mode
./socat_manager.sh listen --port 8080 --capture
./socat_manager.sh forward --lport 8080 --rhost 10.0.0.1 --rport 80 --capture
./socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --capture
./socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --capture
./socat_manager.sh batch --ports "8080,8443" --capture
```

Capture log files are written to: `logs/capture-<proto>-<port>-<host>-<rport>-<timestamp>.log`

For tunnel mode, capture logs contain **decrypted** traffic between the TLS termination point and the remote target.

For dual-stack with capture, each protocol gets its own capture log.

---

## Watchdog Auto-Restart

The `--watchdog` flag enables automatic restart if the socat process crashes:

```bash
./socat_manager.sh listen --port 8080 --watchdog
```

Behavior:

- Initial restart delay: 1 second
- Exponential backoff: 1s, 2s, 4s, 8s, 16s, 32s, 60s (capped)
- Maximum restarts: 10 (configurable in source)
- Graceful stop: writes a `.stop` signal file that the watchdog checks between restarts

---

## Logging

### Log Types

| Log | Path | Description |
|-----|------|-------------|
| Master execution | `logs/socat_manager-<timestamp>.log` | All operations for this script invocation |
| Session-specific | `logs/session-<sid>-<timestamp>.log` | Per-session audit trail |
| Session errors | `logs/session-<sid>-error.log` | Socat stderr output (non-capture mode) |
| Listener data | `logs/listener-<proto>-<port>.log` | Raw incoming data (listen/batch modes) |
| Traffic capture | `logs/capture-<proto>-<port>-<timestamp>.log` | Hex dump traffic (when `--capture` enabled) |

### Log Format

Master and session logs use structured format:

```
2026-03-20T14:30:00.123 [INFO] [corr:a1b2c3d4] [session] Session registered: name=redir-tcp4-8443 pid=12345 pgid=12345 mode=redirect proto=tcp4 port=8443
```

Fields: ISO-8601 timestamp, severity level, correlation ID, component name, message.

---

## Directory Structure

```
socat_manager.sh          # Main script
├── sessions/             # Session metadata files (.session) [perms: 700]
│   ├── a1b2c3d4.session  # Active session file [perms: 600]
│   └── e5f67890.session
├── logs/                 # All log files
│   ├── socat_manager-2026-03-20T14-30-00.log   # Master execution log
│   ├── session-a1b2c3d4-2026-03-20T14-30-00.log  # Session log
│   ├── session-a1b2c3d4-error.log               # Session stderr
│   ├── listener-tcp4-8080.log                    # Listener data capture
│   └── capture-tcp4-8443-example.com-443-2026-03-20T14-30-00.log  # Traffic capture
├── certs/                # Auto-generated TLS certificates (tunnel mode)
│   ├── socat-tunnel-2026-03-20T14-30-00.pem  # Certificate [perms: 644]
│   └── socat-tunnel-2026-03-20T14-30-00.key  # Private key [perms: 600]
└── conf/                 # Configuration files (batch port configs)
    └── ports.conf
```

All directories are created automatically on first run.

---

## Security Considerations

### Input Validation

- All ports validated as integers in range 1-65535
- All hostnames validated against IPv4, IPv6, and RFC 1123 patterns
- Shell metacharacters (`; | & $ \` ( ) { } [ ] < > ! #`) blocked in hostnames
- Path traversal (`..`) and injection characters blocked in file paths
- Session IDs validated as exactly 8 lowercase hex characters
- Protocol strings validated against whitelist (tcp4, tcp6, udp4, udp6)

### Process Isolation

- Each socat process runs in its own process group (`setsid`)
- Session files have restricted permissions (600)
- Session directory has restricted permissions (700)
- Private key files generated with 600 permissions
- Port-based fallback kill only targets processes with comm name `socat` (verified via `ps`)

### What This Tool Does NOT Do

- Does not encrypt traffic (except tunnel mode TLS)
- Does not authenticate connections to the listener/forwarder/redirector
- Does not implement rate limiting or connection throttling
- Does not filter or inspect traffic content (capture is passive hex dump)
- Self-signed certificates (tunnel mode default) are not trusted by clients unless explicitly configured

For production deployments, layer additional security controls (firewall rules, TLS certificate pinning, network segmentation) around sessions managed by this tool.

---

## Troubleshooting

### Session appears DEAD in status but port is still bound

The original process may have been killed without going through `socat_manager.sh stop`. Run:

```bash
./socat_manager.sh status --cleanup    # Remove stale session files
./socat_manager.sh status --verbose    # Show system-level socat listeners via ss
```

Then manually kill any orphaned socat processes:

```bash
ss -tlnp | grep :8443                  # Find PID
kill <PID>                              # Or: kill -9 <PID>
```

### "Port already in use" when launching

Another process is bound to the port. Check with:

```bash
ss -tlnp | grep :<PORT>               # TCP
ss -ulnp | grep :<PORT>               # UDP
```

### Watchdog keeps restarting

The socat process is crashing immediately. Check the session error log:

```bash
cat logs/session-<SID>-error.log
```

Common causes: invalid remote host (DNS resolution failure), connection refused on remote port, certificate errors (tunnel mode).

### Stop falls through to SIGKILL

If SIGTERM doesn't work within the grace period (5 seconds), socat may have child processes that aren't responding to SIGTERM. This is expected behavior — SIGKILL is the fallback. Check:

```bash
./socat_manager.sh status <SID>        # Verify it's actually stopped
ss -tlnp | grep :<PORT>               # Verify port is freed
```

---

## Version History

| Version | Changes |
|---------|---------|
| **2.3.0** | `--capture` extended to all operational modes (listen, batch, forward, tunnel, redirect). `--proto` added to tunnel mode (with TLS-aware validation). |
| **2.2.0** | Protocol-aware stop: stopping TCP no longer kills UDP on shared ports. `--proto` added to redirect mode. Full documentation and annotation restoration. |
| **2.1.0** | Fixed terminal blocking (PID-file handoff via `setsid` + `exec`). Fixed wrong PID tracking. Added `--dual-stack` to all modes. Increased stop grace period to 5s. |
| **2.0.0** | Session ID system (8-char hex). PGID tracking via `setsid`. Session files (`.session`). Comprehensive stop sequence with port verification. |
| **1.0.0** | Initial release. Six operational modes. PID-file tracking. Basic stop/status. |

---

## License

This project is provided as-is for operational and educational use. See LICENSE file for terms if present, otherwise all rights reserved by the author.
