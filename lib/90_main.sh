#======================================================================
# MAIN DISPATCHER
# Routes the first positional argument (mode) to the appropriate
# handler function, passing all remaining arguments through.
#======================================================================

main() {
    # Ensure directory structure exists
    _ensure_dirs

    # Hidden mode: detached watchdog supervisor (re-exec of this script). Handled
    # before all user-facing setup (no banner, migration, or dependency check -
    # the parent already validated the environment). Not shown in help.
    if [[ "${1:-}" == "__supervise" ]]; then
        _watchdog_run "${2:?Supervisor requires a session ID}"
        return $?
    fi

    # Extract the global --log-format flag from anywhere in the argument list and
    # strip it so per-mode parsers never see it. It is exported (via
    # SOCAT_MANAGER_LOG_FORMAT) so the detached watchdog supervisor re-exec logs
    # in the same format.
    local -a _passthru_args=()
    while [[ $# -gt 0 ]]; do
        case "${1}" in
            --log-format)
                local _fmt="${2:?--log-format requires a value (text|json)}"
                case "${_fmt}" in
                    text|json)
                        LOG_FORMAT="${_fmt}"
                        export SOCAT_MANAGER_LOG_FORMAT="${LOG_FORMAT}"
                        ;;
                    *)
                        log_error "Invalid --log-format '${_fmt}' (expected text or json)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            --log-level)
                local _lvl="${2:?--log-level requires a value (DEBUG|INFO|WARNING|ERROR|CRITICAL)}"
                # Normalize to upper case so "info" and "INFO" both work.
                _lvl="${_lvl^^}"
                case "${_lvl}" in
                    DEBUG|INFO|WARNING|ERROR|CRITICAL)
                        LOG_LEVEL="${_lvl}"
                        export SOCAT_MANAGER_LOG_LEVEL="${LOG_LEVEL}"
                        ;;
                    *)
                        log_error "Invalid --log-level '${2}' (expected DEBUG, INFO, WARNING, ERROR, or CRITICAL)"
                        exit 1
                        ;;
                esac
                shift 2
                ;;
            -v|--verbose)
                # Verbose is a global flag (documented under GLOBAL OPTIONS) and
                # is also accepted by the per-mode parsers. Handle it here so it
                # works in the global position (before the mode, or on its own)
                # rather than being mistaken for the mode name.
                VERBOSE_MODE=true
                shift
                ;;
            *)
                _passthru_args+=("${1}")
                shift
                ;;
        esac
    done
    set -- ${_passthru_args[@]+"${_passthru_args[@]}"}

    # No arguments: launch interactive menu
    if [[ $# -lt 1 ]]; then
        interactive_menu
        return 0
    fi

    local mode="${1}"
    shift  # Remove mode from argument list

    # Handle global help before mode dispatch
    case "${mode}" in
        -h|--help|help)
            show_main_help
            exit 0
            ;;
        menu)
            interactive_menu
            return 0
            ;;
        --version)
            echo "socat_manager.sh v${SCRIPT_VERSION}"
            exit 0
            ;;
    esac

    # Initialize master log
    log_info "=== socat_manager v${SCRIPT_VERSION} started (mode: ${mode}) ===" "main"
    log_debug "PID: ${SCRIPT_PID}, User: $(whoami), PWD: $(pwd)" "main"

    # Migrate legacy session files if any exist
    migrate_legacy_sessions

    # Check for socat (required for all modes except status/stop/help)
    # Skip socat check if user is just asking for help (-h/--help in args)
    local needs_socat=true
    case "${mode}" in
        status|stop|audit) needs_socat=false ;;
    esac
    for arg in "$@"; do
        [[ "${arg}" == "-h" || "${arg}" == "--help" ]] && needs_socat=false
    done
    [[ "${needs_socat}" == true ]] && check_socat

    # Dispatch to mode handler
    case "${mode}" in
        listen)   mode_listen "$@" ;;
        batch)    mode_batch "$@" ;;
        forward)  mode_forward "$@" ;;
        tunnel)   mode_tunnel "$@" ;;
        redirect) mode_redirect "$@" ;;
        status)   mode_status "$@" ;;
        stop)     mode_stop "$@" ;;
        audit)    mode_audit "$@" ;;
        *)
            log_error "Unknown mode '${mode}'"
            echo "" >&2
            echo -e "  Valid modes: listen, batch, forward, tunnel, redirect, status, stop, audit" >&2
            echo -e "  Run '${SCRIPT_NAME} --help' for full usage." >&2
            exit 1
            ;;
    esac
}

# Entry point
# Guard allows sourcing without execution (used by test framework).
# When executed directly (./socat_manager.sh), BASH_SOURCE[0] == $0 → runs main.
# When sourced (source socat_manager.sh), BASH_SOURCE[0] != $0 → functions loaded only.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
