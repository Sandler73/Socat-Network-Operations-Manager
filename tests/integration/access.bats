#!/usr/bin/env bats
#======================================================================
# TEST SUITE : access.bats
#======================================================================
# Synopsis   : Integration tests for the --allow / --tcpwrap source
#              filters across the listener modes.
#
# Description: Verifies that the mode parsers translate --allow (source
#              CIDR) and --tcpwrap (TCP wrappers) into the correct socat
#              address options (range=, tcpwrap=) on the LISTENER, that
#              host bits are masked, and that invalid values are rejected
#              before any process is launched. The socat stub records the
#              exact argv it receives for inspection.
#
# Version    : 2.4.3
#======================================================================

load ../helpers/test_helper

setup() {
    helper_setup
    cd "${TEST_TMPDIR}"
    export SOCAT_STUB_SLEEP=3
}

teardown() {
    pkill -x socat 2>/dev/null || true
    helper_teardown
}

_launch_line() {
    # Emit the most recent socat launch (exclude the `-V` version probe).
    grep -oE 'ARGS=.*(LISTEN).*' "${TEST_TMPDIR}/.socat_stub.log" 2>/dev/null | tail -1
}

@test "P-03: listen --allow masks IPv4 host bits and adds tcpwrap" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" listen \
        --port 18091 --allow 10.1.2.3/8 --tcpwrap myd
    [ "$status" -eq 0 ]
    sleep 0.3
    local line; line="$(_launch_line)"
    [[ "${line}" == *"TCP4-LISTEN:18091"* ]]
    [[ "${line}" == *"range=10.0.0.0/8"* ]]
    [[ "${line}" == *"tcpwrap=myd"* ]]
}

@test "P-03: forward --allow renders bracketed IPv6 with default tcpwrap" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" forward \
        --lport 18092 --rhost 10.0.0.9 --rport 443 --allow 2001:db8:abcd::/48 --tcpwrap
    [ "$status" -eq 0 ]
    sleep 0.3
    local line; line="$(_launch_line)"
    [[ "${line}" == *"range=[2001:db8:abcd:0:0:0:0:0]/48"* ]]
    [[ "${line}" == *"tcpwrap=socat"* ]]
}

@test "P-03: redirect --allow adds range without tcpwrap" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" redirect \
        --lport 18093 --rhost 10.0.0.9 --rport 443 --allow 192.168.5.66/24
    [ "$status" -eq 0 ]
    sleep 0.3
    local line; line="$(_launch_line)"
    [[ "${line}" == *"range=192.168.5.0/24"* ]]
    [[ "${line}" != *"tcpwrap="* ]]
}

@test "P-03: tunnel --allow applies filter to the OPENSSL listener" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" tunnel \
        --port 18094 --rhost 10.0.0.9 --rport 22 --allow 10.0.0.0/8 --tcpwrap twrap
    [ "$status" -eq 0 ]
    sleep 0.3
    run grep -oE 'ARGS=.*OPENSSL-LISTEN.*' "${TEST_TMPDIR}/.socat_stub.log"
    [[ "$output" == *"range=10.0.0.0/8"* ]]
    [[ "$output" == *"tcpwrap=twrap"* ]]
}

@test "P-03: invalid --allow CIDR is rejected before launch" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 18095 --allow 999.0.0.0/8
    [ "$status" -ne 0 ]
}

@test "P-03: invalid --tcpwrap name is rejected before launch" {
    run bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 18096 --tcpwrap "bad name"
    [ "$status" -ne 0 ]
}
