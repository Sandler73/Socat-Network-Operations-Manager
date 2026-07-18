#======================================================================
# SOCAT COMMAND BUILDERS
# Constructs socat command strings for each operational mode.
# Separates command construction from execution for testability,
# dry-run support, and audit logging.
#======================================================================

# Function: build_socat_listen_cmd
# Description: Build a socat command string for a listener.
#              Constructs a unidirectional listener that captures
#              incoming data to a log file. When capture mode is enabled,
#              socat's -v -x flags add a text-readable hex + ASCII dump
#              of the traffic on stderr (redirected to a capture log by the
#              launcher). View it with any text tool (cat, less); it is not
#              a pcap and is not read by tcpdump/wireshark.
# Parameters:
#   $1 - Protocol (tcp4, tcp6, udp4, udp6)
#   $2 - Port number
#   $3 - Log file path for captured data
#   $4 - Additional socat options (optional)
#   $5 - Capture mode enabled (true/false, default: false)
# Outputs: The constructed socat command string
build_socat_listen_cmd() {
    local proto="${1:?Protocol required}"
    local port="${2:?Port required}"
    local logfile="${3:?Log file required}"
    local extra_opts="${4:-}"
    local capture="${5:-false}"
    local filter_opts="${6:-}"

    # Map protocol to socat address type (uppercase as socat expects)
    local socat_proto
    case "${proto}" in
        tcp4) socat_proto="TCP4-LISTEN" ;;
        tcp6) socat_proto="TCP6-LISTEN" ;;
        udp4) socat_proto="UDP4-LISTEN" ;;
        udp6) socat_proto="UDP6-LISTEN" ;;
    esac

    # Base listener options:
    #   reuseaddr  - Allow rebinding immediately after close (avoids TIME_WAIT)
    #   fork       - Fork a child process per connection (multi-session)
    local listen_opts="reuseaddr,fork"

    # TCP-specific options
    if [[ "${proto}" == tcp* ]]; then
        # backlog   - Connection queue depth
        # keepalive - Enable TCP keepalive probes
        listen_opts+=",backlog=${DEFAULT_BACKLOG},keepalive"
    fi

    # Append any extra user-provided socat address options
    if [[ -n "${extra_opts}" ]]; then
        listen_opts+=",${extra_opts}"
    fi
    listen_opts+="${filter_opts}"

    # Capture mode: add -v -x for a text-readable hex + ASCII traffic dump
    # on stderr. The launcher redirects stderr to a capture log file.
    local verbose_flag=""
    if [[ "${capture}" == true ]]; then
        verbose_flag="-v -x"
    fi

    # Build the command:
    #   -u        = Unidirectional (from left to right) for logging listeners
    #   -v -x     = Text-readable hex + ASCII traffic dump (capture mode only,
#               written to stderr, redirected to the capture log)
    #   The listener captures incoming data to the log file
    #   creat     = Create file if it doesn't exist
    #   append    = Append to existing file (don't overwrite)
    echo "socat ${verbose_flag} -u ${socat_proto}:${port},${listen_opts} OPEN:${logfile},creat,append"
}

# Function: build_socat_forward_cmd
# Description: Build a socat command for port forwarding (bidirectional).
#              Creates a full-duplex proxy between a local listener and
#              a remote target. When capture mode is enabled, socat's -v
#              -v -x flags add a text-readable hex + ASCII dump on stderr for both
#              directions of traffic.
# Parameters:
#   $1 - Listen protocol (tcp4, tcp6, udp4, udp6)
#   $2 - Local port to listen on
#   $3 - Remote host to forward to
#   $4 - Remote port to forward to
#   $5 - Remote protocol (optional, defaults to match listen)
#   $6 - Capture mode enabled (true/false, default: false)
# Outputs: The constructed socat command string
# Function: format_socat_endpoint
# Description: Compose a socat remote endpoint address, bracketing IPv6 literal
#              hosts. socat requires IPv6 literals in bracket form so the address
#              parser can separate host from port - e.g. TCP6:[fe80::1]:443. A
#              bare TCP6:fe80::1:443 is ambiguous and fails. Hostnames and IPv4
#              addresses never contain a colon, so bracketing is applied only when
#              a colon is present and the host is not already bracketed.
# Parameters:
#   $1 - socat address prefix (e.g. TCP4, TCP6, UDP6)
#   $2 - Remote host (hostname, IPv4, or IPv6 literal)
#   $3 - Remote port
# Outputs: "<prefix>:<host-or-bracketed-host>:<port>"
format_socat_endpoint() {
    local prefix="${1:?Address prefix required}"
    local host="${2:?Remote host required}"
    local port="${3:?Remote port required}"

    if [[ "${host}" == *:* && "${host}" != \[*\] ]]; then
        host="[${host}]"
    fi

    printf '%s:%s:%s' "${prefix}" "${host}" "${port}"
}

build_socat_forward_cmd() {
    local listen_proto="${1:?Listen protocol required}"
    local lport="${2:?Local port required}"
    local rhost="${3:?Remote host required}"
    local rport="${4:?Remote port required}"
    local remote_proto="${5:-${listen_proto}}"
    local capture="${6:-false}"
    local filter_opts="${7:-}"

    # Map protocols to socat address types
    local socat_listen socat_remote
    case "${listen_proto}" in
        tcp4) socat_listen="TCP4-LISTEN" ;;
        tcp6) socat_listen="TCP6-LISTEN" ;;
        udp4) socat_listen="UDP4-LISTEN" ;;
        udp6) socat_listen="UDP6-LISTEN" ;;
    esac
    case "${remote_proto}" in
        tcp4) socat_remote="TCP4" ;;
        tcp6) socat_remote="TCP6" ;;
        udp4) socat_remote="UDP4" ;;
        udp6) socat_remote="UDP6" ;;
    esac

    # Capture mode: add -v for verbose hex dump on stderr
    local verbose_flag=""
    if [[ "${capture}" == true ]]; then
        verbose_flag="-v -x"
    fi

    # Forwarding is bidirectional (no -u flag):
    #   Left side:  Listener accepting connections
    #   Right side: Connector to remote target
    local listen_opts="reuseaddr,fork"
    if [[ "${listen_proto}" == tcp* ]]; then
        listen_opts+=",backlog=${DEFAULT_BACKLOG}"
    fi

    listen_opts+="${filter_opts}"
    echo "socat ${verbose_flag} ${socat_listen}:${lport},${listen_opts} $(format_socat_endpoint "${socat_remote}" "${rhost}" "${rport}")"
}

# Function: build_socat_tunnel_cmd
# Description: Build a socat command for an encrypted (OpenSSL) tunnel.
#              Accepts TLS connections on a local port and forwards
#              plaintext traffic to a remote target. When capture mode
#              is enabled, socat's -v -x flags add a text-readable hex + ASCII dump
#              on stderr showing the decrypted traffic in both directions.
# Parameters:
#   $1 - Local port to listen on (encrypted endpoint)
#   $2 - Remote host to tunnel to
#   $3 - Remote port to tunnel to
#   $4 - Certificate PEM file path
#   $5 - Key PEM file path
#   $6 - Capture mode enabled (true/false, default: false)
#   $7 - Remote protocol family for the plaintext leg (tcp4/tcp6,
#        default: tcp4). Lets an IPv6 remote target be reached over TCP6
#        instead of being forced onto TCP4.
# Outputs: The constructed socat command string
build_socat_tunnel_cmd() {
    local lport="${1:?Local port required}"
    local rhost="${2:?Remote host required}"
    local rport="${3:?Remote port required}"
    local cert="${4:?Certificate required}"
    local key="${5:?Key required}"
    local capture="${6:-false}"
    local remote_proto="${7:-tcp4}"
    local filter_opts="${8:-}"

    # Capture mode: add -v for verbose hex dump on stderr
    # For tunnels, this captures the DECRYPTED traffic between
    # the TLS termination point and the remote target.
    local verbose_flag=""
    if [[ "${capture}" == true ]]; then
        verbose_flag="-v -x"
    fi

    # Map the remote leg to a socat TCP address type. Tunnels are TLS/TCP
    # only; UDP is rejected earlier by the mode parser.
    local socat_remote
    case "${remote_proto}" in
        tcp6) socat_remote="TCP6" ;;
        *)    socat_remote="TCP4" ;;
    esac

    # OpenSSL listener accepts encrypted connections and forwards
    # plaintext to the remote target:
    #   OPENSSL-LISTEN - Accept TLS/SSL connections
    #   cert/key       - Server certificate and private key
    #   verify=0       - Don't verify client certificates (server mode)
    #   fork           - Handle multiple connections
    #   reuseaddr      - Allow rebinding immediately after close
    echo "socat ${verbose_flag} OPENSSL-LISTEN:${lport},cert=${cert},key=${key},verify=0,reuseaddr,fork${filter_opts} $(format_socat_endpoint "${socat_remote}" "${rhost}" "${rport}")"
}

# Function: build_socat_redirect_cmd
# Description: Build a socat command for transparent traffic redirection.
#              Bidirectional forwarding with optional traffic logging.
#              Protocol-aware: supports TCP and UDP independently.
# Parameters:
#   $1 - Protocol (tcp4, tcp6, udp4, udp6)
#   $2 - Local port to listen on
#   $3 - Remote host to redirect to
#   $4 - Remote port to redirect to
#   $5 - Enable capture mode (true/false)
# Outputs: The constructed socat command string
build_socat_redirect_cmd() {
    local proto="${1:?Protocol required}"
    local lport="${2:?Local port required}"
    local rhost="${3:?Remote host required}"
    local rport="${4:?Remote port required}"
    local capture="${5:-false}"
    local filter_opts="${6:-}"

    # Map protocol to socat address types
    local socat_listen socat_remote
    case "${proto}" in
        tcp4) socat_listen="TCP4-LISTEN"; socat_remote="TCP4" ;;
        tcp6) socat_listen="TCP6-LISTEN"; socat_remote="TCP6" ;;
        udp4) socat_listen="UDP4-LISTEN"; socat_remote="UDP4" ;;
        udp6) socat_listen="UDP6-LISTEN"; socat_remote="UDP6" ;;
    esac

    # If capture is enabled, use socat's -v (verbose) mode to
    # capture traffic hex dumps to stderr (redirected to log by launcher)
    local verbose_flag=""
    if [[ "${capture}" == true ]]; then
        verbose_flag="-v -x"
    fi

    # Build listener options
    local listen_opts="reuseaddr,fork"
    if [[ "${proto}" == tcp* ]]; then
        listen_opts+=",backlog=${DEFAULT_BACKLOG}"
    fi

    listen_opts+="${filter_opts}"
    echo "socat ${verbose_flag} ${socat_listen}:${lport},${listen_opts} $(format_socat_endpoint "${socat_remote}" "${rhost}" "${rport}")"
}

