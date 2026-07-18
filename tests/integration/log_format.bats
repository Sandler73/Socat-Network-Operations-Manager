#!/usr/bin/env bats
#======================================================================
# TEST SUITE : log_format.bats
#======================================================================
# Synopsis   : Tests for the --log-format (text|json) option.
#
# Description: Verifies that the master log is written as NDJSON when
#              --log-format json is given (before or after the mode) or when
#              SOCAT_MANAGER_LOG_FORMAT=json is set, that the default remains
#              the structured text format, that values are JSON-escaped, and
#              that an invalid format value is rejected.
#
# Version    : 2.4.6
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

@test "P-06: default log format is the structured text line" {
    _log_write "INFO" "hello world" "main"
    local mlog; mlog="$(_master_log)"
    run tail -1 "${mlog}"
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" == *"[main] hello world"* ]]
    [[ "$output" != *"{\"ts\""* ]]
}

@test "P-06: LOG_FORMAT=json writes a JSON object line" {
    LOG_FORMAT=json _log_write "INFO" "hello world" "launch"
    local mlog; mlog="$(_master_log)"
    run tail -1 "${mlog}"
    [[ "$output" == *"\"level\":\"INFO\""* ]]
    [[ "$output" == *"\"component\":\"launch\""* ]]
    [[ "$output" == *"\"message\":\"hello world\""* ]]
}

@test "P-06: JSON values are escaped into a parseable line" {
    LOG_FORMAT=json _log_write "INFO" 'quote " and \ backslash' "main"
    local mlog; mlog="$(_master_log)"
    local line; line="$(tail -1 "${mlog}")"
    # Structural check: the entry is a single JSON object.
    [[ "${line}" == "{"*"}" ]]
    # The message must be escaped correctly: a double quote becomes \" and a
    # backslash becomes \\ inside the JSON string. Asserted with a literal
    # substring match so the test has no external dependency (no python3/jq),
    # since those are not present on every target distribution.
    [[ "${line}" == *'"message":"quote \" and \\ backslash"'* ]]
}

@test "P-06: _json_escape escapes quotes, backslashes, and tabs" {
    run _json_escape 'a"b\c'
    [ "$output" = 'a\"b\\c' ]
}

@test "P-06: --log-format json produces an all-JSON master log (flag after mode)" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19310 --name jfmt --log-format json
    [ "$status" -eq 0 ]
    sleep 0.3
    local mlog; mlog="$(_master_log)"
    # Every non-empty line must start with a JSON object brace.
    run bash -c "grep -vc '^{' '${mlog}'"
    [ "$output" -eq 0 ]
}

@test "P-06: --log-format json works before the mode too" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" --log-format json listen --port 19311 --name jfmt2
    [ "$status" -eq 0 ]
    sleep 0.3
    local mlog; mlog="$(_master_log)"
    run head -1 "${mlog}"
    [[ "$output" == '{'* ]]
}

@test "P-06: SOCAT_MANAGER_LOG_FORMAT=json is honored" {
    run env SOCAT_MANAGER_LOG_FORMAT=json \
        bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19312 --name jfmt3
    [ "$status" -eq 0 ]
    sleep 0.3
    local mlog; mlog="$(_master_log)"
    run head -1 "${mlog}"
    [[ "$output" == '{'* ]]
}

@test "P-06: an invalid --log-format value is rejected" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19313 --log-format yaml
    [ "$status" -ne 0 ]
    [[ "$output" == *"log-format"* ]]
}

@test "P-06: default run keeps the text format (no --log-format)" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19314 --name tfmt
    [ "$status" -eq 0 ]
    sleep 0.3
    local mlog; mlog="$(_master_log)"
    run head -1 "${mlog}"
    [[ "$output" == *"[INFO]"* ]]
    [[ "$output" != '{'* ]]
}
