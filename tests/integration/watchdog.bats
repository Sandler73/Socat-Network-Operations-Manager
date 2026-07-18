#!/usr/bin/env bats
#======================================================================
# TEST SUITE : watchdog.bats
#======================================================================
# Synopsis   : Regression coverage for the watchdog auto-restart supervisor.
#
# Description: Verifies the behaviors that were previously advertised but not
#              implemented (watchdog_loop had no callers) and the stale-PID
#              defect that would have followed:
#                - session_update_process / _session_write_field refresh fields
#                  in place without disturbing the rest of the session file
#                - a supervised launch registers the session and records a live
#                  socat PID plus watchdog metadata
#                - when the supervised socat dies, the supervisor restarts it and
#                  refreshes the recorded PID (no stale PID left behind)
#                - the .stop signal / stop path tears the supervisor down and
#                  leaves no session behind
#
# Notes      : Integration cases use the socat stub and poll with generous
#              timeouts because the supervisor runs as a detached re-exec.
#
# Version    : 2.3.1
#======================================================================

load ../helpers/test_helper

setup() { helper_setup; }
teardown() { helper_teardown; }

# --- Deterministic field-update mechanics (no processes) ---------------

@test "_session_write_field: replaces an existing field in place" {
    session_register "aaaa1111" "svc" "1000" "1000" "listen" "tcp4" "9000" "socat X Y" "" ""
    _session_write_field "aaaa1111" "PID" "2222"
    run session_read_field "${SESSION_DIR}/aaaa1111.session" "PID"
    [ "$output" = "2222" ]
    # Other fields untouched
    run session_read_field "${SESSION_DIR}/aaaa1111.session" "SESSION_NAME"
    [ "$output" = "svc" ]
    run session_read_field "${SESSION_DIR}/aaaa1111.session" "LOCAL_PORT"
    [ "$output" = "9000" ]
}

@test "_session_write_field: appends a new field when absent" {
    session_register "aaaa2222" "svc" "1000" "1000" "listen" "tcp4" "9000" "socat X Y" "" ""
    run session_read_field "${SESSION_DIR}/aaaa2222.session" "WATCHDOG"
    [ -z "$output" ]
    _session_write_field "aaaa2222" "WATCHDOG" "true"
    run session_read_field "${SESSION_DIR}/aaaa2222.session" "WATCHDOG"
    [ "$output" = "true" ]
}

@test "_session_write_field: preserves 0600 permissions after update" {
    session_register "aaaa3333" "svc" "1000" "1000" "listen" "tcp4" "9000" "socat X Y" "" ""
    _session_write_field "aaaa3333" "PID" "4242"
    run stat -c '%a' "${SESSION_DIR}/aaaa3333.session"
    [ "$output" = "600" ]
}

@test "session_update_process: refreshes both PID and PGID" {
    session_register "bbbb1111" "svc" "1000" "1000" "listen" "tcp4" "9000" "socat X Y" "" ""
    session_update_process "bbbb1111" "5555" "5555"
    run session_read_field "${SESSION_DIR}/bbbb1111.session" "PID"
    [ "$output" = "5555" ]
    run session_read_field "${SESSION_DIR}/bbbb1111.session" "PGID"
    [ "$output" = "5555" ]
}

# --- Supervisor integration -------------------------------------------

@test "launch_supervised_session: registers session with live PID and watchdog metadata" {
    export SOCAT_STUB_SLEEP=30
    launch_supervised_session "wd-listen" "listen" "tcp4" "9101" \
        "socat -u TCP4-LISTEN:9101,reuseaddr,fork OPEN:${TEST_TMPDIR}/d.log,creat,append" \
        "" "" "" 5 1
    [ -n "$LAUNCH_SID" ]
    local sf="${SESSION_DIR}/${LAUNCH_SID}.session"
    [ -f "$sf" ]

    run session_read_field "$sf" "WATCHDOG"
    [ "$output" = "true" ]
    run session_read_field "$sf" "SUPERVISOR_PID"
    [ -n "$output" ]

    local pid
    pid="$(session_read_field "$sf" "PID")"
    [ -n "$pid" ]
    [ "$pid" != "0" ]
    kill -0 "$pid" 2>/dev/null
}

@test "watchdog: restarts socat on crash and refreshes the recorded PID" {
    export SOCAT_STUB_SLEEP=30
    launch_supervised_session "wd-restart" "listen" "tcp4" "9102" \
        "socat -u TCP4-LISTEN:9102,reuseaddr,fork OPEN:${TEST_TMPDIR}/d2.log,creat,append" \
        "" "" "" 5 1
    local sf="${SESSION_DIR}/${LAUNCH_SID}.session"

    local pid1
    pid1="$(session_read_field "$sf" "PID")"
    [ -n "$pid1" ] && [ "$pid1" != "0" ]

    # Simulate a crash: kill the current socat.
    kill -KILL "$pid1" 2>/dev/null || true

    # The supervisor should relaunch after its backoff and write a new PID.
    local pid2="$pid1" waited=0
    while (( waited < 60 )); do
        pid2="$(session_read_field "$sf" "PID")"
        if [[ -n "$pid2" && "$pid2" != "0" && "$pid2" != "$pid1" ]] && kill -0 "$pid2" 2>/dev/null; then
            break
        fi
        sleep 0.2
        ((waited++)) || true
    done

    [ "$pid2" != "$pid1" ]
    kill -0 "$pid2" 2>/dev/null
}

@test "watchdog: stop tears down the supervisor and removes the session" {
    export SOCAT_STUB_SLEEP=30
    launch_supervised_session "wd-stop" "listen" "tcp4" "9103" \
        "socat -u TCP4-LISTEN:9103,reuseaddr,fork OPEN:${TEST_TMPDIR}/d3.log,creat,append" \
        "" "" "" 5 1
    local sid="$LAUNCH_SID"
    local sf="${SESSION_DIR}/${sid}.session"
    local sup
    sup="$(session_read_field "$sf" "SUPERVISOR_PID")"

    _stop_session "$sid"

    # Session file removed and supervisor no longer running.
    [ ! -f "$sf" ]
    run kill -0 "$sup" 2>/dev/null
    [ "$status" -ne 0 ]

    # No respawn: give it more than one backoff interval and confirm still gone.
    sleep 2
    [ ! -f "$sf" ]
}
