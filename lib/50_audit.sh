#======================================================================
# AUDIT STORE (optional, SQLite-backed)
#
# Records framework events - session launches, stops, watchdog restarts,
# crashes, and errors - to a SQLite database for after-the-fact review.
#
# Availability and activation:
#   The store is active only when the `sqlite3` command is available AND
#   auditing is not disabled. Auditing is on by default when sqlite3 is
#   present; it is turned off when SOCAT_MANAGER_AUDIT is set to a false-like
#   value (0, false, no, off). On systems without sqlite3 the store is simply
#   inactive - no error, no behavioural change.
#
# Environment variables:
#   SOCAT_MANAGER_AUDIT                - false-like value disables auditing
#   SOCAT_MANAGER_AUDIT_REDACT         - true-like value masks remote hosts
#   SOCAT_MANAGER_AUDIT_DB             - override the database file path
#   SOCAT_MANAGER_AUDIT_RETENTION_DAYS - prune events older than N days (0=keep)
#
# Injection safety:
#   Every value is emitted as a properly escaped SQL literal (single quotes
#   doubled) or, for integer columns, as a validated integer or NULL. No user
#   value is ever concatenated into SQL unescaped.
#======================================================================

readonly AUDIT_SCHEMA_VERSION=1

# Per-process guard so the schema is initialised at most once.
_AUDIT_INITIALIZED=false
# Set true once a "sqlite3 missing but audit requested" warning has been shown.
_AUDIT_WARNED=false

# Function: _audit_available
# Description: True when the sqlite3 command-line tool is on PATH.
_audit_available() {
    command -v sqlite3 &>/dev/null
}

# Function: _audit_enabled
# Description: True when auditing should record events: sqlite3 is available and
#              SOCAT_MANAGER_AUDIT is not set to a false-like value. Emits a
#              one-time warning if auditing was explicitly requested (a true-like
#              value) but sqlite3 is unavailable.
_audit_enabled() {
    local raw
    raw="$(printf '%s' "${SOCAT_MANAGER_AUDIT:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"

    case "${raw}" in
        0|false|no|off) return 1 ;;
    esac

    if ! _audit_available; then
        case "${raw}" in
            1|true|yes|on)
                if [[ "${_AUDIT_WARNED}" != true ]]; then
                    log_warning "Auditing requested but sqlite3 is not installed; audit store inactive" "audit"
                    _AUDIT_WARNED=true
                fi
                ;;
        esac
        return 1
    fi
    return 0
}

# Function: _audit_redaction_enabled
# Description: True when remote host values should be masked in recorded events.
_audit_redaction_enabled() {
    local raw
    raw="$(printf '%s' "${SOCAT_MANAGER_AUDIT_REDACT:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
    case "${raw}" in
        1|true|yes|on) return 0 ;;
    esac
    return 1
}

# Function: _audit_retention_days
# Description: Echo the configured retention window in days (0 = keep forever).
_audit_retention_days() {
    local raw="${SOCAT_MANAGER_AUDIT_RETENTION_DAYS:-}"
    if [[ "${raw}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${raw}"
    else
        printf '0'
    fi
}

# Function: _audit_db_path
# Description: Echo the effective audit database path (env override or the
#              default under the runtime base directory).
_audit_db_path() {
    if [[ -n "${SOCAT_MANAGER_AUDIT_DB:-}" ]]; then
        printf '%s' "${SOCAT_MANAGER_AUDIT_DB}"
    else
        printf '%s' "${BASE_DIR}/audit/audit.db"
    fi
}

# Function: _audit_sql_text
# Description: Render a value as a SQL string literal (single quotes doubled) or
#              NULL when empty. This is the SQLite-correct escaping for text.
# Parameters: $1 - value
_audit_sql_text() {
    local v="${1:-}"
    if [[ -z "${v}" ]]; then
        printf 'NULL'
    else
        printf "'%s'" "${v//\'/\'\'}"
    fi
}

# Function: _audit_sql_int
# Description: Render a value as an integer literal or NULL when not an integer.
# Parameters: $1 - value
_audit_sql_int() {
    local v="${1:-}"
    if [[ "${v}" =~ ^[0-9]+$ ]]; then
        printf '%s' "${v}"
    else
        printf 'NULL'
    fi
}

# Function: _audit_init
# Description: Create the audit directory and schema if needed. Idempotent and
#              guarded so the schema is applied at most once per process.
# Parameters: $1 - database path
# Returns: 0 on success, 1 on failure
_audit_init() {
    local db="${1:?Database path required}"
    [[ "${_AUDIT_INITIALIZED}" == true ]] && return 0

    local dir
    dir="$(dirname "${db}")"
    mkdir -p "${dir}" 2>/dev/null || return 1
    chmod 700 "${dir}" 2>/dev/null || true

    if ! sqlite3 "${db}" "
        PRAGMA journal_mode=WAL;
        CREATE TABLE IF NOT EXISTS events (
            id             INTEGER PRIMARY KEY AUTOINCREMENT,
            ts             TEXT NOT NULL,
            correlation_id TEXT,
            event_type     TEXT NOT NULL,
            session_id     TEXT,
            name           TEXT,
            mode           TEXT,
            proto          TEXT,
            lport          INTEGER,
            rhost          TEXT,
            rport          INTEGER,
            pid            INTEGER,
            pgid           INTEGER,
            detail         TEXT,
            redacted       INTEGER NOT NULL DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_events_session ON events(session_id);
        CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts);
        CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
        PRAGMA user_version=${AUDIT_SCHEMA_VERSION};
    " 2>/dev/null; then
        return 1
    fi

    chmod 600 "${db}" 2>/dev/null || true
    _AUDIT_INITIALIZED=true
    return 0
}

# Function: _audit_record_event
# Description: Record one framework event. A no-op when auditing is inactive, so
#              callers can invoke it unconditionally. Applies optional remote-host
#              redaction and, when configured, prunes events past the retention
#              window.
# Parameters:
#   $1 - event_type (launch|stop|stop_failed|restart|crash|config_change|error)
#   $2 - session id        $7  - remote host
#   $3 - session name      $8  - remote port
#   $4 - mode              $9  - pid
#   $5 - protocol          $10 - pgid
#   $6 - local port        $11 - detail
_audit_record_event() {
    _audit_enabled || return 0

    local event_type="${1:?Event type required}"
    local sid="${2:-}" name="${3:-}" mode="${4:-}" proto="${5:-}"
    local lport="${6:-}" rhost="${7:-}" rport="${8:-}" pid="${9:-}" pgid="${10:-}" detail="${11:-}"

    local db
    db="$(_audit_db_path)"
    _audit_init "${db}" || return 0

    local redacted=0
    if _audit_redaction_enabled && [[ -n "${rhost}" ]]; then
        [[ -n "${detail}" ]] && detail="${detail//${rhost}/HOST-REDACTED}"
        rhost="HOST-REDACTED"
        redacted=1
    fi

    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local sql="INSERT INTO events (ts,correlation_id,event_type,session_id,name,mode,proto,lport,rhost,rport,pid,pgid,detail,redacted) VALUES ($(_audit_sql_text "${ts}"),$(_audit_sql_text "${CORRELATION_ID}"),$(_audit_sql_text "${event_type}"),$(_audit_sql_text "${sid}"),$(_audit_sql_text "${name}"),$(_audit_sql_text "${mode}"),$(_audit_sql_text "${proto}"),$(_audit_sql_int "${lport}"),$(_audit_sql_text "${rhost}"),$(_audit_sql_int "${rport}"),$(_audit_sql_int "${pid}"),$(_audit_sql_int "${pgid}"),$(_audit_sql_text "${detail}"),${redacted});"

    sqlite3 "${db}" "${sql}" 2>/dev/null || log_debug "audit: failed to record ${event_type} event" "audit"

    local rd
    rd="$(_audit_retention_days)"
    if (( rd > 0 )); then
        sqlite3 "${db}" "DELETE FROM events WHERE julianday(ts) < julianday('now','-${rd} days');" 2>/dev/null || true
    fi

    return 0
}

