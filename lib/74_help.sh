#======================================================================
# HELP SYSTEM
# Per-mode help documentation accessible via -h/--help
# Each mode provides usage synopsis, options, and examples
#======================================================================

show_main_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh - socat network operations manager

SYNOPSIS
    socat_manager.sh <MODE> [OPTIONS]

MODES
    listen      Start a single TCP/UDP listener on a port
    batch       Start multiple listeners (port list, range, or config)
    forward     Forward local port to remote host:port (bidirectional)
    tunnel      Create encrypted (TLS/SSL) tunnel via socat + OpenSSL
    redirect    Redirect/proxy traffic with optional capture
    status      Display all active managed sessions
    stop        Stop sessions (by ID, name, port, PID, or all)
    audit       View the persistent audit history (requires sqlite3)
    menu        Launch the interactive menu

GLOBAL OPTIONS
    --proto <PROTOCOL>   Select protocol: tcp, tcp4, tcp6, udp, udp4, udp6
    --dual-stack         Launch both TCP and UDP sessions simultaneously
    --capture            Enable traffic capture (readable hex + ASCII dump)
    --log-format <FMT>   Log file format: text (default) or json (NDJSON)
    --log-level <LEVEL>  Minimum level to log: DEBUG, INFO (default), WARNING,
                         ERROR, CRITICAL. -v/--verbose forces DEBUG.
    -v, --verbose        Enable debug-level console output
    -h, --help           Show help (context-sensitive per mode)

EXAMPLES
    # Start a TCP listener on port 8080
    bash socat_manager.sh listen --port 8080

    # Start a UDP-only listener
    bash socat_manager.sh listen --port 5353 --proto udp4

    # Listener on both TCP and UDP
    bash socat_manager.sh listen --port 8080 --dual-stack

    # Batch listeners on common ports (requires root for <1024)
    sudo bash socat_manager.sh batch --ports "21,22,23,25,80,443"

    # Batch from a port range with dual-stack
    bash socat_manager.sh batch --range 8000-8010 --dual-stack

    # Forward local:8080 to 192.168.1.10:80
    bash socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80

    # Forward UDP-only
    bash socat_manager.sh forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4

    # Encrypted tunnel: TLS:4443 → 10.0.0.5:22
    bash socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22

    # Redirect with traffic capture
    bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --capture

    # Forward with traffic capture
    bash socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80 --capture

    # Listener with traffic capture
    bash socat_manager.sh listen --port 8080 --capture

    # Redirect UDP-only (e.g., DNS proxy)
    bash socat_manager.sh redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4

    # Redirect both TCP and UDP with capture
    bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack --capture

    # Check all session status
    bash socat_manager.sh status

    # Check specific session (by ID, name, or port)
    bash socat_manager.sh status a1b2c3d4
    bash socat_manager.sh status redir-tcp4-8443-example.com-443
    bash socat_manager.sh status 8443

    # Stop specific session by ID
    bash socat_manager.sh stop a1b2c3d4

    # Stop everything
    bash socat_manager.sh stop --all

SESSION MANAGEMENT
    Each socat process is assigned a unique 8-character hex Session ID.
    Sessions are tracked in sessions/ via .session metadata files.
    Each session records: Session ID, PID, PGID, mode, protocol, ports,
    full socat command, start time, and correlation ID.

    Processes are launched in isolated process groups (via setsid) with
    PID-file handoff for reliable cross-invocation tracking and stop.
    The script returns to the prompt immediately after launching sessions.

PROTOCOL SELECTION
    --proto <PROTOCOL>   Select a single protocol (tcp4, tcp6, udp4, udp6).
                         Default: tcp4. Available on listen, batch, forward,
                         redirect modes. Tunnel mode is TLS/TCP-only.

    --dual-stack         Launch sessions on BOTH TCP and UDP simultaneously.
                         Each protocol gets its own session ID for independent
                         management. Stop operations are protocol-aware: stopping
                         a TCP session does NOT affect a UDP session on the same
                         port, and vice versa.

RELIABILITY
    --watchdog flag enables auto-restart with exponential backoff.
    Max 10 restarts before giving up. Backoff: 1s, 2s, 4s... 60s cap.

LOGGING
    Master execution log:  logs/socat_manager-<timestamp>.log
    Per-listener data:     logs/listener-<proto>-<port>.log
    Session-specific:      logs/session-<sid>-<timestamp>.log
    Session errors:        logs/session-<sid>-error.log
    Traffic capture:       logs/capture-<proto>-<ports>-<timestamp>.log

DEPENDENCIES
    Required:     socat
    Optional:     openssl (tunnel mode), ss/netstat (status)
    Install:      sudo apt-get install -y socat openssl

VERSION
    2.3.0
HELPEOF
}

show_listen_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh listen - Start a single network listener

SYNOPSIS
    socat_manager.sh listen --port <PORT> [OPTIONS]

DESCRIPTION
    Start a single TCP or UDP listener that captures incoming data
    to a log file. The listener forks per connection for concurrent
    client handling. Use --proto to select UDP or a specific address
    family, and --dual-stack to listen on both TCP and UDP.

OPTIONS
    -p, --port <PORT>        Port number to listen on (required)
    --proto <PROTOCOL>       Protocol: tcp, tcp4, tcp6, udp, udp4, udp6
                             (default: tcp4)
    --dual-stack             Also start listener on alternate protocol
                             (e.g., tcp4 primary → also starts udp4)
    --bind <ADDRESS>         Bind to specific IP address
    --name <n>            Custom session name
    --logfile <PATH>         Custom log file for captured data
    --capture                Enable traffic capture (verbose hex dump)
    --watchdog               Enable auto-restart on crash
    --socat-opts <OPTS>      Additional socat address options
    --allow <CIDR>           Accept only connections from an IPv4/IPv6
                             source range (maps to socat range=)
    --tcpwrap [NAME]         Enforce /etc/hosts.allow and /etc/hosts.deny
                             via TCP wrappers (default daemon name: socat)
    -v, --verbose            Debug output
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh listen --port 8080
    bash socat_manager.sh listen --port 5353 --proto udp4
    bash socat_manager.sh listen --port 8080 --dual-stack
    bash socat_manager.sh listen --port 8080 --capture
    bash socat_manager.sh listen --port 4443 --proto tcp6
    bash socat_manager.sh listen --port 80 --watchdog --bind 0.0.0.0
HELPEOF
}

show_batch_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh batch - Start multiple listeners

SYNOPSIS
    socat_manager.sh batch --ports <LIST> | --range <START-END> | --config <FILE>

DESCRIPTION
    Start listeners on multiple ports simultaneously. Accepts port lists,
    ranges, or config files. Each port gets an independent session with
    a unique session ID. --dual-stack launches both TCP and UDP per port.

OPTIONS
    --ports <LIST>           Comma-separated port list (e.g., "21,22,80,443")
    --range <START-END>      Port range (e.g., "8000-8010")
    --config <FILE>          Config file (one port per line, # comments)
    --proto <PROTOCOL>       Protocol for all listeners (default: tcp4)
    --dual-stack             Start both TCP and UDP per port
    --capture                Enable traffic capture (verbose hex dump)
    --watchdog               Enable auto-restart for all listeners
    --allow <CIDR>           Accept only connections from an IPv4/IPv6
                             source range (maps to socat range=)
    --tcpwrap [NAME]         Enforce /etc/hosts.allow and /etc/hosts.deny
                             via TCP wrappers (default daemon name: socat)
    -v, --verbose            Debug output
    -h, --help               Show this help

EXAMPLES
    sudo bash socat_manager.sh batch --ports "21,22,23,25,80,443,445"
    bash socat_manager.sh batch --ports "80,443" --capture
    bash socat_manager.sh batch --range 8000-8010 --dual-stack
    bash socat_manager.sh batch --range 8000-8005 --proto udp4
    bash socat_manager.sh batch --config ./ports.conf --watchdog
HELPEOF
}

show_forward_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh forward - Forward connections to a remote target

SYNOPSIS
    socat_manager.sh forward --lport <PORT> --rhost <HOST> --rport <PORT>

DESCRIPTION
    Create a bidirectional port forwarder. Local connections are proxied
    to a remote target. Use --proto to select UDP or a specific address
    family, and --dual-stack to forward both TCP and UDP.

OPTIONS
    --lport <PORT>           Local port to listen on (required)
    --rhost <HOST>           Remote host to forward to (required)
    --rport <PORT>           Remote port to forward to (required)
    --proto <PROTOCOL>       Listen protocol (default: tcp4)
    --remote-proto <PROTO>   Remote protocol (default: matches --proto)
    --dual-stack             Also start forwarder on alternate protocol
    --capture                Enable traffic capture (verbose hex dump)
    --logfile <PATH>         Custom capture log file
    --name <n>            Custom session name
    --watchdog               Enable auto-restart
    --allow <CIDR>           Accept only connections from an IPv4/IPv6
                             source range (maps to socat range=)
    --tcpwrap [NAME]         Enforce /etc/hosts.allow and /etc/hosts.deny
                             via TCP wrappers (default daemon name: socat)
    -v, --verbose            Debug output
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80
    bash socat_manager.sh forward --lport 5353 --rhost 10.0.0.1 --rport 53 --proto udp4
    bash socat_manager.sh forward --lport 8080 --rhost 192.168.1.10 --rport 80 --dual-stack
    bash socat_manager.sh forward --lport 5433 --rhost db.internal --rport 5432 --watchdog
HELPEOF
}

show_tunnel_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh tunnel - Create an encrypted TLS tunnel

SYNOPSIS
    socat_manager.sh tunnel --port <PORT> --rhost <HOST> --rport <PORT>

DESCRIPTION
    Accepts TLS/SSL connections on the local port and forwards
    plaintext traffic to the remote target. Auto-generates a
    self-signed certificate if --cert/--key are not provided.
    TLS tunnels are TCP-only. --dual-stack adds a plaintext UDP
    forwarder on the same port (with a warning that UDP is unencrypted).

OPTIONS
    -p, --port <PORT>        Local TLS listen port (required)
    --rhost <HOST>           Remote target host (required)
    --rport <PORT>           Remote target port (required)
    --cert <PATH>            Path to PEM certificate file
    --key <PATH>             Path to PEM private key file
    --cn <CN>                Common Name for self-signed cert
    --dual-stack             Also start plaintext UDP forwarder on same port
    --proto <PROTOCOL>       Validate protocol (tcp/tcp4 accepted; udp rejected
                             with guidance to use forward mode instead)
    --capture                Enable traffic capture (verbose hex dump of
                             decrypted traffic between TLS endpoint and target)
    --logfile <PATH>         Custom capture log file
    --name <n>            Custom session name
    --watchdog               Enable auto-restart
    --key-type <rsa|ec>      Self-signed key algorithm (default: rsa)
    --allow <CIDR>           Accept only connections from an IPv4/IPv6
                             source range (maps to socat range=)
    --tcpwrap [NAME]         Enforce /etc/hosts.allow and /etc/hosts.deny
                             via TCP wrappers (default daemon name: socat)
    -v, --verbose            Debug output
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22
    bash socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --dual-stack
    bash socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --capture
    bash socat_manager.sh tunnel --port 8443 --rhost db.internal --rport 5432 \
        --cert /etc/ssl/cert.pem --key /etc/ssl/key.pem
HELPEOF
}

show_redirect_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh redirect - Redirect/proxy traffic

SYNOPSIS
    socat_manager.sh redirect --lport <PORT> --rhost <HOST> --rport <PORT>

DESCRIPTION
    Redirect traffic transparently between a local port and a remote
    target. Optionally captures bidirectional traffic hex dumps for
    inspection. Use --proto to select UDP or a specific address family,
    and --dual-stack to redirect both TCP and UDP.

OPTIONS
    --lport <PORT>           Local listen port (required)
    --rhost <HOST>           Remote target host (required)
    --rport <PORT>           Remote target port (required)
    --proto <PROTOCOL>       Protocol: tcp, tcp4, tcp6, udp, udp4, udp6
                             (default: tcp4)
    --dual-stack             Also start redirector on alternate protocol
    --capture                Enable traffic capture (hex dump)
    --logfile <PATH>         Custom capture log file
    --name <n>            Custom session name
    --watchdog               Enable auto-restart
    --allow <CIDR>           Accept only connections from an IPv4/IPv6
                             source range (maps to socat range=)
    --tcpwrap [NAME]         Enforce /etc/hosts.allow and /etc/hosts.deny
                             via TCP wrappers (default daemon name: socat)
    -v, --verbose            Debug output
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443
    bash socat_manager.sh redirect --lport 5353 --rhost 8.8.8.8 --rport 53 --proto udp4
    bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack
    bash socat_manager.sh redirect --lport 3307 --rhost db.local --rport 3306 --capture
    bash socat_manager.sh redirect --lport 8443 --rhost example.com --rport 443 --dual-stack --capture
HELPEOF
}

show_stop_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh stop - Stop managed sessions

SYNOPSIS
    socat_manager.sh stop <SESSION_ID>
    socat_manager.sh stop --all | --name <n> | --port <PORT> | --pid <PID>

DESCRIPTION
    Stop one or more managed socat sessions. The first positional
    argument is treated as a session ID. Alternatively, use named
    flags to stop by other selectors.

    The stop process terminates the entire process group (PGID),
    verifies the port is freed, and removes the session file only
    after confirming all processes are dead.

    Stop operations are protocol-aware: stopping a TCP session on
    a shared port does NOT affect a UDP session on the same port,
    and vice versa. This is critical for dual-stack configurations
    where TCP and UDP run independently on the same port.

OPTIONS
    <SESSION_ID>             Stop session by its 8-char hex ID (positional)
    --all                    Stop all managed sessions
    --name <n>            Stop session by name
    --port <PORT>            Stop all sessions on a port (all protocols)
    --pid <PID>              Stop session by PID
    -v, --verbose            Debug output
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh stop a1b2c3d4
    bash socat_manager.sh stop --all
    bash socat_manager.sh stop --name redir-tcp4-8443-example.com-443
    bash socat_manager.sh stop --port 8443
HELPEOF
}

show_status_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh status - Show active session status

SYNOPSIS
    socat_manager.sh status [SESSION_ID | SESSION_NAME | PORT] [OPTIONS]

DESCRIPTION
    Without arguments, displays a summary table of all managed sessions.
    With a positional argument, shows detailed information for the
    matching session including process tree, port status, and logs.

    The argument is matched against session IDs (8-char hex), session
    names (e.g., redir-tcp4-8443-example.com-443), and port numbers.
    Port lookups may return multiple sessions when dual-stack is active.

OPTIONS
    <SESSION_ID>             Show detail for a specific session (positional)
    --cleanup                Remove dead session files
    -v, --verbose            Show system-level listener info
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh status
    bash socat_manager.sh status a1b2c3d4
    bash socat_manager.sh status redir-tcp4-8443-example.com-443
    bash socat_manager.sh status 8443
    bash socat_manager.sh status --cleanup
    bash socat_manager.sh status --verbose
HELPEOF
}

