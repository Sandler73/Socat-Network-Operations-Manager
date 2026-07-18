#======================================================================
# BACKWARD COMPATIBILITY
# Migrate v1 (.pid) and v2.0 session files on startup.
# Detects legacy session files and converts them to v2.2 format.
# Dead legacy sessions are cleaned up automatically.
#======================================================================

# Function: migrate_legacy_sessions
# Description: Detect and migrate v1 .pid session files to v2.2 .session
#              format. Preserves original metadata and adds new v2.2 fields
#              where possible. Dead sessions are removed automatically.
migrate_legacy_sessions() {
    local migrated=0

    for old_file in "${SESSION_DIR}"/*.pid; do
        [[ ! -f "${old_file}" ]] && continue

        local old_name pid mode proto lport rhost rport

        old_name="$(basename "${old_file}" .pid)"
        pid=$(grep '^PID=' "${old_file}" 2>/dev/null | cut -d= -f2)
        mode=$(grep '^MODE=' "${old_file}" 2>/dev/null | cut -d= -f2)
        proto=$(grep '^PROTOCOL=' "${old_file}" 2>/dev/null | cut -d= -f2)
        lport=$(grep '^LOCAL_PORT=' "${old_file}" 2>/dev/null | cut -d= -f2)
        rhost=$(grep '^REMOTE_HOST=' "${old_file}" 2>/dev/null | cut -d= -f2)
        rport=$(grep '^REMOTE_PORT=' "${old_file}" 2>/dev/null | cut -d= -f2)

        # Skip if PID is not valid/alive (dead session from old version)
        if [[ -z "${pid}" ]] || ! kill -0 "${pid}" 2>/dev/null; then
            rm -f "${old_file}" 2>/dev/null
            log_debug "Removed dead legacy session: ${old_name}" "migrate"
            continue
        fi

        # Generate session ID for this legacy session
        local sid
        sid="$(generate_session_id)" || continue

        # Derive PGID from the running process
        local pgid
        pgid="$(ps -o pgid= -p "${pid}" 2>/dev/null | tr -d ' ')" || pgid="${pid}"

        # Create v2.2 session file
        session_register "${sid}" "${old_name}" "${pid}" "${pgid}" \
            "${mode:-unknown}" "${proto:-tcp4}" "${lport:-0}" "" "${rhost:-}" "${rport:-}"

        # Remove old v1 file
        rm -f "${old_file}" 2>/dev/null
        ((migrated++)) || true
        log_info "Migrated legacy session '${old_name}' → SID ${sid}" "migrate"
    done

    if (( migrated > 0 )); then
        log_info "Migrated ${migrated} legacy session(s) to v2.2 format"
    fi
}

