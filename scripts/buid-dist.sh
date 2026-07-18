#!/usr/bin/env bash
#======================================================================
# SCRIPT     : scripts/build-dist.sh
#======================================================================
# Synopsis   : Assemble the single-file socat_manager.sh from lib/ modules.
#
# Description: Concatenates the module sources under lib/ (ordered by their
#              numeric filename prefix) into the distributed single-file
#              script socat_manager.sh, inserting a generated-file notice
#              immediately after the shebang. The single-file form is the
#              shipped, self-contained artifact; lib/ is the editable source.
#
# Execution  : bash scripts/build-dist.sh [--check]
#              --check : build to a temporary file and diff against the
#                        committed socat_manager.sh; exit non-zero if they
#                        differ (used by `make verify-build`). Does not write.
#
# Version    : 2.5.1
#======================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

OUT="socat_manager.sh"
CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

# Module sources, ordered by numeric prefix (glob sort is lexicographic and the
# prefixes are fixed-width, so this is the intended assembly order).
shopt -s nullglob
LIBS=(lib/*.sh)
shopt -u nullglob

if (( ${#LIBS[@]} == 0 )); then
    echo "build-dist: no lib/*.sh modules found" >&2
    exit 1
fi

tmp_concat="$(mktemp)"
tmp_out="$(mktemp)"
trap 'rm -f "${tmp_concat}" "${tmp_out}"' EXIT

cat "${LIBS[@]}" > "${tmp_concat}"

# Insert the generated notice right after the shebang line.
{
    head -n 1 "${tmp_concat}"
    cat <<'NOTICE'
#
# ============================ GENERATED FILE ============================
# This single-file script is assembled by scripts/build-dist.sh from the
# module sources under lib/. Do not edit socat_manager.sh directly - edit
# the relevant lib/NN_*.sh module and rebuild with `make build`. The
# single-file form is the distributed, self-contained artifact.
# =======================================================================
NOTICE
    tail -n +2 "${tmp_concat}"
} > "${tmp_out}"

if [[ "${CHECK}" == true ]]; then
    if [[ ! -f "${OUT}" ]]; then
        echo "build-dist --check: ${OUT} does not exist (run 'make build')" >&2
        exit 1
    fi
    if cmp -s "${tmp_out}" "${OUT}"; then
        echo "build-dist --check: ${OUT} is up to date with lib/ (${#LIBS[@]} modules)"
        exit 0
    fi
    echo "build-dist --check: ${OUT} is STALE - rebuild with 'make build'" >&2
    diff "${OUT}" "${tmp_out}" | head -40 >&2 || true
    exit 1
fi

cp "${tmp_out}" "${OUT}"
chmod +x "${OUT}"
echo "Built ${OUT} from ${#LIBS[@]} modules ($(wc -l < "${OUT}") lines)"
