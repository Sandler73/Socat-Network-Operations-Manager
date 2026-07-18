#======================================================================
# PORT UTILITIES
# Functions for checking port availability and protocol alternation.
# Port checks are protocol-aware to prevent cross-protocol interference
# during stop operations on dual-stack configurations.
#======================================================================

# Function: check_port_available
# Description: Check if a port is available for binding on a specific
#              protocol. Uses ss (preferred) or netstat to detect
#              existing listeners. Only checks the specified protocol,
#              not both TCP and UDP.
# Parameters:
#   $1 - Port number
#   $2 - Protocol (tcp4, udp4, etc.)
# Returns: 0 if available, 1 if in use
check_port_available() {
    local port="${1:?Port required}"
    local proto="${2:-tcp4}"

    # Determine if checking TCP or UDP
    local check_type="tcp"
    [[ "${proto}" == *"udp"* ]] && check_type="udp"

    # Try ss first (preferred, modern), fall back to netstat
    if command -v ss &>/dev/null; then
        local ss_flag="-tln"
        [[ "${check_type}" == "udp" ]] && ss_flag="-uln"

        if ss "${ss_flag}" 2>/dev/null | grep -qE ":${port}\b"; then
            return 1  # Port in use
        fi
    elif command -v netstat &>/dev/null; then
        # netstat: -t for TCP, -u for UDP
        local netstat_flag="-tln"
        [[ "${check_type}" == "udp" ]] && netstat_flag="-uln"

        if netstat "${netstat_flag}" 2>/dev/null | grep -qE ":${port}\b"; then
            return 1  # Port in use
        fi
    else
        # No tool available; warn and proceed
        log_warning "Neither ss nor netstat available; cannot check port ${port}" "port-check"
    fi

    return 0  # Port available
}

# Function: check_port_freed
# Description: Verify that a port has been released after stopping a session.
#              Retries multiple times with a delay to account for TIME_WAIT.
#              Protocol-aware: only checks the specified protocol.
# Parameters:
#   $1 - Port number
#   $2 - Protocol to check (tcp4, udp4, etc.)
#   $3 - Max retries (default: STOP_VERIFY_RETRIES)
# Returns: 0 if freed, 1 if still in use
check_port_freed() {
    local port="${1:?Port required}"
    local proto="${2:-tcp4}"
    local max_retries="${3:-${STOP_VERIFY_RETRIES}}"
    local attempt=0

    while (( attempt < max_retries )); do
        if check_port_available "${port}" "${proto}"; then
            return 0
        fi
        sleep "${STOP_VERIFY_INTERVAL}"
        ((attempt++)) || true
    done

    return 1  # Port still in use
}

# Function: get_alt_protocol
# Description: Return the alternate protocol for dual-stack operations.
#              Maps TCP→UDP and UDP→TCP within the same address family.
# Parameters:
#   $1 - Protocol (tcp4, tcp6, udp4, udp6)
# Outputs: The alternate protocol string
get_alt_protocol() {
    local proto="${1:?Protocol required}"
    case "${proto}" in
        tcp4) echo "udp4" ;;
        tcp6) echo "udp6" ;;
        udp4) echo "tcp4" ;;
        udp6) echo "tcp6" ;;
        *)    echo "" ;;
    esac
}

