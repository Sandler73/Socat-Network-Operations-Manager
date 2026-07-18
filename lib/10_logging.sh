#======================================================================
# LOGGING INFRASTRUCTURE
# Dual output: always to file, optionally to console
# Per-execution master log + per-listener individual logs
# Compliant with OWASP Logging Cheat Sheet / NIST SP 800-92
#======================================================================

VERBOSE_MODE=false  # Set by --verbose / -v flag

# Log output format for the master and session log files. "text" produces the
# structured line format; "json" produces one JSON object per line (NDJSON) for
# ingestion by log pipelines. Console output is always human-readable regardless.
# Defaults from SOCAT_MANAGER_LOG_FORMAT and may be overridden by --log-format.
LOG_FORMAT="${SOCAT_MANAGER_LOG_FORMAT:-text}"
case "${LOG_FORMAT}" in
    text|json) ;;
    *) LOG_FORMAT="text" ;;
esac

# Minimum severity to emit to the master log and console. Messages ranked below
# this level are suppressed from both. Order (low to high):
# DEBUG < INFO < WARNING < ERROR < CRITICAL. Defaults from
# SOCAT_MANAGER_LOG_LEVEL and may be overridden by --log-level. The --verbose /
# -v flag lowers the effective threshold to DEBUG so debug output is shown
# regardless of this setting.
LOG_LEVEL="${SOCAT_MANAGER_LOG_LEVEL:-INFO}"
case "${LOG_LEVEL}" in
    DEBUG|INFO|WARNING|ERROR|CRITICAL) ;;
    *) LOG_LEVEL="INFO" ;;
esac

# Function: _log_level_rank
# Description: Map a log level name to a numeric rank for threshold comparison.
# Parameters:
#   $1 - level name
# Outputs: integer rank (unknown level maps to INFO's rank)
_log_level_rank() {
    case "${1:-INFO}" in
        DEBUG)    echo 0 ;;
        INFO)     echo 1 ;;
        WARNING)  echo 2 ;;
        ERROR)    echo 3 ;;
        CRITICAL) echo 4 ;;
        *)        echo 1 ;;
    esac
}

# Terminal detection: disable color codes when stderr is not a terminal
# (e.g., when output is piped to a file or another command)
USE_COLOR=true
if [[ ! -t 2 ]]; then
    USE_COLOR=false
fi

# Guard: tracks whether directories have been initialized this execution
_DIRS_ENSURED=false

# Function: _ensure_dirs
# Description: Create required directory structure if missing.
#              Sets restrictive permissions on session directory
#              to protect PID/session metadata from unauthorized access.
#              Uses a guard variable to avoid redundant mkdir/chmod
#              system calls on every log write.
_ensure_dirs() {
    [[ "${_DIRS_ENSURED}" == true ]] && return 0
    mkdir -p "${LOG_DIR}" "${SESSION_DIR}" "${CONF_DIR}" "${CERT_DIR}" 2>/dev/null || true
    # Restrict session directory permissions (session files contain PIDs and commands)
    chmod 700 "${SESSION_DIR}" 2>/dev/null || true
    _DIRS_ENSURED=true
}

# Function: _json_escape
# Description: Escape a string for safe inclusion inside a JSON double-quoted
#              value. Handles backslash, double quote, and the common control
#              characters (tab, carriage return, newline).
# Parameters:
#   $1 - string to escape
# Outputs: the escaped string (no surrounding quotes)
_json_escape() {
    local s="${1:-}"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\n'/\\n}"
    printf '%s' "${s}"
}

# Function: _log_write
# Description: Core log writer - appends a structured entry to the master log
#              and optionally echoes to the console with color coding. The file
#              format follows LOG_FORMAT: "text" writes
#              TIMESTAMP [LEVEL] [corr:ID] [component] message
#              and "json" writes one JSON object per line. Console output is
#              always human-readable.
# Parameters:
#   $1 - Log level (DEBUG, INFO, WARNING, ERROR, CRITICAL)
#   $2 - Message text
#   $3 - Optional: component/module name (default: "main")
_log_write() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local component="${3:-main}"

    # Threshold filter: suppress messages ranked below the configured LOG_LEVEL
    # from both the file and the console. The --verbose / -v flag lowers the
    # effective threshold to DEBUG so debug output is always shown when set.
    local effective_level="${LOG_LEVEL}"
    [[ "${VERBOSE_MODE}" == true ]] && effective_level="DEBUG"
    if (( $(_log_level_rank "${level}") < $(_log_level_rank "${effective_level}") )); then
        return 0
    fi

    local timestamp
    timestamp="$(date '+%Y-%m-%dT%H:%M:%S.%3N')"

    # File log line - text or JSON per LOG_FORMAT.
    local log_line
    if [[ "${LOG_FORMAT}" == json ]]; then
        log_line="{\"ts\":\"${timestamp}\",\"level\":\"${level}\",\"correlation_id\":\"${CORRELATION_ID}\",\"component\":\"$(_json_escape "${component}")\",\"message\":\"$(_json_escape "${message}")\"}"
    else
        log_line="${timestamp} [${level}] [corr:${CORRELATION_ID}] [${component}] ${message}"
    fi

    # Always write to master log file
    echo "${log_line}" >> "${MASTER_LOG}" 2>/dev/null || true

    # Console output: everything that passed the threshold filter above is shown
    # on the console (DEBUG reaches here only when the effective threshold is
    # DEBUG, i.e. --log-level DEBUG or --verbose).
    local console_output=true

    if [[ "${console_output}" == true ]]; then
        local color="${CLR_WHITE}" symbol="${SYM_INFO}"
        case "${level}" in
            DEBUG)    color="${CLR_DIM}";     symbol="…" ;;
            INFO)     color="${CLR_CYAN}";    symbol="${SYM_INFO}" ;;
            WARNING)  color="${CLR_YELLOW}";  symbol="${SYM_WARN}" ;;
            ERROR)    color="${CLR_RED}";     symbol="${SYM_FAIL}" ;;
            CRITICAL) color="${CLR_RED}${CLR_BOLD}"; symbol="${SYM_FAIL}" ;;
        esac
        if [[ "${USE_COLOR}" == true ]]; then
            echo -e "  ${color}[${symbol}]${CLR_RESET} ${message}" >&2
        else
            echo "  [${symbol}] ${message}" >&2
        fi
    fi
}

# Convenience logging functions - wrap _log_write with preset levels
log_debug()    { _log_write "DEBUG"    "$1" "${2:-main}"; }
log_info()     { _log_write "INFO"     "$1" "${2:-main}"; }
log_success()  { echo -e "  ${CLR_GREEN}[${SYM_OK}]${CLR_RESET} $1" >&2; _log_write "INFO" "$1" "${2:-main}"; }
log_warning()  { _log_write "WARNING"  "$1" "${2:-main}"; }
log_error()    { _log_write "ERROR"    "$1" "${2:-main}"; }
log_critical() { _log_write "CRITICAL" "$1" "${2:-main}"; }

# Function: log_session
# Description: Write to a session-specific log file (per-listener/session).
#              These logs persist independently of the master execution log
#              and provide per-session audit trails.
# Parameters:
#   $1 - Session name/ID (used in filename)
#   $2 - Log level
#   $3 - Message
log_session() {
    local session="${1:-unknown}"
    local level="${2:-INFO}"
    local message="${3:-}"
    local session_log="${LOG_DIR}/session-${session}-${EXEC_TIMESTAMP}.log"
    local timestamp
    timestamp="$(date '+%Y-%m-%dT%H:%M:%S.%3N')"
    echo "${timestamp} [${level}] [corr:${CORRELATION_ID}] ${message}" >> "${session_log}" 2>/dev/null || true
}

