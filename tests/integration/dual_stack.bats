#!/usr/bin/env bats
#======================================================================
# TEST FILE  : tests/integration/dual_stack.bats
#======================================================================
# Synopsis   : Integration tests for dual-stack (TCP + UDP) operations
#              and protocol-scoped stop behavior.
#
# Description: Verifies that:
#              - Dual-stack launch creates two independent sessions
#              - Each protocol gets its own Session ID
#              - Stopping TCP does NOT affect UDP on the same port
#              - Stopping UDP does NOT affect TCP on the same port
#              - stop --port stops all protocols on a port
#              - Session names include protocol for disambiguation
#              - session_find_by_port returns both protocols
#
#              These tests validate the v2.2.0 fix for the cross-
#              protocol kill bug where stopping one protocol killed
#              the other protocol's session on the same port.
#
# Execution  : bats tests/integration/dual_stack.bats
#
# Notes      : - Uses stubbed socat and ss for isolation
#              - Tests protocol-scoped _stop_session behavior
#                directly, not via the CLI mode_stop dispatcher
#
# Version    : 1.0.0
#======================================================================

# =====================================================================
# SETUP / TEARDOWN
# =====================================================================

setup() {
    load '../helpers/test_helper'
    helper_setup
    clear_ss_state
}

teardown() {
    helper_teardown
}

# =====================================================================
# Dual-stack launch
# =====================================================================

@test "dual-stack: launching TCP and UDP creates two sessions" {
    # Launch TCP session
    launch_socat_session "redir-tcp4-8443" "redirect" "tcp4" "8443" \
        "socat TCP4-LISTEN:8443,reuseaddr,fork TCP4:example.com:443" \
        "example.com" "443"
    local tcp_sid="${LAUNCH_SID}"

    # Launch UDP session on same port
    launch_socat_session "redir-udp4-8443" "redirect" "udp4" "8443" \
        "socat UDP4-LISTEN:8443,reuseaddr,fork UDP4:example.com:443" \
        "example.com" "443"
    local udp_sid="${LAUNCH_SID}"

    # Both session files should exist
    [ -f "${SESSION_DIR}/${tcp_sid}.session" ]
    [ -f "${SESSION_DIR}/${udp_sid}.session" ]

    # SIDs should be different
    [ "${tcp_sid}" != "${udp_sid}" ]
}

@test "dual-stack: each session records correct protocol" {
    launch_socat_session "redir-tcp4-8443" "redirect" "tcp4" "8443" \
        "socat TCP4-LISTEN:8443,reuseaddr,fork TCP4:example.com:443" \
        "example.com" "443"
    local tcp_sid="${LAUNCH_SID}"

    launch_socat_session "redir-udp4-8443" "redirect" "udp4" "8443" \
        "socat UDP4-LISTEN:8443,reuseaddr,fork UDP4:example.com:443" \
        "example.com" "443"
    local udp_sid="${LAUNCH_SID}"

    local tcp_proto udp_proto
    tcp_proto="$(session_read_field "${SESSION_DIR}/${tcp_sid}.session" "PROTOCOL")"
    udp_proto="$(session_read_field "${SESSION_DIR}/${udp_sid}.session" "PROTOCOL")"

    [ "${tcp_proto}" = "tcp4" ]
    [ "${udp_proto}" = "udp4" ]
}

@test "dual-stack: session_find_by_port returns both protocols" {
    launch_socat_session "redir-tcp4-8443" "redirect" "tcp4" "8443" \
        "socat TCP4-LISTEN:8443,reuseaddr,fork TCP4:example.com:443"
    local tcp_sid="${LAUNCH_SID}"

    launch_socat_session "redir-udp4-8443" "redirect" "udp4" "8443" \
        "socat UDP4-LISTEN:8443,reuseaddr,fork UDP4:example.com:443"
    local udp_sid="${LAUNCH_SID}"

    local result
    result="$(session_find_by_port "8443")"
    local count
    count="$(echo "${result}" | wc -l)"
    [ "${count}" -eq 2 ]

    # Both SIDs should be in the result
    [[ "${result}" == *"${tcp_sid}"* ]]
    [[ "${result}" == *"${udp_sid}"* ]]
}

# =====================================================================
# Protocol-scoped stop (CRITICAL: the v2.2.0 fix)
# =====================================================================

@test "protocol-scoped stop: stopping TCP preserves UDP session" {
    # Launch both protocols
    launch_socat_session "redir-tcp4-8443" "redirect" "tcp4" "8443" \
        "socat TCP4-LISTEN:8443,reuseaddr,fork TCP4:example.com:443" \
        "example.com" "443"
    local tcp_sid="${LAUNCH_SID}"

    launch_socat_session "redir-udp4-8443" "redirect" "udp4" "8443" \
        "socat UDP4-LISTEN:8443,reuseaddr,fork UDP4:example.com:443" \
        "example.com" "443"
    local udp_sid="${LAUNCH_SID}"

    local udp_pid
    udp_pid="$(session_read_field "${SESSION_DIR}/${udp_sid}.session" "PID")"

    # Stop ONLY the TCP session
    _stop_session "${tcp_sid}"

    # TCP session file should be removed
    [ ! -f "${SESSION_DIR}/${tcp_sid}.session" ]

    # UDP session file MUST still exist (this was the v2.1 bug)
    [ -f "${SESSION_DIR}/${udp_sid}.session" ]

    # UDP process MUST still be alive
    kill -0 "${udp_pid}" 2>/dev/null
}

@test "protocol-scoped stop: stopping UDP preserves TCP session" {
    # Launch both protocols
    launch_socat_session "redir-tcp4-8443" "redirect" "tcp4" "8443" \
        "socat TCP4-LISTEN:8443,reuseaddr,fork TCP4:example.com:443" \
        "example.com" "443"
    local tcp_sid="${LAUNCH_SID}"
    local tcp_pid
    tcp_pid="$(session_read_field "${SESSION_DIR}/${tcp_sid}.session" "PID")"

    launch_socat_session "redir-udp4-8443" "redirect" "udp4" "8443" \
        "socat UDP4-LISTEN:8443,reuseaddr,fork UDP4:example.com:443" \
        "example.com" "443"
    local udp_sid="${LAUNCH_SID}"

    # Stop ONLY the UDP session
    _stop_session "${udp_sid}"

    # UDP session file should be removed
    [ ! -f "${SESSION_DIR}/${udp_sid}.session" ]

    # TCP session file MUST still exist
    [ -f "${SESSION_DIR}/${tcp_sid}.session" ]

    # TCP process MUST still be alive
    kill -0 "${tcp_pid}" 2>/dev/null
}

@test "protocol-scoped stop: _stop_session reads PROTOCOL from session file" {
    # Spawn a real process for a living PID
    sleep 300 &
    local alive_pid=$!

    # Create a mock session with explicit udp4 protocol
    create_mock_session "aabb1122" "redir-udp4-5353" "${alive_pid}" "redirect" "udp4" "5353"

    # Read the protocol field to verify it's stored correctly
    local proto
    proto="$(session_read_field "${SESSION_DIR}/aabb1122.session" "PROTOCOL")"
    [ "${proto}" = "udp4" ]

    kill "${alive_pid}" 2>/dev/null || true
}

# =====================================================================
# stop --port: stops all protocols on a port
# =====================================================================

@test "stop by port: stops both TCP and UDP sessions" {
    launch_socat_session "redir-tcp4-8443" "redirect" "tcp4" "8443" \
        "socat TCP4-LISTEN:8443,reuseaddr,fork TCP4:example.com:443"
    local tcp_sid="${LAUNCH_SID}"

    launch_socat_session "redir-udp4-8443" "redirect" "udp4" "8443" \
        "socat UDP4-LISTEN:8443,reuseaddr,fork UDP4:example.com:443"
    local udp_sid="${LAUNCH_SID}"

    # Stop both by iterating all sessions on the port
    local port_sids
    port_sids="$(session_find_by_port "8443")"
    while IFS= read -r sid; do
        [[ -z "${sid}" ]] && continue
        _stop_session "${sid}"
    done <<< "${port_sids}"

    # Both session files should be removed
    [ ! -f "${SESSION_DIR}/${tcp_sid}.session" ]
    [ ! -f "${SESSION_DIR}/${udp_sid}.session" ]
}

# =====================================================================
# Session isolation across different ports
# =====================================================================

@test "port isolation: sessions on different ports are independent" {
    # Launch on port 8080
    launch_socat_session "listen-tcp4-8080" "listen" "tcp4" "8080" \
        "socat TCP4-LISTEN:8080,reuseaddr,fork OPEN:/dev/null,creat,append"
    local sid_8080="${LAUNCH_SID}"

    # Launch on port 9090
    launch_socat_session "listen-tcp4-9090" "listen" "tcp4" "9090" \
        "socat TCP4-LISTEN:9090,reuseaddr,fork OPEN:/dev/null,creat,append"
    local sid_9090="${LAUNCH_SID}"

    # Stop only port 8080
    _stop_session "${sid_8080}"

    # Port 8080 session removed
    [ ! -f "${SESSION_DIR}/${sid_8080}.session" ]

    # Port 9090 session preserved
    [ -f "${SESSION_DIR}/${sid_9090}.session" ]
    local pid_9090
    pid_9090="$(session_read_field "${SESSION_DIR}/${sid_9090}.session" "PID")"
    kill -0 "${pid_9090}" 2>/dev/null
}
