#!/usr/bin/env bats
#======================================================================
# TEST SUITE : base_dir.bats
#======================================================================
# Synopsis   : Tests for the SOCAT_MANAGER_BASE directory override.
#
# Description: Verifies that runtime data (sessions, logs, certs, conf)
#              is rooted at SOCAT_MANAGER_BASE when set, that the value is
#              made absolute, and that the default (unset) roots data at
#              the script directory. A supervised launch confirms the
#              detached watchdog re-exec resolves the same base.
#
# Version    : 2.4.4
#======================================================================

load ../helpers/test_helper

setup() {
    helper_setup
    export SOCAT_STUB_SLEEP=5
}

teardown() {
    pkill -x socat 2>/dev/null || true
    helper_teardown
}

@test "P-05: SOCAT_MANAGER_BASE roots session data at the override" {
    local base="${TEST_TMPDIR}/override-base"
    run env SOCAT_MANAGER_BASE="${base}" \
        bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19110 --name basecheck
    [ "$status" -eq 0 ]
    sleep 0.3
    # The session directory and a session file must exist under the override.
    [ -d "${base}/sessions" ]
    [ -d "${base}/logs" ]
    run bash -c "ls '${base}/sessions'/*.session 2>/dev/null | wc -l"
    [ "$output" -ge 1 ]
}

@test "P-05: a relative SOCAT_MANAGER_BASE is resolved to an absolute path" {
    cd "${TEST_TMPDIR}"
    run env SOCAT_MANAGER_BASE="reldata" \
        bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19111 --name relcheck
    [ "$status" -eq 0 ]
    sleep 0.3
    [ -d "${TEST_TMPDIR}/reldata/sessions" ]
}

@test "P-05: default base (unset) is the script directory" {
    # With no override, data is created beside the (symlinked) script in TEST_TMPDIR.
    run env -u SOCAT_MANAGER_BASE \
        bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19112 --name defcheck
    [ "$status" -eq 0 ]
    sleep 0.3
    [ -d "${TEST_TMPDIR}/sessions" ]
}

@test "P-05: supervised session under an override is found and stopped" {
    local base="${TEST_TMPDIR}/sup-base"
    run env SOCAT_MANAGER_BASE="${base}" \
        bash "${TEST_TMPDIR}/socat_manager.sh" listen --port 19113 --watchdog --name supcheck
    [ "$status" -eq 0 ]
    sleep 1.2
    run bash -c "ls '${base}/sessions'/*.session 2>/dev/null | wc -l"
    [ "$output" -ge 1 ]
    # Stop must resolve the same base to find and remove the session.
    run env SOCAT_MANAGER_BASE="${base}" \
        bash "${TEST_TMPDIR}/socat_manager.sh" stop --all
    [ "$status" -eq 0 ]
    sleep 0.4
    run bash -c "ls '${base}/sessions'/*.session 2>/dev/null | wc -l"
    [ "$output" -eq 0 ]
}
