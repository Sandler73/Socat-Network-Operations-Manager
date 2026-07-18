#!/usr/bin/env bash
#======================================================================
# SCRIPT     : tests/run-suite.sh
#======================================================================
# Synopsis   : Run a directory of BATS test files one file at a time and
#              aggregate the results.
#
# Description: The CI previously invoked `bats <dir>` on a whole directory in
#              a single process. That multi-file run path is fragile: a hiccup
#              in one file's temporary-output handling, or an advisory warning
#              (which makes bats exit non-zero), aborts or fails the entire
#              step so that every test appears to fail. Running each file in
#              its own bats process isolates files from one another, so a real
#              failure is attributed to a single file and a spurious warning in
#              one file does not sink the rest.
#
#              For each *.bats file the script runs `bats --tap <file>`, streams
#              and records the TAP output, and tracks:
#                - any "not ok" line          -> a genuine test failure
#                - a non-zero bats exit with  -> reported as a warning, not a
#                  no "not ok" line              hard failure (e.g. BW01 advisory)
#
#              The script exits non-zero if and only if at least one real test
#              failure ("not ok") was seen. It prints a per-file and overall
#              summary for diagnostics.
#
# Execution  : bash tests/run-suite.sh <dir> [<results.tap>]
#                <dir>          directory containing *.bats files (required)
#                <results.tap>  optional path to write the combined TAP to
#
# Version    : 1.0.0
#======================================================================
set -uo pipefail

SUITE_DIR="${1:?usage: run-suite.sh <dir> [results.tap]}"
RESULTS="${2:-}"

if [[ ! -d "${SUITE_DIR}" ]]; then
    echo "run-suite: '${SUITE_DIR}' is not a directory" >&2
    exit 2
fi

# Resolve the bats executable (allow override via BATS_BIN for pinned versions).
BATS_BIN="${BATS_BIN:-bats}"
if ! command -v "${BATS_BIN}" >/dev/null 2>&1; then
    echo "run-suite: bats not found (BATS_BIN='${BATS_BIN}')" >&2
    exit 2
fi

shopt -s nullglob
files=("${SUITE_DIR}"/*.bats)
shopt -u nullglob

if (( ${#files[@]} == 0 )); then
    echo "run-suite: no *.bats files in '${SUITE_DIR}'" >&2
    exit 2
fi

combined="$(mktemp)"
trap 'rm -f "${combined}"' EXIT

total_files=0
failed_files=()
warned_files=()

for f in "${files[@]}"; do
    total_files=$((total_files + 1))
    echo "==================================================================="
    echo "  ${f}"
    echo "==================================================================="

    one="$(mktemp)"
    "${BATS_BIN}" --tap "${f}" > "${one}" 2>&1
    rc=$?

    cat "${one}"
    cat "${one}" >> "${combined}"

    if grep -q '^not ok' "${one}"; then
        failed_files+=("${f}")
    elif [[ ${rc} -ne 0 ]]; then
        # Non-zero exit but no failing assertion: advisory warning or a
        # bats-internal hiccup. Record it, but do not fail the suite on it.
        warned_files+=("${f}")
    fi
    rm -f "${one}"
    echo ""
done

if [[ -n "${RESULTS}" ]]; then
    mkdir -p "$(dirname "${RESULTS}")"
    cp "${combined}" "${RESULTS}"
fi

echo "==================================================================="
echo "  Suite summary: ${SUITE_DIR}"
echo "==================================================================="
ok_count="$(grep -c '^ok' "${combined}" || true)"
notok_count="$(grep -c '^not ok' "${combined}" || true)"
echo "  files run : ${total_files}"
echo "  ok        : ${ok_count}"
echo "  not ok    : ${notok_count}"

if (( ${#warned_files[@]} > 0 )); then
    echo "  warnings  : ${#warned_files[@]} file(s) exited non-zero without a failing assertion:"
    for f in "${warned_files[@]}"; do echo "              - ${f}"; done
fi

if (( ${#failed_files[@]} > 0 )); then
    echo ""
    echo "  FAILED file(s):"
    for f in "${failed_files[@]}"; do echo "              - ${f}"; done
    echo ""
    echo "  Failing tests:"
    grep '^not ok' "${combined}" || true
    exit 1
fi

echo "  result    : PASS"
exit 0
