#!/usr/bin/env bash
# =============================================================================
# socat_manager virtual environment activation script
# =============================================================================
# Source this file to set up the isolated socat_manager environment.
#
# Usage:
#   source activate.sh          # Activate the environment
#   socat-manager --version     # Use the tool
#   deactivate_socat            # Deactivate when done
#
# This script:
#   1. Sets SOCAT_MANAGER_HOME to this venv directory
#   2. Adds the venv to PATH (socat_manager.sh accessible as 'socat-manager')
#   3. Creates an alias for convenient invocation
#   4. Provides a 'deactivate_socat' function to restore the original environment
#   5. Displays activation confirmation
#
# Notes:
#   - Deactivating does NOT stop running sessions (they run independently)
#   - Run `socat-manager stop --all` before deactivating if needed
#
# Version: 1.0.0
# =============================================================================

# Resolve the venv directory (where this script lives)
SOCAT_MANAGER_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SOCAT_MANAGER_HOME

# Save original PATH for deactivation
_SOCAT_OLD_PATH="${PATH}"

# Add venv to PATH
export PATH="${SOCAT_MANAGER_HOME}:${PATH}"

# Create convenient alias
alias socat-manager="${SOCAT_MANAGER_HOME}/socat_manager.sh"

# Deactivation function
deactivate_socat() {
    export PATH="${_SOCAT_OLD_PATH}"
    unset SOCAT_MANAGER_HOME _SOCAT_OLD_PATH
    unalias socat-manager 2>/dev/null
    unset -f deactivate_socat
    echo "[i] socat_manager venv deactivated"
}

# Change to venv directory so runtime dirs are created here
cd "${SOCAT_MANAGER_HOME}"

echo ""
echo "  socat_manager virtual environment activated"
echo "  Home: ${SOCAT_MANAGER_HOME}"
echo "  Run:  socat-manager <MODE> [OPTIONS]"
echo "  Exit: deactivate_socat"
echo ""
