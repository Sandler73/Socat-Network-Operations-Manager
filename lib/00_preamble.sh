#!/usr/bin/env bash
#======================================================================
# SCRIPT     : socat_manager.sh
#======================================================================
# Synopsis   : socat-based network listener, forwarder,
#              tunneler, and traffic redirector with reliability and
#              multi-session management.
#
# Description: Provides a unified interface for socat network operations
#              across eight operational modes:
#
#              listen   - Start a single TCP/UDP listener on a port
#              batch    - Start multiple listeners from port list/range
#              forward  - Forward traffic between local/remote endpoints
#              tunnel   - Create encrypted (OpenSSL) tunnels via socat
#              redirect - Redirect/proxy traffic transparently
#              status   - Display all active managed sessions
#              stop     - Stop sessions by ID, name, port, PID, or all
#              audit    - Review recorded lifecycle events (SQLite store)
#
#              All modes include automatic session tracking via unique
#              session IDs, process group (PGID) management, per-session
#              logging, connection counting, and optional auto-restart
#              (watchdog) for reliability.
#
#              All operational modes support --proto to select TCP or UDP
#              individually, and --dual-stack to launch both TCP and UDP
#              sessions simultaneously on the same port.
#
#              All operational modes support --capture for a text-readable
#              hex + ASCII traffic dump via socat -v -x (written to a
#              per-session capture log).
#
#              The listener modes (listen, batch, forward, tunnel, redirect)
#              additionally support source-address access control via
#              --allow <CIDR> (socat range=) and --tcpwrap [NAME]
#              (/etc/hosts.allow and /etc/hosts.deny). Tunnel mode accepts
#              --key-type <rsa|ec> to select the self-signed key algorithm.
#
#              Logging is configurable: --log-format <text|json> selects the
#              file format (NDJSON for pipelines) and --log-level
#              <DEBUG|INFO|WARNING|ERROR|CRITICAL> sets the minimum severity
#              emitted (-v/--verbose forces DEBUG). When sqlite3 is present,
#              session launches, stops, restarts, and crashes are recorded to
#              an audit store reviewable with the audit command.
#
#              When invoked with no arguments, the script launches an
#              interactive menu-driven interface with guided input,
#              validation, and cancel/escape support for all modes.
#              CLI mode remains fully functional for scripted use.
#
# Notes      : - Requires socat installed and in PATH
#              - Root/sudo required for privileged ports (<1024)
#              - Sessions tracked in sessions/ directory via .session files
#              - Each session gets a unique 8-character hex Session ID
#              - Processes launched in isolated process groups (setsid)
#                with PID-file handoff for reliable cross-invocation
#                tracking, status, and stop
#              - Stop operations are protocol-aware: stopping a TCP session
#                on a shared port does not affect a UDP session on the same
#                port, and vice versa
#              - Per-execution and per-listener logs in logs/ directory
#              - Supports TCP4, TCP6, UDP4, UDP6 protocol families
#              - Auto-restart via --watchdog flag for crash recovery
#              - Batch mode accepts port lists, ranges, or config files
#              - Tunnel mode generates self-signed certs if none provided
#                (RSA-2048 by default, or EC prime256v1 via --key-type ec)
#              - Source-address access control on listener modes via --allow
#                (CIDR range) and --tcpwrap (TCP wrappers)
#              - Optional SQLite audit store records session lifecycle events
#                when sqlite3 is available (opt out with SOCAT_MANAGER_AUDIT)
#              - Runtime data directory is overridable with SOCAT_MANAGER_BASE
#              - All socat PIDs and PGIDs tracked for clean shutdown
#              - Script returns to prompt immediately after launch
#                (no terminal blocking; status/stop from same terminal)
#
# Execution  : bash socat_manager.sh <MODE> [OPTIONS]
#
# Examples   :
#   # Single TCP listener on port 8080
#   bash socat_manager.sh listen --port 8080
#
#   # UDP-only listener on port 5353
#   bash socat_manager.sh listen --port 5353 --proto udp4
#
#   # Listener on both TCP and UDP
#   bash socat_manager.sh listen --port 8080 --dual-stack
#
#   # Batch listeners on common service ports (requires root)
#   sudo bash socat_manager.sh batch --ports "21,22,23,25,80,443"
#
#   # Port range batch with dual-stack
#   bash socat_manager.sh batch --range 8000-8010 --dual-stack
#
#   # Forward local:8080 to remote 192.168.1.10:80
#   bash socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80
#
#   # Forward UDP-only
#   bash socat_manager.sh forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4
#
#   # Encrypted tunnel listener on 4443
#   bash socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22
#
#   # Redirect TCP traffic (transparent proxy)
#   bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443
#
#   # Redirect UDP-only (e.g., DNS proxy)
#   bash socat_manager.sh redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4
#
#   # Redirect both TCP and UDP with capture
#   bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack --capture
#
#   # Show all active sessions
#   bash socat_manager.sh status
#
#   # Show specific session details
#   bash socat_manager.sh status a1b2c3d4
#
#   # Stop a specific session by ID
#   bash socat_manager.sh stop a1b2c3d4
#
#   # Stop everything
#   bash socat_manager.sh stop --all
#
#   # Launch interactive menu
#   bash socat_manager.sh
#   bash socat_manager.sh menu
#
# Version    : 2.5.1
# Dependencies: socat, openssl (for tunnel mode), ss/netstat (for status),
#              setsid (util-linux), flock (util-linux, for session locking),
#              sqlite3 (optional, enables the audit store and audit command)
#======================================================================

set -euo pipefail

