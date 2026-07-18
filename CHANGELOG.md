# Changelog

All notable changes to socat_manager.sh are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Added
- **Interactive menu system**: Running with no arguments launches a full-featured
  menu-driven interface with guided input collection, validation at every prompt,
  and cancel/escape support (type `q` at any prompt to return to main menu).
  Also accessible via `socat-manager menu`.
- **ASCII art banner**: Stylized SOCAT block-letter banner in the interactive menu.
- **Dependency check menu**: Option 8 in the interactive menu checks all required
  and recommended dependencies with version info and status indicators.

### Security (Audit Remediation)
- **C-1**: Eliminated all `eval` calls - watchdog uses `bash -c` instead.
- **C-2**: New `validate_socat_opts()` - whitelist validation on `--socat-opts` input.
- **C-4**: New `validate_session_name()` - whitelist validation on `--name` input,
  wired into all four mode parsers (listen, forward, tunnel, redirect).
- **H-3**: `stop --pid` input validated as numeric-only before use.
- **H-4**: `session_read_field` uses `awk` exact-match instead of `grep` regex.
- **H-5**: All `DEFAULT_*` configuration variables marked `readonly`.
- **M-2**: Advisory file locking via `flock` for session directory operations.
- **M-4**: `MAX_SESSIONS=256` limit enforced at launch time.
- **M-5**: Capture log files created with `chmod 600` (all 9 code paths).
- **M-6**: IPv6 validation enhanced with length (2-39) and colon count (≤7) checks.
- **L-1**: Terminal detection - color codes disabled when stderr is not a terminal.
- **L-4**: Removed unused `DEFAULT_TIMEOUT`, `DEFAULT_MAX_CHILDREN`, `DEFAULT_BUFFER_SIZE`.

### Changed
- No-args behavior: shows interactive menu instead of help text.
- Session file format comment updated to v2.3.
- `_ensure_dirs` uses guard variable (called once, not per log write).
- **Makefile v2.0.0**: Added `test-smoke` target (menu launch, help, version, syntax - no BATS needed).
  `lint` now checks all bash files (stubs, helpers). `check-deps` checks `flock`. `dist` includes
  `wiki/` and `.github/`. `clean` removes test artifacts and lock files. `verify` tests menu launch.
- **Test suite**: 220 tests (up from 187). Added 33 tests covering `validate_socat_opts` (12),
  `validate_session_name` (11), IPv6 rejection (4), `session_read_field` awk behavior (3),
  `_session_lock` (3).
- `.shellcheckrc`: Documented SC2015 pattern and nameref usage.
- `.gitignore`: Added `sessions/.lock`.

---

## [2.5.1] - 2026-07-17

### Fixed

- **`-v` and `--verbose` were rejected as an unknown mode when used in the global
  position.** The global argument pre-parse (added for `--log-format` and
  `--log-level`) did not recognize `-v`/`--verbose`, so a leading or standalone
  `-v` fell through and was treated as the mode name. Verbose is now handled in
  the pre-parse and works before the mode, after the mode, and on its own, while
  still being accepted by the per-mode parsers.
- **A test required python3, which is not present on every target distribution.**
  The JSON-escaping test in `log_format.bats` used `python3` to parse the log
  line; on runners without python3 it exited 127, which newer BATS reports as a
  BW01 warning and fails the suite. The test now verifies the escaping with a
  dependency-free shell string match. Added global-verbose regression tests.

---

## [2.5.0] - 2026-07-17

### Added

- **Example files for `conf/` and `certs/`.** `conf/` now ships an annotated
  batch configuration (`example-ports.conf`) and a `README.md` documenting the
  config-file format. `certs/` ships a `README.md` covering certificate
  generation, bring-your-own certificates, and the storage convention, plus a
  sample public certificate (`example-tunnel.pem.sample`, no private key). Both
  are included in the release tarball and tracked by git (runtime data and
  private keys remain ignored).

### Documentation

- Expanded the README batch and tunnel sections with the config-file format
  (inline comments, single-port entries) and certificate handling (auto-
  generation naming, `--key-type`, bring-your-own, a manual generation command),
  each pointing to the new example files. Corrected a stale `--file` reference to
  `--config`, and updated the Configuration Reference directory table.

---

## [2.4.9] - 2026-07-17

### Fixed

- **Interactive menu closed the framework on Ctrl+C** instead of returning to the
  menu. The global INT trap runs a handler that exits; the menu now installs a
  non-exiting INT trap for its lifetime, so Ctrl+C cancels the current prompt and
  unwinds to the menu. The CLI keeps the original cleanup-on-signal behaviour.
- **Interactive menu appeared to hang after a stop** ("Stop summary" with no
  return to the menu, and any key closing the framework). Root cause: the session
  lock used `exec 200>file 2>/dev/null`; with no command after `exec`, the
  `2>/dev/null` was applied to the shell permanently and silenced all later
  stderr, which is where the entire menu UI is written. The redirection is now
  scoped so only the file descriptor is affected. All four stop paths (all, name,
  port, PID) return to the menu.
- **Menu prompts could loop or exit on closed stdin.** Prompt reads now detect
  end-of-input and unwind cleanly instead of spinning on empty input or tripping
  `set -e`.
- **Traffic capture files were not readable by any tool.** Capture now uses
  socat `-v -x`, producing a plain-text hex + ASCII dump viewable with any text
  tool. This is not a pcap; the documentation explains the format and how to run
  a separate packet capture if a pcap is needed. In listen mode the raw received
  bytes remain in a separate data-log file.

### Added

- **`--log-level <DEBUG|INFO|WARNING|ERROR|CRITICAL>`** sets the minimum severity
  written to the master log and console (default INFO). `-v`/`--verbose` forces
  DEBUG. Also settable via `SOCAT_MANAGER_LOG_LEVEL`; exported for the watchdog
  re-exec. Added the `log_level` test suite (9 tests).

### Changed

- Refreshed the script header block to describe all current modes and options
  (the `audit` command, `--allow`, `--tcpwrap`, `--key-type`, `--log-format`,
  `--log-level`, the audit store, `SOCAT_MANAGER_BASE`, and the readable capture
  format), and added `sqlite3` to the optional dependencies.

---

## [2.4.8] - 2026-07-16

### Fixed

- **Removed all em-dash (U+2014) and other dash-like Unicode from the entire
  project (code, tests, and documentation)**, per the project style rule. A prior
  scan using `grep -P` had missed these because of locale handling; a reliable
  UTF-8-aware scan found and a character swap remediated every occurrence
  (spacing preserved). This changed some user-facing output text (menu and help
  lines now use a hyphen separator).
- **Removed AI-language indicators** ("comprehensive" and similar) from code
  comments, help text, and shipped documentation.

### Documentation

- Corrected the test count across the documentation to the current suite size, and
  corrected the SECURITY command-execution section to describe the current
  argv-based launch and the `--socat-opts` keyword allowlist (previously described
  the older interpolated `bash -c` model).
- Documented the newer options and features in the README and Configuration
  Reference: `--allow`, `--tcpwrap`, `--key-type`, `--log-format`, the `audit`
  command, and the `SOCAT_MANAGER_*` environment variables.
- Normalized stale version call-outs to describe current behavior, with version
  history kept in this changelog. Added disambiguation notes between the Developer
  Guide (API reference) and Development Guide (workflow). Removed a stray planning
  document from the wiki.

---

## [2.4.7] - 2026-07-15

### Changed

- **De-monolith (A-01)**: the utility is now developed as focused module sources
  under `lib/` (18 modules: preamble, constants, logging, display, validation,
  session, port, builders, cert, audit, watchdog, modes, signal, depcheck, help,
  compat, menu, main) and assembled into the single-file `socat_manager.sh` by
  `scripts/build-dist.sh` (`make build`). The shipped artifact remains one
  self-contained script - the initial split is byte-for-byte identical to the
  previous file apart from a generated-file notice, so behaviour is unchanged.
  `make verify-build` checks the single file is in sync with `lib/` and runs as
  the first step of `make test`. ShellCheck continues to run against the assembled
  script. The detached watchdog supervisor re-exec is unaffected (it runs the
  single-file artifact).

---

## [2.4.6] - 2026-07-15

### Added

- **JSON log output (P-06)**: a new `--log-format <text|json>` global option (also
  settable with `SOCAT_MANAGER_LOG_FORMAT`) writes the master and session log files
  as newline-delimited JSON objects (`ts`, `level`, `correlation_id`, `component`,
  `message`) for ingestion by log pipelines. The default remains the structured
  text line, and console output stays human-readable in both modes. The flag may
  appear before or after the mode and is exported so the detached watchdog
  supervisor logs in the same format. All values are JSON-escaped.

---

## [2.4.5] - 2026-07-15

### Added

- **Optional SQLite audit store (P-04)**: framework events - session launches,
  stops, failed stops, watchdog restarts, and crashes - are recorded to a SQLite
  database under `<base>/audit/audit.db` when the `sqlite3` command is available.
  A new `audit` command lists and filters the history (`--limit`, `--type`,
  `--session`, `--prune`). Auditing is on by default when sqlite3 is present and is
  disabled with `SOCAT_MANAGER_AUDIT` set to a false-like value; systems without
  sqlite3 are unaffected. Remote-host redaction (`SOCAT_MANAGER_AUDIT_REDACT`), a
  configurable database path (`SOCAT_MANAGER_AUDIT_DB`), and a retention window
  (`SOCAT_MANAGER_AUDIT_RETENTION_DAYS`) are supported. This matches the Python
  variant's audit feature.

### Security

- Every recorded value is emitted as a properly escaped SQL literal (single quotes
  doubled) or, for integer columns, a validated integer or NULL - no user value is
  concatenated into SQL unescaped. Audit view filters are escaped the same way.

---

## [2.4.4] - 2026-07-15

### Added

- **`SOCAT_MANAGER_BASE` environment override (P-05)**: runtime data directories
  (`logs/`, `sessions/`, `conf/`, `certs/`) are now rooted at a base directory that
  can be set with the `SOCAT_MANAGER_BASE` environment variable. A relative value
  is resolved to an absolute path, and the resolved base is exported so the
  detached watchdog supervisor derives identical paths. When unset, the base
  remains the script's own directory, preserving existing behaviour. This allows
  running against a dedicated data directory or isolating concurrent instances, and
  matches the Python variant.

---

## [2.4.3] - 2026-07-15

### Added

- **Source-address access control (P-03)**: new `--allow <CIDR>` and
  `--tcpwrap [NAME]` options on the listener modes (listen, batch, forward,
  tunnel, redirect). `--allow` restricts accepted client sources to an IPv4 or
  IPv6 range and maps to socat's address-level `range=` option; host bits are
  masked (10.1.2.3/8 becomes 10.0.0.0/8) and IPv6 ranges are rendered in the
  bracketed form socat expects. `--tcpwrap` enforces `/etc/hosts.allow` and
  `/etc/hosts.deny` through TCP wrappers (`tcpwrap=`), defaulting the daemon name
  to `socat`. Both filters apply to the listener side only. This brings the bash
  utility to parity with the Python variant's source-filtering feature.

### Security

- New validators `validate_source_range` (IPv4/IPv6 CIDR with host-bit masking)
  and `validate_tcpwrap_name` (short token, no metacharacters) ensure the values
  cannot inject additional socat options.

---

## [2.4.2] - 2026-07-15

### Security

- **Exact local-port matching in the last-resort port killer (S-05)**: `_kill_by_port`
  previously located PIDs with a loose `grep ":<port> "` substring over the whole
  `ss` output, which could match a peer-side port or a longer port containing the
  same digits. Matching is now performed with awk against the local address column
  only, comparing the final colon-separated field exactly (IPv6 forms such as
  `[::]:<port>` included). PID extraction no longer relies on `grep -P` (`\K`),
  which is GNU-only; awk ERE is used instead. The socat version probe in the
  dependency check was likewise moved off `grep -P` to `sed` for portability.

---

## [2.4.1] - 2026-07-15

### Security

- **Hardened self-signed tunnel certificates (S-04)**: generated certificates now
  include a `subjectAltName` (derived from the CN - an IP SAN for IP literals, a
  DNS SAN for names, always plus `DNS:localhost` and `IP:127.0.0.1`), since modern
  TLS clients ignore the CN. The signature digest is pinned to SHA-256 explicitly,
  and a new tunnel `--key-type` flag selects `rsa` (RSA-2048, default) or `ec`
  (prime256v1). Requires OpenSSL 1.1.1+ for the SAN extension.

### Added

- **`tunnel --key-type <rsa|ec>`**: choose the self-signed key algorithm.

---

## [2.4.0] - 2026-07-15

### Security

- **Stricter host validation (S-03)**: IPv6 validation previously checked only the
  character set, total length, and colon count, so malformed literals such as
  `12345::`, `1::2::3`, and `:::` were accepted. Validation now enforces IPv6
  structure - each group is 1-4 hex digits, at most one `::` compression, and the
  correct group count (8 without compression, fewer with). Hostnames are now
  additionally capped at the RFC-mandated 253-character maximum (labels remain
  capped at 63).

---

## [2.3.9] - 2026-07-15

### Security

- **`--socat-opts` now uses a keyword allowlist (S-02)**: validation previously
  only restricted the character set, which permitted any well-formed socat address
  option - including program-spawning options such as `exec`, `system`, and
  `shell`. Each comma-separated option is now checked against an allowlist of
  known-safe socat address options (socket tuning, bind/backlog, TLS material,
  privilege drop); unknown or dangerous keywords are rejected. The character
  filter is retained as a first pass.

---

## [2.3.8] - 2026-07-15

### Security

- **Hardened process launch against command-string re-parsing (S-01)**: socat was
  previously executed by interpolating the command string into `bash -c "... exec
  ${cmd} ..."`, which re-parses it through the shell. Whitelist validation made
  this safe in practice but left a fragile injection surface. Launch now tokenizes
  the command with a plain field split and passes the tokens as positional
  parameters to a fixed, non-interpolated launcher script that runs `exec "$@"`.
  Shell metacharacters (`;`, `$(...)`, backticks, quotes) and globs in any
  component are treated as literal arguments and never executed. The stored
  `SOCAT_CMD`, session display, and watchdog relaunch behavior are unchanged.

---

## [2.3.7] - 2026-07-15

### Fixed

- **Single-port ranges were rejected**: `validate_port_range` required
  `start < end`, so a degenerate range such as `8080-8080` (a valid way to
  express one port in batch mode) was refused. It now accepts `start == end`
  and yields that single port; only a genuinely inverted range (`start > end`)
  is rejected.

---

## [2.3.6] - 2026-07-15

### Fixed

- **`stop` removed the session file even when the process was not confirmed
  dead**: the tracking file was deleted unconditionally and the return code was
  always success, which orphaned any process that survived the stop sequence and
  hid the failure from callers. The session file (and its `.stop` signal) are now
  removed only when death is confirmed; otherwise the file is retained so the
  session stays visible and can be retried, and a non-zero status is returned.
  Callers already tallied stopped/failed by return code and now reflect reality.

---

## [2.3.5] - 2026-07-15

### Fixed

- **`forward --logfile` was silently ignored**: the flag assigned to an undeclared
  global that no code read, so a user-specified capture path had no effect (and it
  leaked a variable into the global scope under `set -u`). It now overrides the
  capture log path via the mode's declared `capture_logfile`, consistent with
  `redirect` and `tunnel`; the auto-generated path is used only when `--logfile`
  is absent.

---

## [2.3.4] - 2026-07-15

### Fixed

- **Encrypted tunnel remote leg was hardcoded to TCP4**: `build_socat_tunnel_cmd`
  always connected to the remote target over `TCP4`, so an IPv6 remote was
  unreachable and `--proto tcp6` was silently downgraded to TCP4 with a warning.
  The remote leg now selects its family (TCP4/TCP6): `--proto tcp6` is honored,
  and an IPv6 literal target is auto-routed over TCP6 (an IPv6 literal cannot be
  reached over TCP4). The OpenSSL listener side and UDP rejection are unchanged.

---

## [2.3.3] - 2026-07-15

### Fixed

- **IPv6 remote literals were not bracketed**: the forward, tunnel, and redirect
  builders concatenated `host:port` directly, so an IPv6 remote such as `fe80::1`
  produced the malformed `TCP6:fe80::1:443` that socat cannot parse. A new
  `format_socat_endpoint` helper brackets IPv6 literals (`TCP6:[fe80::1]:443`)
  while leaving hostnames and IPv4 addresses unchanged, and is now used by all
  three remote builders.

---

## [2.3.2] - 2026-07-15

### Fixed

- **`listen --capture` produced no capture file**: On the primary listener path,
  `mode_listen` declared `capture_logfile` but never assigned it, so `--capture`
  fell through to the session error log - no `0600` capture file was created and
  the displayed "Capture Log" was blank. The primary listener now creates its
  capture log (`capture-<proto>-<port>-<timestamp>.log`, mode `0600`) up front and
  wires it as the socat stderr target, matching forward/tunnel/redirect/batch and
  the dual-stack alternate that were already correct.

---

## [2.3.1] - 2026-07-15

### Fixed

- **Watchdog auto-restart now functions**: The `--watchdog` flag previously
  parsed, printed, and prompted everywhere but never started a supervisor - the
  restart loop had no caller and no session ran under supervision. Supervised
  sessions now spawn a detached supervisor (a hidden `__supervise` re-exec of the
  script, isolated with `setsid`) that owns the socat process, restarts it on
  crash with bounded exponential backoff (1s→60s) up to the configured limit, and
  honors the `.stop` signal for deliberate shutdown.
- **Stale PID after restart**: When a supervised socat is restarted, the session
  file's `PID` field is refreshed to the live process, so `status` and `stop`
  always act on the running instance instead of a dead PID from the prior crash.

### Changed

- Extracted a shared `_spawn_socat` launch primitive used by both the single-shot
  launcher and the supervisor, keeping launch semantics (PID-file handoff,
  liveness check, process-group isolation) identical on every path.
- Session files gain `WATCHDOG`, `WATCHDOG_MAX`, `WATCHDOG_INTERVAL`,
  `STDERR_LOG`, and `SUPERVISOR_PID` fields for supervised sessions; a supervised
  session records the supervisor as its process-group leader so a single group
  signal on `stop` tears down the supervisor and socat together.

---

### Added

- **`--capture` flag on all operational modes**: Traffic capture via socat's `-v` verbose hex dump is now available on `listen`, `batch`, `forward`, `tunnel`, and `redirect` modes (previously only `redirect`). Each mode routes socat stderr to a per-session, per-protocol capture log file through the `launch_socat_session` stderr redirect parameter.
- **`--proto` flag on tunnel mode**: Tunnel mode now accepts `--proto` for CLI consistency. TCP variants (`tcp`, `tcp4`) are accepted silently. `tcp6` produces a warning with TCP4 fallback. UDP variants (`udp`, `udp4`, `udp6`) produce a clear error message with explicit guidance to use `forward --proto udp4` instead.
- **`--logfile` flag on forward and tunnel modes**: Custom capture log file path can now be specified for forward and tunnel modes when `--capture` is enabled.
- **Capture parameter on all command builders**: `build_socat_listen_cmd`, `build_socat_forward_cmd`, `build_socat_tunnel_cmd`, and `build_socat_redirect_cmd` all accept a capture boolean parameter that controls inclusion of the socat `-v` flag.
- **Capture log isolation for dual-stack**: When `--capture` and `--dual-stack` are combined, each protocol gets its own independent capture log file (e.g., `capture-tcp4-8443-...log` and `capture-udp4-8443-...log`).

### Changed

- Updated help text for all modes to document `--capture` in OPTIONS sections with examples.
- Updated help text for tunnel mode to document `--proto` with TLS-aware validation behavior.
- Updated main help to list `--capture` as a global option available on all modes.
- Updated script header description to note universal `--capture` availability.
- Version bumped from 2.2.0 to 2.3.0.

### Fixed

- **Tunnel `--proto` rejection**: Previously, `./socat_manager.sh tunnel --port 4443 --rhost host --rport 22 --proto tcp4` returned `"Unknown tunnel option: --proto"` because the tunnel argument parser lacked a `--proto` case entry. Now handled with TLS-aware validation logic.

---

## [2.2.0] - 2026-03-20

### Added

- **`--proto` flag on redirect mode**: Redirect mode now accepts `--proto` for individual TCP or UDP protocol selection. Previously, redirect hardcoded TCP4 regardless of user intent.
- **Protocol-aware stop operations**: The `_stop_session` function now reads the `PROTOCOL` field from the session file and scopes all port checks, port-based fallback kills, and port-freed verification to the session's own protocol only.
- **Protocol-scoped `_kill_by_port`**: The last-resort port-based kill function now accepts a protocol parameter and uses protocol-specific `ss` flags (`-tlnp` for TCP, `-ulnp` for UDP) instead of querying both protocols. The `lsof` fallback also uses `-iTCP` or `-iUDP` flags.
- **Protocol-scoped `check_port_freed`**: Port-freed verification now accepts a protocol parameter and only checks the specified protocol.
- **Full function documentation restoration**: All functions restored to full multi-line documentation blocks with Description, Parameters, Returns, Outputs, and inline code comments explaining socat options, validation logic, process group mechanics, and the PID-file handoff architecture.
- **Inline code comment restoration**: Restored explanatory comments throughout the codebase including socat address options (`reuseaddr`, `fork`, `backlog`, `keepalive`), command builder logic, validation rationale, and process lifecycle mechanics.
- **Session file protocol field in session names**: Redirect mode session names now include the protocol for disambiguation (e.g., `redir-tcp4-8443-example.com-443` instead of `redir-8443-example.com-443`).

### Changed

- Updated help text for all modes with full DESCRIPTION sections, complete OPTIONS tables, and additional examples showing `--proto` and `--dual-stack` usage.
- Updated stop mode help to document protocol-aware stop behavior.
- Updated status detail view to show port status scoped to the session's protocol.
- Session file format version updated to v2.2.
- Version bumped from 2.1.0 to 2.2.0.

### Fixed

- **Cross-protocol kill on dual-stack stop** (critical): Stopping a TCP session on a shared port no longer kills the UDP session on the same port (and vice versa). Root cause was a three-step chain: (1) `_stop_session` checked `check_port_available` for both `tcp4` and `udp4` regardless of which session was being stopped; (2) `_kill_by_port` merged TCP and UDP PIDs into a single kill list; (3) `session_cleanup_dead` then swept the orphaned other-protocol session file. All three functions are now protocol-scoped.

---

## [2.1.0] - 2026-03-20

### Added

- **`--dual-stack` flag on all operational modes**: `listen`, `batch`, `forward`, `tunnel`, and `redirect` modes now support `--dual-stack` to launch both TCP and UDP sessions simultaneously on the same port. Each protocol receives its own independent Session ID for separate lifecycle management.
- **`get_alt_protocol` utility function**: Returns the alternate protocol for dual-stack operations (tcp4 to udp4, tcp6 to udp6, and vice versa).
- **Protocol-aware `build_socat_redirect_cmd`**: The redirect command builder now accepts a protocol parameter instead of hardcoding TCP4, enabling UDP redirectors.
- **Tunnel dual-stack advisory**: When `--dual-stack` is used with tunnel mode, a warning is logged that the UDP component is a plaintext forwarder (TLS is TCP-only).
- **PID-file handoff launch pattern**: Replaced the v2.0 `setsid cmd & ; $!` pattern with `setsid bash -c 'echo $$ > pidfile; exec socat ...'`. The inner bash writes its PID to a staging file before `exec` replaces it with socat (preserving the PID). The parent reads the real socat PID from this file.
- **`LAUNCH_SID` global variable**: Session IDs are now returned from `launch_socat_session` via a global variable instead of stdout, preventing `$()` subshell file descriptor inheritance.
- **`PID_FILE_WAIT_ITERS` constant**: Configurable timeout (default 20 iterations at 0.1s = 2 seconds) for waiting on the PID staging file.
- **Session error logs**: Non-capture mode stderr from socat processes is now captured to `logs/session-<SID>-error.log` for post-mortem debugging.

### Changed

- Stop grace period increased from 3 seconds to 5 seconds (`STOP_GRACE_SECONDS=5`).
- All mode functions updated to use `launch_socat_session` with the `LAUNCH_SID` global pattern instead of `$()` subshell capture.
- Version bumped from 2.0.0 to 2.1.0.

### Fixed

- **Terminal blocking on launch** (critical): Running `./socat_manager.sh redirect --lport 8443 ...` previously hung at "Starting Redirector" and required a second terminal for status/stop. Root cause: `sid="$(launch_socat_session ...)"` created a `$()` subshell that waited for all child processes holding its stdout file descriptor to close. The backgrounded socat process inherited this fd, keeping the pipe open indefinitely. Fixed by returning the session ID via `LAUNCH_SID` global variable and redirecting all socat stdout/stderr before `exec`.
- **Wrong PID tracked** (critical): The stored PID was the `setsid` wrapper process PID (which forks internally and exits immediately), not the actual socat PID. This caused SIGTERM during stop to target a dead process, falling through to SIGKILL every time. Fixed by the PID-file handoff pattern where socat's real PID (which equals its PGID under setsid) is captured from the staging file.
- **SIGTERM always falling through to SIGKILL**: Direct consequence of the wrong-PID bug. With the correct PID/PGID now stored, `kill -TERM -${PGID}` correctly targets the live socat process group, and graceful SIGTERM shutdown works as intended.

---

## [2.0.0] - 2026-03-20

### Added

- **Unique Session ID system**: Every launched socat process receives an 8-character hex Session ID generated from `/proc/sys/kernel/random/uuid` with collision checking against existing sessions.
- **Session file format (`.session`)**: Replaced v1.0 `.pid` files with full `.session` metadata files containing: SESSION_ID, SESSION_NAME, PID, PGID, MODE, PROTOCOL, LOCAL_PORT, REMOTE_HOST, REMOTE_PORT, SOCAT_CMD, STARTED, CORRELATION, LAUNCHER_PID.
- **Process group isolation via `setsid`**: All socat processes launched through `setsid` to create isolated process groups. PGID stored in session files for reliable tree kill.
- **`disown` after backgrounding**: Background processes disowned to prevent SIGHUP on script exit.
- **Multi-step stop sequence**: 9-step stop process: read metadata, signal watchdog, SIGTERM process group, SIGTERM PID and children, wait grace period, SIGKILL if alive, port-based fallback kill, verify port freed, remove session file.
- **`session_detail` function**: Detailed view for individual sessions showing all metadata, process tree (via `pstree`), port binding status, socat command string, and associated log files.
- **Flexible status command**: `status` accepts optional positional argument matched against Session ID (8-char hex), session name, or port number. Port lookups return multiple sessions for dual-stack.
- **Flexible stop command**: `stop` accepts positional Session ID as first argument, plus `--all`, `--name`, `--port`, `--pid` flags for alternative selectors.
- **`session_find_by_name`**: Search sessions by human-readable name.
- **`session_find_by_port`**: Search sessions by local port number.
- **`session_find_by_pid`**: Search sessions by PID.
- **`session_cleanup_dead`**: Remove session files for dead processes (both PID and PGID confirmed dead).
- **`_cleanup_orphaned_socat`**: Detect socat processes not tracked by any session file and report them (does not auto-kill to prevent collateral damage).
- **`_kill_by_port` fallback**: Last-resort kill of socat processes on a port via `ss`/`lsof`. Only targets processes with comm name `socat` (verified via `ps`).
- **`check_port_freed` verification**: Post-stop verification that the port has been released, with configurable retry count and interval.
- **`validate_session_id` function**: Input validation for session IDs (8 lowercase hex characters).
- **Session directory permissions**: `sessions/` set to 700, individual `.session` files set to 600.
- **`STOP_GRACE_SECONDS` constant**: Configurable grace period before SIGKILL (default 3 seconds).
- **`STOP_VERIFY_RETRIES` and `STOP_VERIFY_INTERVAL` constants**: Configurable post-stop port verification timing.
- **Backward compatibility migration**: Automatic detection and migration of v1.0 `.pid` session files to v2.0 `.session` format on startup. Dead legacy sessions are cleaned up automatically.
- **Status table with PGID column**: Session list table now includes PGID alongside PID.

### Changed

- Session tracking moved from `.pid` files keyed by session name to `.session` files keyed by Session ID.
- Stop command no longer uses `pgrep -P ${SCRIPT_PID}` (which only worked within the same script invocation). Now uses session file metadata for cross-invocation reliability.
- Status command enhanced from simple list to support both overview and detail views.
- Help text for status and stop modes updated with new Session ID-based usage patterns and examples.
- Version bumped from 1.0.0 to 2.0.0.

### Removed

- Direct `pgrep -P ${SCRIPT_PID}` usage for stop --all (replaced by session file enumeration).
- Reliance on script PID for process ownership tracking (replaced by PGID-based process group tracking).

---

## [1.0.0] - 2026-03-20

### Added

- **Initial release** of socat_manager.sh with six operational modes.
- **`listen` mode**: Start a single TCP or UDP listener on a specified port with unidirectional data capture to log file. Options: `--port`, `--proto`, `--bind`, `--name`, `--logfile`, `--watchdog`, `--socat-opts`.
- **`batch` mode**: Start multiple listeners from comma-separated port lists (`--ports`), port ranges (`--range`), or config files (`--config`). Supports `--dual-stack` for TCP+UDP per port.
- **`forward` mode**: Bidirectional port forwarding between local and remote endpoints. Options: `--lport`, `--rhost`, `--rport`, `--proto`, `--remote-proto` for cross-protocol forwarding.
- **`tunnel` mode**: Encrypted TLS/SSL tunnel via socat + OpenSSL. Auto-generates self-signed certificates if `--cert`/`--key` not provided. Options: `--port`, `--rhost`, `--rport`, `--cert`, `--key`, `--cn`.
- **`redirect` mode**: Transparent traffic redirection/proxy with optional traffic capture (`--capture`) via socat `-v` hex dump. Options: `--lport`, `--rhost`, `--rport`, `--capture`, `--logfile`.
- **`status` mode**: Display all active managed sessions in formatted table with PID, mode, protocol, port, remote target, and alive/dead status.
- **`stop` mode**: Stop sessions by `--name`, `--port`, `--pid`, or `--all`. Sends SIGTERM with grace period, then SIGKILL. Cleans up session files.
- **Session tracking via PID files**: Each session registered in `sessions/` directory via `.pid` files containing PID, MODE, PROTOCOL, LOCAL_PORT, REMOTE_HOST, REMOTE_PORT, STARTED, CORRELATION, MASTER_PID.
- **Watchdog auto-restart**: `--watchdog` flag enables background monitoring with exponential backoff (1s, 2s, 4s, 8s, 16s, 32s, 60s cap) and configurable max restarts (default 10). Graceful stop via `.stop` signal file.
- **Structured logging infrastructure**: Dual output (console + file). Master execution log per invocation. Per-session log files. Structured format: `TIMESTAMP [LEVEL] [corr:ID] [component] message`. Color-coded console output with severity symbols.
- **Input validation suite**: Whitelist-based validation for ports (1-65535), port ranges (max 1000 span), port lists, hostnames (IPv4, IPv6, RFC 1123), protocols (tcp4, tcp6, udp4, udp6), and file paths (path traversal and injection prevention).
- **Port conflict detection**: Pre-launch check via `ss` (preferred) or `netstat` fallback to detect port conflicts before binding.
- **Socat command builders**: Separated command construction (`build_socat_listen_cmd`, `build_socat_forward_cmd`, `build_socat_tunnel_cmd`, `build_socat_redirect_cmd`) from execution for testability and audit logging.
- **Self-signed certificate generation**: OpenSSL-based RSA 2048-bit certificate generation for tunnel mode with restrictive private key permissions (600).
- **Signal handling**: Trap handlers for INT, TERM, HUP signals with graceful child process cleanup.
- **Dependency checking**: Socat availability verification with per-distribution install guidance.
- **Colored terminal output**: Severity-coded output with Unicode symbols.
- **Correlation ID**: Per-execution correlation ID (first 8 chars of UUID) for log correlation across sessions.
- **Context-sensitive help system**: Per-mode help accessible via `-h`/`--help` with synopsis, options, and examples.
- **Banner display**: Styled ASCII box header showing mode, version, and correlation ID.
- **Script metadata**: Version string (`--version`), script directory resolution, execution timestamp.
- **Directory auto-creation**: `logs/`, `sessions/`, `conf/`, `certs/` directories created automatically on first run.

### Dependencies

- **Required**: socat, bash 4.4+, coreutils
- **Optional**: openssl (tunnel mode), iproute2/ss (status/stop verification), net-tools/netstat (fallback), lsof (fallback), psmisc/pstree (status detail)

---

## Version Comparison

| Capability | v1.0.0 | v2.0.0 | v2.1.0 | v2.2.0 | v2.3.0 |
|------------|--------|--------|--------|--------|--------|
| Session tracking | .pid files by name | .session files by SID | .session + PID-file handoff | .session + protocol field | .session + protocol field |
| Process isolation | Background `&` | setsid + disown | setsid + exec + PID-file | setsid + exec + PID-file | setsid + exec + PID-file |
| Stop reliability | pgrep by script PID | PGID-based tree kill | Correct PID/PGID via pidfile | Protocol-scoped stop | Protocol-scoped stop |
| Terminal blocking | Yes (hangs) | Yes (hangs) | Fixed (non-blocking) | Fixed | Fixed |
| Dual-stack | batch only | batch only | All modes | All modes | All modes |
| --proto on redirect | No (hardcoded TCP4) | No (hardcoded TCP4) | No (hardcoded TCP4) | Yes | Yes |
| --proto on tunnel | No | No | No | No | Yes (TCP-aware validation) |
| --capture | redirect only | redirect only | redirect only | redirect only | All modes |
| Protocol-aware stop | No | No | No | Yes | Yes |
| Cross-protocol kill bug | N/A | N/A | Present | Fixed | Fixed |
| Session detail view | No | Yes | Yes | Yes (protocol-scoped) | Yes |
| Documentation density | Full | Full | Reduced (bug) | Restored | Full |
