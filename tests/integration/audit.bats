#!/usr/bin/env bats
#======================================================================
# TEST SUITE : audit.bats
#======================================================================
# Synopsis   : Tests for the optional SQLite-backed audit store.
#
# Description: Exercises the audit recording and view paths against a
#              sqlite3 stub. Verifies event recording produces well-formed,
#              injection-safe INSERT statements, that disabling the store
#              suppresses recording, that remote-host redaction works, and
#              that the audit view command lists and filters events.
#
# Version    : 2.4.5
#======================================================================

load ../helpers/test_helper

setup() {
    helper_setup
    # The helper disables auditing by default; re-enable it for this suite.
    export SOCAT_MANAGER_AUDIT=1
    export SOCAT_STUB_SLEEP=3
    rm -f "${TEST_TMPDIR}/.sqlite3_stub.log"
}

teardown() {
    pkill -x socat 2>/dev/null || true
    helper_teardown
}

_last_insert() {
    grep -o 'INSERT INTO events.*' "${TEST_TMPDIR}/.sqlite3_stub.log" 2>/dev/null | tail -1
}

@test "P-04: audit is active when sqlite3 is available and not disabled" {
    run _audit_enabled
    [ "$status" -eq 0 ]
}

@test "P-04: audit is inactive when SOCAT_MANAGER_AUDIT is false-like" {
    SOCAT_MANAGER_AUDIT=off run _audit_enabled
    [ "$status" -ne 0 ]
}

@test "P-04: record_event emits a well-formed INSERT with bound-style literals" {
    _audit_record_event "launch" "a1b2c3d4" "svc" "listen" "tcp4" "8080" "10.0.0.9" "443" "12345" "12345" "single-shot launch"
    local line; line="$(_last_insert)"
    [[ "${line}" == *"INSERT INTO events"* ]]
    [[ "${line}" == *"'launch'"* ]]
    [[ "${line}" == *"'a1b2c3d4'"* ]]
    # integer columns are unquoted
    [[ "${line}" == *",8080,"* ]]
    [[ "${line}" == *",443,"* ]]
}

@test "P-04: single quotes in text values are escaped (no SQL injection)" {
    _audit_record_event "launch" "s1" "o'brien" "listen" "tcp4" "8080" "" "" "1" "1" "detail with ' quote"
    local line; line="$(_last_insert)"
    [[ "${line}" == *"'o''brien'"* ]]
    [[ "${line}" == *"'detail with '' quote'"* ]]
}

@test "P-04: recording is suppressed when auditing is disabled" {
    SOCAT_MANAGER_AUDIT=0 _audit_record_event "launch" "s1" "svc" "listen" "tcp4" "8080" "" "" "1" "1" "x"
    [ ! -s "${TEST_TMPDIR}/.sqlite3_stub.log" ] || ! grep -q 'INSERT INTO events' "${TEST_TMPDIR}/.sqlite3_stub.log"
}

@test "P-04: remote host is redacted when redaction is enabled" {
    export SOCAT_MANAGER_AUDIT_REDACT=1
    _audit_record_event "launch" "s1" "svc" "forward" "tcp4" "8080" "192.168.9.9" "443" "1" "1" "forward to 192.168.9.9:443"
    local line; line="$(_last_insert)"
    [[ "${line}" == *"'HOST-REDACTED'"* ]]
    [[ "${line}" == *"HOST-REDACTED:443"* ]]
    [[ "${line}" != *"192.168.9.9"* ]]
    # redacted flag set to 1 (last value before the closing paren)
    [[ "${line}" == *",1);" ]]
}

@test "P-04: a real launch records a launch event" {
    export SOCAT_MANAGER_BASE="${TEST_TMPDIR}/abase"
    run env SOCAT_MANAGER_BASE="${TEST_TMPDIR}/abase" SOCAT_MANAGER_AUDIT=1 \
        bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19200 --name auditcheck
    [ "$status" -eq 0 ]
    sleep 0.3
    run grep -c "INSERT INTO events" "${TEST_TMPDIR}/.sqlite3_stub.log"
    [ "$output" -ge 1 ]
    grep 'INSERT INTO events' "${TEST_TMPDIR}/.sqlite3_stub.log" | grep -q "'launch'"
}

@test "P-04: audit view lists events" {
    # Make the database file appear to exist so the view proceeds to query.
    mkdir -p "${TEST_TMPDIR}/audit"
    : > "${TEST_TMPDIR}/audit/audit.db"
    export SOCAT_MANAGER_AUDIT_DB="${TEST_TMPDIR}/audit/audit.db"
    run bash "${TEST_TMPDIR}/socat_manager.sh" audit --limit 5
    [ "$status" -eq 0 ]
    [[ "$output" == *"TIMESTAMP"* ]]
    [[ "$output" == *"launch"* ]]
}

@test "P-04: audit view rejects a non-numeric --limit" {
    mkdir -p "${TEST_TMPDIR}/audit"
    : > "${TEST_TMPDIR}/audit/audit.db"
    export SOCAT_MANAGER_AUDIT_DB="${TEST_TMPDIR}/audit/audit.db"
    run bash "${TEST_TMPDIR}/socat_manager.sh" audit --limit abc
    [ "$status" -ne 0 ]
}

@test "P-04: audit view filters are emitted as escaped SQL" {
    mkdir -p "${TEST_TMPDIR}/audit"
    : > "${TEST_TMPDIR}/audit/audit.db"
    export SOCAT_MANAGER_AUDIT_DB="${TEST_TMPDIR}/audit/audit.db"
    run bash "${TEST_TMPDIR}/socat_manager.sh" audit --type "launch" --session "a1b2c3d4"
    [ "$status" -eq 0 ]
    grep -q "event_type='launch'" "${TEST_TMPDIR}/.sqlite3_stub.log"
    grep -q "session_id='a1b2c3d4'" "${TEST_TMPDIR}/.sqlite3_stub.log"
}
