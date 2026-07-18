#!/usr/bin/env bats
#======================================================================
# TEST SUITE : log_level.bats
#======================================================================
# Synopsis   : Tests for the --log-level severity threshold option.
#
# Description: Verifies that LOG_LEVEL suppresses messages ranked below the
#              configured level from the master log, that DEBUG is hidden at
#              the default INFO level and shown at DEBUG, that --verbose forces
#              DEBUG regardless of LOG_LEVEL, that the CLI flag is parsed
#              (case-insensitively) and exported for the watchdog re-exec, and
#              that an invalid level is rejected.
#
# Version    : 2.4.9
#======================================================================

load ../helpers/test_helper

setup() {
    helper_setup
    export SOCAT_STUB_SLEEP=3
}

teardown() {
    pkill -x socat 2>/dev/null || true
    helper_teardown
}

_master_log() {
    ls "${TEST_TMPDIR}"/logs/socat_manager-*.log 2>/dev/null | head -1
}

@test "B-03: default level INFO suppresses DEBUG from the master log" {
    LOG_LEVEL="INFO" VERBOSE_MODE=false _log_write "DEBUG" "debug hidden" "main"
    LOG_LEVEL="INFO" VERBOSE_MODE=false _log_write "INFO" "info shown" "main"
    local mlog; mlog="$(_master_log)"
    run cat "${mlog}"
    [[ "$output" == *"info shown"* ]]
    [[ "$output" != *"debug hidden"* ]]
}

@test "B-03: LOG_LEVEL=DEBUG includes DEBUG lines" {
    LOG_LEVEL="DEBUG" VERBOSE_MODE=false _log_write "DEBUG" "debug visible" "main"
    local mlog; mlog="$(_master_log)"
    run cat "${mlog}"
    [[ "$output" == *"debug visible"* ]]
}

@test "B-03: LOG_LEVEL=WARNING suppresses INFO but keeps WARNING" {
    LOG_LEVEL="WARNING" VERBOSE_MODE=false _log_write "INFO" "info gone" "main"
    LOG_LEVEL="WARNING" VERBOSE_MODE=false _log_write "WARNING" "warn kept" "main"
    local mlog; mlog="$(_master_log)"
    run cat "${mlog}"
    [[ "$output" == *"warn kept"* ]]
    [[ "$output" != *"info gone"* ]]
}

@test "B-03: LOG_LEVEL=ERROR keeps ERROR and CRITICAL only" {
    LOG_LEVEL="ERROR" VERBOSE_MODE=false _log_write "WARNING" "warn gone" "main"
    LOG_LEVEL="ERROR" VERBOSE_MODE=false _log_write "ERROR" "err kept" "main"
    LOG_LEVEL="ERROR" VERBOSE_MODE=false _log_write "CRITICAL" "crit kept" "main"
    local mlog; mlog="$(_master_log)"
    run cat "${mlog}"
    [[ "$output" == *"err kept"* ]]
    [[ "$output" == *"crit kept"* ]]
    [[ "$output" != *"warn gone"* ]]
}

@test "B-03: --verbose forces DEBUG even when LOG_LEVEL is higher" {
    LOG_LEVEL="ERROR" VERBOSE_MODE=true _log_write "DEBUG" "verbose debug" "main"
    local mlog; mlog="$(_master_log)"
    run cat "${mlog}"
    [[ "$output" == *"verbose debug"* ]]
}

@test "B-03: --log-level flag is parsed and applied (WARNING hides startup INFO)" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" --log-level WARNING status
    [ "$status" -eq 0 ]
    # The startup "=== socat_manager ... started ===" line is INFO and must be
    # suppressed on the console at WARNING.
    [[ "$output" != *"started (mode: status)"* ]]
}

@test "B-03: --log-level is case-insensitive" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" --log-level debug status
    [ "$status" -eq 0 ]
}

@test "B-03: invalid --log-level value is rejected" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" --log-level bogus status
    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid --log-level"* ]]
}

@test "B-03: --log-level exports SOCAT_MANAGER_LOG_LEVEL for the watchdog re-exec" {
    # The pre-parse must export the resolved level so a detached supervisor
    # re-exec logs at the same threshold.
    run bash -c "source '${TEST_TMPDIR}/socat_manager.sh'; main --log-level ERROR status >/dev/null 2>&1; echo \"\${SOCAT_MANAGER_LOG_LEVEL}\""
    [[ "$output" == *"ERROR"* ]]
}

@test "verbose: -v in the global position is not mistaken for the mode" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" -v status
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unknown mode"* ]]
}

@test "verbose: --verbose in the global position is not mistaken for the mode" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" --verbose status
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unknown mode"* ]]
}

@test "verbose: -v enables DEBUG-level console output" {
    # With -v, the startup DEBUG line (PID/User/PWD) must appear on the console.
    run bash "${TEST_TMPDIR}/socat_manager.sh" -v status
    [[ "$output" == *"PID:"* ]]
}

@test "verbose: -v after the mode still works" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" status -v
    [ "$status" -eq 0 ]
    [[ "$output" != *"Unknown mode"* ]]
}
