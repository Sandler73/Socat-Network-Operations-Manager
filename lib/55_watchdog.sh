#======================================================================
# WATCHDOG / AUTO-RESTART
# Supervises a managed socat session and restarts it if it crashes.
#
# Design:
#   A supervised session is launched by re-executing this script as a
#   detached process (setsid) in a hidden "__supervise" mode. The
#   supervisor becomes its own session/process-group leader, so it (and
#   the socat children it starts) survive the exit of the foreground
#   manager, and a single `kill -PGID` on stop terminates the whole tree.
#
#   The supervisor reads the full socat command and its parameters from
#   the session file (the single source of truth), launches socat as a
#   direct child via the PID-file handoff, records its own PID/PGID and
#   the live socat PID into the session file, then blocks on `wait`. When
#   socat exits it checks the .stop signal for a deliberate stop, applies
#   bounded exponential backoff (1s→60s), relaunches, and - critically -
#   refreshes the session file PID so status/stop never see a stale PID.
#
# Session-file fields used by the supervisor:
#   SOCAT_CMD          - command to (re)launch
#   STDERR_LOG         - capture/stderr redirect target (may be empty)
#   WATCHDOG           - "true" for supervised sessions
#   WATCHDOG_MAX       - maximum restarts before giving up
#   WATCHDOG_INTERVAL  - base health/backoff interval (seconds)
#   SUPERVISOR_PID     - the supervisor's own PID (recorded at startup)
#======================================================================

# Function: launch_supervised_session
# Description: Register a supervised session and spawn a detached watchdog
#              supervisor that owns the socat process. Mirrors the parameter
#              contract of launch_socat_session and returns the session ID via
#              the LAUNCH_SID global.
# Parameters:
#   $1 - Session name
#   $2 - Mode
#   $3 - Protocol
#   $4 - Local port
#   $5 - Full socat command string
#   $6 - Optional: remote host
#   $7 - Optional: remote port
#   $8 - Optional: stderr redirect file (capture log)
#   $9 - Optional: max restarts   (default: DEFAULT_WATCHDOG_MAX_RESTARTS)
#   $10- Optional: base interval   (default: DEFAULT_WATCHDOG_INTERVAL)
# Returns: 0 on success (LAUNCH_SID set), 1 on failure
launch_supervised_session() {
    local name="${1:?Session name required}"
    local mode="${2:?Mode required}"
    local proto="${3:?Protocol required}"
    local lport="${4:?Local port required}"
    local socat_cmd="${5:?Socat command required}"
    local rhost="${6:-}"
    local rport="${7:-}"
    local stderr_redirect="${8:-}"
    local max_restarts="${9:-${DEFAULT_WATCHDOG_MAX_RESTARTS}}"
    local interval="${10:-${DEFAULT_WATCHDOG_INTERVAL}}"

    LAUNCH_SID=""

    # Enforce the same session cap as the single-shot launcher.
    local _active_count=0
    for _sf in "${SESSION_DIR}"/*.session; do
        [[ -f "${_sf}" ]] && ((_active_count++)) || true
    done
    if (( _active_count >= MAX_SESSIONS )); then
        log_error "Maximum session count (${MAX_SESSIONS}) reached. Stop existing sessions first." "watchdog"
        return 1
    fi

    local sid
    sid="$(generate_session_id)" || {
        log_error "Failed to generate session ID for '${name}'" "watchdog"
        return 1
    }

    # Register the session up front with a placeholder process identity; the
    # supervisor fills in the real PID/PGID once socat is running.
    session_register "${sid}" "${name}" "0" "0" \
        "${mode}" "${proto}" "${lport}" "${socat_cmd}" "${rhost}" "${rport}"

    # Record watchdog metadata for the supervisor to read.
    _session_write_field "${sid}" "WATCHDOG" "true"
    _session_write_field "${sid}" "WATCHDOG_MAX" "${max_restarts}"
    _session_write_field "${sid}" "WATCHDOG_INTERVAL" "${interval}"
    _session_write_field "${sid}" "STDERR_LOG" "${stderr_redirect}"

    # Spawn the detached supervisor by re-executing this script. setsid makes it
    # a session leader that survives manager exit; the supervisor records its own
    # PID/PGID and refreshes the socat PID as it runs.
    setsid bash "${SCRIPT_SELF}" __supervise "${sid}" </dev/null &>/dev/null &

    # Wait for the supervisor to bring socat up (PID becomes non-zero and alive).
    local wait_count=0
    local live=false
    while (( wait_count < PID_FILE_WAIT_ITERS + 10 )); do
        local cur_pid
        cur_pid="$(session_read_field "${SESSION_DIR}/${sid}.session" "PID")"
        if [[ -n "${cur_pid}" && "${cur_pid}" != "0" ]] && kill -0 "${cur_pid}" 2>/dev/null; then
            live=true
            break
        fi
        sleep 0.1
        ((wait_count++)) || true
    done

    if [[ "${live}" != true ]]; then
        log_error "Supervised session ${sid} (${name}) failed to come up" "watchdog"
        # Signal the supervisor to give up and remove the registration.
        touch "${SESSION_DIR}/${sid}.stop" 2>/dev/null || true
        sleep 0.3
        session_unregister "${sid}"
        return 1
    fi

    log_session "${sid}" "INFO" "Supervised session active (watchdog)"

    # Record the supervised launch in the optional audit store.
    _audit_record_event "launch" "${sid}" "${name}" "${mode}" "${proto}" \
        "${lport}" "${rhost}" "${rport}" "" "" "supervised launch (watchdog, max=${max_restarts})"

    LAUNCH_SID="${sid}"
    return 0
}

# Function: _watchdog_run
# Description: The supervisor loop. Runs in the detached __supervise process.
#              Reads its parameters from the session file, then repeatedly
#              launches socat, refreshes the recorded PID, waits for exit, and
#              restarts with exponential backoff until the .stop signal is seen
#              or the restart budget is exhausted.
# Parameters:
#   $1 - Session ID
_watchdog_run() {
    local sid="${1:?Session ID required}"
    local sf="${SESSION_DIR}/${sid}.session"

    if [[ ! -f "${sf}" ]]; then
        log_error "Watchdog: session ${sid} not found" "watchdog"
        return 1
    fi

    local name socat_cmd stderr_log max_restarts interval
    name="$(session_read_field "${sf}" "SESSION_NAME")"
    socat_cmd="$(session_read_field "${sf}" "SOCAT_CMD")"
    stderr_log="$(session_read_field "${sf}" "STDERR_LOG")"
    max_restarts="$(session_read_field "${sf}" "WATCHDOG_MAX")"
    interval="$(session_read_field "${sf}" "WATCHDOG_INTERVAL")"
    [[ -z "${max_restarts}" ]] && max_restarts="${DEFAULT_WATCHDOG_MAX_RESTARTS}"
    [[ -z "${interval}" ]] && interval="${DEFAULT_WATCHDOG_INTERVAL}"

    # Fields used only to enrich audit records.
    local wd_mode wd_proto wd_lport wd_rhost wd_rport
    wd_mode="$(session_read_field "${sf}" "MODE")"
    wd_proto="$(session_read_field "${sf}" "PROTOCOL")"
    wd_lport="$(session_read_field "${sf}" "LOCAL_PORT")"
    wd_rhost="$(session_read_field "${sf}" "REMOTE_HOST")"
    wd_rport="$(session_read_field "${sf}" "REMOTE_PORT")"

    # Record the supervisor's own identity. As a setsid session leader its
    # process group equals its PID; stop uses this to terminate the whole tree.
    _session_write_field "${sid}" "SUPERVISOR_PID" "$$"
    _session_write_field "${sid}" "PGID" "$$"

    log_info "Watchdog supervising '${name}' [${sid}] (max ${max_restarts} restarts)" "watchdog"

    local restart_count=0
    local backoff=1

    while (( restart_count <= max_restarts )); do
        # Deliberate stop requested before (re)launch?
        if [[ -f "${SESSION_DIR}/${sid}.stop" ]]; then
            rm -f "${SESSION_DIR}/${sid}.stop" 2>/dev/null || true
            log_info "Watchdog: stop signal received for '${name}' [${sid}]" "watchdog"
            break
        fi

        # Launch socat inline (this supervisor is already detached) so we can
        # wait on it directly and it inherits our process group.
        if ! _spawn_socat "${sid}" "${socat_cmd}" "${stderr_log}" "inline"; then
            log_error "Watchdog: socat failed to start for '${name}' [${sid}]" "watchdog"
            ((restart_count++)) || true
            (( restart_count > max_restarts )) && break
            sleep "${backoff}"
            backoff=$(( backoff * 2 )); (( backoff > 60 )) && backoff=60
            continue
        fi

        local pid="${_SPAWNED_PID}"
        # Refresh the recorded PID so status/stop track the live process. PGID
        # stays the supervisor's group (constant across restarts).
        _session_write_field "${sid}" "PID" "${pid}"
        log_info "Watchdog: socat PID ${pid} up (restart #${restart_count}) [${sid}]" "watchdog"
        log_session "${sid}" "INFO" "Watchdog (re)launched socat PID ${pid} (restart #${restart_count})"

        # The initial bring-up is already recorded as "launch"; only record
        # subsequent respawns as restart events.
        if (( restart_count >= 1 )); then
            _audit_record_event "restart" "${sid}" "${name}" "${wd_mode}" "${wd_proto}" \
                "${wd_lport}" "${wd_rhost}" "${wd_rport}" "${pid}" "$$" "watchdog restart #${restart_count}"
        fi

        # Block until socat exits (zero CPU while healthy).
        wait "${pid}" 2>/dev/null || true

        # Deliberate stop while running?
        if [[ -f "${SESSION_DIR}/${sid}.stop" ]]; then
            rm -f "${SESSION_DIR}/${sid}.stop" 2>/dev/null || true
            log_info "Watchdog: graceful stop for '${name}' [${sid}]" "watchdog"
            break
        fi

        ((restart_count++)) || true
        if (( restart_count > max_restarts )); then
            log_error "Watchdog: max restarts (${max_restarts}) reached for '${name}' [${sid}]" "watchdog"
            _audit_record_event "crash" "${sid}" "${name}" "${wd_mode}" "${wd_proto}" \
                "${wd_lport}" "${wd_rhost}" "${wd_rport}" "" "$$" "watchdog gave up after ${max_restarts} restarts"
            break
        fi

        log_warning "Watchdog: socat exited; restarting in ${backoff}s (${restart_count}/${max_restarts}) [${sid}]" "watchdog"
        sleep "${backoff}"
        backoff=$(( backoff * 2 )); (( backoff > 60 )) && backoff=60
    done

    session_unregister "${sid}"
    log_info "Watchdog exiting for '${name}' [${sid}]" "watchdog"
    return 0
}

# Function: _launch_session
# Description: Launch a session either directly or under the watchdog supervisor,
#              based on the leading flag. Keeps the per-mode launch call sites to
#              a single, uniform form and guarantees --watchdog behaves
#              identically everywhere. Both targets set LAUNCH_SID.
# Parameters:
#   $1     - Supervised flag ("true" to run under the watchdog)
#   $2..   - Standard launch arguments (name, mode, proto, lport, cmd,
#            rhost, rport, stderr_file)
# Returns: 0 on success (LAUNCH_SID set), 1 on failure
_launch_session() {
    local supervised="${1:-false}"
    shift
    if [[ "${supervised}" == true ]]; then
        launch_supervised_session "$@"
    else
        launch_socat_session "$@"
    fi
}

