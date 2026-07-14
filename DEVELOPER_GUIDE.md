# Developer Guide — Exhaustive Code Reference

## Socat Network Operations Manager (Python Variant) v0.9.0

This document provides an exhaustive reference for every source module, every class, every function, every constant, and every significant variable in the framework. It is generated from actual source code inspection and documents real behavior, security properties, cross-references, and wiring details.

**Total codebase**: 19 source modules, 6,779 lines, 115 functions, 5 frozen dataclasses, 30+ constants

## Table of Contents

1. [__init__.py](#--init--) — Package Initialization
1. [config.py](#config) — Configuration Constants, Frozen Dataclasses, and Protocol Maps
1. [logging_setup.py](#logging-setup) — Structured Dual-Output Logging and Display Helpers
1. [validation.py](#validation) — Whitelist Input Validators (Trust Boundary)
1. [session.py](#session) — Session CRUD, Lookup, Locking, Migration, and Cleanup
1. [commands.py](#commands) — Socat Command String Builders
1. [process.py](#process) — Process Launch, Stop Sequence, and Port Availability
1. [watchdog.py](#watchdog) — Monitor-First Auto-Restart with Exponential Backoff
1. [certs.py](#certs) — TLS Self-Signed Certificate Generation
1. [cli.py](#cli) — CLI Argument Parser (argparse)
1. [__main__.py](#--main--) — Entry Point, Signal Handlers, and CLI Dispatch
1. [menu.py](#menu) — Interactive TUI Menu System
1. [modes/listen.py](#modeslisten) — Listen Mode Handler
1. [modes/batch.py](#modesbatch) — Batch Mode Handler
1. [modes/forward.py](#modesforward) — Forward Mode Handler
1. [modes/tunnel.py](#modestunnel) — Tunnel Mode Handler
1. [modes/redirect.py](#modesredirect) — Redirect Mode Handler
1. [modes/status.py](#modesstatus) — Status Mode Handler
1. [modes/stop.py](#modesstop) — Stop Mode Handler

---

## `__init__.py`

**Path**: `src/socat_manager/__init__.py`  
**Lines**: 21  
**Purpose**: Package Initialization

**Module docstring**: Socat Network Operations Manager — Python variant.

### Constants and Module-Level Variables

- **`__version__`** `str` = `'0.1.0'` (line 19)
- **`__author__`** `str` = `'Sandler73'` (line 20)
- **`__project__`** `str` = `'Socat Network Operations Manager'` (line 21)


## `config.py`

**Path**: `src/socat_manager/config.py`  
**Lines**: 432  
**Purpose**: Configuration Constants, Frozen Dataclasses, and Protocol Maps

**Module docstring**: Configuration constants and defaults for socat-manager.

**Design Rationale**: This module is the single source of truth for all configuration values in the framework. Every constant, default, protocol mapping, field name, validation limit, and UI symbol is defined here and imported by other modules. This eliminates magic numbers and strings from the codebase and ensures consistency across all 19 source files.

**Architecture Role**: Foundation layer — imported by every other module. No module-level imports from other socat_manager modules (zero circular dependency risk). All dataclasses use `frozen=True, slots=True` for immutability and memory efficiency.

**Key Design Decisions**:
- `resolve_base_dir()` checks `SOCAT_MANAGER_BASE` environment variable first, then falls back to the script's parent directory. This allows operators to redirect all runtime artifacts (sessions/, logs/, certs/) to a custom location without code changes.
- `RuntimePaths` is a frozen dataclass with computed properties (`log_dir`, `session_dir`, `cert_dir`, `conf_dir`, `session_lock_file`) that derive paths from `base_dir`. This ensures directory structure is consistent and centralized.
- `EXEC_TIMESTAMP` and `CORRELATION_ID` are generated once at import time and remain constant for the entire execution. This means every log entry, session file, and capture log within a single invocation shares the same correlation ID for traceability.
- Protocol maps (`SOCAT_LISTEN_ADDR`, `SOCAT_CONNECT_ADDR`, `ALT_PROTOCOL`, `PROTOCOL_NORMALIZATION`) are the bridge between user-facing protocol names and socat's address format strings. The command builders in `commands.py` look up these maps to construct correct socat syntax.
- `SessionFields` uses a frozen dataclass (not an enum) so field names are plain strings that can be used directly as dictionary keys and matched against session file KEY=VALUE lines.

**Cross-References**: Imported by every module in the framework. `RuntimePaths` is instantiated in `logging_setup.get_paths()` which serves as the global path provider. `SESSION_FIELDS` is used by `session.py` for exact-key field matching. `DEFAULTS` is used by `process.py` (launch stability delay, stop grace period), `watchdog.py` (max restarts), and all mode handlers.

### Constants and Module-Level Variables

- **`SCRIPT_NAME`** `Final[str]` = `'socat-manager'` (line 45)
- **`SCRIPT_VERSION`** `Final[str]` = `'0.1.0'` (line 46)
- **`DEFAULTS`** `Final[Defaults]` = `Defaults()` (line 164)
- **`EXEC_TIMESTAMP`** `Final[str]` = `_generate_exec_timestamp()` (line 205)
- **`CORRELATION_ID`** `Final[str]` = `_generate_correlation_id()` (line 206)
- **`SCRIPT_PID`** `Final[int]` = `os.getpid()` (line 207)
- **`COLORS`** `Final[Colors]` = `Colors()` (line 256)
- **`SYMBOLS`** `Final[Symbols]` = `Symbols()` (line 257)
- **`VALID_PROTOCOLS`** `Final[frozenset[str]]` = `frozenset({'tcp4', 'tcp6', 'udp4', 'udp6'})` (line 265)
- **`PROTOCOL_NORMALIZATION`** `Final[dict[str, str]]` = `{'tcp': 'tcp4', 'tcp4': 'tcp4', 'tcp6': 'tcp6', 'udp': 'udp4', 'udp4': 'udp4', 'udp6': 'udp6'}` (line 270)
- **`ALT_PROTOCOL`** `Final[dict[str, str]]` = `{'tcp4': 'udp4', 'udp4': 'tcp4', 'tcp6': 'udp6', 'udp6': 'tcp6'}` (line 280)
- **`SOCAT_LISTEN_ADDR`** `Final[dict[str, str]]` = `{'tcp4': 'TCP4-LISTEN', 'tcp6': 'TCP6-LISTEN', 'udp4': 'UDP4-LISTEN', 'udp6': 'UDP6-LISTEN'}` (line 288)
- **`SOCAT_CONNECT_ADDR`** `Final[dict[str, str]]` = `{'tcp4': 'TCP4', 'tcp6': 'TCP6', 'udp4': 'UDP4', 'udp6': 'UDP6'}` (line 296)
- **`SESSION_FIELDS`** `Final[SessionFields]` = `SessionFields()` (line 329)
- **`SESSION_FILE_VERSION`** `Final[str]` = `'v2.3'` (line 332)
- **`REQUIRED_COMMANDS`** `Final[tuple[str, ...]]` = `('socat', 'openssl', 'ss')` (line 340). Note: the bash variant requires the `setsid` binary; the Python variant uses `os.setsid()` via `preexec_fn` instead.
- **`OPTIONAL_COMMANDS`** `Final[tuple[str, ...]]` = `('flock', 'lsof', 'pstree')` (line 341)
- **`PORT_MIN`** `Final[int]` = `1` (line 350)
- **`PORT_MAX`** `Final[int]` = `65535` (line 351)
- **`PRIVILEGED_PORT_THRESHOLD`** `Final[int]` = `1024` (line 352)
- **`PORT_RANGE_MAX_SPAN`** `Final[int]` = `1000` (line 355)
- **`SESSION_NAME_MAX_LENGTH`** `Final[int]` = `64` (line 358)
- **`SESSION_ID_LENGTH`** `Final[int]` = `8` (line 361)
- **`HOSTNAME_FORBIDDEN_CHARS`** `Final[str]` = `';|&$`(){}[]<>!#'` (line 364)
- **`FILEPATH_FORBIDDEN_CHARS`** `Final[str]` = `';|&$`'` (line 367)
- **`SOCAT_OPTS_WHITELIST`** `Final[str]` = `'a-zA-Z0-9=,.:/_\\-'` (line 370)
- **`SESSION_NAME_WHITELIST`** `Final[str]` = `'a-zA-Z0-9._\\-'` (line 373)
- **`IPV6_MIN_LENGTH`** `Final[int]` = `2` (line 376)
- **`IPV6_MAX_LENGTH`** `Final[int]` = `39` (line 377)
- **`IPV6_MAX_COLONS`** `Final[int]` = `7` (line 378)

### Class `RuntimePaths`
**Decorators**: `dataclass(frozen=True, slots=True)`  
**Defined at**: line 91–124

Immutable container for all runtime directory and file paths.

All paths are derived from base_dir. Directories are NOT created here;
_ensure_dirs() in the logging/session modules handles creation with
correct permissions.

**Attributes**:

- `base_dir`: `Path`

**Methods**:

#### `log_dir() -> Path`
**Defined at**: line 101–104 (4 lines)

Directory for all log files.

---

#### `session_dir() -> Path`
**Defined at**: line 106–109 (4 lines)

Directory for session metadata files (permissions 0o700).

**Security annotations**:

- Sets restrictive directory permissions (0o700)

---

#### `conf_dir() -> Path`
**Defined at**: line 111–114 (4 lines)

Directory for configuration files (e.g., ports.conf).

---

#### `cert_dir() -> Path`
**Defined at**: line 116–119 (4 lines)

Directory for TLS certificates and private keys.

---

#### `session_lock_file() -> Path`
**Defined at**: line 121–124 (4 lines)

Advisory lock file for session directory operations.

---

### Class `Defaults`
**Decorators**: `dataclass(frozen=True, slots=True)`  
**Defined at**: line 133–160

Immutable default operational values.

Every field corresponds 1:1 to a bash DEFAULT_* or timing constant.

**Attributes**:

- `protocol`: `str` = `'tcp4'`
- `backlog`: `int` = `128`
- `watchdog_poll_interval`: `int` = `5`
- `watchdog_max_restarts`: `int` = `10`
- `max_sessions`: `int` = `256`
- `stop_grace_seconds`: `int` = `5`
- `stop_verify_retries`: `int` = `5`
- `stop_verify_interval`: `float` = `0.5`
- `launch_stability_delay`: `float` = `0.3`

### Class `Colors`
**Decorators**: `dataclass(frozen=True, slots=True)`  
**Defined at**: line 217–233

ANSI escape sequences for terminal color output.

These are raw escape strings. The logging and display layers
gate their use on terminal detection (is stderr a TTY?).

**Attributes**:

- `reset`: `str` = `'\x1b[0m'`
- `bold`: `str` = `'\x1b[1m'`
- `dim`: `str` = `'\x1b[2m'`
- `red`: `str` = `'\x1b[31m'`
- `green`: `str` = `'\x1b[32m'`
- `yellow`: `str` = `'\x1b[33m'`
- `blue`: `str` = `'\x1b[34m'`
- `magenta`: `str` = `'\x1b[35m'`
- `cyan`: `str` = `'\x1b[36m'`
- `white`: `str` = `'\x1b[37m'`

### Class `Symbols`
**Decorators**: `dataclass(frozen=True, slots=True)`  
**Defined at**: line 237–252

Unicode status symbols for terminal output.

Matches bash SYM_* constants (lines 177-187) exactly.

**Attributes**:

- `ok`: `str` = `'✓'`
- `fail`: `str` = `'✗'`
- `warn`: `str` = `'!'`
- `info`: `str` = `'i'`
- `arrow`: `str` = `'→'`
- `plus`: `str` = `'+'`
- `listen`: `str` = `'◉'`
- `forward`: `str` = `'⇄'`
- `tunnel`: `str` = `'⊙'`
- `session`: `str` = `'■'`

### Class `SessionFields`
**Decorators**: `dataclass(frozen=True, slots=True)`  
**Defined at**: line 311–326

Session file field names — must match bash session_register() output.

**Attributes**:

- `session_id`: `str` = `'SESSION_ID'`
- `session_name`: `str` = `'SESSION_NAME'`
- `pid`: `str` = `'PID'`
- `pgid`: `str` = `'PGID'`
- `mode`: `str` = `'MODE'`
- `protocol`: `str` = `'PROTOCOL'`
- `local_port`: `str` = `'LOCAL_PORT'`
- `remote_host`: `str` = `'REMOTE_HOST'`
- `remote_port`: `str` = `'REMOTE_PORT'`
- `socat_cmd`: `str` = `'SOCAT_CMD'`
- `started`: `str` = `'STARTED'`
- `correlation`: `str` = `'CORRELATION'`
- `launcher_pid`: `str` = `'LAUNCHER_PID'`

### Functions

#### `resolve_base_dir() -> Path`
**Defined at**: line 53–83 (31 lines)

Resolve the base directory for runtime data (logs, sessions, certs, conf).

Resolution order:
    1. SOCAT_MANAGER_BASE environment variable (explicit override)
    2. Parent of the entry-point script's directory
    3. Current working directory as last resort

**Returns**: Absolute Path to the base directory.

---

#### `_generate_correlation_id() -> str`
**Defined at**: line 172–186 (15 lines)

Generate an 8-character hex correlation ID for this execution.

Uses uuid4 as primary entropy source.  Falls back to a
timestamp+PID hash if uuid generation fails unexpectedly.

**Returns**: 8-character lowercase hex string.

---

#### `_generate_exec_timestamp() -> str`
**Defined at**: line 189–200 (12 lines)

Generate an ISO-ish timestamp for this execution.

Format: YYYY-MM-DDTHH-MM-SS (hyphens in time for safe filenames).
Matches bash EXEC_TIMESTAMP format exactly.

**Returns**: Timestamp string safe for use in filenames.

---

#### `protocol_transport(proto: str) -> str`
**Defined at**: line 314–323 (10 lines)

Return the transport component of a normalized protocol: `udp` for UDP protocols, `tcp` otherwise. A protocol is a transport plus an address family, and scope derivation for socket queries lives here so configuration is the single source of truth for the protocol model.

**Parameters**:

- proto: Normalized protocol (tcp4, tcp6, udp4, udp6).

**Returns**: `udp` or `tcp`.

---

#### `protocol_family(proto: str) -> str`
**Defined at**: line 326–335 (10 lines)

Return the address family component of a normalized protocol: `6` for IPv6 protocols, `4` otherwise.

**Parameters**:

- proto: Normalized protocol (tcp4, tcp6, udp4, udp6).

**Returns**: `6` or `4`.

---

#### `socket_scope_flags(proto: str) -> list[str]`
**Defined at**: line 338–353 (16 lines)

Build the socket-listing flags that scope a query to one protocol. Both `ss` and `netstat` accept the same short flags: `-t`/`-u` selects the transport, `-4`/`-6` selects the address family, `-l -n` restricts to listening sockets without name resolution. A `tcp4` query yields `["-t", "-4", "-l", "-n"]`. Consumed by the port-availability and port-cleanup functions in `process.py` and by the port-status section of `session_detail()`.

**Parameters**:

- proto: Normalized protocol (tcp4, tcp6, udp4, udp6).

**Returns**: Flag list scoping a query to one transport and one address family.

---


## `logging_setup.py`

**Path**: `src/socat_manager/logging_setup.py`  
**Lines**: 451  
**Purpose**: Structured Dual-Output Logging and Display Helpers

**Module docstring**: Structured logging configuration for socat-manager.

### Constants and Module-Level Variables

- **`_dirs_ensured`** `bool` = `False` (line 58)
- **`USE_COLOR`** `Final[bool]` = `hasattr(sys.stderr, 'isatty') and sys.stderr.isatty()` (line 63)
- **`verbose_mode`** `bool` = `False` (line 66)
- **`_paths`** `RuntimePaths | None` = `None` (line 69)

### Class `StructuredFormatter`
**Defined at**: line 131–197

Custom formatter producing structured log lines.

Format: TIMESTAMP [LEVEL] [corr:CORRELATION_ID] [component] message

Matches the bash _log_write() output format (lines 230-270).
Terminal output includes ANSI color codes when USE_COLOR is True.

**Attributes**:

- `LEVEL_COLORS`: `dict[int, str]`

**Methods**:

#### `__init__(use_color: bool) -> None`
**Defined at**: line 153–160 (8 lines)

Initialize the structured formatter.

**Parameters**:

- use_color: Whether to include ANSI color escape sequences.

---

#### `format(record: logging.LogRecord) -> str`
**Defined at**: line 162–201 (40 lines)

Format a log record into the structured format.

**Parameters**:

- record: The log record to format.

**Returns**: Formatted log string.

---

### Functions

#### `get_paths() -> RuntimePaths`
**Defined at**: line 72–81 (10 lines)

Get or create the cached RuntimePaths instance.

**Returns**: RuntimePaths resolved from the current base directory.

---

#### `set_base_dir(base_dir: Path) -> None`
**Defined at**: line 84–91 (8 lines)

Override the base directory (for testing or explicit configuration).

**Parameters**:

- base_dir: New base directory path.

---

#### `_ensure_dirs() -> None`
**Defined at**: line 98–128 (31 lines)

Create required directory structure if missing.

Sets restrictive permissions on session directory (0o700) to protect
PID/session metadata from unauthorized access. Uses a guard variable
to avoid redundant mkdir/chmod system calls on every log write.

Matches bash _ensure_dirs() (lines 213-228).

**Security annotations**:

- Sets restrictive directory permissions (0o700)

---

#### `setup_logging(log_level: int) -> logging.Logger`
**Defined at**: line 208–261 (54 lines)

Configure and return the application logger with dual output.

Creates:
    - File handler: writes to master log in logs/ directory
    - Console handler: writes to stderr with optional color

The master log filename follows the bash convention:
    logs/{SCRIPT_NAME}-{EXEC_TIMESTAMP}.log

**Parameters**:

- log_level: Minimum log level (default: INFO). Set to DEBUG
- when verbose_mode is True.

**Returns**: Configured logging.Logger instance.

---

#### `get_logger() -> logging.Logger`
**Defined at**: line 264–273 (10 lines)

Get the application logger, initializing if needed.

**Returns**: The socat_manager logger instance.

---

#### `log_debug(msg: str, component: str = 'main') -> None`
**Defined at**: line 281–288 (8 lines)

Log a DEBUG message with component context.

**Parameters**:

- msg: The message to log.
- component: Component/subsystem identifier.

---

#### `log_info(msg: str, component: str = 'main') -> None`
**Defined at**: line 291–298 (8 lines)

Log an INFO message with component context.

**Parameters**:

- msg: The message to log.
- component: Component/subsystem identifier.

---

#### `log_warning(msg: str, component: str = 'main') -> None`
**Defined at**: line 301–308 (8 lines)

Log a WARNING message with component context.

**Parameters**:

- msg: The message to log.
- component: Component/subsystem identifier.

---

#### `log_error(msg: str, component: str = 'main') -> None`
**Defined at**: line 311–318 (8 lines)

Log an ERROR message with component context.

**Parameters**:

- msg: The message to log.
- component: Component/subsystem identifier.

---

#### `log_critical(msg: str, component: str = 'main') -> None`
**Defined at**: line 321–328 (8 lines)

Log a CRITICAL message with component context.

**Parameters**:

- msg: The message to log.
- component: Component/subsystem identifier.

---

#### `log_success(msg: str, component: str = 'main') -> None`
**Defined at**: line 331–350 (20 lines)

Log a success message with green checkmark on terminal.

Matches bash log_success() (line 273): prints a styled terminal
message AND writes an INFO-level log entry.

**Parameters**:

- msg: The message to log.
- component: Component/subsystem identifier.

---

#### `log_session(session_id: str, level: str, msg: str) -> None`
**Defined at**: line 359–392 (34 lines)

Write a log entry to a per-session audit log file.

Session logs are separate from the master log. Each session gets
its own log file: logs/session-{session_id}.log

This writes directly to the file (not via the logging module) to
maintain isolation between session audit trails.

**Parameters**:

- session_id: The 8-character hex session identifier.
- level: Log level string (DEBUG, INFO, WARNING, ERROR, CRITICAL).
- msg: The message to log.

---

#### `print_banner(subtitle: str = '') -> None`
**Defined at**: line 401–420 (20 lines)

Print a styled section banner to stderr.

**Parameters**:

- subtitle: Optional subtitle text (e.g., "Listener", "Forwarder").

---

#### `print_section(title: str) -> None`
**Defined at**: line 423–435 (13 lines)

Print a section header to stderr.

**Parameters**:

- title: Section title text.

---

#### `print_kv(key: str, value: object) -> None`
**Defined at**: line 438–451 (14 lines)

Print a key-value pair to stderr.

**Parameters**:

- key: The label/key text.
- value: The value to display.

---


## `validation.py`

**Path**: `src/socat_manager/validation.py`  
**Lines**: 647  
**Purpose**: Whitelist Input Validators (Trust Boundary)

**Module docstring**: Input validation for all user-supplied parameters.

**Design Rationale**: This module implements the trust boundary — the point where untrusted user input is validated before it can reach any command builder, file operation, or system call. Every validator uses a whitelist approach (only explicitly allowed characters/patterns pass) rather than a blacklist (trying to catch bad characters). Whitelists fail closed (reject unknown input), while blacklists fail open.

**Architecture Role**: Called by all mode handlers at the beginning of execution, before any socat command is constructed. Also called by menu.py prompt functions for interactive input validation. The validators sit between user input and `commands.py` / `process.py` — nothing reaches a subprocess call without passing through at least one validator.

**Security Properties**:
- All validators raise `ValidationError` (subclass of `ValueError`) on invalid input — never silently correct or sanitize
- Shell metacharacters (`;|&$\`(){}[]<>!#`) rejected by hostname and filepath validators for defense-in-depth
- Socat opts use strict character whitelist: `[a-zA-Z0-9=,.:/_-]`
- IPv6 validation handles full, compressed (::), and mixed IPv4-mapped forms
- Session ID validation uses exact regex `^[a-f0-9]{8}$` preventing partial-match attacks
- Port validation warns on privileged ports (<1024) but does not reject them

**Cross-References**: Called by all 5 operational mode handlers, all menu prompt functions. `ValidationError` caught by mode handlers for user-friendly error messages before `sys.exit(1)`.

### Constants and Module-Level Variables

- **`_PORT_RANGE_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^(\\d+)-(\\d+)$')` (line 89)
- **`_NUMERIC_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^[0-9]+$')` (line 92)
- **`_IPV4_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})$')` (line 95)
- **`_IPV6_CANDIDATE_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^[0-9a-fA-F:]+$')` (line 100)
- **`_HOSTNAME_PATTERN`** `Final[re.Pattern[str]]` (line 104)
- **`_SESSION_ID_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^[a-f0-9]{8}$')` (line 110)
- **`_SESSION_NAME_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^[a-zA-Z0-9._-]+$')` (line 113)
- **`_SOCAT_OPTS_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('^[a-zA-Z0-9=,.:/_-]+$')` (line 116)
- **`_HOSTNAME_FORBIDDEN_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('[;|&$`()\\{\\}\\[\\]<>!#]')` (line 119)
- **`_FILEPATH_FORBIDDEN_PATTERN`** `Final[re.Pattern[str]]` = `re.compile('[;|&$`]')` (line 124)

### Class `ValidationError`
**Defined at**: line 63–81

Raised when user input fails validation.

Inherits from ValueError for compatibility with standard exception
handling patterns. Carries the original input and a human-readable
reason for logging and user feedback.

**Methods**:

#### `__init__(message: str, field: str, value: str) -> None`
**Defined at**: line 75–85 (11 lines)

Initialize a ValidationError.

**Parameters**:

- message: Human-readable error description.
- field: Name of the field/parameter that failed validation.
- value: The invalid value (sanitized for logging).

---

### Functions

#### `validate_port(port: str | int) -> int`
**Defined at**: line 149–189 (41 lines)

Validate a port number is numeric and within valid range (1-65535).

Warns if the port is privileged (<1024) and the process is not running
as root, but does NOT reject it — the user may have capabilities or
plan to run with sudo.

**Parameters**:

- port: Port number as string or integer.

**Returns**: Validated port number as integer.

**Raises**:

- ValidationError: If port is non-numeric or out of range.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `validate_port_range(range_str: str) -> list[int]`
**Defined at**: line 197–237 (41 lines)

Validate a port range string and return the list of ports.

Format: START-END where START < END. Maximum span is 1000 ports
to prevent accidental resource exhaustion.

**Parameters**:

- range_str: Port range string (e.g., "8000-8010").

**Returns**: List of integer port numbers in the range [START, END].

**Raises**:

- ValidationError: If format is invalid, ports are invalid,
- start >= end, or span exceeds 1000.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `validate_port_list(list_str: str) -> list[int]`
**Defined at**: line 245–280 (36 lines)

Validate a comma/semicolon-separated port list.

Sanitizes input by removing spaces and replacing semicolons with
commas. Skips invalid individual ports but logs warnings for them.
Returns at least one valid port or raises ValidationError.

**Parameters**:

- list_str: Comma or semicolon separated port numbers
- (e.g., "21,22,80,443").

**Returns**: List of valid integer port numbers.

**Raises**:

- ValidationError: If no valid ports are found in the list.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `validate_hostname(host: str) -> str`
**Defined at**: line 288–376 (89 lines)

Validate a hostname or IP address for use as a network target.

Accepts:
    - IPv4 addresses (four octets, each 0-255)
    - IPv6 addresses (hex:colon format, length 2-39, max 7 colons, each non-empty group validated to 1-4 hex characters via `_IPV6_GROUP_PATTERN`)
    - RFC 1123 hostnames (alphanumeric, hyphens, dots)

Rejects shell metacharacters to prevent command injection. Forbidden character pattern derived from `config.HOSTNAME_FORBIDDEN_CHARS`.

**Parameters**:

- host: Hostname or IP address string.

**Returns**: The validated hostname string (unchanged).

**Raises**:

- ValidationError: If hostname is empty, contains forbidden
- characters, or fails all format checks.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `is_ipv6_literal(host: str) -> bool`

Report whether a host string is an IPv6 literal. A host is treated as an IPv6 literal when it contains a colon and consists only of hex digits and colons — the same shape the hostname validator uses to route a value into IPv6 handling. Hostnames and IPv4 literals contain no colons and return False. This is used to select the address family of a connector for a validated host, so an IPv6 target is reached over an IPv6 connector.

**Parameters**:

- host: Host string (expected to have passed `validate_hostname`).

**Returns**: True if the host is an IPv6 literal, False otherwise.

---

#### `validate_protocol(proto: str) -> str`
**Defined at**: line 405–431 (27 lines)

Validate and normalize a protocol string.

Accepts shorthand (tcp, udp) and explicit forms (tcp4, tcp6, etc.).
Returns the normalized canonical protocol string.

**Parameters**:

- proto: Protocol string to validate.

**Returns**: Normalized protocol string (tcp4, tcp6, udp4, or udp6).

**Raises**:

- ValidationError: If protocol is not in the accepted whitelist.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `validate_writable_path(path: str) -> str`

Validate a path that will be written to. A write target such as a capture or log file is created by socat at launch, so this does not require the path to exist or be readable. It applies the structural safety checks: a non-empty path, no parent-directory traversal component, and none of the shell metacharacters that `config.FILEPATH_FORBIDDEN_CHARS` forbids. The forbidden character set comes from configuration, so this validator and `validate_file_path()` share one definition rather than each carrying a separate literal.

**Parameters**:

- path: File path string to validate as a write target.

**Returns**: The validated path string (stripped of surrounding whitespace).

**Raises**:

- ValidationError: If the path is empty, contains a traversal component, or contains a forbidden character.

**Security annotations**:

- Rejects `..` as a path component (traversal), allowing `..` only within a single name
- Rejects the config-defined shell metacharacter set (`config.FILEPATH_FORBIDDEN_CHARS`)

---

#### `validate_file_path(path: str) -> str`
**Defined at**: line 418–470

Validate a file path is safe and accessible for use.

Performs five checks in order:
  1. Non-empty path
  2. Path traversal detection — component-based check (`".." in path.split("/")`) that correctly allows legal filenames like `file..ext` while blocking actual traversal sequences
  3. Shell metacharacter rejection via `FILEPATH_FORBIDDEN_CHARS` from config
  4. File existence verification via `os.path.isfile()`
  5. File readability verification via `os.access(path, os.R_OK)`

**Parameters**:

- path: File path string to validate.

**Returns**: The validated path string (unchanged).

**Raises**:

- ValidationError: If path is empty, contains traversal components, contains forbidden characters, does not exist, or is not readable.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input
- Component-based traversal check prevents false positives on legal filenames

---

#### `validate_socat_opts(opts: str) -> str`
**Defined at**: line 528–560 (33 lines)

Validate user-provided socat address options for safety.

Allows only characters valid in socat address options:
alphanumeric, equals, commas, dots, colons, hyphens, forward
slashes, and underscores. Rejects all shell metacharacters.

Empty string is valid (no extra options).

**Parameters**:

- opts: Socat options string to validate.

**Returns**: The validated options string (unchanged).

**Raises**:

- ValidationError: If options contain forbidden characters.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `validate_session_name(name: str) -> str`
**Defined at**: line 568–610 (43 lines)

Validate a user-provided session name for safety.

Allows only alphanumeric characters, hyphens, underscores, and dots.
Maximum length 64 characters. Prevents injection into session files
(SESSION_NAME=<value>) and log messages.

**Parameters**:

- name: Session name string to validate.

**Returns**: The validated session name (unchanged).

**Raises**:

- ValidationError: If name is empty, too long, or contains
- forbidden characters.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---

#### `validate_session_id(sid: str) -> str`
**Defined at**: line 618–647 (30 lines)

Validate a session ID is a valid 8-character lowercase hex string.

Prevents injection via session ID parameters that flow into file
paths (sessions/{sid}.session) and log messages.

**Parameters**:

- sid: Session ID string to validate.

**Returns**: The validated session ID (unchanged).

**Raises**:

- ValidationError: If session ID is empty or not exactly 8
- lowercase hex characters.

**Security annotations**:

- Validates input through whitelist validators before use
- Raises ValidationError on invalid input

---


## `session.py`

**Path**: `src/socat_manager/session.py`  
**Lines**: 1124  
**Purpose**: Session CRUD, Lookup, Locking, Migration, and Cleanup

**Module docstring**: Session management: registration, lookup, cleanup, and locking.

**Design Rationale**: Centralized session lifecycle management. Every socat process gets a registered session file that persists on disk, enabling cross-invocation tracking — sessions launched in one terminal can be queried and stopped from another terminal, even after the original management script exits.

**Architecture Role**: Core data layer. Called by `process.py` (register/unregister during launch/stop), `watchdog.py` (process identity update on restart, unregister on max restarts), all mode handlers (for session lookup), and `__main__.py` (legacy migration on startup).

**Key Design Decisions**:
- Session files use KEY=VALUE text format for cross-variant interoperability with the bash implementation. Both variants can read each other's session files.
- `session_read_field()` uses exact-key matching: splits on `=` and compares the left side exactly. This prevents a line like `LAUNCHER_PID=67890` from matching a search for field `PID`. This is a deliberate security control against field confusion attacks.
- Session files are named `{sid}.session`, so a session ID is the file stem and is identical to the `SESSION_ID` field by construction. The lookup and enumeration functions (`session_find_by_name`, `session_find_by_port`, `session_find_by_pid`, `session_get_all_ids`) derive the ID from the file name through `_sid_from_file()` rather than reading the `SESSION_ID` field back, so a matched file is not opened a second time to recover its ID. The helper skips a file whose name contains characters that would be unsafe in a constructed path.
- `session_read_all_fields()` reads the entire file in a single pass and returns a dict. The listing and detail views both read once through it and then evaluate liveness from the fields already in hand, so neither re-opens the file for the alive check.
- `process_alive()` decides liveness from a recorded PID and PGID that the caller has already read. `session_is_alive()` is a thin wrapper that reads a session's fields once and delegates to it. Callers holding a session's fields call `process_alive()` directly. The primary check routes through `process.process_is_running()`, so a socat process launched by this framework that has exited but not yet been collected is reported as dead rather than as a live zombie.
- `session_lock()` is a context manager using `fcntl.flock` for advisory file locking. If the lock cannot be acquired (another process holds it), it logs a warning and proceeds — matching bash behavior where `_session_lock || log_debug "Proceeding without lock"`.
- `session_update_process()` rewrites only the process identity fields (`PID`, `PGID`, `STARTED`) of an existing session, preserving every other field. It runs under the advisory lock and publishes the new record with an atomic rename, so the session file is never observed half-written. The watchdog calls it after every restart, which keeps the record aligned with the process that actually owns the port.
- `session_cleanup_dead()` acquires the advisory lock before iterating to prevent TOCTOU races with concurrent stop/launch operations. Both PID AND PGID must be confirmed dead before removal.
- `migrate_legacy_sessions()` converts v1 `.pid` files to v2.3 `.session` format, deriving PGID from the running process via `ps -o pgid=`. Dead legacy sessions are simply removed.
- `session_detail()` shows 5 sections: metadata, process tree (pstree with ps fallback), port status (ss query protocol-scoped), socat command, associated log files.

**Security Properties**: Session files created with 0o600 permissions, including the temporary file used for in-place process identity updates. Session directory 0o700. Advisory locking prevents concurrent manipulation. Exact-key matching prevents field injection. Session record updates are published by atomic rename, so readers never see a truncated record.

### Functions

#### `generate_session_id() -> str`
**Defined at**: line 78–101 (24 lines)

Generate a unique 8-character hex session ID.

Uses uuid4 as primary entropy source. Checks for collisions against
existing session files (extremely unlikely but handled).

**Returns**: 8-character lowercase hex string guaranteed unique among current session files.

**Raises**:

- RuntimeError: If unable to generate a unique ID after 100 attempts.

---

#### `session_lock() -> Generator[None, None, None]`
**Defined at**: line 109–142 (34 lines)

Acquire an advisory file lock on the session directory.

Uses fcntl.flock for cooperative locking. This protects against
race conditions when multiple socat-manager instances modify
session files concurrently.

The lock is automatically released when the context manager exits.

Yields:
    None — the lock is held for the duration of the with block.

**Raises**:

- OSError: If the lock file cannot be opened or locked.

**Security annotations**:

- Uses advisory file locking (fcntl.flock)
- Sets restrictive file permissions (0o600)

---

#### `session_register(sid: str, name: str, pid: int, pgid: int, mode: str, proto: str = 'tcp4', lport: int = 0, socat_cmd: str = '', rhost: str = '', rport: str = '') -> None`
**Defined at**: line 150–247 (98 lines)

Register a new socat session by writing a session file.

Creates a KEY=VALUE text file in the session directory with
full metadata. File permissions are set to 0o600 to
protect command strings and PID information.

The file format is interoperable with the bash version — a user
can manage sessions created by either variant interchangeably.

**Parameters**:

- sid: Unique 8-character hex session ID.
- name: Human-readable session name.
- pid: PID of the socat process.
- pgid: Process group ID (PGID) for tree kill.
- mode: Operational mode (listen, forward, tunnel, redirect, etc.).
- proto: Protocol (tcp4, udp4, etc.).
- lport: Local port number.
- socat_cmd: Full socat command string (for restart/audit).
- rhost: Optional remote host.
- rport: Optional remote port.

**Security annotations**:

- Sets restrictive file permissions (0o600)
- Strips `\n` and `\r` from all string values before writing to prevent KEY=VALUE injection via crafted inputs

---

#### `session_update_process(sid: str, pid: int, pgid: int) -> bool`

Update the tracked process identity of an existing session.

Rewrites the `PID`, `PGID`, and `STARTED` fields of a session file while preserving every other field (name, mode, protocol, ports, socat command, correlation ID, launcher PID) and the file header comments.

The session file is the authoritative record of which process a session owns. Any component that replaces the process behind a session — the watchdog, when it re-launches after an unexpected exit — calls this so that `session_is_alive()` and `stop_session()` act on the process that is currently running rather than a terminated predecessor.

The rewrite runs under the advisory session lock. Content is written to a temporary file with 0o600 permissions in the session directory and then renamed over the original. Rename within a directory is atomic, so a concurrent reader observes either the complete previous record or the complete new one, never a partially written file.

**Parameters**:

- sid: Session ID whose process identity is being updated.
- pid: PID of the process the session now owns.
- pgid: Process group ID of the process the session now owns.

**Returns**: True if the session file was updated, False if it does not exist or could not be rewritten.

**Security annotations**:

- Holds the advisory session lock for the read-modify-write cycle
- Temporary file created with 0o600 via `os.open()`; permissions carry through the rename
- Atomic replace prevents readers from observing a truncated session record
- Only the process identity fields are substituted; all other content is preserved verbatim

---

#### `session_unregister(sid: str) -> None`
**Defined at**: line 372–393 (22 lines)

Remove a session file and all associated signal files.

Called after confirmed process termination. Removes:
    - {sid}.session  — session metadata
    - {sid}.stop     — stop signal file
    - {sid}.launching — PID staging file

**Parameters**:

- sid: Session ID to unregister.

---

#### `session_read_field(session_file: Path, field: str) -> str`
**Defined at**: line 402–447 (46 lines)

Read a specific field from a session file using exact key match.

Parses KEY=VALUE lines. Uses split('=', 1) to handle values
containing '=' characters (e.g., socat command strings with
cert=path options).

SECURITY: Uses exact string comparison on the key portion,
NOT regex matching or substring search. This prevents partial
key matches (e.g., searching for 'PID' matching 'LAUNCHER_PID').
Matches bash awk: $1 == key {print substr($0, length(key)+2); exit}

**Parameters**:

- session_file: Path to the session file.
- field: Exact field name to look up (e.g., "PID", "PROTOCOL").

**Returns**: Field value as string, or empty string if not found.

---

#### `session_find_by_name(target_name: str) -> list[str]`
**Defined at**: line 482–501 (20 lines)

Find session IDs matching an exact session name.

**Parameters**:

- target_name: Session name to search for (exact match).

**Returns**: List of matching session IDs (may be empty).

---

#### `session_find_by_port(target_port: int | str) -> list[str]`
**Defined at**: line 504–524 (21 lines)

Find session IDs matching a local port.

**Parameters**:

- target_port: Port number to search for.

**Returns**: List of matching session IDs (may be empty).

---

#### `session_find_by_pid(target_pid: int | str) -> list[str]`
**Defined at**: line 527–547 (21 lines)

Find session IDs matching a PID.

**Parameters**:

- target_pid: Process ID to search for.

**Returns**: List of matching session IDs (may be empty).

---

#### `process_alive(pid_str: str, pgid_str: str) -> bool`

Check whether a recorded process identity is still running, working entirely from values the caller has already read.

Checks the primary PID first, then falls back to the process group; the session is alive if either responds. The group fallback covers the case where the primary process has been replaced but the group still holds live members. The primary check routes through `process.process_is_running()`, so an exited-but-uncollected socat child is reported as dead rather than as a live zombie.

Because it takes the identity as arguments, a caller that has loaded a session's fields — the listing and detail views both do — evaluates liveness without a second read of the session file.

**Parameters**:

- pid_str: Recorded PID as a string (empty if absent).
- pgid_str: Recorded PGID as a string (empty if absent).

**Returns**: True if the recorded process or its group is alive, False otherwise.

---

#### `session_is_alive(sid: str) -> bool`
**Defined at**: line 603–628 (26 lines)

Check if a registered session's process is still running.

Checks both the primary PID and the process group. A session is
considered alive if either the PID or the PGID responds to
signal 0 (existence check).

**Parameters**:

- sid: Session ID to check.

**Returns**: True if the session's process is alive, False otherwise.

**Security annotations**:

- Sends signals to processes/groups

---

#### `session_get_all_ids() -> list[str]`
**Defined at**: line 636–650 (15 lines)

List all registered session IDs.

**Returns**: List of session ID strings (may be empty).

---

#### `session_count() -> int`
**Defined at**: line 657–664 (8 lines)

Count the number of active session files.

**Returns**: Number of .session files in the session directory.

---

#### `session_list() -> bool`
**Defined at**: line 672–739 (68 lines)

List all registered sessions with their status.

Displays a formatted table of sessions including session ID, name,
PID, PGID, mode, protocol, port, remote target, and alive/dead status.

**Returns**: True if any sessions were found, False if none.

---

#### `session_read_all_fields(session_file: Path) -> dict[str, str]`
**Defined at**: line 747–780 (34 lines)

Read all fields from a session file in a single pass.

Returns a dict of KEY→VALUE pairs. Skips comments and empty lines.
Uses exact key match via split('=', 1). This avoids the N+1 problem
of calling session_read_field() once per field.

**Parameters**:

- session_file: Path to the session file.

**Returns**: Dict of field name → value. Empty dict if file not found.

---

#### `session_detail(sid: str) -> bool`
**Defined at**: line 790–966 (177 lines)

Display detailed information for a specific session.

Shows all session metadata fields, process status with process tree,
port binding status via ss, socat command, and associated log files.
Matches bash session_detail() output (lines 1014-1129).

**Parameters**:

- sid: Session ID to display details for.

**Returns**: True if session was found, False otherwise.

---

#### `migrate_legacy_sessions() -> int`
**Defined at**: line 974–1084 (111 lines)

Migrate v1 legacy .pid session files to v2.2+ .session format.

Scans the session directory for .pid files (pre-v2.2 format), checks
if the tracked process is alive, and if so creates a new v2.3 .session
file. Dead legacy sessions are simply removed.

**Returns**: Number of sessions migrated.

**Security annotations**:

- Sends signals to processes/groups

---

#### `session_cleanup_dead() -> int`
**Defined at**: line 1092–1124 (33 lines)

Remove session files for dead processes.

Acquires advisory lock before iterating to prevent TOCTOU race
conditions with concurrent stop/launch operations. Both the PID
and PGID must be confirmed dead before removal. This prevents
premature cleanup of sessions where the primary PID has been
replaced but the process group is still alive.

**Returns**: Number of dead sessions cleaned up.

---


## `commands.py`

**Path**: `src/socat_manager/commands.py`  
**Lines**: 358  
**Purpose**: Socat Command String Builders

**Module docstring**: Socat command string builders for all operational modes.

**Design Rationale**: Centralized socat command construction. The 4 builder functions are the ONLY place in the codebase where socat command strings are assembled. This ensures consistent, auditable command construction with no ad-hoc string concatenation in mode handlers.

**Architecture Role**: Called by mode handlers (listen, batch, forward, tunnel, redirect) to produce the `cmd` argument list passed to `launch_socat_session()`. The builders look up protocol maps in `config.py` to translate user-facing protocol names into socat address format strings.

**Security Properties**: Builders produce `list[str]` argument lists (never shell strings). All parameters have already been validated by the trust boundary (`validation.py`) before reaching the builders. The builders perform no validation themselves — they trust that inputs have been sanitized. This separation of concerns keeps the validation logic centralized.

**Address Formatting**: socat address fields are colon-delimited, so a host embedded in an address is passed through `format_socat_host()` before use. An IPv6 literal contains colons of its own and is enclosed in square brackets, without which socat cannot determine where the address ends and the port begins and rejects the address. Hostnames and IPv4 literals contain no colons and pass through unchanged. Every builder that embeds a remote target applies this, and the `bind=` option in listen mode applies it to the local bind address.

**Command Pattern**: Every builder produces a list like `["socat", <flags>, "<listen_addr>:<port>,<options>", "<connect_addr>"]`. The `-u` flag (unidirectional) is used for listen mode; `-v` for capture; forward/redirect/tunnel use bidirectional. `cmd_list_to_string()` joins the list for display and session file storage.

### Functions

#### `format_socat_host(host: str) -> str`

Format a host for inclusion in a socat address.

socat address fields are colon-delimited. An IPv6 literal carries colons of its own, so it is enclosed in square brackets to keep those colons from being read as field separators. Without the brackets an address such as `TCP6:2001:db8::1:443` is ambiguous — socat cannot tell where the address ends and the port begins — and is rejected.

Hostnames and IPv4 literals contain no colons and are returned unchanged. A host that is already bracketed is returned unchanged, so the function is idempotent.

**Parameters**:

- host: Hostname, IPv4 literal, or IPv6 literal (already validated).

**Returns**: The host, bracketed if it is an IPv6 literal.

| Input | Output |
|-------|--------|
| `2001:db8::1` | `[2001:db8::1]` |
| `::1` | `[::1]` |
| `10.0.0.5` | `10.0.0.5` |
| `example.com` | `example.com` |

---

#### `format_socat_endpoint(host: str, port: int | str) -> str`

Format a host and port as a socat address endpoint in `HOST:PORT` form, bracketing IPv6 literals through `format_socat_host()`. The port remains the final colon-delimited field, so it is always unambiguously parseable.

**Parameters**:

- host: Hostname, IPv4 literal, or IPv6 literal (already validated).
- port: Port number.

**Returns**: Endpoint string, for example `[2001:db8::1]:443` or `10.0.0.5:80`.

---

#### `cmd_list_to_string(cmd: list[str]) -> str`
**Defined at**: line 96–109 (14 lines)

Join a command argument list into a single string.

Used for recording in session files (SOCAT_CMD= field) and for
display purposes. The resulting string matches what bash's
build_socat_*_cmd() functions echo.

**Parameters**:

- cmd: Command argument list.

**Returns**: Space-joined command string.

---

#### `build_socat_listen_cmd(proto: str, port: int, logfile: str, extra_opts: str = '', capture: bool = False) -> list[str]`
**Defined at**: line 117–174 (58 lines)

Build a socat command for a single-port listener.

The listener captures incoming data unidirectionally (-u flag)
from the network to a log file. When capture mode is enabled,
socat's -v flag adds verbose hex dump output on stderr.

**Parameters**:

- proto: Normalized protocol (tcp4, tcp6, udp4, udp6).
- port: Port number to listen on.
- logfile: Path to the data capture log file.
- extra_opts: Additional socat address options (pre-validated).
- capture: Whether to enable traffic capture (-v flag).

**Returns**: Command argument list for subprocess.Popen. Example output (as string): socat -u TCP4-LISTEN:8080,reuseaddr,fork,backlog=128,keepalive OPEN:/path/log,creat,append socat -v -u TCP4-LISTEN:8080,reuseaddr,fork,backlog=128,keepalive OPEN:/path/log,creat,append

**Security annotations**:

- Uses subprocess.Popen with argument list (never shell=True)

---

#### `build_socat_forward_cmd(listen_proto: str, lport: int, rhost: str, rport: int, remote_proto: str = '', capture: bool = False) -> list[str]`
**Defined at**: line 182–237 (56 lines)

Build a socat command for bidirectional port forwarding.

Creates a full-duplex proxy between a local listener and a remote
target. No -u flag (bidirectional). When capture mode is enabled,
socat's -v flag captures both directions.

**Parameters**:

- listen_proto: Local listen protocol (tcp4, tcp6, udp4, udp6).
- lport: Local port to listen on.
- rhost: Remote host to forward to.
- rport: Remote port to forward to.
- remote_proto: Remote protocol (defaults to listen_proto).
- capture: Whether to enable traffic capture (-v flag).

**Returns**: Command argument list for subprocess.Popen. Example output (as string): socat TCP4-LISTEN:8080,reuseaddr,fork,backlog=128,keepalive TCP4:10.0.0.5:80

**Security annotations**:

- Uses subprocess.Popen with argument list (never shell=True)

---

#### `build_socat_tunnel_cmd(lport: int, rhost: str, rport: int, cert: str, key: str, capture: bool = False, remote_proto: str = 'tcp4') -> list[str]`
**Defined at**: line 245–302 (58 lines)

Build a socat command for an encrypted (OpenSSL) tunnel.

Accepts TLS connections on a local port and forwards plaintext
traffic to a remote target. When capture mode is enabled,
the hex dump shows DECRYPTED traffic.

**Parameters**:

- lport: Local port to listen on (encrypted endpoint).
- rhost: Remote host to tunnel to.
- rport: Remote port to tunnel to.
- cert: Path to certificate PEM file.
- key: Path to private key PEM file.
- capture: Whether to enable traffic capture (-v flag).
- remote_proto: Remote address family selector (tcp4 or tcp6). The listener is TLS over TCP; the remote leg's transport is TCP and its family follows this selector, so an IPv6 remote target is reached over a TCP6 connector. An unrecognized value falls back to TCP4.

**Returns**: Command argument list for subprocess.Popen. Example output (as string): `socat OPENSSL-LISTEN:4443,cert=/path/cert.pem,key=/path/key.pem,verify=0,reuseaddr,fork TCP4:10.0.0.5:22` for an IPv4 target, or `... TCP6:[2001:db8::1]:22` for an IPv6 target.

**Security annotations**:

- Uses subprocess.Popen with argument list (never shell=True)

---

#### `build_socat_redirect_cmd(proto: str, lport: int, rhost: str, rport: int, capture: bool = False) -> list[str]`
**Defined at**: line 310–358 (49 lines)

Build a socat command for transparent traffic redirection.

Bidirectional forwarding with optional traffic logging.
Protocol-aware: supports TCP and UDP independently.

**Parameters**:

- proto: Protocol (tcp4, tcp6, udp4, udp6).
- lport: Local port to listen on.
- rhost: Remote host to redirect to.
- rport: Remote port to redirect to.
- capture: Whether to enable traffic capture (-v flag).

**Returns**: Command argument list for subprocess.Popen. Example output (as string): socat TCP4-LISTEN:8443,reuseaddr,fork,backlog=128,keepalive TCP4:example.com:443

**Security annotations**:

- Uses subprocess.Popen with argument list (never shell=True)

---


## `process.py`

**Path**: `src/socat_manager/process.py`  
**Lines**: 798  
**Purpose**: Process Launch, Stop Sequence, and Port Availability

**Module docstring**: Process launch, stop, and port management for socat-manager.

**Design Rationale**: Process management is the most security-critical module. It controls how socat processes are spawned (with what privileges, in what isolation), how they are terminated (with what signal sequence), and how ports are verified. Every design decision here has security implications.

**Architecture Role**: Called by all 5 operational mode handlers for `launch_socat_session()` and `check_port_available()`. Called by `modes/stop.py` for `stop_session()`. The watchdog launches its own replacement processes and writes the resulting process identity back to the session record.

**Key Design Decisions**:
- `subprocess.Popen` with argument lists only — the `cmd` parameter is always a `list[str]`, never a shell string. The `shell=True` parameter is never used anywhere in this module or the entire codebase. This eliminates command injection as a vulnerability class.
- `os.setsid` as `preexec_fn` creates a new session and process group for each socat process. The PGID equals the PID (because the process is the session leader). This means: (a) killing the management script does not kill managed sessions, (b) `os.killpg(pgid, signal)` reliably targets the entire process tree including fork children, (c) sessions survive terminal disconnects.
- `launch_socat_session()` returns a `(sid, pid)` tuple — the PID is needed by the watchdog to monitor the already-running process. In earlier versions, this returned only `sid`, forcing the watchdog to launch its own socat (causing the BUG-01 crash loop).
- `close_fds=True` on Popen ensures no file descriptor leaks from the management script to the socat process.
- Every launched socat process is a direct child of the management process, and its `Popen` handle is retained in a module-level registry keyed by PID. Retaining the handle is what makes liveness reporting truthful. When a child exits, the kernel keeps its process table entry until the parent collects the exit status; until then the entry is a zombie, and a zombie still answers signal 0. A liveness check written against `os.kill(pid, 0)` alone would therefore report an exited child as alive for as long as it went uncollected, and any poll waiting for that child to die would wait forever. `process_is_running()` consults the handle first, since polling it both collects a terminated child and reports the truth; it falls back to signal 0 qualified by a zombie check for processes this instance did not launch. `reap_child()` collects the status and drops the handle, so the registry only ever holds processes that are still running and cannot grow without bound.
- Stability check: after launch, a 0.3-second delay followed by `process_is_running()` verifies the process survived startup. Because the launched process is a retained child, this consults its handle and distinguishes a running process from one that exited immediately and has not yet been collected. If the process died immediately (e.g., port already bound), the launch is reported as failed.
- The 9-step stop sequence is protocol-scoped in two dimensions. The protocol model has four members (`tcp4`, `tcp6`, `udp4`, `udp6`), so scope is a transport and an address family, and every port operation carries both. `_scope_flags()` derives the socket-listing flags from the session's protocol: `-t`/`-u` selects the transport, `-4`/`-6` selects the family, `-l -n` restricts the listing to listening sockets. A `tcp4` operation queries `ss -t -4 -l -n`; the cleanup path adds `-p` to attach owning processes. `kill_by_port()` then kills only processes verified as socat via `/proc/{pid}/comm`. The family dimension is not optional: `tcp4` and `tcp6` listeners are independent sockets that can hold the same port number simultaneously, which is precisely what dual-stack operation creates. A transport-only scope would let a launch check treat an IPv6 listener as occupying the IPv4 port, and would let the cleanup path terminate the other family's socat session.
- `pkill -TERM -P` and `pkill -KILL -P` in steps 4 and 6 kill direct children by parent PID — belt-and-suspenders alongside the process group kill for cases where a child escapes the group.

**Security Properties**: No shell=True, argument-list-only subprocess, setsid isolation, close_fds=True, stability verification through the retained child handle, port operations scoped to a single transport and address family, socat-only process verification before any signal, advisory locking, error log files created with 0o600 permissions, stop_session validates SID against path traversal before path construction. Terminated children are collected rather than left as zombie entries, so a long-running management process does not consume process table slots.

### Functions

#### `launch_socat_session(name: str, mode: str, proto: str, lport: int, cmd: list[str], rhost: str = '', rport: str = '', stderr_redirect: str = '') -> tuple[str, int]`
**Defined at**: line 85–235 (151 lines)

Launch a socat process with session tracking and process isolation.

Creates a new process group via os.setsid, verifies the process
survives startup, and registers a session file with metadata.

Key differences from bash:
    - Python's Popen.pid gives the real socat PID directly
      (no setsid wrapper PID problem, no PID-file handoff needed)
    - Returns (session_id, pid) tuple directly (no global variable
      needed, no $() subshell blocking issue)

**Parameters**:

- name: Human-readable session name.
- mode: Operational mode (listen, forward, tunnel, redirect, etc.).
- proto: Normalized protocol (tcp4, udp4, etc.).
- lport: Local port number.
- cmd: Socat command as argument list for Popen.
- rhost: Optional remote host (for session file recording).
- rport: Optional remote port (for session file recording).
- stderr_redirect: Path to redirect stderr (for capture mode).
- Empty string = stderr to session error log.

**Returns**: Tuple of (session_id, pid) where session_id is the 8-character hex string and pid is the socat process PID.

**Raises**:

- RuntimeError: If launch fails (max sessions, PID death, etc.).

**Security annotations**:

- Uses subprocess.Popen with argument list (never shell=True)
- Creates isolated process group via os.setsid
- Sends signals to processes/groups

---

#### `register_child(process: subprocess.Popen) -> None`
**Defined at**: line 261–268 (8 lines)

Record a child process handle so its exit status can be collected. Every process launched by the framework is a direct child of the management process; retaining its handle is what lets an exited child be collected rather than left as a zombie. Called by `launch_socat_session()` and by the watchdog on every replacement launch. The handle registry is guarded by a lock.

**Parameters**:

- process: The Popen handle of a freshly launched child.

---

#### `reap_child(pid: int) -> int | None`
**Defined at**: line 271–297 (27 lines)

Collect the exit status of a terminated child and drop its handle. Collecting the status removes the process table entry, so the child stops being a zombie. A child that is still running is left alone.

**Parameters**:

- pid: PID of the child to collect.

**Returns**: The child's exit status, or None if the PID is not a child of this process or is still running.

---

#### `process_is_running(pid: int) -> bool`
**Defined at**: line 322–358 (37 lines)

Check whether a process is running, treating an exited but uncollected child as dead. For a child of this process the Popen handle is authoritative: polling it collects a terminated child and reports the truth. An exited child stays in the process table as a zombie until collected, and a zombie still answers signal 0, so a check written against signal 0 alone would report a dead child as alive. For a process this instance did not launch, signal 0 is used, qualified by a zombie check via `/proc/{pid}/stat`.

**Parameters**:

- pid: Process ID to check.

**Returns**: True if the process is running, False if it has exited.

---

#### `_is_zombie(pid: int) -> bool`
**Defined at**: line 300–319 (20 lines)

Report whether a PID names a process that has exited but not been reaped, by reading its state from `/proc/{pid}/stat`. Used to qualify a signal-0 liveness check for processes that are not children of this instance.

**Parameters**:

- pid: Process ID to inspect.

**Returns**: True if the process is in the zombie state, False otherwise.

---

#### `check_port_available(port: int, proto: str) -> bool`
**Defined at**: line 396–451 (56 lines)

Check if a port is available for binding on a specific protocol.

Uses ss (preferred) or netstat to detect existing listeners. The query is scoped to both the transport and the address family of the supplied protocol, so a `tcp6` listener never masks an available `tcp4` port and a UDP listener never masks an available TCP port. This is what makes dual-stack and mixed-family deployments correct.

**Parameters**:

- port: Port number to check.
- proto: Protocol to check (tcp4, tcp6, udp4, udp6).

**Returns**: True if the port is available, False if in use.

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)
- Query scope is derived from the protocol, never widened: the listing covers one transport and one address family

---

#### `check_port_freed(port: int, proto: str, retries: int = 0) -> bool`
**Defined at**: line 459–486 (28 lines)

Verify that a port has been released after stopping a session.

Retries multiple times with a delay to account for TIME_WAIT state. Scoped to the transport and address family of the supplied protocol, so a listener of the other family on the same port number does not keep this check reporting the port as still in use.

**Parameters**:

- port: Port number to verify.
- proto: Protocol to check (tcp4, tcp6, udp4, udp6).
- retries: Maximum retry attempts (0 = use default from config).

**Returns**: True if the port is freed, False if still in use.

---

#### `kill_by_port(port: int, proto: str) -> None`
**Defined at**: line 494–560 (67 lines)

Last-resort function to kill socat processes on a specific port.

Uses ss or lsof to find PIDs bound to the port. Only targets processes whose command name contains 'socat' to avoid killing unrelated services.

The query is scoped to both the transport and the address family of the supplied protocol. Without the family scope this function would enumerate listeners of the other family on the same port number and could terminate an unrelated socat session — a session on `tcp6` while stopping a session on `tcp4`, for example. The two are independent sockets and a stop directed at one must never disturb the other. The `lsof` fallback carries the same scope through its `-i4` and `-i6` selectors.

**Parameters**:

- port: Port number to clean up.
- proto: Protocol scope (tcp4, tcp6, udp4, udp6).

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)
- Enumeration is scoped to one transport and one address family, so the cleanup cannot reach a session of the other family
- Every candidate PID is verified as socat via `/proc/{pid}/comm` before any signal is sent
- Sends signals to processes/groups

---

#### `_extract_pids_from_line(line: str, pids: set[int]) -> None`
**Defined at**: line 563–578 (16 lines)

Extract PID numbers from an ss -p output line.

ss -p includes process info in format: "users:(("socat",pid=12345,fd=4))"
We extract the numeric PID values.

**Parameters**:

- line: A single line from ss output.
- pids: Set to add found PIDs to (mutated in place).

---

#### `_is_socat_process(pid: int) -> bool`
**Defined at**: line 581–598 (18 lines)

Check if a PID belongs to a socat process.

Reads /proc/{pid}/comm to verify the process name contains 'socat'.
This prevents kill_by_port from killing unrelated services.

**Parameters**:

- pid: Process ID to check.

**Returns**: True if the process is socat, False otherwise.

---

#### `_line_matches_port(line: str, port: int) -> bool`
**Defined at**: line 374–388 (15 lines)

Check whether a single line of `ss` or `netstat` output refers to the given local port, matching the port as the trailing component of an address so a different port that merely contains the digits is not matched.

**Parameters**:

- line: A single line of socket-listing output.
- port: Port number to match.

**Returns**: True if the line's address ends with the port number.

---

#### `stop_session(sid: str) -> bool`
**Defined at**: line 606–798 (193 lines)

Execute the 9-step stop sequence for a session.

This is the critical stop path. Every step must be protocol-scoped
to prevent cross-protocol interference on dual-stack configurations.

Steps:
    1. Read PROTOCOL from session file
    2. Touch .stop signal file (tells watchdog not to restart)
    3. os.killpg(pgid, SIGTERM) — SIGTERM entire process group
    4. os.kill(pid, SIGTERM) — direct SIGTERM to PID
    5. Wait up to STOP_GRACE_SECONDS in 0.5s intervals
    6. SIGKILL if still alive (process group + PID)
    7. kill_by_port() — protocol-scoped fallback
    8. check_port_freed() — verify port released
    9. Remove session file + signal files

**Parameters**:

- sid: Session ID to stop.

**Returns**: True if session was successfully stopped, False if issues remain.

**Security annotations**:

- Validates SID against path traversal characters (`/`, `\`, `..`, `\0`) before constructing file paths
- Uses subprocess.run with argument list (never shell=True)
- Sends signals to processes/groups
- Uses `DEFAULTS.stop_verify_retries` for port verification retry count

---


## `watchdog.py`

**Path**: `src/socat_manager/watchdog.py`  
**Lines**: 363  
**Purpose**: Monitor-First Auto-Restart with Exponential Backoff

**Module docstring**: Watchdog auto-restart monitor for socat sessions.

**Design Rationale**: The watchdog provides reliability by auto-restarting socat processes that crash unexpectedly. The critical design principle is MONITOR-FIRST: the watchdog NEVER launches the initial socat process. It receives the PID of an already-running process and waits for it to die through `process_is_running()`, which polls the retained child handle and reports an exited child truthfully rather than as a live zombie. Only after confirmed death does it enter the restart loop.

**Architecture Role**: Started by all 5 operational mode handlers when `--watchdog` is enabled. Runs as a daemon thread (`daemon=True`) so it doesn't prevent the main process from exiting. The mode handler passes the initial PID from `launch_socat_session()`.

**Bug History**: The original design (pre-v0.1.0) launched its own socat process. This caused BUG-01 (CRITICAL): the watchdog bound the same port that the primary launch had already bound, causing immediate exit code 1 and a crash loop through all 10 restart attempts. The complete rewrite to monitor-first eliminated this entire class of bugs.

**Behavioral Flow**:
1. Phase 1 (Monitor): Poll `os.kill(initial_pid, 0)` every 1 second. Zero CPU when healthy. Check for `.stop` signal file on each poll.
2. On death: Check `.stop` file — if present, exit gracefully (deliberate stop, not crash).
3. Phase 2 (Restart Loop): Sleep with exponential backoff (`backoff_initial`, doubles each restart, capped at 60s). Launch replacement socat via `subprocess.Popen` with same parameters. Rewrite the session record with the replacement PID and PGID via `session_update_process()`. Monitor the replacement PID. Repeat until `max_restarts` reached.
4. On max restarts: Log error, call `session_unregister()`, exit thread.

**Session Record Ownership**: The session file is the authoritative record of which process a session owns, and it is what `session_is_alive()` and `stop_session()` read. A restart replaces the process, so the watchdog writes the new PID and PGID back to the session file before it begins monitoring the replacement. Without that write-back the record would continue to name the terminated predecessor: status output would report the session dead while the replacement still held the port, and the stop sequence would signal a PID that no longer exists — leaving the live replacement running and reachable only through the port-based fallback. A failed replacement launch does not touch the record; the watchdog exits and the session is unregistered.

**Configurable Parameters**: `max_restarts` (default 10, CLI flag `--max-restarts`), `backoff_initial` (default 1 second, CLI flag `--backoff`). Both are prompted in the interactive menu when watchdog is enabled.

**Thread Safety**: Runs as a daemon thread. Session file operations use advisory locking, including the process identity update performed after each restart, which is published by atomic rename. The child handle registry in `process.py` is the one piece of state shared with the main thread, and it is guarded by a lock. The `.stop` signal file is the only coordination mechanism between the stop sequence and the watchdog.

**Death Detection**: The monitored socat process is a child of the management process, so `_wait_for_pid_death()` evaluates liveness through `process.process_is_running()` rather than signal 0. An exited child stays in the process table as a zombie until its exit status is collected, and a zombie answers signal 0, so a poll written against signal 0 alone would never observe the exit: the watchdog would block on its first dead process and stop restarting altogether. Once death is observed the child is collected through `reap_child()`, which clears the process table entry. Restarts therefore leave nothing behind, however many of them occur.

### Functions

#### `watchdog_loop(session_id: str, session_name: str, cmd: list[str], initial_pid: int, max_restarts: int = 0, backoff_initial: int = 1, stderr_redirect: str = '') -> None`
**Defined at**: line 73–193 (121 lines)

Background watchdog that monitors a process and auto-restarts on crash.

IMPORTANT: This function does NOT launch the initial socat process.
It monitors the already-running process identified by initial_pid.
Only after that process dies does it enter the restart loop.

On each restart, exponential backoff is applied starting from
backoff_initial seconds, doubling each time, capped at 60 seconds.

The .stop signal file tells the watchdog "this was a deliberate
stop — do NOT restart."

**Parameters**:

- session_id: Session ID being monitored.
- session_name: Human-readable session name.
- cmd: Socat command as argument list (used for restarts).
- initial_pid: PID of the already-running process to monitor.
- max_restarts: Maximum restart attempts (0 = use default).
- backoff_initial: Initial backoff delay in seconds (default: 1).
- stderr_redirect: Path for stderr redirection (capture mode).

**Security annotations**:

- Sends signals to processes/groups

---

#### `_wait_for_pid_death(pid: int, session_id: str, paths: object) -> None`
**Defined at**: line 200–232 (33 lines)

Block until a process dies, evaluating liveness through `process_is_running()`, then collect the child.

Checks every 1 second. Also checks for .stop signal file to allow
early exit on deliberate stop.

**Parameters**:

- pid: Process ID to monitor.
- session_id: Session ID (for .stop file check).
- paths: RuntimePaths instance.

**Security annotations**:

- Sends signals to processes/groups

---

#### `_launch_replacement(cmd: list[str], session_id: str, session_name: str, restart_count: int, stderr_redirect: str) -> int`
**Defined at**: line 235–299 (65 lines)

Launch a replacement socat process for the watchdog.

**Parameters**:

- cmd: Socat command as argument list.
- session_id: Session ID for logging.
- session_name: Session name for logging.
- restart_count: Current restart attempt number.
- stderr_redirect: Path for stderr redirection.

**Returns**: PID of the launched process, or 0 on failure.

**Security annotations**:

- Uses subprocess.Popen with argument list (never shell=True)
- Creates isolated process group via os.setsid

---

#### `_handle_stop_signal(stop_file: Path, session_id: str, session_name: str) -> None`
**Defined at**: line 302–320 (19 lines)

Handle a .stop signal file — graceful watchdog exit.

**Parameters**:

- stop_file: Path to the .stop signal file.
- session_id: Session ID.
- session_name: Session name.

---

#### `start_watchdog(session_id: str, session_name: str, cmd: list[str], initial_pid: int, max_restarts: int = 0, backoff_initial: int = 1, stderr_redirect: str = '') -> threading.Thread`
**Defined at**: line 327–363 (37 lines)

Start a watchdog monitor as a daemon thread.

The watchdog monitors the already-running process (initial_pid)
and only re-launches on death. It does NOT launch the initial process.

**Parameters**:

- session_id: Session ID to monitor.
- session_name: Human-readable session name.
- cmd: Socat command as argument list (used for restarts).
- initial_pid: PID of the already-running process.
- max_restarts: Maximum restart attempts (0 = use default).
- backoff_initial: Initial backoff seconds between restarts (default: 1).
- stderr_redirect: Path for stderr redirection (capture mode).

**Returns**: The started daemon Thread object.

---


## `certs.py`

**Path**: `src/socat_manager/certs.py`  
**Lines**: 129  
**Purpose**: TLS Self-Signed Certificate Generation

**Module docstring**: TLS certificate generation for tunnel mode.

**Design Rationale**: Single-purpose module for TLS certificate generation. Isolates OpenSSL subprocess interaction from the tunnel mode handler.

**Architecture Role**: Called only by `modes/tunnel.py` when `--cert` and `--key` are not provided. Generates a self-signed certificate using `openssl req -x509 -newkey rsa:2048`.

**Security Properties**: Uses `subprocess.run` with argument list (never shell=True). Sets 0o600 permissions on generated key files via the calling mode handler. The generated certificate uses `/CN=<cn>` where `cn` defaults to `localhost` and can be overridden via `--cn`. Certificate validity is 365 days.

### Functions

#### `generate_self_signed_cert(cn: str = 'localhost') -> tuple[str, str]`
**Defined at**: line 48–129 (82 lines)

Generate a self-signed certificate and private key for TLS tunnels.

Creates a 2048-bit RSA key pair with a self-signed X.509 certificate
valid for 365 days. Files are written to the certs/ directory.

Private key permissions are set to 0o600 (owner read/write only)
via os.open() to avoid race conditions between create and chmod.

**Parameters**:

- cn: Common Name for the certificate (default: "localhost").

**Returns**: Tuple of (cert_path, key_path) as absolute path strings.

**Raises**:

- RuntimeError: If openssl is not found or certificate generation fails.

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)
- Sets restrictive file permissions (0o600)

---


## `cli.py`

**Path**: `src/socat_manager/cli.py`  
**Lines**: 337  
**Purpose**: CLI Argument Parser (argparse)

**Module docstring**: CLI argument parser for socat-manager.

**Design Rationale**: Single function `build_parser()` that constructs the complete argparse configuration. Having all CLI definitions in one place makes it easy to audit what flags are available and ensures consistency across modes.

**Architecture Role**: Called by `__main__.main()` for CLI dispatch and by `menu._confirm_and_execute()` for re-parsing menu-constructed argument lists. Returns an `ArgumentParser` with 10 subparsers (7 modes + menu + help + version).

**Key Design Decisions**:
- `RawDescriptionHelpFormatter` on all subparsers preserves the epilog examples formatting.
- `--max-restarts` and `--backoff` are on all 5 operational mode parsers (not just listen) because any mode can use watchdog.
- `help` and `version` are subcommands (not just flags) so operators can type `socat-manager help` and `socat-manager version` in addition to `--help` and `--version`.
- The main parser epilog includes a complete mini-reference with examples, session management explanation, protocol selection guide, reliability notes, and logging paths — matching bash `show_main_help()`.

### Functions

#### `build_parser() -> argparse.ArgumentParser`
**Defined at**: line 31–337 (307 lines)

Build and return the complete CLI argument parser.

**Returns**: Configured ArgumentParser with subparsers for all modes.

---


## `__main__.py`

**Path**: `src/socat_manager/__main__.py`  
**Lines**: 282  
**Purpose**: Entry Point, Signal Handlers, and CLI Dispatch

**Module docstring**: Entry point for socat-manager: CLI dispatch and menu fallback.

**Design Rationale**: Thin dispatch layer. Parses CLI arguments, installs signal handlers, checks dependencies, and routes to the appropriate mode handler or interactive menu. Deliberately kept minimal to reduce the attack surface of the entry point.

**Architecture Role**: Top-level entry point. Called by `socat-manager.py` (standalone runner), pip-installed `socat-manager` console script, or `python3 -m socat_manager`. Imports are deferred (inside functions) to minimize startup time and avoid circular imports. The standalone runner (`socat-manager.py`) checks `sys.version_info >= (3, 12)` before importing and wraps the import in `try/except ImportError` for clear error messages on misconfigured installations.

**Signal Handling**: Three handlers registered in `main()`:
- `SIGTERM`: Clean exit with code 0. Does NOT stop managed sessions (they survive via setsid).
- `SIGINT` (Ctrl+C): Clean exit with code 130 (standard Unix convention: 128 + signal number).
- `SIGHUP` (terminal hangup): Clean exit with code 0. Managed sessions survive.

**Dispatch Flow**: `main()` → `build_parser()` → `parse_args()` → route by `args.mode`: None/"menu" → `interactive_menu()`, "help" → `print_help()`, "version" → print version, operational modes → `check_socat()` → `dispatch_mode()` → mode handler.

### Functions

#### `_handle_sigterm(signum: int, frame: Any) -> None`
**Defined at**: line 48–59 (12 lines)

Handle SIGTERM for clean shutdown.

Does NOT stop managed sessions (they survive via setsid).
Only cleans up the management script itself.

**Parameters**:

- signum: Signal number received.
- frame: Current stack frame (unused).

**Security annotations**:

- May call sys.exit() on fatal errors

---

#### `_handle_sigint(signum: int, frame: Any) -> None`
**Defined at**: line 62–71 (10 lines)

Handle SIGINT (Ctrl+C) for clean exit.

**Parameters**:

- signum: Signal number received.
- frame: Current stack frame (unused).

**Security annotations**:

- May call sys.exit() on fatal errors

---

#### `_handle_sighup(signum: int, frame: Any) -> None`
**Defined at**: line 74–85 (12 lines)

Handle SIGHUP (terminal hangup) for clean exit.

Does NOT stop managed sessions (they survive via setsid).
Matches bash trap 'cleanup_handler HUP' HUP behavior.

**Parameters**:

- signum: Signal number received.
- frame: Current stack frame (unused).

**Security annotations**:

- May call sys.exit() on fatal errors

---

#### `check_socat() -> None`
**Defined at**: line 92–129 (38 lines)

Verify socat is installed and in PATH.

Prints installation instructions if not found.

**Raises**:

- SystemExit: If socat is not found.

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)
- May call sys.exit() on fatal errors

---

#### `initialize_logging(args: Any) -> None`

Apply the verbose flag and configure logging for this invocation.

This is the single initialization point for logging. It runs once per invocation, immediately after argument parsing and before any path that produces output — the interactive menu, the mode handlers, and the startup banner all depend on it. The verbose flag is applied before the logger is configured, because the flag determines the effective log level and that level is fixed once the handlers are attached.

**Parameters**:

- args: Parsed argparse Namespace, which may carry a `verbose` flag.

---

#### `dispatch_mode(args: Any) -> None`
**Defined at**: line 136–182

Dispatch to the appropriate mode handler based on parsed args. Handles all 8 mode values: listen, batch, forward, tunnel, redirect, status, stop, and menu. The menu case imports and calls `interactive_menu()` directly.

**Parameters**:

- args: Parsed argparse Namespace with 'mode' attribute.

**Security annotations**:

- May call sys.exit() on fatal errors
- Deferred imports prevent circular dependencies

---

#### `main() -> None`
**Defined at**: line 209–277 (69 lines)

Main entry point for socat-manager.

Parses CLI arguments and dispatches to the appropriate handler.
No arguments (or 'menu' subcommand) launches interactive mode.

---


## `menu.py`

**Path**: `src/socat_manager/menu.py`  
**Lines**: 900  
**Purpose**: Interactive TUI Menu System

**Module docstring**: Interactive menu system for socat-manager.

**Design Rationale**: Full-featured interactive TUI that provides guided, validated input for every operational mode. Designed for operators who prefer menu-driven interfaces over remembering CLI flags. Every prompt validates input and supports cancel (`q`/`quit`/`cancel`/`back`) to return to the parent menu.

**Architecture Role**: Alternative entry point alongside CLI. Constructs the same argument lists that the CLI would produce, then passes them to `dispatch_mode()` via `_confirm_and_execute()`. This means the menu and CLI produce identical behavior — the menu is purely a UI layer.

**Key Design Decisions**:
- `_MenuCancel` exception is the cancel propagation mechanism. Every prompt function raises it on cancel keywords or Ctrl+C/Ctrl+D. Submenu functions catch it to return to the root menu.
- `_confirm_and_execute()` wraps `dispatch_mode()` in `try/except` catching `SystemExit`, `KeyboardInterrupt`, and generic `Exception`. This ensures the menu always returns to the main loop after execution, even if a mode handler calls `sys.exit(1)` on validation failure. This was BUG-03 fix.
- After listener execution, `_offer_paired_forward()` asks the user if they want to configure a forward with the listener's port pre-filled. This simplifies the common listen-then-forward workflow.
- `_collect_common_flags()` handles protocol, dual-stack, capture, watchdog (with configurable max_restarts and backoff prompts), and session name — shared across all 5 operational modes.
- Ctrl+C at the main menu prompt exits gracefully with "Goodbye". Ctrl+C during submenu or execution returns to the menu loop.
- The socat opts prompt shows 3 examples (`reuseaddr,fork`, `bind=10.0.0.1`, `keepalive,nodelay`) to guide operators.

**Cross-References**: Imports `cli.build_parser()` and `__main__.dispatch_mode()` locally inside `_confirm_and_execute()` to avoid circular imports. Uses all validation functions from `validation.py` for prompt input checking.

### Constants and Module-Level Variables

- **`_CANCEL_KEYWORDS`** `frozenset[str]` = `frozenset({'q', 'quit', 'cancel', 'back', 'exit'})` (line 59)

### Class `_MenuCancel`
**Defined at**: line 54–56

Raised when user enters a cancel keyword at any menu prompt.

### Functions

#### `_is_cancel(text: str) -> bool`
**Defined at**: line 62–64 (3 lines)

Check if user input is a cancel keyword.

---

#### `_prompt(text: str, default: str = '') -> str`
**Defined at**: line 71–104 (34 lines)

Display a prompt and read input. Raises _MenuCancel on cancel keywords.

**Parameters**:

- text: Prompt text to display.
- default: Default value if user presses Enter.

**Returns**: User input or default value.

**Raises**:

- _MenuCancel: If user enters a cancel keyword.

---

#### `_prompt_yn(text: str, default: str = 'n') -> bool`
**Defined at**: line 107–143 (37 lines)

Prompt for a yes/no answer. Raises _MenuCancel on cancel.

**Parameters**:

- text: Prompt text.
- default: Default answer ('y' or 'n').

**Returns**: True for yes, False for no.

**Raises**:

- _MenuCancel: On cancel keyword.

---

#### `_prompt_choice(text: str, max_val: int, default: str = '') -> int`
**Defined at**: line 146–163 (18 lines)

Prompt for a numbered choice. Raises _MenuCancel on cancel.

**Parameters**:

- text: Prompt text.
- max_val: Maximum valid selection number.
- default: Default selection.

**Returns**: Selected number.

---

#### `_prompt_port(text: str = 'Port', default: str = '') -> int`
**Defined at**: line 166–173 (8 lines)

Prompt for a validated port number.

**Security annotations**:

- Validates input through whitelist validators before use

---

#### `_prompt_host(text: str = 'Host', default: str = '') -> str`
**Defined at**: line 176–183 (8 lines)

Prompt for a validated hostname/IP.

**Security annotations**:

- Validates input through whitelist validators before use

---

#### `_prompt_protocol(text: str = 'Protocol', default: str = 'tcp4') -> str`
**Defined at**: line 186–193 (8 lines)

Prompt for a validated protocol.

**Security annotations**:

- Validates input through whitelist validators before use

---

#### `_prompt_name(text: str = 'Session name', default: str = '') -> str`
**Defined at**: line 196–205 (10 lines)

Prompt for a validated session name (optional — empty returns default).

**Security annotations**:

- Validates input through whitelist validators before use

---

#### `_print_error(msg: str) -> None`
**Defined at**: line 212–217 (6 lines)

Print an error message to stderr.

---

#### `_menu_header(title: str) -> None`
**Defined at**: line 220–232 (13 lines)

Print a boxed submenu header.

---

#### `_cancel_hint() -> None`
**Defined at**: line 235–240 (6 lines)

Print the cancel hint line.

---

#### `_cancelled() -> None`
**Defined at**: line 243–248 (6 lines)

Print the cancelled message.

---

#### `_pause() -> None`
**Defined at**: line 251–256 (6 lines)

Wait for user to press Enter.

---

#### `_menu_banner() -> None`
**Defined at**: line 259–281 (23 lines)

Display the ASCII art SOCAT banner.

---

#### `_collect_common_flags(args: list[str], offer_protocol: bool = True, offer_dualstack: bool = True) -> None`
**Defined at**: line 288–339 (52 lines)

Collect common flags shared across operational modes.

Mutates the args list in place by appending collected flags.
When watchdog is enabled, prompts for max restart attempts and
backoff delay interval.

**Parameters**:

- args: Command argument list to append to.
- offer_protocol: Whether to offer protocol selection.
- offer_dualstack: Whether to offer dual-stack option.

**Raises**:

- _MenuCancel: On cancel at any prompt.

---

#### `_menu_listen() -> list[str] | None`
**Defined at**: line 346–391 (46 lines)

Listen mode submenu. Returns args list or None on cancel.

After listener configuration, offers to configure a paired forward
to simplify operational setup.

**Security annotations**:

- Validates input through whitelist validators before use

---

#### `_menu_batch() -> list[str] | None`
**Defined at**: line 394–419 (26 lines)

Batch mode submenu.

---

#### `_menu_forward() -> list[str] | None`
**Defined at**: line 422–440 (19 lines)

Forward mode submenu.

---

#### `_menu_tunnel() -> list[str] | None`
**Defined at**: line 443–476 (34 lines)

Tunnel mode submenu.

---

#### `_menu_redirect() -> list[str] | None`
**Defined at**: line 479–491 (13 lines)

Redirect mode submenu.

---

#### `_menu_status() -> list[str] | None`
**Defined at**: line 494–514 (21 lines)

Status mode submenu.

---

#### `_menu_stop() -> list[str] | None`
**Defined at**: line 517–548 (32 lines)

Stop mode submenu.

---

#### `_menu_check_deps() -> None`
**Defined at**: line 551–605 (55 lines)

Display dependency check results.

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)

---

#### `_confirm_and_execute(args: list[str], dispatch_fn: object) -> None`
**Defined at**: line 612–661 (50 lines)

Show the constructed command, confirm, and execute.

Wraps execution in try/except to ensure graceful return to menu
on any error including SystemExit and KeyboardInterrupt. Watchdog
threads are daemon=True so they continue in background without
blocking the menu return.

After executing a listener, offers to configure a paired forward.

**Parameters**:

- args: The command arguments (mode + flags).
- dispatch_fn: Unused (kept for API compatibility).

**Security annotations**:

- May call sys.exit() on fatal errors

---

#### `_offer_paired_forward(listener_args: list[str]) -> None`
**Defined at**: line 664–707 (44 lines)

Offer to configure a paired forward after a listener is launched.

Pre-fills the local port from the listener configuration to
simplify operational setup.

**Parameters**:

- listener_args: The listener command arguments that were just executed.

---

#### `_menu_show_help() -> None`
**Defined at**: line 714–798 (85 lines)

Display full help with narrative sections.

Matches the bash show_main_help() output with full operational
details, session management explanation, protocol selection guide,
reliability features, logging paths, and CLI usage examples.

---

#### `interactive_menu() -> None`
**Defined at**: line 805–900 (96 lines)

Main interactive menu loop.

Displays the root menu, dispatches to submenus, and loops
until the user exits (option 0).

---


## `modes/listen.py`

**Path**: `src/socat_manager/modes/listen.py`  
**Lines**: 269  
**Purpose**: Listen Mode Handler

**Module docstring**: Listen mode handler — single TCP/UDP listener on a port.

### Functions

#### `mode_listen(args: Any) -> None`
**Defined at**: line 60–256 (197 lines)

Execute listen mode: start a single TCP/UDP listener.

Handles argument validation, port availability checks, command
construction, process launch, and optional dual-stack/watchdog.

**Parameters**:

- args: Parsed argparse Namespace with listen-mode attributes:
- port, proto, bind, name, logfile, capture, watchdog,
- dual_stack, socat_opts, verbose.

**Raises**:

- SystemExit: On validation failure or launch error.

**Security annotations**:

- Validates input through whitelist validators before use
- User-provided `--logfile` path validated for path traversal (component-based `..` check) and shell metacharacters before reaching socat `OPEN:` address
- May call sys.exit() on fatal errors

---

#### `_create_capture_log(path: str) -> None`

Create a capture log file with restrictive permissions (0o600).

**Parameters**:

- path: Path to the capture log file.

**Security annotations**:

- Sets restrictive file permissions (0o600)

---


## `modes/batch.py`

**Path**: `src/socat_manager/modes/batch.py`  
**Lines**: 272  
**Purpose**: Batch Mode Handler

**Module docstring**: Batch mode handler — multiple listeners from port list, range, or config file.

### Functions

#### `mode_batch(args: Any) -> None`
**Defined at**: line 54–263 (210 lines)

Execute batch mode: start multiple listeners.

Supports three port sources (mutually exclusive):
    --ports  : comma-separated port list (e.g., "21,22,80,443")
    --range  : port range (e.g., "8000-8010")
    --file   : config file with one port per line

Ports are deduplicated via `sorted(set(ports))` before launching.
Duplicate ports in the input are logged and removed.
Each port gets an independent session with its own session ID.

**Parameters**:

- args: Parsed argparse Namespace with batch-mode attributes.

**Raises**:

- SystemExit: On validation failure or if no ports specified.

**Security annotations**:

- Validates input through whitelist validators before use
- May call sys.exit() on fatal errors

---

#### `_create_capture_log(path: str) -> None`
**Defined at**: line 266–272 (7 lines)

Create a capture log file with restrictive permissions (0o600).

**Security annotations**:

- Sets restrictive file permissions (0o600)

---


## `modes/forward.py`

**Path**: `src/socat_manager/modes/forward.py`  
**Lines**: 230  
**Purpose**: Forward Mode Handler

**Module docstring**: Forward mode handler — bidirectional port forwarding.

### Functions

#### `mode_forward(args: Any) -> None`
**Defined at**: line 53–221 (169 lines)

Execute forward mode: bidirectional port forwarding.

**Parameters**:

- args: Parsed argparse Namespace with forward-mode attributes:
- lport, rhost, rport, proto, remote_proto, name, capture,
- watchdog, dual_stack, verbose.

**Raises**:

- SystemExit: On validation failure or launch error.

**Security annotations**:

- Validates input through whitelist validators before use
- May call sys.exit() on fatal errors

---

#### `_create_capture_log(path: str) -> None`
**Defined at**: line 224–230 (7 lines)

Create a capture log file with restrictive permissions (0o600).

**Security annotations**:

- Sets restrictive file permissions (0o600)

---


## `modes/tunnel.py`

**Path**: `src/socat_manager/modes/tunnel.py`  
**Lines**: 324  
**Purpose**: Tunnel Mode Handler

**Module docstring**: Tunnel mode handler — TLS-encrypted tunnel via socat+OpenSSL.

### Functions

#### `mode_tunnel(args: Any) -> None`
**Defined at**: line 62–315 (254 lines)

Execute tunnel mode: TLS-encrypted tunnel.

TLS tunnels are TCP-only by definition. If --proto udp is specified,
the command exits with an error and guidance to use forward mode.
Dual-stack adds a plaintext UDP forwarder with a clear warning.

The `--cn` parameter is validated via `validate_session_name()` before
reaching `openssl -subj "/CN=..."`. Default CN `localhost` bypasses
validation. This prevents unvalidated characters from reaching the
openssl subprocess argument.

**Parameters**:

- args: Parsed argparse Namespace with tunnel-mode attributes:
- port, rhost, rport, cert, key, cn, name, capture,
- watchdog, dual_stack, proto, verbose.

**Raises**:

- SystemExit: On validation failure or launch error.

**Security annotations**:

- Validates input through whitelist validators before use
- `--cn` validated via `validate_session_name()` before reaching openssl subprocess
- Detects and warns on cert/key mismatch (one provided without the other) — forces regeneration instead of silently ignoring the provided file
- May call sys.exit() on fatal errors

---

#### `_create_capture_log(path: str) -> None`

Create a capture log file with restrictive permissions (0o600).

**Security annotations**:

- Sets restrictive file permissions (0o600)

- Sets restrictive file permissions (0o600)

---


## `modes/redirect.py`

**Path**: `src/socat_manager/modes/redirect.py`  
**Lines**: 215  
**Purpose**: Redirect Mode Handler

**Module docstring**: Redirect mode handler — transparent port redirection.

### Functions

#### `mode_redirect(args: Any) -> None`
**Defined at**: line 51–206 (156 lines)

Execute redirect mode: transparent port redirection.

**Parameters**:

- args: Parsed argparse Namespace with redirect-mode attributes:
- lport, rhost, rport, proto, name, capture, watchdog,
- dual_stack, verbose.

**Raises**:

- SystemExit: On validation failure or launch error.

**Security annotations**:

- Validates input through whitelist validators before use
- May call sys.exit() on fatal errors

---

#### `_create_capture_log(path: str) -> None`
**Defined at**: line 209–215 (7 lines)

Create a capture log file with restrictive permissions (0o600).

**Security annotations**:

- Sets restrictive file permissions (0o600)

---


## `modes/status.py`

**Path**: `src/socat_manager/modes/status.py`  
**Lines**: 168  
**Purpose**: Status Mode Handler

**Module docstring**: Status mode handler — session listing, detail, and cleanup.

### Functions

#### `mode_status(args: Any) -> None`
**Defined at**: line 44–105 (62 lines)

Execute status mode: display session information.

Lookup priority for the optional positional argument:
    1. Session ID (8-char hex, exact file match)
    2. Session name (exact match across all session files)
    3. Port number (may match multiple sessions for dual-stack)

**Parameters**:

- args: Parsed argparse Namespace with status-mode attributes:
- target (positional), cleanup, verbose.

**Security annotations**:

- May call sys.exit() on fatal errors

---

#### `_show_system_listeners() -> None`
**Defined at**: line 108–168 (61 lines)

Display socat processes detected by ss or netstat.

Used in verbose mode to show system-level listener information.

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)

---


## `modes/stop.py`

**Path**: `src/socat_manager/modes/stop.py`  
**Lines**: 207  
**Purpose**: Stop Mode Handler

**Module docstring**: Stop mode handler — session termination by various selectors.

### Functions

#### `mode_stop(args: Any) -> None`
**Defined at**: line 46–181 (136 lines)

Execute stop mode: terminate sessions.

Selectors (mutually prioritized):
    positional: Session ID or name (first non-flag argument)
    --all:      Stop all registered sessions
    --name:     Stop by session name
    --port:     Stop all sessions on a port (all protocols)
    --pid:      Stop by PID

**Parameters**:

- args: Parsed argparse Namespace with stop-mode attributes:
- target (positional), all, name, port, pid, verbose.

**Raises**:

- SystemExit: If no selector specified or on validation failure.

**Security annotations**:

- Validates input through whitelist validators before use
- May call sys.exit() on fatal errors

---

#### `_cleanup_orphaned_socat() -> None`
**Defined at**: line 184–207 (24 lines)

Report any orphaned socat processes not tracked by sessions.

This is a safety net after --all stop. It checks for socat processes
still running and logs warnings but does NOT kill them automatically
(they may belong to other users or instances).

**Security annotations**:

- Uses subprocess.run with argument list (never shell=True)

---

