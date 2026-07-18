#!/usr/bin/env bats
#======================================================================
# TEST SUITE : security.bats
#======================================================================
# Synopsis   : Security-focused regression tests for the launch path.
#
# Description: The socat process is launched through an argv array passed as
#              positional parameters to a fixed launcher script, rather than by
#              interpolating the command string into `bash -c`. These tests
#              confirm that (1) the argv handed to socat matches the constructed
#              command exactly, and (2) shell metacharacters embedded in the
#              command are treated as literal arguments and never executed.
#
# Version    : 2.3.8
#======================================================================

load ../helpers/test_helper

setup() { helper_setup; }
teardown() { helper_teardown; }

@test "S-01: launch passes the command through as an exact argv" {
    export SOCAT_STUB_SLEEP=3
    _spawn_socat "sec00010" \
        "socat -v TCP4-LISTEN:9500,reuseaddr,fork OPEN:/dev/null,creat,append" "" "setsid"
    [ -n "${_SPAWNED_PID}" ]
    sleep 0.2

    # The stub logs the argv it received; it must equal the command minus 'socat'.
    run grep -o 'ARGS=.*' "${TEST_TMPDIR}/.socat_stub.log"
    [[ "$output" == "ARGS=-v TCP4-LISTEN:9500,reuseaddr,fork OPEN:/dev/null,creat,append" ]]

    kill "${_SPAWNED_PID}" 2>/dev/null || true
}

@test "S-01: shell metacharacters in the command are not executed" {
    export SOCAT_STUB_SLEEP=3
    local marker="${TEST_TMPDIR}/PWNED"
    rm -f "${marker}"

    # A command-substitution token embedded in the command. If the command were
    # ever re-parsed by a shell, this would create the marker file. Via argv it
    # is passed to socat as inert literal arguments.
    local evil='socat TCP4-LISTEN:9501,reuseaddr,fork $(touch '"${marker}"') OPEN:/dev/null'
    _spawn_socat "sec00011" "${evil}" "" "setsid"
    sleep 0.5

    # The injected command must NOT have run.
    [ ! -f "${marker}" ]

    [ -n "${_SPAWNED_PID}" ] && kill "${_SPAWNED_PID}" 2>/dev/null || true
}

@test "S-01: a semicolon command separator is inert" {
    export SOCAT_STUB_SLEEP=3
    local marker="${TEST_TMPDIR}/SEMI"
    rm -f "${marker}"

    local evil='socat TCP4-LISTEN:9502,reuseaddr,fork OPEN:/dev/null ; touch '"${marker}"
    _spawn_socat "sec00012" "${evil}" "" "setsid"
    sleep 0.5

    [ ! -f "${marker}" ]
    [ -n "${_SPAWNED_PID}" ] && kill "${_SPAWNED_PID}" 2>/dev/null || true
}

@test "S-01: a non-socat command is rejected" {
    run _spawn_socat "sec00013" "rm -rf /tmp/should-not-run" "" "setsid"
    [ "$status" -ne 0 ]
}

# =====================================================================
# S-04: self-signed certificate hardening (SAN, sha256, EC option)
# =====================================================================

@test "S-04: certificate is signed with sha256 and carries a subjectAltName" {
    run generate_self_signed_cert "tunnel.example.com" "rsa"
    [ "$status" -eq 0 ]
    run grep -o 'ARGS=.*' "${TEST_TMPDIR}/.openssl_stub.log"
    [[ "$output" == *"-sha256"* ]]
    [[ "$output" == *"subjectAltName=DNS:tunnel.example.com"* ]]
    [[ "$output" == *"DNS:localhost"* ]]
    [[ "$output" == *"IP:127.0.0.1"* ]]
}

@test "S-04: an IP common name yields an IP subjectAltName" {
    run generate_self_signed_cert "10.0.0.5" "rsa"
    [ "$status" -eq 0 ]
    run grep -o 'ARGS=.*' "${TEST_TMPDIR}/.openssl_stub.log"
    [[ "$output" == *"subjectAltName=IP:10.0.0.5"* ]]
}

@test "S-04: EC key type selects prime256v1" {
    run generate_self_signed_cert "localhost" "ec"
    [ "$status" -eq 0 ]
    run grep -o 'ARGS=.*' "${TEST_TMPDIR}/.openssl_stub.log"
    [[ "$output" == *"-newkey ec"* ]]
    [[ "$output" == *"ec_paramgen_curve:prime256v1"* ]]
}

@test "S-04: default key type remains RSA-2048" {
    run generate_self_signed_cert "localhost"
    [ "$status" -eq 0 ]
    run grep -o 'ARGS=.*' "${TEST_TMPDIR}/.openssl_stub.log"
    [[ "$output" == *"-newkey rsa:2048"* ]]
}

@test "S-04: tunnel rejects an invalid --key-type" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" tunnel \
        --port 4443 --rhost 10.0.0.1 --rport 22 --key-type bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"key-type"* ]] || [[ "$output" == *"rsa or ec"* ]]
}

# =====================================================================
# S-05: _kill_by_port matches the exact local port (not substrings or
# peer ports) and extracts PIDs portably (no grep -P).
# =====================================================================

@test "S-05: _kill_by_port kills only the exact local-port match" {
    local killlog="${TEST_TMPDIR}/killed.log"
    : > "${killlog}"

    # Controlled ss output: target port 8080 appears as a local port (pid 1111)
    # and inside an IPv6 local address (pid 4444); a substring port 18080
    # (pid 2222) and a peer-side 8080 (pid 3333) must be ignored.
    ss() {
        cat <<'SSOUT'
State Recv-Q Send-Q Local-Address:Port Peer-Address:Port Process
LISTEN 0 128 0.0.0.0:8080 0.0.0.0:* users:(("socat",pid=1111,fd=5))
LISTEN 0 128 0.0.0.0:18080 0.0.0.0:* users:(("socat",pid=2222,fd=5))
LISTEN 0 128 0.0.0.0:9090 10.0.0.1:8080 users:(("socat",pid=3333,fd=5))
LISTEN 0 128 [::]:8080 [::]:* users:(("socat",pid=4444,fd=5))
SSOUT
    }
    # Every candidate PID looks like socat so the safety gate passes.
    ps() { echo "socat"; }
    # Record kill targets instead of signalling.
    kill() { [[ "$1" == "-KILL" ]] && echo "$2" >> "${killlog}"; return 0; }

    _kill_by_port "8080" "tcp4"

    unset -f ss ps kill

    # Exactly the two exact-port socat PIDs were killed.
    run sort -u "${killlog}"
    [[ "$output" == *"1111"* ]]
    [[ "$output" == *"4444"* ]]
    [[ "$output" != *"2222"* ]]
    [[ "$output" != *"3333"* ]]
}
