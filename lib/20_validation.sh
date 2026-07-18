#======================================================================
# INPUT VALIDATION
# Whitelist-based validation following OWASP/CWE-20 standards
# Validates ports, IPs, hostnames, protocols, file paths, and
# session IDs. All validators return 0 on success, 1 on failure.
#======================================================================

# Function: validate_port
# Description: Validate that a value is a valid port number (1-65535).
#              Warns if port is privileged (<1024) and not running as root.
# Parameters:
#   $1 - Port number to validate
# Returns: 0 on success, 1 on failure
validate_port() {
    local port="${1:-}"

    # Must be a positive integer
    if ! [[ "${port}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid port '${port}': must be a number" "validation"
        return 1
    fi

    # Must be in valid range
    if (( port < 1 || port > 65535 )); then
        log_error "Port ${port} out of range (1-65535)" "validation"
        return 1
    fi

    # Warn if privileged port and not root
    if (( port < 1024 )) && [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log_warning "Port ${port} is privileged (<1024); root/sudo required" "validation"
    fi

    return 0
}

# Function: validate_port_range
# Description: Validate a port range string (e.g., "8000-8010").
#              Echoes each port on a separate line for consumption.
#              Enforces a maximum span of 1000 ports to prevent
#              accidental resource exhaustion.
# Parameters:
#   $1 - Port range string (format: START-END)
# Outputs: One port number per line
# Returns: 0 on success, 1 on failure
validate_port_range() {
    local range="${1:-}"

    if ! [[ "${range}" =~ ^[0-9]+-[0-9]+$ ]]; then
        log_error "Invalid port range '${range}': use format START-END" "validation"
        return 1
    fi

    local start="${range%-*}"
    local end="${range#*-}"

    if ! validate_port "${start}" || ! validate_port "${end}"; then
        return 1
    fi

    if (( start > end )); then
        log_error "Range start (${start}) must not exceed end (${end})" "validation"
        return 1
    fi

    # Sanity check: don't allow absurdly large ranges
    local span=$(( end - start + 1 ))
    if (( span > 1000 )); then
        log_error "Port range too large (${span} ports). Max 1000." "validation"
        return 1
    fi

    for (( p = start; p <= end; p++ )); do
        echo "${p}"
    done
}

# Function: validate_port_list
# Description: Validate a comma-separated port list (e.g., "21,22,80,443").
#              Echoes each valid port on a separate line. Sanitizes input
#              by removing spaces and replacing semicolons with commas.
# Parameters:
#   $1 - Comma-separated port list
# Outputs: One valid port number per line
# Returns: 0 if at least one valid port found, 1 otherwise
validate_port_list() {
    local list="${1:-}"

    # Sanitize: remove spaces, replace semicolons with commas
    list="${list// /}"
    list="${list//;/,}"

    IFS=',' read -ra ports <<< "${list}"
    local valid_count=0

    for port in "${ports[@]}"; do
        [[ -z "${port}" ]] && continue
        if validate_port "${port}"; then
            echo "${port}"
            ((valid_count++)) || true
        fi
    done

    if (( valid_count == 0 )); then
        log_error "No valid ports found in list '${list}'" "validation"
        return 1
    fi
}

# Function: validate_hostname
# Description: Validate a hostname or IP address for use as a target.
#              Accepts IPv4, IPv6, or RFC 1123-compliant hostnames.
#              Blocks shell metacharacters to prevent command injection.
# Parameters:
#   $1 - Hostname or IP to validate
# Returns: 0 on success, 1 on failure
validate_hostname() {
    local host="${1:-}"

    # Empty check
    if [[ -z "${host}" ]]; then
        log_error "Empty hostname/IP provided" "validation"
        return 1
    fi

    # Sanitize: strip dangerous characters (command injection prevention)
    if [[ "${host}" =~ [\;\|\&\$\`\(\)\{\}\[\]\<\>\!\#] ]]; then
        log_error "Hostname contains forbidden characters: '${host}'" "validation"
        return 1
    fi

    # IPv4 validation (four octets, each 0-255)
    if [[ "${host}" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra octets <<< "${host}"
        for octet in "${octets[@]}"; do
            if (( octet > 255 )); then
                log_error "Invalid IPv4 address: ${host} (octet ${octet} > 255)" "validation"
                return 1
            fi
        done
        return 0
    fi

    # IPv6 validation (standard and :: compressed forms).
    if [[ "${host}" == *:* ]] && [[ "${host}" =~ ^[0-9a-fA-F:]+$ ]]; then
        # No run of three or more colons.
        if [[ "${host}" == *":::"* ]]; then
            log_error "Invalid IPv6 address: '${host}' (':::' is not allowed)" "validation"
            return 1
        fi
        # At most one '::' compression. Remove the first '::'; a remaining '::'
        # means there were two, which is invalid.
        local _has_compress=0
        if [[ "${host}" == *"::"* ]]; then
            _has_compress=1
            local _stripped="${host/::/}"
            if [[ "${_stripped}" == *"::"* ]]; then
                log_error "Invalid IPv6 address: '${host}' (multiple '::')" "validation"
                return 1
            fi
        fi
        # Each non-empty group must be 1-4 hex digits; count real groups.
        local -a _groups
        IFS=':' read -ra _groups <<< "${host}"
        local _g _count=0
        for _g in "${_groups[@]}"; do
            [[ -z "${_g}" ]] && continue
            if ! [[ "${_g}" =~ ^[0-9a-fA-F]{1,4}$ ]]; then
                log_error "Invalid IPv6 address: '${host}' (bad group '${_g}')" "validation"
                return 1
            fi
            ((_count++)) || true
        done
        # Group-count rules: exactly 8 without compression; 1-7 with '::'
        # (a bare '::' yields 0 real groups and is valid).
        if (( _has_compress )); then
            if (( _count > 7 )); then
                log_error "Invalid IPv6 address: '${host}' (too many groups)" "validation"
                return 1
            fi
        else
            if (( _count != 8 )); then
                log_error "Invalid IPv6 address: '${host}' (expected 8 groups, got ${_count})" "validation"
                return 1
            fi
        fi
        return 0
    fi

    # Hostname validation (RFC 1123). Total length is capped at 253 characters;
    # each label is capped at 63 by the pattern below.
    if (( ${#host} > 253 )); then
        log_error "Hostname too long (${#host} chars, max 253): '${host}'" "validation"
        return 1
    fi
    if [[ "${host}" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    fi

    log_error "Invalid hostname/IP: '${host}'" "validation"
    return 1
}

# Function: validate_protocol
# Description: Validate and normalize the protocol string.
#              Accepts shorthand (tcp, udp) and explicit forms (tcp4, tcp6, etc.).
#              Returns the normalized protocol string on stdout.
# Parameters:
#   $1 - Protocol string (tcp, tcp4, tcp6, udp, udp4, udp6)
# Outputs: Normalized protocol string (tcp4, tcp6, udp4, udp6)
# Returns: 0 on success, 1 on failure
validate_protocol() {
    local proto="${1:-tcp}"
    proto="${proto,,}"  # lowercase

    case "${proto}" in
        tcp|tcp4)   echo "tcp4" ;;
        tcp6)       echo "tcp6" ;;
        udp|udp4)   echo "udp4" ;;
        udp6)       echo "udp6" ;;
        *)
            log_error "Invalid protocol '${proto}'. Supported: tcp, tcp4, tcp6, udp, udp4, udp6" "validation"
            return 1
            ;;
    esac
}

# Function: validate_file_path
# Description: Validate a file path is safe. Blocks path traversal
#              (../) and shell metacharacters to prevent injection.
# Parameters:
#   $1 - File path to validate
# Returns: 0 on success, 1 on failure
validate_file_path() {
    local path="${1:-}"

    if [[ -z "${path}" ]]; then
        log_error "Empty file path" "validation"
        return 1
    fi

    # Block path traversal
    if [[ "${path}" == *".."* ]]; then
        log_error "Path traversal detected in '${path}'" "validation"
        return 1
    fi

    # Block command injection characters in paths
    if [[ "${path}" =~ [\;\|\&\$\`] ]]; then
        log_error "Forbidden characters in path '${path}'" "validation"
        return 1
    fi

    return 0
}


# Function: validate_socat_opts
# Description: Validate user-provided socat address options. Two passes:
#              (1) a character whitelist that blocks shell metacharacters
#              (defence in depth), and (2) a per-option keyword allowlist so
#              only known-safe socat address options are accepted. Options that
#              can spawn programs or shells (exec, system, shell) are absent from
#              the allowlist and therefore rejected, as is any unknown keyword.
#              These options are appended to a socat address (LISTEN:port,<opts>).
# Parameters:
#   $1 - socat options string to validate (comma-separated)
# Returns: 0 if safe, 1 otherwise
validate_socat_opts() {
    local opts="${1:-}"

    if [[ -z "${opts}" ]]; then
        return 0  # Empty is valid (no extra opts)
    fi

    # Pass 1 - character whitelist: alphanumeric, = , . : / _ -
    # Rejects shell metacharacters, whitespace, and redirection characters.
    if [[ "${opts}" =~ [^a-zA-Z0-9=,.:/_-] ]]; then
        log_error "Forbidden characters in socat options '${opts}'. Allowed: alphanumeric, = , . : / _ -" "validation"
        return 1
    fi

    # Pass 2 - keyword allowlist. Space-padded lists allow a simple containment
    # test. Bare flags take no value; key=value options are matched on the key.
    # Underscores in keys are normalised to hyphens for lookup.
    local allowed_bare=" reuseaddr reuseport fork keepalive so-keepalive nodelay tcp-nodelay nonblock cork broadcast ignoreeof crnl rawer cool-write end-close dontroute o-nonblock "
    local allowed_kv=" bind backlog keepidle tcp-keepidle keepintvl tcp-keepintvl keepcnt tcp-keepcnt mss tos ttl pf rcvbuf sndbuf rcvbuf-late sndbuf-late rcvtimeo sndtimeo retry interval connect-timeout mode perm user group uid gid range cert key cafile capath verify cipher method dhparam su setuid setgid "

    local -a tokens
    IFS=',' read -ra tokens <<< "${opts}"

    local token key
    for token in "${tokens[@]}"; do
        [[ -z "${token}" ]] && continue
        if [[ "${token}" == *=* ]]; then
            key="${token%%=*}"
            key="${key//_/-}"
            if [[ "${allowed_kv}" != *" ${key} "* ]]; then
                log_error "Unsupported socat option '${key}' in --socat-opts (not in allowlist)" "validation"
                return 1
            fi
        else
            key="${token//_/-}"
            if [[ "${allowed_bare}" != *" ${key} "* ]]; then
                log_error "Unsupported socat option '${key}' in --socat-opts (not in allowlist)" "validation"
                return 1
            fi
        fi
    done

    return 0
}

# Function: _expand_ipv6
# Description: Expand a (validated) IPv6 address to eight colon-separated
#              hexadecimal groups, resolving any "::" compression. The input is
#              assumed to have already passed validate_hostname. Used by the
#              source-range masker so host bits can be cleared per group.
# Parameters:
#   $1 - IPv6 address (compressed or full)
# Outputs: Eight space-separated hex groups (e.g. "2001 db8 0 0 0 0 0 1")
# Returns: 0 on success, 1 if the address cannot be expanded to 8 groups
_expand_ipv6() {
    local addr="${1:?IPv6 address required}"
    local -a full=()

    if [[ "${addr}" == *"::"* ]]; then
        local lpart="${addr%%::*}" rpart="${addr##*::}"
        local -a left=() right=() l2=() r2=()
        [[ -n "${lpart}" ]] && IFS=':' read -ra left <<< "${lpart}"
        [[ -n "${rpart}" ]] && IFS=':' read -ra right <<< "${rpart}"
        local g
        for g in "${left[@]}";  do [[ -n "${g}" ]] && l2+=("${g}"); done
        for g in "${right[@]}"; do [[ -n "${g}" ]] && r2+=("${g}"); done
        local fill=$(( 8 - ${#l2[@]} - ${#r2[@]} ))
        (( fill < 0 )) && return 1
        full=("${l2[@]}")
        local i
        for (( i = 0; i < fill; i++ )); do full+=("0"); done
        full+=("${r2[@]}")
    else
        IFS=':' read -ra full <<< "${addr}"
    fi

    (( ${#full[@]} != 8 )) && return 1
    printf '%s\n' "${full[*]}"
    return 0
}

# Function: validate_source_range
# Description: Validate an IPv4 or IPv6 source range in CIDR notation and render
#              it in the form socat's address-level "range" option expects:
#              "network/prefix" for IPv4 and "[network]/prefix" for IPv6. Host
#              bits are permitted on input and masked off, so 10.1.2.3/8 and
#              10.0.0.0/8 both yield 10.0.0.0/8.
# Parameters:
#   $1 - Source range in CIDR notation (e.g. 10.0.0.0/8 or 2001:db8::/32)
# Outputs: The masked range value (without the "range=" prefix)
# Returns: 0 if valid, 1 otherwise
validate_source_range() {
    local cidr="${1:-}"
    # Trim surrounding whitespace.
    cidr="${cidr#"${cidr%%[![:space:]]*}"}"
    cidr="${cidr%"${cidr##*[![:space:]]}"}"

    if [[ "${cidr}" != */* ]]; then
        log_error "Invalid source range '${cidr}': expected CIDR notation (address/prefix)" "validation"
        return 1
    fi

    local addr="${cidr%/*}" prefix="${cidr##*/}"
    if ! [[ "${prefix}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid source range '${cidr}': non-numeric prefix" "validation"
        return 1
    fi

    # ---- IPv4 ----
    if [[ "${addr}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; then
        local -a oct
        IFS='.' read -ra oct <<< "${addr}"
        local o
        for o in "${oct[@]}"; do
            if (( o > 255 )); then
                log_error "Invalid source range '${cidr}': octet ${o} > 255" "validation"
                return 1
            fi
        done
        if (( prefix > 32 )); then
            log_error "Invalid source range '${cidr}': IPv4 prefix must be 0-32" "validation"
            return 1
        fi
        local ipnum=$(( (oct[0] << 24) | (oct[1] << 16) | (oct[2] << 8) | oct[3] ))
        local mask
        if (( prefix == 0 )); then
            mask=0
        else
            mask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
        fi
        local net=$(( ipnum & mask ))
        printf '%d.%d.%d.%d/%d\n' \
            $(( (net >> 24) & 255 )) $(( (net >> 16) & 255 )) \
            $(( (net >> 8) & 255 ))  $(( net & 255 )) "${prefix}"
        return 0
    fi

    # ---- IPv6 ----
    if [[ "${addr}" == *:* ]] && validate_hostname "${addr}" >/dev/null 2>&1; then
        if (( prefix > 128 )); then
            log_error "Invalid source range '${cidr}': IPv6 prefix must be 0-128" "validation"
            return 1
        fi
        local groups
        if ! groups="$(_expand_ipv6 "${addr}")"; then
            log_error "Invalid source range '${cidr}': malformed IPv6 network" "validation"
            return 1
        fi
        local -a grp
        read -ra grp <<< "${groups}"
        # Mask host bits group by group (each group covers 16 bits).
        local idx val gbits gmask
        for idx in "${!grp[@]}"; do
            val=$(( 16#${grp[idx]} ))
            local group_start=$(( idx * 16 ))
            if (( prefix >= group_start + 16 )); then
                :                                   # fully inside prefix: keep
            elif (( prefix <= group_start )); then
                val=0                               # fully outside prefix: zero
            else
                gbits=$(( prefix - group_start ))   # 1..15 bits retained
                gmask=$(( (0xFFFF << (16 - gbits)) & 0xFFFF ))
                val=$(( val & gmask ))
            fi
            grp[idx]=$(printf '%x' "${val}")
        done
        local masked
        masked="$(IFS=':'; echo "${grp[*]}")"
        printf '[%s]/%d\n' "${masked}" "${prefix}"
        return 0
    fi

    log_error "Invalid source range '${cidr}': expected IPv4 or IPv6 CIDR (e.g. 10.0.0.0/8, 2001:db8::/32)" "validation"
    return 1
}

# Function: validate_tcpwrap_name
# Description: Validate a TCP-wrappers daemon name for socat's tcpwrap= option.
#              The name is looked up in /etc/hosts.allow and /etc/hosts.deny and
#              is restricted to a short token so it cannot inject further socat
#              options or shell metacharacters.
# Parameters:
#   $1 - Daemon name
# Returns: 0 if valid, 1 otherwise
validate_tcpwrap_name() {
    local name="${1:-}"
    if [[ ! "${name}" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
        log_error "Invalid tcpwrap daemon name '${name}'. Allowed: 1-64 characters of alphanumerics and . _ -" "validation"
        return 1
    fi
    return 0
}

# Function: build_filter_opts
# Description: Assemble the listener source-filter option fragment from an
#              optional allow-range and an optional TCP-wrappers name. The result
#              is comma-prefixed so it can be appended directly to a listener's
#              option list (e.g. "reuseaddr,fork" + fragment). Empty when neither
#              filter is requested.
# Parameters:
#   $1 - Rendered range value (already validated), or empty
#   $2 - Validated tcpwrap daemon name, or empty
# Outputs: ",range=<value>[,tcpwrap=<name>]" or "" (empty)
build_filter_opts() {
    local range_value="${1:-}"
    local tcpwrap_name="${2:-}"
    local fragment=""
    [[ -n "${range_value}" ]] && fragment+=",range=${range_value}"
    [[ -n "${tcpwrap_name}" ]] && fragment+=",tcpwrap=${tcpwrap_name}"
    printf '%s' "${fragment}"
}

# Function: validate_session_name
# Description: Validate a user-provided session name for safety.
#              Allows only alphanumeric characters, hyphens, underscores,
#              and dots. Maximum length 64 characters. Prevents injection
#              into session files (SESSION_NAME=<value>) and log messages.
# Parameters:
#   $1 - Session name to validate
# Returns: 0 if valid, 1 if invalid
validate_session_name() {
    local name="${1:-}"

    if [[ -z "${name}" ]]; then
        log_error "Empty session name" "validation"
        return 1
    fi

    # Maximum length check
    if (( ${#name} > 64 )); then
        log_error "Session name too long (${#name} chars, max 64): '${name}'" "validation"
        return 1
    fi

    # Whitelist: alphanumeric, hyphens, underscores, dots
    if [[ "${name}" =~ [^a-zA-Z0-9._-] ]]; then
        log_error "Invalid characters in session name '${name}'. Allowed: alphanumeric, . _ -" "validation"
        return 1
    fi

    return 0
}

# Function: validate_session_id
# Description: Validate a session ID is a valid 8-character hex string.
#              Prevents injection via session ID parameters.
# Parameters:
#   $1 - Session ID to validate
# Returns: 0 if valid, 1 if invalid
validate_session_id() {
    local sid="${1:-}"

    if [[ -z "${sid}" ]]; then
        log_error "Empty session ID" "validation"
        return 1
    fi

    # Session IDs must be exactly 8 lowercase hex characters
    if ! [[ "${sid}" =~ ^[a-f0-9]{8}$ ]]; then
        log_error "Invalid session ID '${sid}': must be 8 hex characters" "validation"
        return 1
    fi

    return 0
}

