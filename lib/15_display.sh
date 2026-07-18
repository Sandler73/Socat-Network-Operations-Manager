#======================================================================
# DISPLAY UTILITIES
#======================================================================

# Function: print_banner
# Description: Display styled script header with mode information
# Parameters:
#   $1 - Mode name (e.g., "Listener", "Forwarder")
print_banner() {
    local mode="${1:-Manager}"
    echo -e "" >&2
    echo -e "  ${CLR_BOLD}${CLR_CYAN}╔══════════════════════════════════════════════╗${CLR_RESET}" >&2
    echo -e "  ${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}  ${CLR_BOLD}socat ${mode}${CLR_RESET}  (v${SCRIPT_VERSION})$(printf '%*s' $((27 - ${#mode} - ${#SCRIPT_VERSION})) '')${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}" >&2
    echo -e "  ${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}  Correlation: ${CORRELATION_ID}                       ${CLR_BOLD}${CLR_CYAN}║${CLR_RESET}" >&2
    echo -e "  ${CLR_BOLD}${CLR_CYAN}╚══════════════════════════════════════════════╝${CLR_RESET}" >&2
    echo -e "" >&2
}

# Function: print_section
# Description: Print a visual section divider with title
# Parameters:
#   $1 - Section title
print_section() {
    echo -e "" >&2
    echo -e "  ${CLR_BOLD}─── ${1} ───${CLR_RESET}" >&2
}

# Function: print_kv
# Description: Print a key-value pair with consistent alignment
# Parameters:
#   $1 - Key label
#   $2 - Value
print_kv() {
    printf "  ${CLR_DIM}%-20s${CLR_RESET} %s\n" "${1}:" "${2}" >&2
}

