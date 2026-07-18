#======================================================================
# MODE: listen
# Start a single TCP or UDP listener on a specified port.
# Captures incoming data to a per-port log file.
# Supports --proto for protocol selection and --dual-stack for both.
# Supports --watchdog for auto-restart on crash.
#======================================================================

# Function: mode_listen
# Description: Parse listen-mode arguments and start a single listener.
#              Uses launch_socat_session for reliable process tracking.
#              When --dual-stack is specified, launches both TCP and UDP
#              listeners on the same port with independent session IDs.
# Parameters: All remaining CLI arguments after "listen"
mode_listen() {
    local port="" proto="${DEFAULT_PROTOCOL}" extra_opts=""
    local use_watchdog=false session_name="" logfile="" bind_addr=""
    local allow_cidr="" tcpwrap_name="" range_value="" filter_opts=""
    local dual_stack=false capture=false capture_logfile=""

    # Parse listen-specific arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -p|--port)       port="${2:?--port requires a value}"; shift 2 ;;
            --proto)         proto="${2:?--proto requires a value}"; shift 2 ;;
            --bind)          bind_addr="${2:?--bind requires a value}"; shift 2 ;;
            --name)          session_name="${2:?--name requires a value}"
                             validate_session_name "${session_name}" || exit 1
                             shift 2 ;;
            --logfile)       logfile="${2:?--logfile requires a value}"; shift 2 ;;
            --capture)       capture=true; shift ;;
            --watchdog)      use_watchdog=true; shift ;;
            --dual-stack)    dual_stack=true; shift ;;
            --socat-opts)    extra_opts="${2:?--socat-opts requires a value}"
                             validate_socat_opts "${extra_opts}" || exit 1
                             shift 2 ;;
            --allow)         allow_cidr="${2:?--allow requires a CIDR value}"
                             range_value="$(validate_source_range "${allow_cidr}")" || exit 1
                             shift 2 ;;
            --tcpwrap)       if [[ -n "${2:-}" && "${2}" != -* ]]; then
                                 tcpwrap_name="${2}"; shift 2
                             else
                                 tcpwrap_name="socat"; shift
                             fi
                             validate_tcpwrap_name "${tcpwrap_name}" || exit 1
                             ;;
            -v|--verbose)    VERBOSE_MODE=true; shift ;;
            -h|--help)       show_listen_help; exit 0 ;;
            *)               log_error "Unknown listen option: ${1}"; exit 1 ;;
        esac
    done

    # Validate required arguments
    if [[ -z "${port}" ]]; then
        log_error "Port is required. Use: ${SCRIPT_NAME} listen --port <PORT>"
        exit 1
    fi

    validate_port "${port}" || exit 1
    proto=$(validate_protocol "${proto}") || exit 1

    print_banner "Listener"

    # Check port availability for the primary protocol
    if ! check_port_available "${port}" "${proto}"; then
        log_error "Port ${port} (${proto}) is already in use"
        exit 1
    fi

    # Default session name: protocol-port
    [[ -z "${session_name}" ]] && session_name="${proto}-${port}"

    # Default log file: listener data capture
    [[ -z "${logfile}" ]] && logfile="${LOG_DIR}/listener-${proto}-${port}.log"

    # Construct bind address option if specified
    if [[ -n "${bind_addr}" ]]; then
        validate_hostname "${bind_addr}" || exit 1
        extra_opts="bind=${bind_addr}${extra_opts:+,${extra_opts}}"
    fi

    # Assemble listener source-filter options (range=, tcpwrap=)
    filter_opts="$(build_filter_opts "${range_value}" "${tcpwrap_name}")"

    # Build the socat command
    local cmd
    cmd=$(build_socat_listen_cmd "${proto}" "${port}" "${logfile}" "${extra_opts}" "${capture}" "${filter_opts}")

    # Capture mode: create the primary-listener capture log up front (0600) so
    # its path can be displayed and wired as the socat stderr target. Without
    # this, --capture output falls through to the session error log and no
    # capture file is produced.
    if [[ "${capture}" == true ]]; then
        capture_logfile="${LOG_DIR}/capture-${proto}-${port}-${EXEC_TIMESTAMP}.log"
        touch "${capture_logfile}" && chmod 600 "${capture_logfile}" 2>/dev/null || true
    fi

    # Display configuration
    print_section "Listener Configuration"
    print_kv "Port" "${port}"
    print_kv "Protocol" "${proto}${dual_stack:+ + $(get_alt_protocol "${proto}")}"
    print_kv "Session Name" "${session_name}"
    print_kv "Data Log (raw bytes)" "${logfile}"
    print_kv "Traffic Capture" "${capture}"
    [[ "${capture}" == true ]] && print_kv "Capture Log (hex+ASCII text)" "${capture_logfile}"
    print_kv "Watchdog" "${use_watchdog}"
    print_kv "Dual-Stack" "${dual_stack}"
    [[ -n "${bind_addr}" ]] && print_kv "Bind Address" "${bind_addr}"
    log_debug "Command: ${cmd}" "listen"

    # Launch the listener
    print_section "Starting Listener"

    # Primary protocol listener
    # Determine stderr redirect for capture mode
    local stderr_file=""
    [[ "${capture}" == true && -n "${capture_logfile}" ]] && stderr_file="${capture_logfile}"

    _launch_session "${use_watchdog}" "${session_name}" "listen" "${proto}" "${port}" "${cmd}" "" "" "${stderr_file}" || exit 1
    local primary_sid="${LAUNCH_SID}"

    log_success "Listener active on ${proto}:${port} (SID ${primary_sid})"

    # Dual-stack: also launch alternate protocol listener
    if [[ "${dual_stack}" == true ]]; then
        local alt_proto
        alt_proto="$(get_alt_protocol "${proto}")"
        local alt_name="${alt_proto}-${port}"
        local alt_logfile="${LOG_DIR}/listener-${alt_proto}-${port}.log"
        local alt_cmd
        alt_cmd=$(build_socat_listen_cmd "${alt_proto}" "${port}" "${alt_logfile}" "${extra_opts}" "${capture}" "${filter_opts}")

        if check_port_available "${port}" "${alt_proto}"; then
            local alt_capture_logfile=""
            [[ "${capture}" == true ]] && alt_capture_logfile="${LOG_DIR}/capture-${alt_proto}-${port}-${EXEC_TIMESTAMP}.log"
            [[ -n "${alt_capture_logfile}" ]] && { touch "${alt_capture_logfile}" && chmod 600 "${alt_capture_logfile}" 2>/dev/null || true; }
            local alt_stderr=""
            [[ "${capture}" == true && -n "${alt_capture_logfile}" ]] && alt_stderr="${alt_capture_logfile}"

            _launch_session "${use_watchdog}" "${alt_name}" "listen" "${alt_proto}" "${port}" "${alt_cmd}" "" "" "${alt_stderr}" || {
                log_warning "Dual-stack ${alt_proto} listener failed on port ${port}"
            }
            if [[ -n "${LAUNCH_SID}" ]]; then
                log_success "Listener active on ${alt_proto}:${port} (SID ${LAUNCH_SID})"
            fi
        else
            log_warning "Port ${port} (${alt_proto}) already in use - skipping dual-stack"
        fi
    fi

    log_info "Data captured to: ${logfile}"
    log_info "Stop with: ${SCRIPT_NAME} stop ${primary_sid}"
}

#======================================================================
# MODE: batch
# Start multiple listeners from a port list, range, or config file.
# Supports both TCP and UDP per port (dual-stack option).
# Each listener gets its own session ID for independent management.
#======================================================================

# Function: mode_batch
# Description: Parse batch-mode arguments and start multiple listeners.
#              Supports port lists, ranges, and config files. Each port
#              gets an independent session with unique session ID.
#              --dual-stack launches both TCP and UDP per port.
# Parameters: All remaining CLI arguments after "batch"
mode_batch() {
    local ports_arg="" range_arg="" config_arg="" proto="${DEFAULT_PROTOCOL}"
    local dual_stack=false use_watchdog=false capture=false
    local allow_cidr="" tcpwrap_name="" range_value="" filter_opts=""

    # Parse batch-specific arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --ports)         ports_arg="${2:?--ports requires a value}"; shift 2 ;;
            --range)         range_arg="${2:?--range requires a value}"; shift 2 ;;
            --config)        config_arg="${2:?--config requires a value}"; shift 2 ;;
            --proto)         proto="${2:?--proto requires a value}"; shift 2 ;;
            --dual-stack)    dual_stack=true; shift ;;
            --watchdog)      use_watchdog=true; shift ;;
            --capture)       capture=true; shift ;;
            --allow)         allow_cidr="${2:?--allow requires a CIDR value}"
                             range_value="$(validate_source_range "${allow_cidr}")" || exit 1
                             shift 2 ;;
            --tcpwrap)       if [[ -n "${2:-}" && "${2}" != -* ]]; then
                                 tcpwrap_name="${2}"; shift 2
                             else
                                 tcpwrap_name="socat"; shift
                             fi
                             validate_tcpwrap_name "${tcpwrap_name}" || exit 1
                             ;;
            -v|--verbose)    VERBOSE_MODE=true; shift ;;
            -h|--help)       show_batch_help; exit 0 ;;
            *)               log_error "Unknown batch option: ${1}"; exit 1 ;;
        esac
    done

    # Assemble listener source-filter options once (constant across all ports)
    filter_opts="$(build_filter_opts "${range_value}" "${tcpwrap_name}")"

    # At least one port source is required
    if [[ -z "${ports_arg}" && -z "${range_arg}" && -z "${config_arg}" ]]; then
        log_error "Specify ports with --ports, --range, or --config"
        exit 1
    fi

    proto=$(validate_protocol "${proto}") || exit 1

    print_banner "Batch Listener"

    # Collect all ports into an array from the three possible sources
    local -a all_ports=()

    # From comma-separated list
    if [[ -n "${ports_arg}" ]]; then
        while IFS= read -r p; do
            all_ports+=("${p}")
        done < <(validate_port_list "${ports_arg}")
    fi

    # From range
    if [[ -n "${range_arg}" ]]; then
        while IFS= read -r p; do
            all_ports+=("${p}")
        done < <(validate_port_range "${range_arg}")
    fi

    # From config file (one port per line, # comments, blank lines ignored)
    if [[ -n "${config_arg}" ]]; then
        validate_file_path "${config_arg}" || exit 1
        if [[ ! -f "${config_arg}" ]]; then
            log_error "Config file not found: ${config_arg}"; exit 1
        fi
        while IFS= read -r line; do
            # Strip comments and whitespace
            line="${line%%#*}"
            line="${line// /}"
            [[ -z "${line}" ]] && continue
            if validate_port "${line}" 2>/dev/null; then
                all_ports+=("${line}")
            fi
        done < "${config_arg}"
    fi

    # Deduplicate ports (preserve order)
    local -a unique_ports=()
    local -A seen_ports=()
    for p in "${all_ports[@]}"; do
        if [[ -z "${seen_ports[${p}]+x}" ]]; then
            unique_ports+=("${p}")
            seen_ports[${p}]=1
        fi
    done

    if (( ${#unique_ports[@]} == 0 )); then
        log_error "No valid ports to listen on"; exit 1
    fi

    print_section "Batch Configuration"
    print_kv "Port Count" "${#unique_ports[@]}"
    print_kv "Protocol" "${proto}${dual_stack:+ + $(get_alt_protocol "${proto}")}"
    print_kv "Traffic Capture" "${capture}"
    print_kv "Watchdog" "${use_watchdog}"
    print_kv "Ports" "$(echo "${unique_ports[*]}" | tr ' ' ',')"

    # Launch listeners
    print_section "Starting Listeners"

    local started=0 failed=0

    for port in "${unique_ports[@]}"; do
        # --- Primary protocol listener ---
        local session_name="${proto}-${port}"
        local logfile="${LOG_DIR}/listener-${proto}-${port}.log"

        # Skip if port is in use
        if ! check_port_available "${port}" "${proto}"; then
            log_warning "Port ${port} (${proto}) in use - skipping"
            ((failed++)) || true
            continue
        fi

        # Set up capture stderr redirect for this port
        local capture_logfile=""
        local stderr_file=""
        if [[ "${capture}" == true ]]; then
            capture_logfile="${LOG_DIR}/capture-${proto}-${port}-${EXEC_TIMESTAMP}.log"
            touch "${capture_logfile}" && chmod 600 "${capture_logfile}" 2>/dev/null || true
            stderr_file="${capture_logfile}"
        fi

        local cmd
        cmd=$(build_socat_listen_cmd "${proto}" "${port}" "${logfile}" "" "${capture}" "${filter_opts}")

        _launch_session "${use_watchdog}" "${session_name}" "batch-listen" "${proto}" "${port}" "${cmd}" "" "" "${stderr_file}" || {
            ((failed++)) || true
            continue
        }
        ((started++)) || true
        log_debug "Started ${proto}:${port} (SID ${LAUNCH_SID})" "batch"

        # --- Dual-stack: also start alternate protocol ---
        if [[ "${dual_stack}" == true ]]; then
            local alt_proto
            alt_proto="$(get_alt_protocol "${proto}")"
            local alt_session="${alt_proto}-${port}"
            local alt_logfile="${LOG_DIR}/listener-${alt_proto}-${port}.log"

            if check_port_available "${port}" "${alt_proto}"; then
                local alt_capture_logfile=""
                local alt_stderr=""
                if [[ "${capture}" == true ]]; then
                    alt_capture_logfile="${LOG_DIR}/capture-${alt_proto}-${port}-${EXEC_TIMESTAMP}.log"
                    touch "${alt_capture_logfile}" && chmod 600 "${alt_capture_logfile}" 2>/dev/null || true
                    alt_stderr="${alt_capture_logfile}"
                fi
                local alt_cmd
                alt_cmd=$(build_socat_listen_cmd "${alt_proto}" "${port}" "${alt_logfile}" "" "${capture}" "${filter_opts}")
                _launch_session "${use_watchdog}" "${alt_session}" "batch-listen" "${alt_proto}" "${port}" "${alt_cmd}" "" "" "${alt_stderr}" || {
                    continue
                }
                ((started++)) || true
                log_debug "Started ${alt_proto}:${port} (SID ${LAUNCH_SID})" "batch"
            fi
        fi
    done

    # Brief settle time for binding
    sleep 0.3

    echo "" >&2
    log_success "Batch complete: ${started} listeners started, ${failed} skipped"
    log_info "Data logs in: ${LOG_DIR}/"
    log_info "Stop all with: ${SCRIPT_NAME} stop --all"
}

#======================================================================
# MODE: forward
# Forward connections from a local port to a remote host:port.
# Bidirectional by default (full proxy). Supports TCP and UDP.
# --proto selects individual protocol; --dual-stack launches both.
#======================================================================

# Function: mode_forward
# Description: Parse forward-mode arguments and set up port forwarding.
#              Uses launch_socat_session for reliable process tracking.
#              Supports --proto for individual protocol and --dual-stack
#              for both TCP and UDP simultaneously.
# Parameters: All remaining CLI arguments after "forward"
mode_forward() {
    local lport="" rhost="" rport="" proto="${DEFAULT_PROTOCOL}" remote_proto=""
    local use_watchdog=false session_name="" dual_stack=false
    local capture=false capture_logfile=""
    local allow_cidr="" tcpwrap_name="" range_value="" filter_opts=""

    # Parse forward-specific arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --lport)         lport="${2:?--lport requires a value}"; shift 2 ;;
            --rhost)         rhost="${2:?--rhost requires a value}"; shift 2 ;;
            --rport)         rport="${2:?--rport requires a value}"; shift 2 ;;
            --proto)         proto="${2:?--proto requires a value}"; shift 2 ;;
            --remote-proto)  remote_proto="${2:?--remote-proto requires a value}"; shift 2 ;;
            --name)          session_name="${2:?--name requires a value}"
                             validate_session_name "${session_name}" || exit 1
                             shift 2 ;;
            --watchdog)      use_watchdog=true; shift ;;
            --dual-stack)    dual_stack=true; shift ;;
            --capture)       capture=true; shift ;;
            --logfile)       capture_logfile="${2:?--logfile requires a value}"; shift 2 ;;
            -v|--verbose)    VERBOSE_MODE=true; shift ;;
            --allow)         allow_cidr="${2:?--allow requires a CIDR value}"
                             range_value="$(validate_source_range "${allow_cidr}")" || exit 1
                             shift 2 ;;
            --tcpwrap)       if [[ -n "${2:-}" && "${2}" != -* ]]; then
                                 tcpwrap_name="${2}"; shift 2
                             else
                                 tcpwrap_name="socat"; shift
                             fi
                             validate_tcpwrap_name "${tcpwrap_name}" || exit 1
                             ;;
            -h|--help)       show_forward_help; exit 0 ;;
            *)               log_error "Unknown forward option: ${1}"; exit 1 ;;
        esac
    done

    # Validate required arguments
    [[ -z "${lport}" ]] && { log_error "--lport is required"; exit 1; }
    [[ -z "${rhost}" ]] && { log_error "--rhost is required"; exit 1; }
    [[ -z "${rport}" ]] && { log_error "--rport is required"; exit 1; }

    validate_port "${lport}" || exit 1
    validate_port "${rport}" || exit 1
    validate_hostname "${rhost}" || exit 1
    proto=$(validate_protocol "${proto}") || exit 1

    # Default remote protocol matches listen protocol
    if [[ -n "${remote_proto}" ]]; then
        remote_proto=$(validate_protocol "${remote_proto}") || exit 1
    else
        remote_proto="${proto}"
    fi

    print_banner "Forwarder"

    # Check port availability for primary protocol
    if ! check_port_available "${lport}" "${proto}"; then
        log_error "Local port ${lport} (${proto}) is already in use"
        exit 1
    fi

    # Default session name
    [[ -z "${session_name}" ]] && session_name="fwd-${lport}-${rhost}-${rport}"

    # Build command
    local cmd
    filter_opts="$(build_filter_opts "${range_value}" "${tcpwrap_name}")"
    cmd=$(build_socat_forward_cmd "${proto}" "${lport}" "${rhost}" "${rport}" "${remote_proto}" "${capture}" "${filter_opts}")

    # Set up capture log if --capture is enabled. A user-supplied --logfile
    # overrides the auto-generated path; otherwise a per-session path is used.
    if [[ "${capture}" == true ]]; then
        [[ -z "${capture_logfile}" ]] && capture_logfile="${LOG_DIR}/capture-${proto}-${lport}-${rhost}-${rport}-${EXEC_TIMESTAMP}.log"
        touch "${capture_logfile}" && chmod 600 "${capture_logfile}" 2>/dev/null || true
    fi

    # Display configuration
    print_section "Forward Configuration"
    print_kv "Local Port" "${lport} (${proto})"
    print_kv "Remote Target" "${rhost}:${rport} (${remote_proto})"
    print_kv "Direction" "Bidirectional"
    print_kv "Session Name" "${session_name}"
    print_kv "Traffic Capture" "${capture}"
    [[ "${capture}" == true ]] && print_kv "Capture Log" "${capture_logfile}"
    print_kv "Dual-Stack" "${dual_stack}"
    print_kv "Watchdog" "${use_watchdog}"
    log_debug "Command: ${cmd}" "forward"

    # Launch
    print_section "Starting Forwarder"

    # Determine stderr redirect for capture mode
    local stderr_file=""
    [[ "${capture}" == true && -n "${capture_logfile}" ]] && stderr_file="${capture_logfile}"

    _launch_session "${use_watchdog}" "${session_name}" "forward" "${proto}" "${lport}" \
        "${cmd}" "${rhost}" "${rport}" "${stderr_file}" || exit 1
    local primary_sid="${LAUNCH_SID}"

    log_success "Forwarder active: ${proto}:${lport} ${SYM_FORWARD} ${rhost}:${rport} (SID ${primary_sid})"

    # Dual-stack: also launch alternate protocol forwarder
    if [[ "${dual_stack}" == true ]]; then
        local alt_proto alt_remote_proto
        alt_proto="$(get_alt_protocol "${proto}")"
        alt_remote_proto="$(get_alt_protocol "${remote_proto}")"
        local alt_name="fwd-${alt_proto}-${lport}-${rhost}-${rport}"
        local alt_cmd
        alt_cmd=$(build_socat_forward_cmd "${alt_proto}" "${lport}" "${rhost}" "${rport}" "${alt_remote_proto}" "${capture}" "${filter_opts}")
            local alt_capture_logfile=""
            local alt_stderr=""
            if [[ "${capture}" == true ]]; then
                alt_capture_logfile="${LOG_DIR}/capture-${alt_proto}-${lport}-${rhost}-${rport}-${EXEC_TIMESTAMP}.log"
                touch "${alt_capture_logfile}" && chmod 600 "${alt_capture_logfile}" 2>/dev/null || true
                alt_stderr="${alt_capture_logfile}"
            fi

        if check_port_available "${lport}" "${alt_proto}"; then
            _launch_session "${use_watchdog}" "${alt_name}" "forward" "${alt_proto}" "${lport}" \
                "${alt_cmd}" "${rhost}" "${rport}" "${alt_stderr}" || {
                log_warning "Dual-stack ${alt_proto} forwarder failed on port ${lport}"
            }
            if [[ -n "${LAUNCH_SID}" ]]; then
                log_success "Forwarder active: ${alt_proto}:${lport} ${SYM_FORWARD} ${rhost}:${rport} (SID ${LAUNCH_SID})"
            fi
        else
            log_warning "Port ${lport} (${alt_proto}) already in use - skipping dual-stack"
        fi
    fi

    log_info "Stop with: ${SCRIPT_NAME} stop ${primary_sid}"
}

#======================================================================
# MODE: tunnel
# Create an encrypted (OpenSSL/TLS) tunnel via socat.
# Accepts TLS connections on a local port and forwards plaintext
# to a remote target. Auto-generates self-signed certs if needed.
# --dual-stack adds a plaintext UDP forwarder (TLS is TCP-only).
#======================================================================

# Function: mode_tunnel
# Description: Parse tunnel-mode arguments and create an encrypted tunnel.
#              Uses launch_socat_session for reliable process tracking.
#              TLS tunnels are inherently TCP-only. When --dual-stack is
#              specified, a plaintext UDP forwarder is added on the same
#              port with a warning that UDP traffic is NOT encrypted.
# Parameters: All remaining CLI arguments after "tunnel"
mode_tunnel() {
    local lport="" rhost="" rport="" cert="" key=""
    local use_watchdog=false session_name="" cn="localhost" dual_stack=false
    local capture=false capture_logfile=""
    local remote_proto="tcp4"
    local key_type="rsa"
    local allow_cidr="" tcpwrap_name="" range_value="" filter_opts=""

    # Parse tunnel-specific arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -p|--port)       lport="${2:?--port requires a value}"; shift 2 ;;
            --rhost)         rhost="${2:?--rhost requires a value}"; shift 2 ;;
            --rport)         rport="${2:?--rport requires a value}"; shift 2 ;;
            --cert)          cert="${2:?--cert requires a value}"; shift 2 ;;
            --key)           key="${2:?--key requires a value}"; shift 2 ;;
            --cn)            cn="${2:?--cn requires a value}"; shift 2 ;;
            --key-type)      key_type="${2:?--key-type requires a value}"
                             key_type="${key_type,,}"
                             if [[ "${key_type}" != "rsa" && "${key_type}" != "ec" ]]; then
                                 log_error "Invalid --key-type: ${key_type} (use rsa or ec)"; exit 1
                             fi
                             shift 2 ;;
            --name)          session_name="${2:?--name requires a value}"
                             validate_session_name "${session_name}" || exit 1
                             shift 2 ;;
            --watchdog)      use_watchdog=true; shift ;;
            --dual-stack)    dual_stack=true; shift ;;
            --proto)         
                # TLS tunnels are TCP-only. Accept --proto for the remote leg
                # family (TCP4/TCP6) and reject UDP with guidance.
                local tunnel_proto="${2:?--proto requires a value}"
                tunnel_proto="${tunnel_proto,,}"
                case "${tunnel_proto}" in
                    tcp|tcp4) remote_proto="tcp4" ;;
                    tcp6)     remote_proto="tcp6" ;;
                    udp|udp4|udp6)
                        log_error "TLS tunnels require TCP. UDP is not supported for encrypted tunnels."
                        log_info "For UDP forwarding, use: ${SCRIPT_NAME} forward --proto udp4 --lport <PORT> --rhost <HOST> --rport <PORT>"
                        exit 1
                        ;;
                    *) log_error "Invalid protocol: ${tunnel_proto}"; exit 1 ;;
                esac
                shift 2 ;;
            --capture)       capture=true; shift ;;
            --logfile)       capture_logfile="${2:?--logfile requires a value}"; shift 2 ;;
            -v|--verbose)    VERBOSE_MODE=true; shift ;;
            --allow)         allow_cidr="${2:?--allow requires a CIDR value}"
                             range_value="$(validate_source_range "${allow_cidr}")" || exit 1
                             shift 2 ;;
            --tcpwrap)       if [[ -n "${2:-}" && "${2}" != -* ]]; then
                                 tcpwrap_name="${2}"; shift 2
                             else
                                 tcpwrap_name="socat"; shift
                             fi
                             validate_tcpwrap_name "${tcpwrap_name}" || exit 1
                             ;;
            -h|--help)       show_tunnel_help; exit 0 ;;
            *)               log_error "Unknown tunnel option: ${1}"; exit 1 ;;
        esac
    done

    # Validate required arguments
    [[ -z "${lport}" ]] && { log_error "--port is required"; exit 1; }
    [[ -z "${rhost}" ]] && { log_error "--rhost is required"; exit 1; }
    [[ -z "${rport}" ]] && { log_error "--rport is required"; exit 1; }

    validate_port "${lport}" || exit 1
    validate_port "${rport}" || exit 1
    validate_hostname "${rhost}" || exit 1

    # An IPv6 literal target cannot be reached over TCP4, so force the remote
    # leg to TCP6 regardless of any --proto default. (Explicit --proto tcp6 sets
    # this too.) Hostnames and IPv4 keep the tcp4 default.
    if [[ "${rhost}" == *:* ]]; then
        remote_proto="tcp6"
    fi

    # Dual-stack advisory: TLS/OpenSSL tunnels are TCP-only by design
    if [[ "${dual_stack}" == true ]]; then
        log_warning "TLS tunnels use TCP only. --dual-stack will add a plaintext UDP forwarder (unencrypted) on the same port." "tunnel"
    fi

    print_banner "Encrypted Tunnel"

    # Generate self-signed cert if none provided
    if [[ -z "${cert}" || -z "${key}" ]]; then
        log_info "No certificate provided; generating self-signed cert..." "tunnel"
        local cert_pair
        cert_pair=$(generate_self_signed_cert "${cn}" "${key_type}") || exit 1
        cert="${cert_pair%% *}"
        key="${cert_pair##* }"
    else
        # Validate provided cert/key paths
        validate_file_path "${cert}" || exit 1
        validate_file_path "${key}" || exit 1
        [[ ! -f "${cert}" ]] && { log_error "Certificate not found: ${cert}"; exit 1; }
        [[ ! -f "${key}" ]] && { log_error "Key not found: ${key}"; exit 1; }
    fi

    # Check port availability
    if ! check_port_available "${lport}" "tcp4"; then
        log_error "Local port ${lport} (tcp4) is already in use"
        exit 1
    fi

    # Default session name
    [[ -z "${session_name}" ]] && session_name="tunnel-${lport}-${rhost}-${rport}"

    # Build command
    local cmd
    filter_opts="$(build_filter_opts "${range_value}" "${tcpwrap_name}")"
    cmd=$(build_socat_tunnel_cmd "${lport}" "${rhost}" "${rport}" "${cert}" "${key}" "${capture}" "${remote_proto}" "${filter_opts}")

    # Set up capture log if --capture is enabled
    if [[ "${capture}" == true ]]; then
        [[ -z "${capture_logfile}" ]] && capture_logfile="${LOG_DIR}/capture-tls-${lport}-${rhost}-${rport}-${EXEC_TIMESTAMP}.log"
        touch "${capture_logfile}" && chmod 600 "${capture_logfile}" 2>/dev/null || true
    fi

    # Display configuration
    print_section "Tunnel Configuration"
    print_kv "Listen Port" "${lport} (TLS/SSL)"
    print_kv "Remote Target" "${rhost}:${rport} (plaintext)"
    print_kv "Certificate" "${cert}"
    print_kv "Key" "${key}"
    print_kv "Session Name" "${session_name}"
    print_kv "Traffic Capture" "${capture}"
    [[ "${capture}" == true ]] && print_kv "Capture Log" "${capture_logfile}"
    print_kv "Dual-Stack" "${dual_stack}"
    print_kv "Watchdog" "${use_watchdog}"
    log_debug "Command: ${cmd}" "tunnel"

    # Launch
    print_section "Starting Tunnel"

    # Determine stderr redirect for capture mode
    local stderr_file=""
    [[ "${capture}" == true && -n "${capture_logfile}" ]] && stderr_file="${capture_logfile}"

    _launch_session "${use_watchdog}" "${session_name}" "tunnel" "tls" "${lport}" \
        "${cmd}" "${rhost}" "${rport}" "${stderr_file}" || exit 1
    local primary_sid="${LAUNCH_SID}"

    log_success "Tunnel active: TLS:${lport} ${SYM_TUNNEL} ${rhost}:${rport} (SID ${primary_sid})"

    # Dual-stack: add plaintext UDP forwarder on same port
    if [[ "${dual_stack}" == true ]]; then
        if check_port_available "${lport}" "udp4"; then
            local udp_name="fwd-udp4-${lport}-${rhost}-${rport}"
            local udp_cmd
            udp_cmd=$(build_socat_forward_cmd "udp4" "${lport}" "${rhost}" "${rport}" "udp4" "${capture}")

            local udp_capture_logfile=""
            local udp_stderr=""
            if [[ "${capture}" == true ]]; then
                udp_capture_logfile="${LOG_DIR}/capture-udp4-${lport}-${rhost}-${rport}-${EXEC_TIMESTAMP}.log"
                touch "${udp_capture_logfile}" && chmod 600 "${udp_capture_logfile}" 2>/dev/null || true
                udp_stderr="${udp_capture_logfile}"
            fi

            _launch_session "${use_watchdog}" "${udp_name}" "tunnel-udp" "udp4" "${lport}" \
                "${udp_cmd}" "${rhost}" "${rport}" "${udp_stderr}" || {
                log_warning "Dual-stack UDP forwarder failed on port ${lport}"
            }
            if [[ -n "${LAUNCH_SID}" ]]; then
                log_success "UDP forwarder active: udp4:${lport} ${SYM_FORWARD} ${rhost}:${rport} (SID ${LAUNCH_SID})"
            fi
        else
            log_warning "Port ${lport} (udp4) already in use - skipping dual-stack"
        fi
    fi

    log_info "Connect with: socat - OPENSSL:localhost:${lport},verify=0"
    log_info "Stop with: ${SCRIPT_NAME} stop ${primary_sid}"
}

#======================================================================
# MODE: redirect
# Redirect/proxy traffic transparently between endpoints.
# Optionally captures bidirectional traffic dumps for inspection.
# Supports --proto for individual TCP/UDP selection and --dual-stack
# for both protocols simultaneously.
#======================================================================

# Function: mode_redirect
# Description: Parse redirect-mode arguments and set up traffic redirection.
#              Uses launch_socat_session for reliable process tracking.
#              Protocol-aware: --proto selects TCP or UDP individually;
#              --dual-stack launches both. Capture mode uses stderr
#              redirection handled cleanly by the launcher.
# Parameters: All remaining CLI arguments after "redirect"
mode_redirect() {
    local lport="" rhost="" rport="" logfile="" proto="${DEFAULT_PROTOCOL}"
    local use_watchdog=false session_name="" capture=false dual_stack=false
    local allow_cidr="" tcpwrap_name="" range_value="" filter_opts=""

    # Parse redirect-specific arguments
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --lport)         lport="${2:?--lport requires a value}"; shift 2 ;;
            --rhost)         rhost="${2:?--rhost requires a value}"; shift 2 ;;
            --rport)         rport="${2:?--rport requires a value}"; shift 2 ;;
            --proto)         proto="${2:?--proto requires a value}"; shift 2 ;;
            --capture)       capture=true; shift ;;
            --logfile)       logfile="${2:?--logfile requires a value}"; shift 2 ;;
            --name)          session_name="${2:?--name requires a value}"
                             validate_session_name "${session_name}" || exit 1
                             shift 2 ;;
            --watchdog)      use_watchdog=true; shift ;;
            --dual-stack)    dual_stack=true; shift ;;
            -v|--verbose)    VERBOSE_MODE=true; shift ;;
            --allow)         allow_cidr="${2:?--allow requires a CIDR value}"
                             range_value="$(validate_source_range "${allow_cidr}")" || exit 1
                             shift 2 ;;
            --tcpwrap)       if [[ -n "${2:-}" && "${2}" != -* ]]; then
                                 tcpwrap_name="${2}"; shift 2
                             else
                                 tcpwrap_name="socat"; shift
                             fi
                             validate_tcpwrap_name "${tcpwrap_name}" || exit 1
                             ;;
            -h|--help)       show_redirect_help; exit 0 ;;
            *)               log_error "Unknown redirect option: ${1}"; exit 1 ;;
        esac
    done

    # Validate required arguments
    [[ -z "${lport}" ]] && { log_error "--lport is required"; exit 1; }
    [[ -z "${rhost}" ]] && { log_error "--rhost is required"; exit 1; }
    [[ -z "${rport}" ]] && { log_error "--rport is required"; exit 1; }

    validate_port "${lport}" || exit 1
    validate_port "${rport}" || exit 1
    validate_hostname "${rhost}" || exit 1
    proto=$(validate_protocol "${proto}") || exit 1

    print_banner "Redirector"

    # Check port availability for primary protocol
    if ! check_port_available "${lport}" "${proto}"; then
        log_error "Local port ${lport} (${proto}) is already in use"
        exit 1
    fi

    # Default session name includes protocol for disambiguation
    [[ -z "${session_name}" ]] && session_name="redir-${proto}-${lport}-${rhost}-${rport}"

    # Set up capture log if requested
    if [[ "${capture}" == true ]]; then
        [[ -z "${logfile}" ]] && logfile="${LOG_DIR}/capture-${proto}-${lport}-${rhost}-${rport}-${EXEC_TIMESTAMP}.log"
        touch "${logfile}" && chmod 600 "${logfile}" 2>/dev/null || true
    fi

    # Build command using protocol-aware builder
    local cmd
    filter_opts="$(build_filter_opts "${range_value}" "${tcpwrap_name}")"
    cmd=$(build_socat_redirect_cmd "${proto}" "${lport}" "${rhost}" "${rport}" "${capture}" "${filter_opts}")

    # Display configuration
    print_section "Redirect Configuration"
    print_kv "Listen Port" "${lport}"
    print_kv "Protocol" "${proto}${dual_stack:+ + $(get_alt_protocol "${proto}")}"
    print_kv "Remote Target" "${rhost}:${rport}"
    print_kv "Traffic Capture" "${capture}"
    [[ "${capture}" == true ]] && print_kv "Capture Log" "${logfile}"
    print_kv "Session Name" "${session_name}"
    print_kv "Dual-Stack" "${dual_stack}"
    print_kv "Watchdog" "${use_watchdog}"
    log_debug "Command: ${cmd}" "redirect"

    # Launch - stderr_redirect parameter handles capture mode cleanly
    print_section "Starting Redirector"

    local stderr_file=""
    [[ "${capture}" == true && -n "${logfile}" ]] && stderr_file="${logfile}"

    _launch_session "${use_watchdog}" "${session_name}" "redirect" "${proto}" "${lport}" \
        "${cmd}" "${rhost}" "${rport}" "${stderr_file}" || exit 1
    local primary_sid="${LAUNCH_SID}"

    log_success "Redirector active: ${proto}:${lport} ${SYM_ARROW} ${rhost}:${rport} (SID ${primary_sid})"

    # Dual-stack: also launch alternate protocol redirector
    if [[ "${dual_stack}" == true ]]; then
        local alt_proto
        alt_proto="$(get_alt_protocol "${proto}")"

        if check_port_available "${lport}" "${alt_proto}"; then
            local alt_name="redir-${alt_proto}-${lport}-${rhost}-${rport}"
            local alt_logfile=""
            if [[ "${capture}" == true ]]; then
                alt_logfile="${LOG_DIR}/capture-${alt_proto}-${lport}-${rhost}-${rport}-${EXEC_TIMESTAMP}.log"
                touch "${alt_logfile}" && chmod 600 "${alt_logfile}" 2>/dev/null || true
            fi
            local alt_cmd
            alt_cmd=$(build_socat_redirect_cmd "${alt_proto}" "${lport}" "${rhost}" "${rport}" "${capture}" "${filter_opts}")
            local alt_stderr=""
            [[ "${capture}" == true && -n "${alt_logfile}" ]] && alt_stderr="${alt_logfile}"

            _launch_session "${use_watchdog}" "${alt_name}" "redirect" "${alt_proto}" "${lport}" \
                "${alt_cmd}" "${rhost}" "${rport}" "${alt_stderr}" || {
                log_warning "Dual-stack ${alt_proto} redirector failed on port ${lport}"
            }
            if [[ -n "${LAUNCH_SID}" ]]; then
                log_success "Redirector active: ${alt_proto}:${lport} ${SYM_ARROW} ${rhost}:${rport} (SID ${LAUNCH_SID})"
            fi
        else
            log_warning "Port ${lport} (${alt_proto}) already in use - skipping dual-stack"
        fi
    fi

    log_info "Stop with: ${SCRIPT_NAME} stop ${primary_sid}"
}

#======================================================================
# MODE: status
# Display all active managed sessions with their health status.
# Supports optional session ID argument for detailed view.
#
# Usage:
#   socat_manager.sh status              - List all sessions
#   socat_manager.sh status <SID>        - Detail for specific session
#   socat_manager.sh status <NAME>       - Detail by session name
#   socat_manager.sh status <PORT>       - Detail by port number
#   socat_manager.sh status --cleanup    - Remove dead session files
#   socat_manager.sh status --verbose    - Include system listener info
#======================================================================

# Function: mode_status
# Description: Show all registered sessions with process status.
#              Accepts an optional positional argument to show detailed
#              information for a specific session. The argument is
#              matched against session IDs (8-char hex), session names,
#              and port numbers in that order.
# Parameters: Optional session identifier and flags
mode_status() {
    local target_sid="" do_cleanup=false

    # Parse arguments - first non-flag argument is treated as session identifier
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            -v|--verbose) VERBOSE_MODE=true; shift ;;
            --cleanup)    do_cleanup=true; shift ;;
            -h|--help)    show_status_help; exit 0 ;;
            -*)           shift ;;  # Skip unknown flags gracefully
            *)
                # First positional argument: session ID, name, or port
                if [[ -z "${target_sid}" ]]; then
                    target_sid="${1}"
                fi
                shift
                ;;
        esac
    done

    # Run cleanup if requested
    if [[ "${do_cleanup}" == true ]]; then
        session_cleanup_dead
    fi

    # If a specific session identifier was provided, show detailed view
    if [[ -n "${target_sid}" ]]; then
        print_banner "Session Status"

        # Try as session ID first (8-char hex)
        if [[ "${target_sid}" =~ ^[a-f0-9]{8}$ ]] && \
           [[ -f "${SESSION_DIR}/${target_sid}.session" ]]; then
            session_detail "${target_sid}"
            return 0
        fi

        # Try as session name (search all session files)
        local found_sid
        found_sid="$(session_find_by_name "${target_sid}" | head -1)"
        if [[ -n "${found_sid}" ]]; then
            session_detail "${found_sid}"
            return 0
        fi

        # Try as port number (may match multiple sessions for dual-stack)
        if [[ "${target_sid}" =~ ^[0-9]+$ ]]; then
            local port_sids
            port_sids="$(session_find_by_port "${target_sid}")"
            if [[ -n "${port_sids}" ]]; then
                while IFS= read -r psid; do
                    session_detail "${psid}"
                    echo "" >&2
                done <<< "${port_sids}"
                return 0
            fi
        fi

        log_error "Session '${target_sid}' not found (searched by ID, name, and port)"
        log_info "Run '${SCRIPT_NAME} status' to see all sessions"
        return 1
    fi

    # No specific session: show overview of all sessions
    print_banner "Session Status"
    session_list

    # Show listening ports via ss if verbose
    if [[ "${VERBOSE_MODE}" == true ]]; then
        print_section "System Listeners (socat)"
        if command -v ss &>/dev/null; then
            ss -tlnp 2>/dev/null | grep -i socat || echo "  (no socat TCP listeners detected via ss)" >&2
            echo "" >&2
            ss -ulnp 2>/dev/null | grep -i socat || echo "  (no socat UDP listeners detected via ss)" >&2
        elif command -v netstat &>/dev/null; then
            netstat -tulnp 2>/dev/null | grep -i socat || echo "  (no socat listeners detected)" >&2
        fi
    fi
}

#======================================================================
# MODE: stop
# Stop one or more sessions by session ID, name, port, PID, or all.
# Protocol-aware: stopping a TCP session on a shared port does NOT
# affect a UDP session on the same port, and vice versa.
#
# Usage:
#   socat_manager.sh stop <SID>          - Stop specific session by ID
#   socat_manager.sh stop --all          - Stop all sessions
#   socat_manager.sh stop --name <n>  - Stop by session name
#   socat_manager.sh stop --port <PORT>  - Stop all on port (all protocols)
#   socat_manager.sh stop --pid <PID>    - Stop by PID
#
# Stop process (per session):
#   1. Read session metadata including PROTOCOL
#   2. Signal watchdog to stop
#   3. SIGTERM the entire process group (-PGID)
#   4. SIGTERM specific PID + children
#   5. Wait grace period (5 seconds)
#   6. SIGKILL if still alive
#   7. Fallback: kill socat by port (protocol-scoped)
#   8. Verify port freed (protocol-scoped)
#   9. Remove session file after confirmed dead
#======================================================================

# Function: mode_stop
# Description: Stop sessions by various selectors.
#              First positional argument is treated as session ID.
# Parameters: All remaining CLI arguments after "stop"
mode_stop() {
    local stop_all=false stop_name="" stop_port="" stop_pid=""
    local target_sid=""

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --all)           stop_all=true; shift ;;
            --name)          stop_name="${2:?--name requires a value}"; shift 2 ;;
            --port)          stop_port="${2:?--port requires a value}"; shift 2 ;;
            --pid)           stop_pid="${2:?--pid requires a value}"; shift 2 ;;
            -v|--verbose)    VERBOSE_MODE=true; shift ;;
            -h|--help)       show_stop_help; exit 0 ;;
            -*)              log_error "Unknown stop option: ${1}"; exit 1 ;;
            *)
                # First positional argument: session ID or name
                if [[ -z "${target_sid}" ]]; then
                    target_sid="${1}"
                fi
                shift
                ;;
        esac
    done

    # Require at least one selector
    if [[ "${stop_all}" != true && -z "${stop_name}" && -z "${stop_port}" && \
          -z "${stop_pid}" && -z "${target_sid}" ]]; then
        log_error "Specify what to stop: <session-id>, --all, --name, --port, or --pid"
        log_info "Run '${SCRIPT_NAME} status' to see active sessions"
        exit 1
    fi

    print_banner "Session Stop"
    local stopped=0 failed=0

    if [[ "${stop_all}" == true ]]; then
        # ─── Stop all registered sessions ───
        print_section "Stopping All Sessions"

        local all_sids
        all_sids="$(session_get_all_ids)"

        if [[ -z "${all_sids}" ]]; then
            log_info "No sessions to stop"
        else
            while IFS= read -r sid; do
                [[ -z "${sid}" ]] && continue
                if _stop_session "${sid}"; then
                    ((stopped++)) || true
                else
                    ((failed++)) || true
                fi
            done <<< "${all_sids}"
        fi

        # Safety net: report any orphaned socat processes
        _cleanup_orphaned_socat

    elif [[ -n "${target_sid}" ]]; then
        # ─── Stop by session ID (positional argument) ───
        # Try as session ID first (8-char hex)
        if [[ "${target_sid}" =~ ^[a-f0-9]{8}$ ]] && \
           [[ -f "${SESSION_DIR}/${target_sid}.session" ]]; then
            if _stop_session "${target_sid}"; then
                ((stopped++)) || true
            else
                ((failed++)) || true
            fi
        else
            # Try as session name
            local found_sids
            found_sids="$(session_find_by_name "${target_sid}")"
            if [[ -n "${found_sids}" ]]; then
                while IFS= read -r sid; do
                    [[ -z "${sid}" ]] && continue
                    if _stop_session "${sid}"; then
                        ((stopped++)) || true
                    else
                        ((failed++)) || true
                    fi
                done <<< "${found_sids}"
            else
                log_warning "Session '${target_sid}' not found"
                ((failed++)) || true
            fi
        fi

    elif [[ -n "${stop_name}" ]]; then
        # ─── Stop by session name ───
        local name_sids
        name_sids="$(session_find_by_name "${stop_name}")"

        if [[ -z "${name_sids}" ]]; then
            log_warning "No sessions found with name '${stop_name}'"
            ((failed++)) || true
        else
            while IFS= read -r sid; do
                [[ -z "${sid}" ]] && continue
                if _stop_session "${sid}"; then
                    ((stopped++)) || true
                else
                    ((failed++)) || true
                fi
            done <<< "${name_sids}"
        fi

    elif [[ -n "${stop_port}" ]]; then
        # ─── Stop all sessions on a specific port (all protocols) ───
        validate_port "${stop_port}" || exit 1

        local port_sids
        port_sids="$(session_find_by_port "${stop_port}")"

        if [[ -z "${port_sids}" ]]; then
            log_warning "No sessions found on port ${stop_port}"
            ((failed++)) || true
        else
            while IFS= read -r sid; do
                [[ -z "${sid}" ]] && continue
                if _stop_session "${sid}"; then
                    ((stopped++)) || true
                else
                    ((failed++)) || true
                fi
            done <<< "${port_sids}"
        fi

    elif [[ -n "${stop_pid}" ]]; then
        # ─── Stop by PID ───
        # Validate PID is numeric only (prevents injection into kill calls)
        if ! [[ "${stop_pid}" =~ ^[0-9]+$ ]]; then
            log_error "Invalid PID '${stop_pid}': must be a number" "stop"
            exit 1
        fi
        local pid_sids
        pid_sids="$(session_find_by_pid "${stop_pid}")"

        if [[ -z "${pid_sids}" ]]; then
            log_warning "No sessions found with PID ${stop_pid}"
            ((failed++)) || true
        else
            while IFS= read -r sid; do
                [[ -z "${sid}" ]] && continue
                if _stop_session "${sid}"; then
                    ((stopped++)) || true
                else
                    ((failed++)) || true
                fi
            done <<< "${pid_sids}"
        fi
    fi

    echo "" >&2
    log_info "Stop summary: ${stopped} stopped, ${failed} failed"

    # Clean up any remaining dead session files
    session_cleanup_dead
}

# Function: _stop_session
# Description: Stop a single session by its session ID. Implements a
#              multi-step, protocol-aware stop sequence:
#
#              1. Read session metadata including PROTOCOL
#              2. Signal watchdog to stop (if applicable)
#              3. SIGTERM the entire process group (-PGID)
#              4. SIGTERM the specific PID + direct children
#              5. Wait grace period (STOP_GRACE_SECONDS)
#              6. SIGKILL if still alive
#              7. Fallback: kill socat by port (ONLY this session's protocol)
#              8. Verify port freed (ONLY this session's protocol)
#              9. Remove session file after confirmed dead
#
#              CRITICAL: Steps 7 and 8 are protocol-scoped. Stopping a TCP
#              session will NOT check/kill UDP on the same port, and vice
#              versa. This prevents cross-protocol interference in
#              dual-stack configurations.
#
# Parameters:
#   $1 - Session ID
# Returns: 0 on success, 1 on failure
_stop_session() {
    local sid="${1:?Session ID required}"
    local session_file="${SESSION_DIR}/${sid}.session"

    if [[ ! -f "${session_file}" ]]; then
        log_warning "Session file not found for '${sid}'"
        return 1
    fi

    # Read session metadata - PROTOCOL is critical for scoped port checks
    local name pid pgid lport mode proto
    name="$(session_read_field "${session_file}" "SESSION_NAME")"
    pid="$(session_read_field "${session_file}" "PID")"
    pgid="$(session_read_field "${session_file}" "PGID")"
    lport="$(session_read_field "${session_file}" "LOCAL_PORT")"
    mode="$(session_read_field "${session_file}" "MODE")"
    proto="$(session_read_field "${session_file}" "PROTOCOL")"

    # Default protocol if not recorded (legacy sessions)
    [[ -z "${proto}" ]] && proto="tcp4"

    log_info "Stopping session ${sid} (${name}, PID ${pid}, PGID ${pgid}, ${proto})..." "stop"
    log_session "${sid}" "INFO" "Stop requested for ${proto} session"

    # Step 1: Signal watchdog to stop gracefully (if applicable)
    touch "${SESSION_DIR}/${sid}.stop" 2>/dev/null || true

    # Step 2: SIGTERM the entire process group (most reliable method)
    # Under setsid, PGID == PID of the socat parent. Killing -PGID
    # terminates socat AND all its forked children in one operation.
    if [[ -n "${pgid}" ]] && [[ "${pgid}" != "0" ]]; then
        if kill -0 "-${pgid}" 2>/dev/null; then
            log_debug "Sending SIGTERM to process group -${pgid}" "stop"
            kill -TERM "-${pgid}" 2>/dev/null || true
        fi
    fi

    # Step 3: Also SIGTERM the specific PID + direct children (belt and suspenders)
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        log_debug "Sending SIGTERM to PID ${pid}" "stop"
        kill -TERM "${pid}" 2>/dev/null || true
        # Kill any direct children that may have been forked by socat
        pkill -TERM -P "${pid}" 2>/dev/null || true
    fi

    # Step 4: Wait grace period for clean shutdown
    local waited=0 is_dead=false
    while (( waited < STOP_GRACE_SECONDS * 2 )); do
        local pid_alive=false pgid_alive=false

        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            pid_alive=true
        fi

        if [[ -n "${pgid}" ]] && [[ "${pgid}" != "0" ]] && kill -0 "-${pgid}" 2>/dev/null; then
            pgid_alive=true
        fi

        if [[ "${pid_alive}" == false && "${pgid_alive}" == false ]]; then
            is_dead=true
            break
        fi

        sleep 0.5
        ((waited++)) || true
    done

    # Step 5: Force kill if still alive
    if [[ "${is_dead}" == false ]]; then
        log_warning "Session ${sid} still alive after grace period, sending SIGKILL..." "stop"

        # SIGKILL the process group
        if [[ -n "${pgid}" ]] && [[ "${pgid}" != "0" ]]; then
            kill -KILL "-${pgid}" 2>/dev/null || true
        fi

        # SIGKILL the specific PID and its children
        if [[ -n "${pid}" ]]; then
            kill -KILL "${pid}" 2>/dev/null || true
            pkill -KILL -P "${pid}" 2>/dev/null || true
        fi

        sleep 0.5
    fi

    # Step 6: Verify PID is truly dead
    local final_check=false
    if [[ -n "${pid}" ]] && ! kill -0 "${pid}" 2>/dev/null; then
        final_check=true
    elif [[ -z "${pid}" ]]; then
        final_check=true
    fi

    # Step 7: Fallback - if port still in use FOR THIS PROTOCOL, kill by port
    # CRITICAL: Only check the session's own protocol. This prevents
    # cross-protocol interference when dual-stack sessions share a port.
    if [[ -n "${lport}" ]] && [[ "${lport}" != "0" ]]; then
        if ! check_port_available "${lport}" "${proto}"; then
            log_warning "Port ${lport} (${proto}) still in use after kill, attempting port-based cleanup..." "stop"
            _kill_by_port "${lport}" "${proto}"
            sleep 0.5
        fi
    fi

    # Step 8: Final port verification (protocol-scoped)
    if [[ -n "${lport}" ]] && [[ "${lport}" != "0" ]]; then
        if ! check_port_freed "${lport}" "${proto}" 3; then
            log_warning "Port ${lport} (${proto}) may still be in TIME_WAIT state" "stop"
        fi
    fi

    # Step 9: Remove tracking files only when the process is confirmed dead.
    # The transient launching marker is always cleared. If death could not be
    # confirmed, the session file (and any .stop signal) are retained so the
    # session stays visible and stoppable on retry, and the failure is reported
    # to the caller rather than masked by a removed file.
    rm -f "${SESSION_DIR}/${sid}.launching" 2>/dev/null || true

    if [[ "${final_check}" == true ]]; then
        local _stop_rhost _stop_rport
        _stop_rhost="$(session_read_field "${session_file}" "REMOTE_HOST")"
        _stop_rport="$(session_read_field "${session_file}" "REMOTE_PORT")"
        _audit_record_event "stop" "${sid}" "${name}" "${mode}" "${proto}" \
            "${lport}" "${_stop_rhost}" "${_stop_rport}" "${pid}" "${pgid}" "session stopped"
        rm -f "${session_file}" "${SESSION_DIR}/${sid}.stop" 2>/dev/null || true
        log_success "Stopped: ${sid} (${name}, ${proto})" "stop"
        log_session "${sid}" "INFO" "Session stopped successfully"
        return 0
    fi

    _audit_record_event "stop_failed" "${sid}" "${name}" "${mode}" "${proto}" \
        "${lport}" "" "" "${pid}" "${pgid}" "stop could not be confirmed"
    log_warning "Session ${sid} (${name}) could not be confirmed stopped - session file retained for retry" "stop"
    log_session "${sid}" "WARNING" "Session stop incomplete; session file retained"
    return 1
}

# Function: _kill_by_port
# Description: Last-resort function to kill socat processes listening on
#              a specific port and protocol. Uses ss or lsof to find PIDs
#              bound to the port. Only targets socat processes to avoid
#              killing unrelated services. Protocol-aware: only queries
#              the specified protocol (TCP or UDP), not both.
# Parameters:
#   $1 - Port number
#   $2 - Protocol (tcp4, udp4, etc.) - determines which ss flag to use
_kill_by_port() {
    local port="${1:?Port required}"
    local proto="${2:-tcp4}"

    # Determine ss flag based on protocol
    local ss_flag="-tlnp"
    if [[ "${proto}" == *"udp"* ]]; then
        ss_flag="-ulnp"
    fi

    # Try ss first to find PIDs on this port for this protocol only. The local
    # address:port is the 4th column; the port is compared exactly (the last
    # colon-separated field) so a matching peer port or a longer port that merely
    # contains these digits cannot cause a false hit. PID extraction uses awk's
    # ERE (portable) rather than grep -P (\K), which is GNU-only.
    if command -v ss &>/dev/null; then
        local pids
        pids="$(ss ${ss_flag} 2>/dev/null | awk -v port="${port}" '
            NR > 1 {
                n = split($4, a, ":")
                if (a[n] == port && match($0, /pid=[0-9]+/)) {
                    print substr($0, RSTART + 4, RLENGTH - 4)
                }
            }' | sort -u || true)"

        if [[ -n "${pids}" ]]; then
            while IFS= read -r p; do
                [[ -z "${p}" ]] && continue
                # Safety check: only kill socat processes
                local proc_name
                proc_name="$(ps -o comm= -p "${p}" 2>/dev/null || true)"
                if [[ "${proc_name}" == "socat" ]]; then
                    log_debug "Killing socat PID ${p} on ${proto}:${port}" "stop"
                    kill -KILL "${p}" 2>/dev/null || true
                else
                    log_debug "Skipping non-socat PID ${p} (${proc_name}) on ${proto}:${port}" "stop"
                fi
            done <<< "${pids}"
        fi
    fi

    # Try lsof as fallback (lsof is not protocol-scoped, so verify manually)
    if command -v lsof &>/dev/null; then
        local lsof_proto_flag=""
        if [[ "${proto}" == *"tcp"* ]]; then
            lsof_proto_flag="-iTCP"
        elif [[ "${proto}" == *"udp"* ]]; then
            lsof_proto_flag="-iUDP"
        fi

        local lsof_pids
        lsof_pids="$(lsof ${lsof_proto_flag} -ti ":${port}" 2>/dev/null || true)"
        if [[ -n "${lsof_pids}" ]]; then
            while IFS= read -r p; do
                [[ -z "${p}" ]] && continue
                local proc_name
                proc_name="$(ps -o comm= -p "${p}" 2>/dev/null || true)"
                if [[ "${proc_name}" == "socat" ]]; then
                    log_debug "Killing socat PID ${p} on ${proto}:${port} (via lsof)" "stop"
                    kill -KILL "${p}" 2>/dev/null || true
                fi
            done <<< "${lsof_pids}"
        fi
    fi
}

# Function: _cleanup_orphaned_socat
# Description: Find socat processes that are not tracked by any session file
#              and report them. Does NOT auto-kill to prevent collateral damage
#              to socat processes managed by other tools or users. Provides
#              commands for manual cleanup.
_cleanup_orphaned_socat() {
    # Collect all PIDs from session files
    local -A tracked_pids=()
    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue
        local p
        p="$(session_read_field "${sf}" "PID")"
        [[ -n "${p}" ]] && tracked_pids[${p}]=1
    done

    # Find all running socat processes
    local socat_pids
    socat_pids="$(pgrep -x socat 2>/dev/null || true)"

    if [[ -z "${socat_pids}" ]]; then
        return 0
    fi

    local orphan_count=0
    while IFS= read -r p; do
        [[ -z "${p}" ]] && continue
        if [[ -z "${tracked_pids[${p}]+x}" ]]; then
            ((orphan_count++)) || true
            if (( orphan_count == 1 )); then
                echo "" >&2
                print_section "Orphaned socat Processes (not tracked)"
            fi
            local proc_info
            proc_info="$(ps -o pid,ppid,start,args -p "${p}" 2>/dev/null | tail -1 || true)"
            echo "    ${proc_info}" >&2
        fi
    done <<< "${socat_pids}"

    if (( orphan_count > 0 )); then
        log_warning "${orphan_count} orphaned socat process(es) found (not managed by this tool)"
        log_info "To kill manually: kill <PID> or kill -9 <PID>"
    fi
}

