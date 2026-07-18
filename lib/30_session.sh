#======================================================================
# SESSION ID GENERATION
# Generates unique 8-character hex session IDs using kernel entropy.
# Falls back to timestamp+PID hash if /proc/sys/kernel/random/uuid
# is unavailable. Checks for collisions against existing sessions.
#======================================================================

# Function: generate_session_id
# Description: Generate a unique 8-character hex session ID.
#              Uses /proc/sys/kernel/random/uuid as primary entropy source.
#              Falls back to timestamp+PID+RANDOM hash via sha256sum.
#              Verifies uniqueness against existing session files to
#              prevent collision (extremely unlikely but handled).
# Outputs: Echoes the 8-character hex session ID
# Returns: 0 on success, 1 if unable to generate unique ID
generate_session_id() {
    local sid=""
    local attempts=0
    local max_attempts=10

    while (( attempts < max_attempts )); do
        # Primary: kernel UUID (high entropy)
        if [[ -r /proc/sys/kernel/random/uuid ]]; then
            sid="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c1-8)"
        fi

        # Fallback: timestamp + PID + random number hashed
        if [[ -z "${sid}" ]] || [[ ${#sid} -ne 8 ]]; then
            sid="$(echo "${RANDOM}${$}$(date +%s%N)" | sha256sum | cut -c1-8)"
        fi

        # Ensure lowercase hex only
        sid="${sid,,}"

        # Check for collision with existing session files
        if [[ ! -f "${SESSION_DIR}/${sid}.session" ]]; then
            echo "${sid}"
            return 0
        fi

        ((attempts++)) || true
        log_debug "Session ID collision on '${sid}', retrying (${attempts}/${max_attempts})" "session"
    done

    # Extremely unlikely: all attempts collided
    log_error "Failed to generate unique session ID after ${max_attempts} attempts" "session"
    return 1
}

#======================================================================
# SESSION MANAGEMENT v2.2
# Tracks all spawned socat processes via session files in sessions/.
# Each session file uses .session extension and contains full
# metadata including PID, PGID, command, protocol, timestamps, and
# session ID.
#
# Key design decisions:
#   - Unique 8-char hex session IDs for unambiguous identification
#   - Process Group ID (PGID) tracking via setsid for tree kill
#   - Full socat command stored for watchdog restart capability
#   - PROTOCOL field stored for protocol-aware stop operations
#   - Launcher PID tracked separately from socat PID
#   - Session files use .session extension (not .pid)
#   - Port-release verification on stop is protocol-scoped
#
# Session file format:
#   SESSION_ID=<8-char-hex>
#   SESSION_NAME=<human-readable-name>
#   PID=<socat-process-pid>
#   PGID=<process-group-id>
#   MODE=<listen|batch-listen|forward|tunnel|redirect|watchdog>
#   PROTOCOL=<tcp4|tcp6|udp4|udp6|tls>
#   LOCAL_PORT=<port>
#   REMOTE_HOST=<host>
#   REMOTE_PORT=<port>
#   SOCAT_CMD=<full-socat-command-string>
#   STARTED=<ISO-8601-timestamp>
#   CORRELATION=<execution-correlation-id>
#   LAUNCHER_PID=<original-script-pid>
#======================================================================

# Advisory lock file for operations that iterate over all session files.
# Prevents TOCTOU race conditions when multiple script invocations run
# concurrently (e.g., stop --all while another instance is launching).
readonly SESSION_LOCK="${SESSION_DIR}/.lock"

# Function: _session_lock
# Description: Acquire an advisory lock on the session directory using
#              flock. Non-blocking: returns 1 if lock is held by another
#              process. Uses file descriptor 200 (reserved for locking).
#              The lock is automatically released when the fd closes.
# Returns: 0 if lock acquired, 1 if busy
_session_lock() {
    { exec 200>"${SESSION_LOCK}"; } 2>/dev/null || return 1
    flock -n 200 2>/dev/null || {
        log_debug "Session directory locked by another process" "session"
        return 1
    }
    return 0
}

# Function: _session_unlock
# Description: Release the advisory session lock by closing fd 200.
_session_unlock() {
    { exec 200>&-; } 2>/dev/null || true
}

# Function: session_register
# Description: Register a new socat session by writing a session file
#              with full metadata. Uses the session ID as the
#              primary key. File permissions set to 600 to protect
#              command strings and PID information.
# Parameters:
#   $1  - Session ID (unique 8-char hex)
#   $2  - Session name (human-readable, e.g., "redir-8443-example.com-443")
#   $3  - PID of the socat process
#   $4  - Process Group ID (PGID) for tree kill
#   $5  - Mode (listen, forward, tunnel, redirect, batch-listen, watchdog)
#   $6  - Protocol (tcp4, udp4, tls, etc.)
#   $7  - Local port
#   $8  - Full socat command string (for restart/audit)
#   $9  - Optional: remote host
#   $10 - Optional: remote port
session_register() {
    local sid="${1:?Session ID required}"
    local name="${2:?Session name required}"
    local pid="${3:?PID required}"
    local pgid="${4:?PGID required}"
    local mode="${5:?Mode required}"
    local proto="${6:-tcp4}"
    local lport="${7:-0}"
    local socat_cmd="${8:-}"
    local rhost="${9:-}"
    local rport="${10:-}"

    local session_file="${SESSION_DIR}/${sid}.session"

    # Write structured session metadata using heredoc
    cat > "${session_file}" << EOF
# socat_manager session file v2.3
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
SESSION_ID=${sid}
SESSION_NAME=${name}
PID=${pid}
PGID=${pgid}
MODE=${mode}
PROTOCOL=${proto}
LOCAL_PORT=${lport}
REMOTE_HOST=${rhost}
REMOTE_PORT=${rport}
SOCAT_CMD=${socat_cmd}
STARTED=$(date '+%Y-%m-%dT%H:%M:%S')
CORRELATION=${CORRELATION_ID}
LAUNCHER_PID=${SCRIPT_PID}
EOF

    # Restrict permissions - session files contain command strings and PIDs
    chmod 600 "${session_file}" 2>/dev/null || true

    log_debug "Session registered: ${sid} (${name}, PID ${pid}, PGID ${pgid})" "session"
    log_session "${sid}" "INFO" "Session registered: name=${name} pid=${pid} pgid=${pgid} mode=${mode} proto=${proto} port=${lport}"
}

# Function: _session_write_field
# Description: Update-or-append a single KEY=VALUE field in a session file.
#              Atomic (writes a temp file then renames). The value is written
#              literally via awk (-v), so it is not subject to regex or shell
#              interpretation. Used to refresh mutable fields (PID/PGID) and to
#              record watchdog metadata without rewriting the whole file.
# Parameters:
#   $1 - Session ID
#   $2 - Field key (e.g., "PID")
#   $3 - Field value
# Returns: 0 on success, 1 on failure
_session_write_field() {
    local sid="${1:?Session ID required}"
    local key="${2:?Field key required}"
    local value="${3:-}"
    local sf="${SESSION_DIR}/${sid}.session"

    [[ -f "${sf}" ]] || return 1

    local tmp="${sf}.tmp.$$"
    if grep -q "^${key}=" "${sf}" 2>/dev/null; then
        # Replace the existing line (exact key match, value written literally).
        awk -F= -v k="${key}" -v v="${value}" \
            '$1 == k { print k "=" v; next } { print }' \
            "${sf}" > "${tmp}" 2>/dev/null || { rm -f "${tmp}" 2>/dev/null; return 1; }
    else
        # Append a new field.
        cp "${sf}" "${tmp}" 2>/dev/null || { rm -f "${tmp}" 2>/dev/null; return 1; }
        printf '%s=%s\n' "${key}" "${value}" >> "${tmp}"
    fi

    chmod 600 "${tmp}" 2>/dev/null || true
    mv -f "${tmp}" "${sf}" 2>/dev/null || { rm -f "${tmp}" 2>/dev/null; return 1; }
    return 0
}

# Function: session_update_process
# Description: Refresh the PID and PGID recorded for a session. Called by the
#              watchdog supervisor after every (re)launch so that status and
#              stop always operate on the currently running socat process, never
#              a stale PID from a crashed instance.
# Parameters:
#   $1 - Session ID
#   $2 - New PID
#   $3 - New PGID
# Returns: 0 on success, 1 on failure
session_update_process() {
    local sid="${1:?Session ID required}"
    local pid="${2:?PID required}"
    local pgid="${3:?PGID required}"

    _session_write_field "${sid}" "PID" "${pid}"   || return 1
    _session_write_field "${sid}" "PGID" "${pgid}" || return 1
    log_debug "Session ${sid} process refreshed: PID=${pid} PGID=${pgid}" "session"
    log_session "${sid}" "INFO" "Process refreshed: PID=${pid} PGID=${pgid}"
    return 0
}

# Function: session_unregister
# Description: Remove a session file and all associated signal files
#              (stop signals, PID staging files). Called after confirmed
#              process termination.
# Parameters:
#   $1 - Session ID
session_unregister() {
    local sid="${1:?Session ID required}"
    rm -f "${SESSION_DIR}/${sid}.session" \
          "${SESSION_DIR}/${sid}.stop" \
          "${SESSION_DIR}/${sid}.launching" 2>/dev/null || true
    log_debug "Session unregistered: ${sid}" "session"
    log_session "${sid}" "INFO" "Session unregistered"
}

# Function: session_read_field
# Description: Read a specific field from a session file.
#              Safe parser that handles missing fields gracefully.
#              Uses grep + cut for reliable KEY=VALUE parsing.
# Parameters:
#   $1 - Path to session file
#   $2 - Field name (e.g., "PID", "PGID", "MODE", "PROTOCOL")
# Outputs: Field value, or empty string if not found
session_read_field() {
    local session_file="${1:?Session file required}"
    local field="${2:?Field name required}"

    if [[ ! -f "${session_file}" ]]; then
        return 0
    fi

    # Extract field value using awk for exact key match (no regex interpretation).
    # awk splits on first "=" and prints everything after it.
    # This prevents grep regex metacharacters in field names from matching
    # unintended lines in the session file.
    awk -F= -v key="${field}" '$1 == key {print substr($0, length(key)+2); exit}' "${session_file}" 2>/dev/null
}

# Function: session_find_by_name
# Description: Find session file(s) matching a session name (exact match).
#              Returns the session ID(s) for matching sessions.
# Parameters:
#   $1 - Session name to search for
# Outputs: Session IDs (one per line)
session_find_by_name() {
    local target_name="${1:?Session name required}"
    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue
        local name
        name="$(session_read_field "${sf}" "SESSION_NAME")"
        if [[ "${name}" == "${target_name}" ]]; then
            session_read_field "${sf}" "SESSION_ID"
        fi
    done
}

# Function: session_find_by_port
# Description: Find session file(s) matching a local port.
# Parameters:
#   $1 - Port number to search for
# Outputs: Session IDs (one per line)
session_find_by_port() {
    local target_port="${1:?Port required}"
    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue
        local port
        port="$(session_read_field "${sf}" "LOCAL_PORT")"
        if [[ "${port}" == "${target_port}" ]]; then
            session_read_field "${sf}" "SESSION_ID"
        fi
    done
}

# Function: session_find_by_pid
# Description: Find session file(s) matching a PID.
# Parameters:
#   $1 - PID to search for
# Outputs: Session IDs (one per line)
session_find_by_pid() {
    local target_pid="${1:?PID required}"
    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue
        local pid
        pid="$(session_read_field "${sf}" "PID")"
        if [[ "${pid}" == "${target_pid}" ]]; then
            session_read_field "${sf}" "SESSION_ID"
        fi
    done
}

# Function: session_is_alive
# Description: Check if a registered session's process is still running.
#              Checks both the primary PID and the process group.
# Parameters:
#   $1 - Session ID
# Returns: 0 if alive, 1 if dead/missing
session_is_alive() {
    local sid="${1:?Session ID required}"
    local session_file="${SESSION_DIR}/${sid}.session"

    if [[ ! -f "${session_file}" ]]; then
        return 1
    fi

    local pid pgid
    pid="$(session_read_field "${session_file}" "PID")"
    pgid="$(session_read_field "${session_file}" "PGID")"

    # Check primary PID first
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        return 0
    fi

    # Fallback: check if any process in the group is alive
    if [[ -n "${pgid}" ]] && [[ "${pgid}" != "0" ]]; then
        if kill -0 "-${pgid}" 2>/dev/null; then
            return 0
        fi
    fi

    return 1
}

# Function: session_get_all_ids
# Description: List all registered session IDs.
# Outputs: Session IDs (one per line), empty if none
session_get_all_ids() {
    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue
        session_read_field "${sf}" "SESSION_ID"
    done
}

# Function: session_list
# Description: List all registered sessions with their status.
#              Displays a formatted table of sessions including
#              session ID, name, PID, PGID, mode, protocol, port,
#              remote target, and alive/dead status.
session_list() {
    local has_sessions=false

    # Check if any sessions exist
    for sf in "${SESSION_DIR}"/*.session; do
        if [[ -f "${sf}" ]]; then
            has_sessions=true
            break
        fi
    done

    if [[ "${has_sessions}" != true ]]; then
        log_info "No active sessions found"
        return 0
    fi

    print_section "Active Sessions"
    printf "\n" >&2

    # Table header
    printf "  ${CLR_BOLD}%-10s %-28s %-8s %-8s %-10s %-6s %-6s %-22s %-8s${CLR_RESET}\n" \
        "SID" "SESSION" "PID" "PGID" "MODE" "PROTO" "LPORT" "REMOTE" "STATUS" >&2
    printf "  %s\n" "$(printf '─%.0s' {1..112})" >&2

    local alive_count=0 dead_count=0

    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue

        local sid name pid pgid mode proto lport rhost rport status status_color

        # Parse session file fields using safe reader
        sid="$(session_read_field "${sf}" "SESSION_ID")"
        name="$(session_read_field "${sf}" "SESSION_NAME")"
        pid="$(session_read_field "${sf}" "PID")"
        pgid="$(session_read_field "${sf}" "PGID")"
        mode="$(session_read_field "${sf}" "MODE")"
        proto="$(session_read_field "${sf}" "PROTOCOL")"
        lport="$(session_read_field "${sf}" "LOCAL_PORT")"
        rhost="$(session_read_field "${sf}" "REMOTE_HOST")"
        rport="$(session_read_field "${sf}" "REMOTE_PORT")"

        # Build remote display string
        local remote="-"
        if [[ -n "${rhost}" && -n "${rport}" ]]; then
            remote="${rhost}:${rport}"
        elif [[ -n "${rhost}" ]]; then
            remote="${rhost}"
        fi

        # Check process status (PID and PGID)
        if session_is_alive "${sid}"; then
            status="ALIVE"
            status_color="${CLR_GREEN}"
            ((alive_count++)) || true
        else
            status="DEAD"
            status_color="${CLR_RED}"
            ((dead_count++)) || true
        fi

        printf "  %-10s %-28s %-8s %-8s %-10s %-6s %-6s %-22s ${status_color}%-8s${CLR_RESET}\n" \
            "${sid}" "${name:0:28}" "${pid}" "${pgid}" "${mode}" "${proto}" "${lport}" "${remote:0:22}" "${status}" >&2
    done

    printf "\n" >&2
    log_info "Sessions: ${alive_count} alive, ${dead_count} dead, $((alive_count + dead_count)) total"
}

# Function: session_detail
# Description: Display detailed information about a specific session.
#              Shows all metadata fields, process tree, port status
#              (for the session's own protocol), and associated log files.
# Parameters:
#   $1 - Session ID
session_detail() {
    local sid="${1:?Session ID required}"
    local session_file="${SESSION_DIR}/${sid}.session"

    if [[ ! -f "${session_file}" ]]; then
        log_error "Session '${sid}' not found"
        return 1
    fi

    print_section "Session Detail: ${sid}"

    # Read all fields
    local name pid pgid mode proto lport rhost rport started socat_cmd correlation launcher_pid

    name="$(session_read_field "${session_file}" "SESSION_NAME")"
    pid="$(session_read_field "${session_file}" "PID")"
    pgid="$(session_read_field "${session_file}" "PGID")"
    mode="$(session_read_field "${session_file}" "MODE")"
    proto="$(session_read_field "${session_file}" "PROTOCOL")"
    lport="$(session_read_field "${session_file}" "LOCAL_PORT")"
    rhost="$(session_read_field "${session_file}" "REMOTE_HOST")"
    rport="$(session_read_field "${session_file}" "REMOTE_PORT")"
    started="$(session_read_field "${session_file}" "STARTED")"
    socat_cmd="$(session_read_field "${session_file}" "SOCAT_CMD")"
    correlation="$(session_read_field "${session_file}" "CORRELATION")"
    launcher_pid="$(session_read_field "${session_file}" "LAUNCHER_PID")"

    # Display session metadata
    print_kv "Session ID" "${sid}"
    print_kv "Session Name" "${name}"
    print_kv "Mode" "${mode}"
    print_kv "Protocol" "${proto}"
    print_kv "Local Port" "${lport}"
    [[ -n "${rhost}" ]] && print_kv "Remote Host" "${rhost}"
    [[ -n "${rport}" ]] && print_kv "Remote Port" "${rport}"
    print_kv "PID" "${pid}"
    print_kv "PGID" "${pgid}"
    print_kv "Started" "${started}"
    print_kv "Correlation ID" "${correlation}"
    print_kv "Launcher PID" "${launcher_pid}"

    # Process status
    echo "" >&2
    print_section "Process Status"

    if session_is_alive "${sid}"; then
        echo -e "  ${CLR_GREEN}[${SYM_OK}] Process is ALIVE${CLR_RESET}" >&2
    else
        echo -e "  ${CLR_RED}[${SYM_FAIL}] Process is DEAD${CLR_RESET}" >&2
    fi

    # Show process tree if alive
    if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
        echo "" >&2
        echo -e "  ${CLR_DIM}Process tree:${CLR_RESET}" >&2
        if command -v pstree &>/dev/null; then
            pstree -p "${pid}" 2>/dev/null | sed 's/^/    /' >&2 || true
        else
            # Fallback: show process info via ps
            ps --forest -o pid,ppid,comm,args -g "${pgid}" 2>/dev/null | sed 's/^/    /' >&2 || \
                ps -o pid,ppid,comm -p "${pid}" 2>/dev/null | sed 's/^/    /' >&2 || true
        fi
    fi

    # Port status (checks only this session's protocol)
    echo "" >&2
    print_section "Port Status"
    if [[ -n "${lport}" ]] && [[ "${lport}" != "0" ]]; then
        if command -v ss &>/dev/null; then
            # Check TCP
            if [[ "${proto}" == tcp* ]] || [[ "${proto}" == "tls" ]]; then
                local tcp_info
                tcp_info="$(ss -tlnp 2>/dev/null | grep ":${lport} " || true)"
                if [[ -n "${tcp_info}" ]]; then
                    echo -e "  ${CLR_GREEN}[${SYM_OK}] Port ${lport} is LISTENING (TCP)${CLR_RESET}" >&2
                    echo "    ${tcp_info}" >&2
                else
                    echo -e "  ${CLR_RED}[${SYM_FAIL}] Port ${lport} is NOT listening (TCP)${CLR_RESET}" >&2
                fi
            fi
            # Check UDP
            if [[ "${proto}" == udp* ]]; then
                local udp_info
                udp_info="$(ss -ulnp 2>/dev/null | grep ":${lport} " || true)"
                if [[ -n "${udp_info}" ]]; then
                    echo -e "  ${CLR_GREEN}[${SYM_OK}] Port ${lport} is LISTENING (UDP)${CLR_RESET}" >&2
                    echo "    ${udp_info}" >&2
                else
                    echo -e "  ${CLR_RED}[${SYM_FAIL}] Port ${lport} is NOT listening (UDP)${CLR_RESET}" >&2
                fi
            fi
        fi
    fi

    # Show socat command
    if [[ -n "${socat_cmd}" ]]; then
        echo "" >&2
        print_section "Socat Command"
        echo "    ${socat_cmd}" >&2
    fi

    # List associated log files
    echo "" >&2
    print_section "Associated Logs"
    local log_count=0
    for lf in "${LOG_DIR}"/session-"${sid}"-*.log "${LOG_DIR}"/session-"${sid}"-error.log \
              "${LOG_DIR}"/capture-*"${lport}"*.log; do
        if [[ -f "${lf}" ]]; then
            echo "    ${lf}" >&2
            ((log_count++)) || true
        fi
    done
    if (( log_count == 0 )); then
        echo "    (no session-specific logs found)" >&2
    fi
}

# Function: session_cleanup_dead
# Description: Remove session files for sessions whose processes have died.
#              Only removes if BOTH PID and PGID are confirmed dead to
#              prevent premature cleanup. This is critical for dual-stack:
#              killing one protocol must not cause cleanup of the other.
session_cleanup_dead() {
    # Acquire advisory lock to prevent TOCTOU with concurrent stop/launch
    _session_lock || log_debug "Proceeding without lock (advisory)" "session"

    local cleaned=0
    for sf in "${SESSION_DIR}"/*.session; do
        [[ ! -f "${sf}" ]] && continue

        local sid pid pgid
        sid="$(session_read_field "${sf}" "SESSION_ID")"
        pid="$(session_read_field "${sf}" "PID")"
        pgid="$(session_read_field "${sf}" "PGID")"

        # Only clean up if BOTH PID and PGID are confirmed dead
        local pid_alive=false pgid_alive=false

        if [[ -n "${pid}" ]] && kill -0 "${pid}" 2>/dev/null; then
            pid_alive=true
        fi

        if [[ -n "${pgid}" ]] && [[ "${pgid}" != "0" ]] && kill -0 "-${pgid}" 2>/dev/null; then
            pgid_alive=true
        fi

        if [[ "${pid_alive}" == false && "${pgid_alive}" == false ]]; then
            rm -f "${sf}" "${SESSION_DIR}/${sid}.stop" "${SESSION_DIR}/${sid}.launching" 2>/dev/null
            ((cleaned++)) || true
            log_debug "Cleaned dead session: ${sid} (PID ${pid})" "session"
        fi
    done

    if (( cleaned > 0 )); then
        log_info "Cleaned ${cleaned} dead session(s)"
    fi
}

#======================================================================
# PROCESS LAUNCH WRAPPER (v2.1+ PID-file handoff)
#
# Architecture:
#   1. Generate session ID
#   2. Create a PID staging file path
#   3. Launch via: setsid bash -c 'echo $$ > pidfile; exec socat ...'
#      - setsid creates a new session + process group
#      - bash -c writes its own PID to the staging file
#      - exec replaces bash with socat (same PID preserved)
#      - All stdout/stderr redirected BEFORE exec (no fd leaks)
#   4. Parent reads the actual socat PID from the staging file
#   5. PGID == PID (because setsid made socat the group leader)
#   6. Register session with correct PID/PGID
#   7. Return session ID via LAUNCH_SID global (no $() subshell)
#
# Why not $() subshell?
#   Command substitution `sid="$(launch...)"` creates a subshell that
#   waits for ALL child processes holding its stdout fd to close. Even
#   with `&` and `disown`, setsid'd socat inherits the subshell's
#   stdout fd, keeping the pipe open. The subshell never completes,
#   and the terminal hangs at "Starting Redirector".
#
# Why PID-file handoff?
#   `setsid cmd &` followed by `$!` captures the PID of the setsid
#   wrapper process, which forks internally and exits immediately.
#   The actual socat runs under a different PID. By having the inner
#   bash write $$ before `exec socat`, we capture socat's real PID.
#   Under setsid, PID == PGID, so SIGTERM -PGID targets the correct
#   process tree including all fork children.
#======================================================================

# Global set by _spawn_socat with the verified socat PID (avoids $() subshell
# blocking, matching the LAUNCH_SID convention).
_SPAWNED_PID=""

# Function: _spawn_socat
# Description: Spawn a single socat instance using the PID-file handoff and
#              verify it is alive. Sets _SPAWNED_PID with the real socat PID.
#              Does NOT register a session - callers own registration. This is
#              the shared primitive behind both the single-shot launcher and the
#              watchdog supervisor, so the launch semantics stay identical.
# Parameters:
#   $1 - Session ID (names the staging file and default error log)
#   $2 - Full socat command string
#   $3 - Optional: stderr redirect file (capture log); defaults to error log
#   $4 - Spawn mode: "setsid" (default, detaches into a new session/group for
#        foreground launches) or "inline" (direct child, for a supervisor that
#        is already a detached session leader and needs to wait on the child)
# Returns: 0 on success (_SPAWNED_PID set), 1 on failure
_spawn_socat() {
    local sid="${1:?Session ID required}"
    local socat_cmd="${2:?Socat command required}"
    local stderr_redirect="${3:-}"
    local spawn_mode="${4:-setsid}"

    _SPAWNED_PID=""

    local error_log="${LOG_DIR}/session-${sid}-error.log"
    local target="${stderr_redirect:-${error_log}}"
    local pid_file="${SESSION_DIR}/${sid}.launching"
    rm -f "${pid_file}" 2>/dev/null || true

    # Tokenize the command into an argv array. This is a plain field split on
    # whitespace (socat address tokens never contain spaces) - NOT a shell parse:
    # metacharacters such as ; $() ` and quotes are treated as literal argument
    # text and no globbing occurs. The tokens are handed to the launcher as
    # positional parameters and exec'd as "$@", so no component of the command is
    # ever interpreted as shell code. This is defence in depth on top of the
    # whitelist input validation performed by the mode parsers.
    local -a socat_argv
    read -ra socat_argv <<< "${socat_cmd}"
    if [[ "${#socat_argv[@]}" -eq 0 || "${socat_argv[0]}" != "socat" ]]; then
        log_error "Session ${sid} failed - malformed socat command" "launch"
        return 1
    fi

    # Fixed launcher script - contains no interpolated user data. Positional
    # parameters carry the variable parts:
    #   $1 = PID staging file, $2 = stderr target, $3.. = socat argv
    # The launcher records its own PID before exec (so the real socat PID is
    # captured) and applies the fd redirections at exec time.
    local launcher='pf="$1"; tg="$2"; shift 2; echo $$ > "$pf"; exec "$@" >/dev/null 2>>"$tg"'

    if [[ "${spawn_mode}" == "inline" ]]; then
        # Caller (the watchdog supervisor) is already a detached session leader.
        # Launch socat as a direct child so the supervisor can wait on it; socat
        # inherits the supervisor's session/process group for group-kill on stop.
        bash -c "${launcher}" socat-launcher "${pid_file}" "${target}" "${socat_argv[@]}" &
    else
        # Detach into a fresh session/process group. $! would be the setsid
        # wrapper (which forks and exits), so the real PID comes from the file.
        setsid bash -c "${launcher}" socat-launcher "${pid_file}" "${target}" "${socat_argv[@]}" &>/dev/null &
    fi

    # Wait for the staging file to appear.
    local wait_count=0
    while [[ ! -f "${pid_file}" ]] && (( wait_count < PID_FILE_WAIT_ITERS )); do
        sleep 0.1
        ((wait_count++)) || true
    done

    if [[ ! -f "${pid_file}" ]]; then
        log_error "Session ${sid} failed to start - PID file not created within timeout" "launch"
        log_session "${sid}" "ERROR" "PID file not created within timeout"
        return 1
    fi

    local socat_pid
    socat_pid="$(cat "${pid_file}" 2>/dev/null | tr -d '[:space:]')"
    rm -f "${pid_file}" 2>/dev/null || true

    if [[ -z "${socat_pid}" ]] || ! [[ "${socat_pid}" =~ ^[0-9]+$ ]]; then
        log_error "Session ${sid} failed - invalid PID in staging file" "launch"
        return 1
    fi

    # Brief pause to verify socat bound the port and is stable.
    sleep 0.3
    if ! kill -0 "${socat_pid}" 2>/dev/null; then
        log_error "Session ${sid} failed - process ${socat_pid} died immediately" "launch"
        log_session "${sid}" "ERROR" "Process died immediately after launch (PID ${socat_pid})"
        return 1
    fi

    _SPAWNED_PID="${socat_pid}"
    return 0
}

# Function: launch_socat_session
# Description: Launch a socat command in an isolated process group and
#              register it as a managed session. Uses the PID-file handoff
#              pattern to capture the real socat PID. Returns the session
#              ID via the LAUNCH_SID global variable to avoid $() subshell
#              terminal blocking.
# Parameters:
#   $1 - Session name (human-readable identifier)
#   $2 - Mode (listen, forward, tunnel, redirect, batch-listen)
#   $3 - Protocol (tcp4, udp4, tls, etc.)
#   $4 - Local port
#   $5 - Full socat command string to execute
#   $6 - Optional: remote host
#   $7 - Optional: remote port
#   $8 - Optional: stderr redirect file (for capture mode)
# Returns: 0 on success (LAUNCH_SID set), 1 on failure
# Side effects: Sets LAUNCH_SID global variable
launch_socat_session() {
    local name="${1:?Session name required}"
    local mode="${2:?Mode required}"
    local proto="${3:?Protocol required}"
    local lport="${4:?Local port required}"
    local socat_cmd="${5:?Socat command required}"
    local rhost="${6:-}"
    local rport="${7:-}"
    local stderr_redirect="${8:-}"

    # Reset global return value
    LAUNCH_SID=""

    # Check maximum session count to prevent resource exhaustion
    local _active_count=0
    for _sf in "${SESSION_DIR}"/*.session; do
        [[ -f "${_sf}" ]] && ((_active_count++)) || true
    done
    if (( _active_count >= MAX_SESSIONS )); then
        log_error "Maximum session count (${MAX_SESSIONS}) reached. Stop existing sessions first." "launch"
        return 1
    fi

    # Generate unique session ID
    local sid
    sid="$(generate_session_id)" || {
        log_error "Failed to generate session ID for '${name}'" "launch"
        return 1
    }

    log_debug "Launching session ${sid} (${name}): ${socat_cmd}" "launch"
    log_session "${sid}" "INFO" "Launching: ${socat_cmd}"

    # Spawn socat detached into its own session/process group and capture the
    # verified PID via _SPAWNED_PID.
    if ! _spawn_socat "${sid}" "${socat_cmd}" "${stderr_redirect}" "setsid"; then
        log_error "Session ${sid} (${name}) failed to launch" "launch"
        return 1
    fi
    local socat_pid="${_SPAWNED_PID}"

    # Under setsid, the socat process IS the session leader and process
    # group leader. Therefore PGID == PID. This is what makes
    # `kill -TERM -${pgid}` reliable for stopping the entire tree.
    local pgid="${socat_pid}"

    # Register the session with the verified, correct PID and PGID
    session_register "${sid}" "${name}" "${socat_pid}" "${pgid}" \
        "${mode}" "${proto}" "${lport}" "${socat_cmd}" "${rhost}" "${rport}"

    log_session "${sid}" "INFO" "Session active: PID=${socat_pid} PGID=${pgid}"

    # Record the launch in the optional audit store (no-op when inactive).
    _audit_record_event "launch" "${sid}" "${name}" "${mode}" "${proto}" \
        "${lport}" "${rhost}" "${rport}" "${socat_pid}" "${pgid}" "single-shot launch"

    # Return session ID via global variable (avoids $() subshell blocking)
    LAUNCH_SID="${sid}"
    return 0
}

