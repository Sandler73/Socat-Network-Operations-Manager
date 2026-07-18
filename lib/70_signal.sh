#======================================================================
# SIGNAL HANDLING / CLEANUP
# Ensures graceful shutdown when interrupted (Ctrl+C, SIGTERM, etc.)
# Only affects child processes of THIS script invocation.
# setsid-launched sessions survive script exit by design.
#======================================================================

# Idempotent guard: prevents double-execution when a signal triggers
# both the signal trap and the EXIT trap.
_CLEANUP_DONE=false

# Function: cleanup_handler
# Description: Trap handler for graceful shutdown. Stops all child
#              processes of THIS script invocation only. Sessions
#              launched via setsid are unaffected (they survive in
#              their own process groups).
# Parameters:
#   $1 - Signal name (set by trap)
cleanup_handler() {
    # Idempotent guard: prevent double-execution
    [[ "${_CLEANUP_DONE}" == true ]] && return 0
    _CLEANUP_DONE=true

    local sig="${1:-UNKNOWN}"
    echo "" >&2
    log_warning "Caught signal ${sig} - shutting down..." "signal"

    # Kill all child processes of THIS script invocation only
    local children
    children=$(jobs -pr 2>/dev/null || true)
    if [[ -n "${children}" ]]; then
        log_info "Terminating child processes: ${children// /, }..." "signal"
        echo "${children}" | xargs kill -TERM 2>/dev/null || true
        sleep 0.5
        echo "${children}" | xargs kill -KILL 2>/dev/null || true
    fi

    log_info "Cleanup complete. Log: ${MASTER_LOG}" "signal"
    exit 0
}

# Register signal traps for clean shutdown
trap 'cleanup_handler INT' INT
trap 'cleanup_handler TERM' TERM
trap 'cleanup_handler HUP' HUP
# NOTE: No EXIT trap. Sessions are launched under setsid in separate
# process groups and are designed to survive script exit. The EXIT trap
# was firing on every normal exit (help, status, stop), producing false
# "shutting down" warnings and killing child processes unnecessarily.
# Signal traps (INT/TERM/HUP) handle the cases where cleanup is needed.

