#======================================================================
# DEPENDENCY CHECK
# Verify that socat is installed before attempting any operations
#======================================================================

# Function: check_socat
# Description: Verify socat is available in PATH and provide install
#              guidance if missing. Called before all operational modes
#              (listen, batch, forward, tunnel, redirect) but skipped
#              for status and stop modes which only need session files.
check_socat() {
    if ! command -v socat &>/dev/null; then
        log_critical "socat is not installed or not in PATH"
        echo "" >&2
        echo -e "  ${CLR_BOLD}Install socat:${CLR_RESET}" >&2
        echo -e "    ${CLR_CYAN}sudo apt-get update && sudo apt-get install -y socat${CLR_RESET}" >&2
        echo -e "    ${CLR_CYAN}# or: sudo yum install -y socat${CLR_RESET}" >&2
        echo -e "    ${CLR_CYAN}# or: sudo pacman -S socat${CLR_RESET}" >&2
        echo "" >&2
        exit 1
    fi

    log_debug "socat found: $(command -v socat) ($(socat -V 2>/dev/null | head -2 | tail -1 | xargs))" "deps"
}

