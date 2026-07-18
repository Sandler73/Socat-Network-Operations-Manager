#======================================================================
# CONSTANTS AND CONFIGURATION
#======================================================================

# Script metadata
readonly SCRIPT_NAME="$(basename "${BASH_SOURCE[0]}" .sh)"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Absolute path to this script file, used to re-exec ourselves as a detached
# watchdog supervisor (see WATCHDOG / AUTO-RESTART). Resolved from BASH_SOURCE
# so it is correct regardless of the invocation name or the caller's CWD.
readonly SCRIPT_SELF="${SCRIPT_DIR}/$(basename "${BASH_SOURCE[0]}")"
readonly SCRIPT_VERSION="2.5.1"
readonly SCRIPT_PID="$$"

# Directory structure
#
# Runtime data (logs, sessions, conf, certs) lives under a base directory.
# Resolution order:
#   1. SOCAT_MANAGER_BASE environment variable (explicit override)
#   2. The script's own directory (SCRIPT_DIR)
# The override lets the tool run against a dedicated data directory (for example
# under /var/lib) instead of writing beside the script, and keeps concurrent or
# containerised instances isolated. The resolved value is exported so the
# detached watchdog supervisor (a re-exec of this script) derives the same paths.
if [[ -n "${SOCAT_MANAGER_BASE:-}" ]]; then
    if [[ -d "${SOCAT_MANAGER_BASE}" ]]; then
        readonly BASE_DIR="$(cd "${SOCAT_MANAGER_BASE}" && pwd)"
    else
        # Directory need not exist yet (_ensure_dirs creates it); just make the
        # path absolute so every process resolves it identically.
        case "${SOCAT_MANAGER_BASE}" in
            /*) readonly BASE_DIR="${SOCAT_MANAGER_BASE}" ;;
            *)  readonly BASE_DIR="$(pwd)/${SOCAT_MANAGER_BASE}" ;;
        esac
    fi
else
    readonly BASE_DIR="${SCRIPT_DIR}"
fi
export SOCAT_MANAGER_BASE="${BASE_DIR}"

readonly LOG_DIR="${BASE_DIR}/logs"
readonly SESSION_DIR="${BASE_DIR}/sessions"
readonly CONF_DIR="${BASE_DIR}/conf"
readonly CERT_DIR="${BASE_DIR}/certs"

# Timestamp for this execution (used in log filenames)
readonly EXEC_TIMESTAMP="$(date '+%Y-%m-%dT%H-%M-%S')"

# Correlation ID for this execution (first 8 chars of a pseudo-UUID)
# Uses cat with error suppression; fallback to timestamp hash if /proc unavailable
readonly CORRELATION_ID="$(cat /proc/sys/kernel/random/uuid 2>/dev/null | tr -d '-' | cut -c1-8 || date +%s%N | sha256sum | cut -c1-8)"

# Master log for this execution
readonly MASTER_LOG="${LOG_DIR}/${SCRIPT_NAME}-${EXEC_TIMESTAMP}.log"

# Default values (readonly to prevent accidental modification)
readonly DEFAULT_PROTOCOL="tcp4"            # Default to IPv4 TCP
readonly DEFAULT_BACKLOG=128                # socat listen backlog
readonly DEFAULT_WATCHDOG_INTERVAL=5        # Seconds between watchdog health checks
readonly DEFAULT_WATCHDOG_MAX_RESTARTS=10   # Max auto-restarts before giving up

# Maximum concurrent sessions to prevent resource exhaustion
readonly MAX_SESSIONS=256

# Stop timing constants
readonly STOP_GRACE_SECONDS=5      # Seconds to wait after SIGTERM before SIGKILL
readonly STOP_VERIFY_RETRIES=5     # Number of verification checks after stop
readonly STOP_VERIFY_INTERVAL=0.5  # Seconds between verification checks

# PID-file handoff timeout (iterations at 0.1s each)
readonly PID_FILE_WAIT_ITERS=20    # 2 seconds max wait for PID file

# Global variable for launch_socat_session to return session ID.
# Using a global avoids $() subshell capture which causes terminal
# blocking due to inherited stdout file descriptors. See the
# PROCESS LAUNCH WRAPPER section for detailed explanation.
LAUNCH_SID=""

# Color codes for terminal output
readonly CLR_RESET="\033[0m"
readonly CLR_BOLD="\033[1m"
readonly CLR_DIM="\033[2m"
readonly CLR_RED="\033[31m"
readonly CLR_GREEN="\033[32m"
readonly CLR_YELLOW="\033[33m"
readonly CLR_BLUE="\033[34m"
readonly CLR_CYAN="\033[36m"
readonly CLR_MAGENTA="\033[35m"
readonly CLR_WHITE="\033[37m"

# Status symbols
readonly SYM_OK="✓"
readonly SYM_FAIL="✗"
readonly SYM_WARN="!"
readonly SYM_INFO="i"
readonly SYM_ARROW="→"
readonly SYM_PLUS="+"
readonly SYM_LISTEN="◉"
readonly SYM_FORWARD="⇄"
readonly SYM_TUNNEL="⊙"
readonly SYM_SESSION="■"

