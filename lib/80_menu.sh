#======================================================================
# INTERACTIVE MENU SYSTEM
# Full-featured menu-driven interface for all socat_manager operations.
# Provides validated, guided input for every mode and option.
# Graceful error recovery: invalid inputs prompt retry, never crash.
#======================================================================

# ─── Menu Utilities ──────────────────────────────────────────────────

# Return code convention:
#   0 = success (value captured via stdout)
#   1 = validation failure (retry automatically)
#   2 = user cancelled (typed q/quit/cancel/back)
# All mode submenus check for return code 2 to abort and return to root.

# Sentinel value for cancel detection on stdout
readonly _MENU_CANCEL="__CANCEL__"

# Function: _menu_header
# Description: Print a formatted menu header with consistent styling.
# Parameters:
#   $1 - Header title text
_menu_header() {
    local title="${1:-Menu}"
    local width=56
    echo "" >&2
    echo -e "  ${CLR_BOLD}${CLR_CYAN}╔$(printf '═%.0s' $(seq 1 ${width}))╗${CLR_RESET}" >&2
    printf "  ${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}  %-$(( width - 2 ))s${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}\n" "${title}" >&2
    echo -e "  ${CLR_BOLD}${CLR_CYAN}╚$(printf '═%.0s' $(seq 1 ${width}))╝${CLR_RESET}" >&2
    echo "" >&2
}

# Function: _menu_cancel_hint
# Description: Print the cancel hint line. Called once per submenu.
_menu_cancel_hint() {
    echo -e "  ${CLR_DIM}(Type 'q' at any prompt to cancel and return to menu)${CLR_RESET}" >&2
    echo "" >&2
}

# Function: _is_cancel
# Description: Check if user input is a cancel keyword.
# Parameters:
#   $1 - User input string
# Returns: 0 if cancel, 1 if not
_is_cancel() {
    local input="${1,,}"  # lowercase
    case "${input}" in
        q|quit|cancel|back|exit) return 0 ;;
        *) return 1 ;;
    esac
}

# Function: _menu_prompt
# Description: Display a prompt and read user input. Detects cancel
#              keywords (q/quit/cancel/back) and returns code 2.
#              Empty input returns the default value.
# Parameters:
#   $1 - Prompt text
#   $2 - Default value (optional)
# Outputs: User input, default value, or _MENU_CANCEL on cancel
# Returns: 0 on input, 2 on cancel
_menu_prompt() {
    local prompt="${1}"
    local default="${2:-}"
    local input=""

    if [[ -n "${default}" ]]; then
        echo -ne "  ${CLR_BOLD}${prompt}${CLR_RESET} [${CLR_DIM}${default}${CLR_RESET}]: " >&2
    else
        echo -ne "  ${CLR_BOLD}${prompt}${CLR_RESET}: " >&2
    fi

    # Read one line. A failed read means end-of-input (closed stdin / Ctrl+D):
    # return code 3 so callers can distinguish it from a cancel keyword (2) and
    # unwind/exit rather than looping on perpetually-empty input.
    if ! read -r input; then
        return 3
    fi

    # Check for cancel
    if _is_cancel "${input}"; then
        echo "${_MENU_CANCEL}"
        return 2
    fi

    if [[ -z "${input}" ]]; then
        echo "${default}"
    else
        echo "${input}"
    fi
    return 0
}

# Function: _menu_prompt_yn
# Description: Prompt for a yes/no decision with default.
#              Supports cancel via q/quit/cancel/back.
# Parameters:
#   $1 - Prompt text
#   $2 - Default (y or n)
# Returns: 0 for yes, 1 for no, 2 for cancel
_menu_prompt_yn() {
    local prompt="${1}"
    local default="${2:-n}"
    local hint="y/N"
    [[ "${default}" == "y" ]] && hint="Y/n"

    while true; do
        echo -ne "  ${CLR_BOLD}${prompt}${CLR_RESET} [${hint}]: " >&2
        local input=""
        # EOF (closed stdin) is treated as a cancel so the caller unwinds rather
        # than looping or tripping set -e on a non-zero read.
        if ! read -r input; then
            return 2
        fi

        # Check cancel
        if _is_cancel "${input}"; then
            return 2
        fi

        input="${input:-${default}}"
        input="${input,,}"  # lowercase
        case "${input}" in
            y|yes) return 0 ;;
            n|no)  return 1 ;;
            *)     echo -e "  ${CLR_RED}Please enter y or n${CLR_RESET}" >&2 ;;
        esac
    done
}

# Function: _menu_prompt_choice
# Description: Prompt user to select from numbered options with cancel.
# Parameters:
#   $1 - Prompt text
#   $2 - Maximum valid option number
#   $3 - Default option (optional)
# Outputs: Selected option number
# Returns: 0 on selection, 2 on cancel
_menu_prompt_choice() {
    local prompt="${1:-Select}"
    local max="${2:-9}"
    local default="${3:-}"

    while true; do
        local input rc
        input="$(_menu_prompt "${prompt}" "${default}")" || { rc=$?; return "${rc}"; }

        # Validate: must be a number within range
        if [[ "${input}" =~ ^[0-9]+$ ]] && (( input >= 0 && input <= max )); then
            echo "${input}"
            return 0
        fi

        echo -e "  ${CLR_RED}Invalid selection '${input}'. Enter 0-${max}.${CLR_RESET}" >&2
    done
}

# Function: _menu_prompt_port
# Description: Prompt for a port number with validation and cancel.
# Parameters:
#   $1 - Prompt text (default: "Port")
#   $2 - Default value (optional)
# Outputs: Validated port number
# Returns: 0 on valid port, 2 on cancel
_menu_prompt_port() {
    local prompt="${1:-Port}"
    local default="${2:-}"

    while true; do
        local input
        input="$(_menu_prompt "${prompt}" "${default}")" || return 2

        if [[ -z "${input}" ]]; then
            echo -e "  ${CLR_RED}Port is required${CLR_RESET}" >&2
            continue
        fi

        if validate_port "${input}" 2>/dev/null; then
            echo "${input}"
            return 0
        fi

        echo -e "  ${CLR_RED}Invalid port '${input}'. Must be 1-65535.${CLR_RESET}" >&2
    done
}

# Function: _menu_prompt_host
# Description: Prompt for a hostname/IP with validation and cancel.
# Parameters:
#   $1 - Prompt text
#   $2 - Default value (optional)
# Outputs: Validated hostname
# Returns: 0 on valid host, 2 on cancel
_menu_prompt_host() {
    local prompt="${1:-Remote host}"
    local default="${2:-}"

    while true; do
        local input
        input="$(_menu_prompt "${prompt}" "${default}")" || return 2

        if [[ -z "${input}" ]]; then
            echo -e "  ${CLR_RED}Hostname/IP is required${CLR_RESET}" >&2
            continue
        fi

        if validate_hostname "${input}" 2>/dev/null; then
            echo "${input}"
            return 0
        fi

        echo -e "  ${CLR_RED}Invalid hostname '${input}'.${CLR_RESET}" >&2
    done
}

# Function: _menu_prompt_protocol
# Description: Present protocol selection menu with cancel.
# Outputs: Normalized protocol string (tcp4, tcp6, udp4, udp6)
# Returns: 0 on selection, 2 on cancel
_menu_prompt_protocol() {
    echo -e "  ${CLR_DIM}Protocol options:${CLR_RESET}" >&2
    echo "    1) TCP/IPv4  (tcp4)" >&2
    echo "    2) TCP/IPv6  (tcp6)" >&2
    echo "    3) UDP/IPv4  (udp4)" >&2
    echo "    4) UDP/IPv6  (udp6)" >&2

    while true; do
        local choice
        choice="$(_menu_prompt "Protocol" "1")" || return 2
        case "${choice}" in
            1|tcp4|tcp) echo "tcp4"; return 0 ;;
            2|tcp6)     echo "tcp6"; return 0 ;;
            3|udp4|udp) echo "udp4"; return 0 ;;
            4|udp6)     echo "udp6"; return 0 ;;
            *)          echo -e "  ${CLR_RED}Enter 1-4${CLR_RESET}" >&2 ;;
        esac
    done
}

# Function: _menu_prompt_name
# Description: Prompt for an optional session name with validation and cancel.
# Outputs: Validated name or empty string
# Returns: 0 on input, 2 on cancel
_menu_prompt_name() {
    while true; do
        local sname
        sname="$(_menu_prompt "Session name")" || return 2
        if [[ -z "${sname}" ]]; then
            echo ""
            return 0
        fi
        if validate_session_name "${sname}" 2>/dev/null; then
            echo "${sname}"
            return 0
        fi
        echo -e "  ${CLR_RED}Invalid name. Use alphanumeric, hyphens, underscores, dots (max 64).${CLR_RESET}" >&2
    done
}

# Function: _menu_pause
# Description: Wait for the user to press Enter before continuing.
_menu_pause() {
    echo "" >&2
    echo -ne "  ${CLR_DIM}Press Enter to return to menu...${CLR_RESET}" >&2
    # Tolerate EOF (closed stdin) so a non-zero read does not trip set -e; the
    # menu loop detects end-of-input separately and exits cleanly.
    read -r || true
}

# Function: _menu_cancelled
# Description: Show cancellation message. Called by submenus on return 2.
_menu_cancelled() {
    echo "" >&2
    echo -e "  ${CLR_YELLOW}Cancelled - returning to main menu.${CLR_RESET}" >&2
    _menu_pause
}

# ─── Shared Optional Flags Collector ─────────────────────────────────

# Function: _menu_collect_common_flags
# Description: Collect optional flags common to multiple modes:
#              protocol, dual-stack, capture, watchdog, session name.
#              Appends to the args array passed by nameref.
# Parameters:
#   $1 - Name of the args array (nameref)
#   $2 - Whether to offer protocol selection (true/false)
#   $3 - Whether to offer session name (true/false)
# Returns: 0 on success, 2 on cancel
_menu_collect_common_flags() {
    local -n _args_ref="${1}"
    local offer_proto="${2:-true}"
    local offer_name="${3:-true}"
    local rc=0

    # Protocol
    if [[ "${offer_proto}" == true ]]; then
        _menu_prompt_yn "Change protocol from tcp4?" || rc=$?
        [[ ${rc} -eq 2 ]] && return 2
        if [[ ${rc} -eq 0 ]]; then
            local proto
            proto="$(_menu_prompt_protocol)" || return 2
            _args_ref+=(--proto "${proto}")
        fi
        rc=0
    fi

    # Dual-stack
    _menu_prompt_yn "Enable dual-stack (TCP + UDP)?" || rc=$?
    [[ ${rc} -eq 2 ]] && return 2
    [[ ${rc} -eq 0 ]] && _args_ref+=(--dual-stack)
    rc=0

    # Capture
    _menu_prompt_yn "Enable traffic capture?" || rc=$?
    [[ ${rc} -eq 2 ]] && return 2
    [[ ${rc} -eq 0 ]] && _args_ref+=(--capture)
    rc=0

    # Watchdog
    _menu_prompt_yn "Enable watchdog auto-restart?" || rc=$?
    [[ ${rc} -eq 2 ]] && return 2
    [[ ${rc} -eq 0 ]] && _args_ref+=(--watchdog)
    rc=0

    # Session name
    if [[ "${offer_name}" == true ]]; then
        _menu_prompt_yn "Set a custom session name?" || rc=$?
        [[ ${rc} -eq 2 ]] && return 2
        if [[ ${rc} -eq 0 ]]; then
            local sname
            sname="$(_menu_prompt_name)" || return 2
            [[ -n "${sname}" ]] && _args_ref+=(--name "${sname}")
        fi
    fi

    return 0
}

# Function: _menu_confirm_execute
# Description: Show the constructed command and ask for confirmation.
# Parameters:
#   $@ - The full argument array
# Returns: 0 if confirmed, 1 if declined, 2 if cancelled
_menu_confirm_execute() {
    local rc=0
    echo "" >&2
    echo -e "  ${CLR_BOLD}Command:${CLR_RESET} ${SCRIPT_NAME}.sh $*" >&2
    echo "" >&2
    _menu_prompt_yn "Execute?" || rc=$?
    return ${rc}
}

# ─── Mode Submenus ───────────────────────────────────────────────────

# Function: _menu_listen
# Description: Interactive submenu for Listen mode with cancel support.
_menu_listen() {
    _menu_header "Listen Mode - Single TCP/UDP Listener"
    _menu_cancel_hint

    local port args=()

    # Required: port
    port="$(_menu_prompt_port "Listen port")" || { _menu_cancelled; return 0; }
    args=(listen --port "${port}")

    # Common flags (protocol, dual-stack, capture, watchdog, name)
    _menu_collect_common_flags args true true || { _menu_cancelled; return 0; }

    # Listen-specific: bind address
    local rc=0
    _menu_prompt_yn "Bind to a specific address?" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        local bind_addr
        bind_addr="$(_menu_prompt_host "Bind address" "0.0.0.0")" || { _menu_cancelled; return 0; }
        args+=(--bind "${bind_addr}")
    fi

    # Listen-specific: socat opts
    rc=0
    _menu_prompt_yn "Provide extra socat address options?" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        while true; do
            local sopts
            sopts="$(_menu_prompt "Socat options")" || { _menu_cancelled; return 0; }
            if validate_socat_opts "${sopts}" 2>/dev/null; then
                args+=(--socat-opts "${sopts}")
                break
            fi
            echo -e "  ${CLR_RED}Invalid characters. Allowed: alphanumeric, = , . : / _ -${CLR_RESET}" >&2
        done
    fi

    # Confirm and execute
    rc=0
    _menu_confirm_execute "${args[@]}" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        main "${args[@]}"
    else
        echo -e "  ${CLR_YELLOW}Cancelled.${CLR_RESET}" >&2
    fi

    _menu_pause
}

# Function: _menu_batch
# Description: Interactive submenu for Batch mode with cancel support.
_menu_batch() {
    _menu_header "Batch Mode - Multiple Listeners"
    _menu_cancel_hint

    local args=(batch)

    # Source selection
    echo "  Port source:" >&2
    echo "    1) Comma-separated list" >&2
    echo "    2) Port range" >&2
    echo "    3) Configuration file" >&2

    local source_choice
    source_choice="$(_menu_prompt_choice "Source" 3 "1")" || { _menu_cancelled; return 0; }

    case "${source_choice}" in
        1)
            while true; do
                local ports_input
                ports_input="$(_menu_prompt "Ports (e.g. 8080,8081,8082)")" || { _menu_cancelled; return 0; }
                if [[ -n "${ports_input}" ]]; then
                    args+=(--ports "${ports_input}")
                    break
                fi
                echo -e "  ${CLR_RED}Port list is required${CLR_RESET}" >&2
            done
            ;;
        2)
            local range_start range_end
            range_start="$(_menu_prompt_port "Range start port")" || { _menu_cancelled; return 0; }
            range_end="$(_menu_prompt_port "Range end port")" || { _menu_cancelled; return 0; }
            args+=(--range "${range_start}-${range_end}")
            ;;
        3)
            while true; do
                local conf_path
                conf_path="$(_menu_prompt "Config file path")" || { _menu_cancelled; return 0; }
                if [[ -f "${conf_path}" ]] && validate_file_path "${conf_path}" 2>/dev/null; then
                    args+=(--file "${conf_path}")
                    break
                fi
                echo -e "  ${CLR_RED}File not found or invalid path: '${conf_path}'${CLR_RESET}" >&2
            done
            ;;
    esac

    # Common flags (protocol, dual-stack, capture, watchdog) - no name for batch
    _menu_collect_common_flags args true false || { _menu_cancelled; return 0; }

    # Confirm and execute
    local rc=0
    _menu_confirm_execute "${args[@]}" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        main "${args[@]}"
    else
        echo -e "  ${CLR_YELLOW}Cancelled.${CLR_RESET}" >&2
    fi

    _menu_pause
}

# Function: _menu_forward
# Description: Interactive submenu for Forward mode with cancel support.
_menu_forward() {
    _menu_header "Forward Mode - Traffic Relay"
    _menu_cancel_hint

    local lport rhost rport args=(forward)

    # Required fields
    lport="$(_menu_prompt_port "Local listen port")" || { _menu_cancelled; return 0; }
    rhost="$(_menu_prompt_host "Remote host")" || { _menu_cancelled; return 0; }
    rport="$(_menu_prompt_port "Remote port")" || { _menu_cancelled; return 0; }
    args+=(--lport "${lport}" --rhost "${rhost}" --rport "${rport}")

    # Common flags
    _menu_collect_common_flags args true true || { _menu_cancelled; return 0; }

    # Confirm and execute
    local rc=0
    _menu_confirm_execute "${args[@]}" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        main "${args[@]}"
    else
        echo -e "  ${CLR_YELLOW}Cancelled.${CLR_RESET}" >&2
    fi

    _menu_pause
}

# Function: _menu_tunnel
# Description: Interactive submenu for Tunnel mode (TLS) with cancel.
_menu_tunnel() {
    _menu_header "Tunnel Mode - TLS Encrypted Tunnel"
    _menu_cancel_hint

    local lport rhost rport args=(tunnel)

    # Required fields
    lport="$(_menu_prompt_port "Local TLS port")" || { _menu_cancelled; return 0; }
    rhost="$(_menu_prompt_host "Remote host")" || { _menu_cancelled; return 0; }
    rport="$(_menu_prompt_port "Remote port")" || { _menu_cancelled; return 0; }
    args+=(--port "${lport}" --rhost "${rhost}" --rport "${rport}")

    # TLS certificate options
    local rc=0
    _menu_prompt_yn "Provide custom TLS certificate?" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        while true; do
            local cert_path key_path
            cert_path="$(_menu_prompt "Certificate file path (.pem)")" || { _menu_cancelled; return 0; }
            key_path="$(_menu_prompt "Private key file path (.key)")" || { _menu_cancelled; return 0; }

            local valid=true
            [[ ! -f "${cert_path}" ]] && { echo -e "  ${CLR_RED}Certificate not found: ${cert_path}${CLR_RESET}" >&2; valid=false; }
            [[ ! -f "${key_path}" ]] && { echo -e "  ${CLR_RED}Key not found: ${key_path}${CLR_RESET}" >&2; valid=false; }

            if [[ "${valid}" == true ]]; then
                args+=(--cert "${cert_path}" --key "${key_path}")
                break
            fi

            rc=0
            _menu_prompt_yn "Retry certificate paths?" || rc=$?
            [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
            [[ ${rc} -ne 0 ]] && { echo -e "  ${CLR_DIM}Using auto-generated self-signed certificate${CLR_RESET}" >&2; break; }
        done
    else
        echo -e "  ${CLR_DIM}Auto-generating self-signed certificate${CLR_RESET}" >&2
    fi

    # Common flags (no separate protocol for tunnel - TLS is TCP only)
    _menu_collect_common_flags args false true || { _menu_cancelled; return 0; }

    # Confirm and execute
    rc=0
    _menu_confirm_execute "${args[@]}" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        main "${args[@]}"
    else
        echo -e "  ${CLR_YELLOW}Cancelled.${CLR_RESET}" >&2
    fi

    _menu_pause
}

# Function: _menu_redirect
# Description: Interactive submenu for Redirect mode with cancel.
_menu_redirect() {
    _menu_header "Redirect Mode - Transparent Port Redirection"
    _menu_cancel_hint

    local lport rhost rport args=(redirect)

    # Required fields
    lport="$(_menu_prompt_port "Local port")" || { _menu_cancelled; return 0; }
    rhost="$(_menu_prompt_host "Redirect target host")" || { _menu_cancelled; return 0; }
    rport="$(_menu_prompt_port "Redirect target port")" || { _menu_cancelled; return 0; }
    args+=(--lport "${lport}" --rhost "${rhost}" --rport "${rport}")

    # Common flags
    _menu_collect_common_flags args true true || { _menu_cancelled; return 0; }

    # Confirm and execute
    local rc=0
    _menu_confirm_execute "${args[@]}" || rc=$?
    [[ ${rc} -eq 2 ]] && { _menu_cancelled; return 0; }
    if [[ ${rc} -eq 0 ]]; then
        main "${args[@]}"
    else
        echo -e "  ${CLR_YELLOW}Cancelled.${CLR_RESET}" >&2
    fi

    _menu_pause
}

# Function: _menu_status
# Description: Interactive submenu for Status mode.
_menu_status() {
    _menu_header "Session Status"

    echo "    1) Show active sessions" >&2
    echo "    2) Show detailed session info" >&2
    echo "    3) Clean up dead sessions" >&2
    echo "    0) Back to main menu" >&2

    local choice
    choice="$(_menu_prompt_choice "Option" 3 "1")" || return 0

    case "${choice}" in
        0) return 0 ;;
        1) main status ;;
        2) main status --detail ;;
        3)
            echo "" >&2
            echo -e "  ${CLR_DIM}Scanning for dead sessions...${CLR_RESET}" >&2
            # Capture output to always give feedback
            local cleanup_output
            cleanup_output="$(main status --cleanup 2>&1)"
            if echo "${cleanup_output}" | grep -qi 'cleaned'; then
                echo "${cleanup_output}" >&2
            else
                echo -e "  ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} No dead sessions found - all sessions are healthy or none exist." >&2
            fi
            ;;
    esac

    _menu_pause
}

# Function: _menu_stop
# Description: Interactive submenu for Stop mode.
_menu_stop() {
    _menu_header "Stop Sessions"

    echo "    1) Stop ALL sessions" >&2
    echo "    2) Stop by session name" >&2
    echo "    3) Stop by port number" >&2
    echo "    4) Stop by PID" >&2
    echo "    0) Back to main menu" >&2

    local choice
    choice="$(_menu_prompt_choice "Option" 4 "1")" || return 0

    case "${choice}" in
        0) return 0 ;;
        1)
            echo "" >&2
            local rc=0
            _menu_prompt_yn "Stop ALL active sessions?" || rc=$?
            if [[ ${rc} -eq 0 ]]; then
                main stop --all
            else
                echo -e "  ${CLR_YELLOW}Cancelled.${CLR_RESET}" >&2
            fi
            ;;
        2)
            # Show current sessions first
            echo "" >&2
            echo -e "  ${CLR_DIM}Active sessions:${CLR_RESET}" >&2
            main status 2>&1 | grep -E '^\s+\[' >&2 || echo -e "  ${CLR_DIM}  (none)${CLR_RESET}" >&2
            echo "" >&2

            local sname
            sname="$(_menu_prompt "Session name to stop")" || sname=""
            if [[ -n "${sname}" ]] && ! _is_cancel "${sname}"; then
                main stop --name "${sname}"
            fi
            ;;
        3)
            local sport
            sport="$(_menu_prompt_port "Port number to stop")" || sport=""
            if [[ $? -eq 0 ]] && [[ -n "${sport}" ]]; then
                main stop --port "${sport}"
            fi
            ;;
        4)
            while true; do
                local spid
                spid="$(_menu_prompt "PID to stop")" || break
                if [[ "${spid}" =~ ^[0-9]+$ ]]; then
                    main stop --pid "${spid}"
                    break
                fi
                echo -e "  ${CLR_RED}PID must be a number${CLR_RESET}" >&2
            done
            ;;
    esac

    _menu_pause
}

# Function: _menu_check_deps
# Description: Check and report status of all dependencies.
_menu_check_deps() {
    _menu_header "Dependency Check"

    local all_ok=true

    # Required dependencies
    echo -e "  ${CLR_BOLD}Required:${CLR_RESET}" >&2

    # bash version
    local bash_ver="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
    if (( BASH_VERSINFO[0] >= 4 && BASH_VERSINFO[1] >= 4 )) || (( BASH_VERSINFO[0] >= 5 )); then
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} bash ${bash_ver} (≥4.4 required)" >&2
    else
        echo -e "    ${CLR_RED}[${SYM_FAIL}]${CLR_RESET} bash ${bash_ver} (≥4.4 required)" >&2
        all_ok=false
    fi

    # socat
    if command -v socat &>/dev/null; then
        local socat_ver
        socat_ver="$(socat -V 2>/dev/null | sed -n 's/.*socat version \([0-9][0-9.]*\).*/\1/p' | head -1)"
        [[ -z "${socat_ver}" ]] && socat_ver="unknown"
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} socat ${socat_ver}" >&2
    else
        echo -e "    ${CLR_RED}[${SYM_FAIL}]${CLR_RESET} socat (not found)" >&2
        all_ok=false
    fi

    # coreutils
    if command -v date &>/dev/null; then
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} coreutils (date, mkdir, chmod, etc.)" >&2
    else
        echo -e "    ${CLR_RED}[${SYM_FAIL}]${CLR_RESET} coreutils (not found)" >&2
        all_ok=false
    fi

    # setsid
    if command -v setsid &>/dev/null; then
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} setsid (util-linux)" >&2
    else
        echo -e "    ${CLR_RED}[${SYM_FAIL}]${CLR_RESET} setsid (not found - install util-linux)" >&2
        all_ok=false
    fi

    echo "" >&2
    echo -e "  ${CLR_BOLD}Recommended:${CLR_RESET}" >&2

    # openssl
    if command -v openssl &>/dev/null; then
        local ssl_ver
        ssl_ver="$(openssl version 2>/dev/null | awk '{print $2}' || echo "unknown")"
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} openssl ${ssl_ver} (tunnel mode TLS)" >&2
    else
        echo -e "    ${CLR_YELLOW}[${SYM_WARN}]${CLR_RESET} openssl (not found - required for tunnel mode)" >&2
    fi

    # ss
    if command -v ss &>/dev/null; then
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} ss (iproute2 - port detection)" >&2
    else
        echo -e "    ${CLR_YELLOW}[${SYM_WARN}]${CLR_RESET} ss (not found - port checks will use netstat)" >&2
    fi

    # flock
    if command -v flock &>/dev/null; then
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} flock (util-linux - session locking)" >&2
    else
        echo -e "    ${CLR_YELLOW}[${SYM_WARN}]${CLR_RESET} flock (not found - concurrent access unprotected)" >&2
    fi

    # lsof
    if command -v lsof &>/dev/null; then
        echo -e "    ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} lsof (fallback port/process detection)" >&2
    else
        echo -e "    ${CLR_YELLOW}[${SYM_WARN}]${CLR_RESET} lsof (not found - optional fallback)" >&2
    fi

    echo "" >&2
    echo -e "  ${CLR_BOLD}Runtime:${CLR_RESET}" >&2
    echo -e "    Script:     ${SCRIPT_DIR}/${SCRIPT_NAME}.sh" >&2
    echo -e "    Version:    ${SCRIPT_VERSION}" >&2
    echo -e "    Sessions:   ${SESSION_DIR}/" >&2
    echo -e "    Logs:       ${LOG_DIR}/" >&2
    echo -e "    Certs:      ${CERT_DIR}/" >&2
    echo -e "    User:       $(whoami)" >&2
    echo -e "    EUID:       ${EUID}" >&2

    echo "" >&2
    if [[ "${all_ok}" == true ]]; then
        echo -e "  ${CLR_GREEN}${CLR_BOLD}All required dependencies satisfied.${CLR_RESET}" >&2
    else
        echo -e "  ${CLR_RED}${CLR_BOLD}Missing required dependencies. Install them before use.${CLR_RESET}" >&2
    fi

    _menu_pause
}

# ─── Root Menu ───────────────────────────────────────────────────────

# Function: _menu_banner
# Description: Print stylized ASCII art banner for the main menu.
_menu_banner() {
    echo "" >&2
    echo -e "  ${CLR_CYAN}${CLR_BOLD}" >&2
    cat >&2 << 'BANNER'
    ╔═══════════════════════════════════════════════════════════╗
    ║                                                           ║
    ║   ███████  ██████   ██████  █████  ████████               ║
    ║   ██      ██    ██ ██      ██   ██    ██                  ║
    ║   ███████ ██    ██ ██      ███████    ██                  ║
    ║        ██ ██    ██ ██      ██   ██    ██                  ║
    ║   ███████  ██████   ██████ ██   ██    ██                  ║
    ║                                                           ║
    ║     N E T W O R K   O P E R A T I O N S   M A N A G E R  ║
    ║                                                           ║
    ╚═══════════════════════════════════════════════════════════╝
BANNER
    echo -e "  ${CLR_RESET}" >&2
    echo -e "  ${CLR_DIM}  Version ${SCRIPT_VERSION}  •  $(date '+%Y-%m-%d %H:%M')  •  User: $(whoami)${CLR_RESET}" >&2
}

# Function: interactive_menu
# Description: Main interactive menu loop. Displays the root menu,
#              dispatches to submenus, and loops until the user exits.
interactive_menu() {
    # Ensure directories exist for status/dep checks
    _ensure_dirs

    # In interactive mode, Ctrl+C (SIGINT) must cancel the current prompt and
    # return to the menu rather than terminating the framework. The global INT
    # trap runs cleanup_handler (which exits); override it for the lifetime of
    # the menu. A prompt read in a command substitution is run in a subshell:
    # SIGINT terminates that subshell (default disposition), its non-zero status
    # is treated as a cancel by the prompt helpers, and the submenu unwinds to
    # this loop. A newline keeps the redrawn prompt clean.
    trap 'printf "\n" >&2' INT

    while true; do
        _menu_banner

        echo "" >&2
        echo -e "  ${CLR_BOLD}Operational Modes:${CLR_RESET}" >&2
        echo -e "    ${CLR_CYAN}1)${CLR_RESET}  Listen     - Start a TCP/UDP listener" >&2
        echo -e "    ${CLR_CYAN}2)${CLR_RESET}  Batch      - Launch multiple listeners" >&2
        echo -e "    ${CLR_CYAN}3)${CLR_RESET}  Forward    - Relay traffic to a remote host" >&2
        echo -e "    ${CLR_CYAN}4)${CLR_RESET}  Tunnel     - Create a TLS-encrypted tunnel" >&2
        echo -e "    ${CLR_CYAN}5)${CLR_RESET}  Redirect   - Transparent port redirection" >&2
        echo "" >&2
        echo -e "  ${CLR_BOLD}Status & Management:${CLR_RESET}" >&2
        echo -e "    ${CLR_CYAN}6)${CLR_RESET}  Session Status" >&2
        echo -e "    ${CLR_CYAN}7)${CLR_RESET}  Stop Sessions" >&2
        echo "" >&2
        echo -e "  ${CLR_BOLD}System:${CLR_RESET}" >&2
        echo -e "    ${CLR_CYAN}8)${CLR_RESET}  Check Dependencies" >&2
        echo -e "    ${CLR_CYAN}9)${CLR_RESET}  Help / CLI Usage" >&2
        echo -e "    ${CLR_CYAN}0)${CLR_RESET}  Exit" >&2

        local choice choice_rc=0
        choice="$(_menu_prompt_choice "Select" 9)" || choice_rc=$?

        # End-of-input (closed stdin / Ctrl+D): exit the menu cleanly rather than
        # spinning on empty reads.
        if [[ ${choice_rc} -eq 3 ]]; then
            echo "" >&2
            echo -e "  ${CLR_DIM}End of input. Goodbye.${CLR_RESET}" >&2
            echo "" >&2
            return 0
        fi

        case "${choice}" in
            1) _menu_listen ;;
            2) _menu_batch ;;
            3) _menu_forward ;;
            4) _menu_tunnel ;;
            5) _menu_redirect ;;
            6) _menu_status ;;
            7) _menu_stop ;;
            8) _menu_check_deps ;;
            9) show_main_help; _menu_pause ;;
            0)
                echo "" >&2
                echo -e "  ${CLR_DIM}Goodbye.${CLR_RESET}" >&2
                echo "" >&2
                return 0
                ;;
        esac
    done
}

# Function: show_audit_help
# Description: Print help for the audit view command.
show_audit_help() {
    cat << 'HELPEOF'
NAME
    socat_manager.sh audit - View the persistent audit history

SYNOPSIS
    socat_manager.sh audit [OPTIONS]

DESCRIPTION
    Print recorded framework events (session launches, stops, watchdog
    restarts, crashes) from the optional SQLite audit store. Requires the
    sqlite3 command-line tool. Auditing is active by default when sqlite3 is
    installed; disable it by setting SOCAT_MANAGER_AUDIT to a false-like value.

OPTIONS
    --limit <N>              Show at most N most-recent events (default: 50)
    --type <EVENT>           Filter by event type (launch, stop, stop_failed,
                             restart, crash, config_change, error)
    --session <SID>          Filter by session id
    --prune                  Apply the configured retention window before
                             listing (SOCAT_MANAGER_AUDIT_RETENTION_DAYS)
    -h, --help               Show this help

EXAMPLES
    bash socat_manager.sh audit
    bash socat_manager.sh audit --limit 20 --type restart
    bash socat_manager.sh audit --session a1b2c3d4
HELPEOF
}

# Function: mode_audit
# Description: Query and display events from the SQLite audit store. Read-only
#              apart from the optional --prune retention pass. All filter values
#              are emitted as escaped SQL literals.
# Parameters: parsed from "$@" (--limit, --type, --session, --prune)
mode_audit() {
    local limit=50 ev_type="" sess="" do_prune=false

    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --limit)   limit="${2:?--limit requires a value}"; shift 2 ;;
            --type)    ev_type="${2:?--type requires a value}"; shift 2 ;;
            --session) sess="${2:?--session requires a value}"; shift 2 ;;
            --prune)   do_prune=true; shift ;;
            -h|--help) show_audit_help; exit 0 ;;
            *)         log_error "Unknown audit option: ${1}"; exit 1 ;;
        esac
    done

    if ! _audit_available; then
        log_error "sqlite3 is not installed; the audit store is unavailable" "audit"
        exit 1
    fi

    if [[ ! "${limit}" =~ ^[0-9]+$ ]] || (( limit < 1 )); then
        log_error "Invalid --limit '${limit}' (expected a positive integer)" "audit"
        exit 1
    fi

    local db
    db="$(_audit_db_path)"
    if [[ ! -f "${db}" ]]; then
        log_info "No audit database found at ${db}" "audit"
        return 0
    fi

    if [[ "${do_prune}" == true ]]; then
        local rd
        rd="$(_audit_retention_days)"
        if (( rd > 0 )); then
            sqlite3 "${db}" "DELETE FROM events WHERE julianday(ts) < julianday('now','-${rd} days');" 2>/dev/null || true
            log_info "Pruned events older than ${rd} days" "audit"
        else
            log_info "Retention not configured (SOCAT_MANAGER_AUDIT_RETENTION_DAYS unset or 0); nothing pruned" "audit"
        fi
    fi

    local where="WHERE 1=1"
    [[ -n "${ev_type}" ]] && where+=" AND event_type=$(_audit_sql_text "${ev_type}")"
    [[ -n "${sess}" ]]    && where+=" AND session_id=$(_audit_sql_text "${sess}")"

    local query="SELECT ts, event_type, IFNULL(session_id,''), IFNULL(name,''), IFNULL(detail,'') FROM events ${where} ORDER BY id DESC LIMIT ${limit};"

    local rows
    rows="$(sqlite3 -separator $'\t' "${db}" "${query}" 2>/dev/null)"

    printf '%-21s %-13s %-10s %-16s %s\n' "TIMESTAMP" "EVENT" "SID" "NAME" "DETAIL"
    if [[ -z "${rows}" ]]; then
        log_info "No audit events match the query." "audit"
        return 0
    fi

    local ts etype esid ename detail
    while IFS=$'\t' read -r ts etype esid ename detail; do
        printf '%-21s %-13s %-10s %-16s %s\n' "${ts}" "${etype}" "${esid}" "${ename}" "${detail}"
    done <<< "${rows}"
    return 0
}

