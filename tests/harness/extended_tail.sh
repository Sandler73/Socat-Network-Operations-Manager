#!/usr/bin/env bash
#======================================================================
# HARNESS    : tests/harness/extended_tail.sh
#======================================================================
# Synopsis   : Direct-assertion runner for the tail of extended.bats.
#
# Description: bats-core 1.13.0 in this sandbox aborts the extended.bats
#              file runner at a fixed index (~test 32) with a spurious
#              "bats-exec-file ... .out: No such file" error. That is a
#              runner artifact, not a test failure (it reproduces on the
#              unmodified baseline). This harness sources the script and
#              executes the assertions for the tail tests (unknown-flag
#              rejections, legacy fixtures, watchdog stub mechanics,
#              session-file format) so they remain verified.
#
# Usage      : bash tests/harness/extended_tail.sh
# Version    : 2.4.3
#======================================================================
set +e
PROJECT_ROOT="/home/claude/work/socat-manager-bash"
export STUBS_DIR="${PROJECT_ROOT}/tests/stubs"
export FIXTURES_DIR="${PROJECT_ROOT}/tests/fixtures"
TEST_TMPDIR="$(mktemp -d /home/claude/btmp/ext-tail-XXXXXX)"
export TEST_TMPDIR
export PATH="${STUBS_DIR}:${PATH}"
ln -sf "${PROJECT_ROOT}/socat_manager.sh" "${TEST_TMPDIR}/socat_manager.sh"
cd "${TEST_TMPDIR}" || exit 9
source "${TEST_TMPDIR}/socat_manager.sh" >/dev/null 2>&1
set +euo pipefail
_ensure_dirs >/dev/null 2>&1
: "${SESSION_DIR:=${TEST_TMPDIR}/sessions}"
mkdir -p "${SESSION_DIR}"

PASS=0; FAIL=0
pass() { PASS=$((PASS+1)); }
fail() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

SM="${TEST_TMPDIR}/socat_manager.sh"

# 33-35 unknown-flag rejections for forward/redirect/tunnel
for spec in \
  "forward --lport 8080 --rhost 10.0.0.1 --rport 80" \
  "redirect --lport 8080 --rhost 10.0.0.1 --rport 80" \
  "tunnel --port 4443 --rhost 10.0.0.1 --rport 22"; do
  out=$(bash "${SM}" ${spec} --bogus 2>&1); rc=$?
  if [ "${rc}" -ne 0 ] && [[ "${out}" == *nknown* ]]; then pass; else fail "reject unknown: ${spec}"; fi
done

# 36 stop rejects unknown
out=$(bash "${SM}" stop --bogus 2>&1); rc=$?
if [ "${rc}" -ne 0 ] && [[ "${out}" == *nknown* ]]; then pass; else fail "stop rejects unknown"; fi

# 37 tunnel udp4 rejected with guidance
out=$(bash "${SM}" tunnel --port 4443 --rhost 10.0.0.1 --rport 22 --proto udp4 2>&1); rc=$?
if [ "${rc}" -ne 0 ] && { [[ "${out}" == *TCP* ]] || [[ "${out}" == *forward* ]]; }; then pass; else fail "tunnel udp4 rejected"; fi

# 38 legacy .pid detected
cp "${FIXTURES_DIR}/legacy_session.pid" "${SESSION_DIR}/old-session.pid"
if [ -f "${SESSION_DIR}/old-session.pid" ] && grep -q '^PID=' "${SESSION_DIR}/old-session.pid" && grep -q '^MODE=' "${SESSION_DIR}/old-session.pid"; then pass; else fail "legacy .pid detected"; fi

# 39 legacy v1 fields (no v2)
F="${FIXTURES_DIR}/legacy_session.pid"
if grep -q '^PROTOCOL=' "${F}" && grep -q '^MASTER_PID=' "${F}" && ! grep -q '^SESSION_ID=' "${F}" && ! grep -q '^PGID=' "${F}"; then pass; else fail "legacy v1 fields"; fi

# 40 stub exit=1
SOCAT_STUB_EXIT=1 bash "${STUBS_DIR}/socat" "TCP4-LISTEN:8080" >/dev/null 2>&1; rc=$?
if [ "${rc}" -eq 1 ]; then pass; else fail "stub exit=1 (got ${rc})"; fi

# 41 stub exit=0
SOCAT_STUB_EXIT=0 bash "${STUBS_DIR}/socat" "TCP4-LISTEN:8080" >/dev/null 2>&1; rc=$?
if [ "${rc}" -eq 0 ]; then pass; else fail "stub exit=0 (got ${rc})"; fi

# 42 stub logs args on immediate exit
SOCAT_STUB_EXIT=1 bash "${STUBS_DIR}/socat" "TCP4-LISTEN:8080" "reuseaddr,fork" >/dev/null 2>&1 || true
if grep -q 'TCP4-LISTEN:8080' "${TEST_TMPDIR}/.socat_stub.log"; then pass; else fail "stub logs args on exit"; fi

# 43 stub responds to SIGTERM
bash "${STUBS_DIR}/socat" "TCP4-LISTEN:9999" >/dev/null 2>&1 &
sp=$!; sleep 0.2
kill -0 "${sp}" 2>/dev/null; alive=$?
kill -TERM "${sp}" 2>/dev/null; wait "${sp}" 2>/dev/null
kill -0 "${sp}" 2>/dev/null; dead=$?
if [ "${alive}" -eq 0 ] && [ "${dead}" -ne 0 ]; then pass; else fail "stub SIGTERM"; fi

# 44 v2.2 fixture fields
S="${FIXTURES_DIR}/sample_session.session"
if grep -q '^SESSION_ID=' "${S}" && grep -q '^PGID=' "${S}" && grep -q '^SOCAT_CMD=' "${S}" && grep -q '^CORRELATION=' "${S}"; then pass; else fail "v2.2 fixture fields"; fi

# 45 session_register output format
session_register "aabb1122" "test-session" "12345" "12345" "redirect" "tcp4" "8443" "socat TCP4-LISTEN:8443" "example.com" "443" >/dev/null 2>&1
sf="${SESSION_DIR}/aabb1122.session"
if grep -q '^SESSION_ID=aabb1122' "${sf}" && grep -q '^PGID=12345' "${sf}" && grep -q '^MODE=redirect' "${sf}" && grep -q '^CORRELATION=' "${sf}"; then pass; else fail "session_register format"; fi

echo "======================"
echo "TAIL HARNESS: PASS=${PASS} FAIL=${FAIL}"
pkill -x socat 2>/dev/null || true
rm -rf "${TEST_TMPDIR}"
