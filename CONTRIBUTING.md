# Contributing to Socat Network Operations Manager (Python Variant)

Thank you for your interest in contributing. This document provides everything
you need to set up a development environment, run tests, follow coding
standards, and submit changes.

---

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
  - [Development Prerequisites](#development-prerequisites)
  - [Setting Up the Development Environment](#setting-up-the-development-environment)
  - [Project Structure](#project-structure)
- [Running Tests](#running-tests)
  - [Full Test Suite](#full-test-suite)
  - [Unit Tests Only](#unit-tests-only)
  - [Integration Tests Only](#integration-tests-only)
  - [Running Specific Tests](#running-specific-tests)
  - [Linting](#linting)
  - [Coverage](#coverage)
- [Writing Tests](#writing-tests)
  - [Test Architecture](#test-architecture)
  - [Test Fixtures](#test-fixtures)
  - [Adding Unit Tests](#adding-unit-tests)
  - [Adding Integration Tests](#adding-integration-tests)
  - [Mocking Patterns](#mocking-patterns)
- [Coding Standards](#coding-standards)
  - [Module Structure](#module-structure)
  - [Function Documentation](#function-documentation)
  - [Type Hints](#type-hints)
  - [Input Validation](#input-validation)
  - [Error Handling](#error-handling)
  - [Security Requirements](#security-requirements)
  - [CLI Flag Checklist](#cli-flag-checklist)
- [Submitting Changes](#submitting-changes)
  - [Branch Naming](#branch-naming)
  - [Commit Messages](#commit-messages)
  - [Pull Request Process](#pull-request-process)
  - [Code Review Checklist](#code-review-checklist)
- [Reporting Bugs](#reporting-bugs)
- [Security Vulnerabilities](#security-vulnerabilities)

---

## Code of Conduct

This project follows the [Contributor Covenant Code of Conduct](CODE_OF_CONDUCT.md).
By participating, you are expected to uphold this code. This includes the
**Responsible Use** section — all contributions must be consistent with
authorized, lawful use of security tooling.

---

## Getting Started

### Development Prerequisites

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| **Python** | 3.12+ | Runtime and development | `sudo apt-get install python3` |
| **socat** | any | Runtime dependency (optional for tests) | `sudo apt-get install -y socat` |
| **pytest** | 9.0+ | Test framework | `pip install pytest` |
| **pytest-cov** | 7.0+ | Coverage reporting | `pip install pytest-cov` |
| **ruff** | 0.15+ | Linting and import sorting | `pip install ruff` |
| **GNU Make** | 3.81+ | Build automation | Pre-installed on most Linux |
| **Git** | 2.0+ | Version control | `sudo apt-get install -y git` |

**Verify all prerequisites at once:**

```bash
make check-deps
```

### Setting Up the Development Environment

**Option 1: Virtual environment (recommended)**

```bash
git clone https://github.com/Sandler73/Socat-Network-Operations-Manager.git
cd Socat-Network-Operations-Manager
make venv
source socat-manager-venv/bin/activate
make test
```

**Option 2: System Python**

```bash
git clone https://github.com/Sandler73/Socat-Network-Operations-Manager.git
cd Socat-Network-Operations-Manager
pip install --break-system-packages -e .
pip install --break-system-packages pytest pytest-cov ruff
make test
```

**Option 3: Standalone (no install)**

```bash
git clone https://github.com/Sandler73/Socat-Network-Operations-Manager.git
cd Socat-Network-Operations-Manager
pip install --break-system-packages pytest pytest-cov ruff
PYTHONPATH=src python3 -m pytest tests/ -q
```

### Project Structure

```
src/socat_manager/          # Production source (19 files, 6,779 lines)
├── __init__.py             # Package version
├── __main__.py             # Entry point, signal handlers, dispatch
├── config.py               # Constants, frozen dataclasses, protocol maps
├── logging_setup.py        # Structured dual-output logging
├── validation.py           # 9 whitelist validators (trust boundary)
├── session.py              # Session CRUD, locking, migration
├── commands.py             # 4 socat command builders
├── process.py              # Launch (setsid), 9-step stop, port checks
├── watchdog.py             # Monitor-first auto-restart
├── certs.py                # TLS certificate generation
├── cli.py                  # argparse (10 subcommands)
├── menu.py                 # Interactive TUI
└── modes/                  # 7 mode handlers
    ├── listen.py, batch.py, forward.py
    ├── tunnel.py, redirect.py
    ├── status.py, stop.py

tests/                       # Test suite (510 tests)
├── conftest.py             # Shared fixtures
├── unit/                   # 355 unit tests (12 files)
├── integration/            # 155 integration tests (6 files)
└── stubs/                  # Mock socat, ss, openssl binaries
```

---

## Running Tests

### Full Test Suite

```bash
make test        # Runs: lint → unit tests → integration tests
```

### Unit Tests Only

```bash
make test-unit   # Fast, ~3 seconds, no I/O
```

### Integration Tests Only

```bash
make test-integration
```

### Running Specific Tests

```bash
# By file:
PYTHONPATH=src python3 -m pytest tests/unit/test_validation.py -v

# By class:
PYTHONPATH=src python3 -m pytest tests/unit/test_session.py::TestSessionReadAllFields -v

# By name pattern:
PYTHONPATH=src python3 -m pytest tests/ -k "test_dual_stack" -v
```

### Linting

```bash
make lint
# Equivalent to: ruff check src/ tests/ --select E,W,F,I --ignore E501
```

Ruff rules enforced: E (errors), W (warnings), F (pyflakes), I (import sorting). Line length 120 (E501 ignored for readability).

### Coverage

```bash
make test-coverage
# Runs pytest with --cov=socat_manager --cov-report=term-missing
```

Current threshold: 68% minimum. Core modules (commands, validation, cli, config) are at 85-100%.

---

## Writing Tests

### Test Architecture

| Directory | Tests | Focus | Speed |
|-----------|-------|-------|-------|
| `tests/unit/` | 355 | Individual functions, validators, parsers | Fast (~3s) |
| `tests/integration/` | 155 | Cross-module behavior, session lifecycle | Medium (~6s) |

Unit tests mock all subprocess calls and filesystem operations. Integration tests use the `paths` fixture for isolated temporary directories.

### Test Fixtures

The shared fixtures in `conftest.py`:

- **`paths`**: Creates an isolated temporary base directory with `sessions/`, `logs/`, `certs/`, `conf/` subdirectories. Automatically cleaned up after each test. All tests that touch the filesystem should use this fixture.
- **`sample_session`**: Registers a sample redirect session (PID 99999, port 8443, tcp4, remote example.com:443). Returns the session ID.
- **`dual_stack_sessions`**: Registers TCP + UDP sessions on port 8080. Returns `(tcp_sid, udp_sid)` tuple.

### Adding Unit Tests

1. Create or edit `tests/unit/test_<module>.py`
2. Import the function under test
3. Use `paths` fixture if the function touches the filesystem
4. Mock `subprocess.Popen` for launch tests, `os.kill` for stop tests
5. `launch_socat_session()` returns `(sid, pid)` tuple — unpack in assertions

```python
class TestMyFunction:
    def test_basic_behavior(self, paths):
        result = my_function(valid_input)
        assert result == expected_output

    def test_invalid_input_raises(self, paths):
        with pytest.raises(ValidationError):
            my_function(invalid_input)
```

### Adding Integration Tests

1. Create or edit `tests/integration/test_<feature>.py`
2. Use `sample_session` or `dual_stack_sessions` fixtures for session-dependent tests
3. Mock `subprocess.Popen` and `os.kill` for process-dependent tests
4. Mock `subprocess.run` when testing stop_session() (pkill calls)

### Mocking Patterns

**Launch tests** — mock Popen to return a controlled PID:

```python
@patch("socat_manager.process.os.kill")
@patch("socat_manager.process.subprocess.Popen")
def test_launch(self, mock_popen, mock_kill, paths):
    mock_proc = MagicMock()
    mock_proc.pid = 54321
    mock_popen.return_value = mock_proc
    mock_kill.return_value = None

    sid, pid = launch_socat_session("test", "listen", "tcp4", 8080, cmd)
    assert pid == 54321
```

**Stop tests** — mock os.kill to simulate dead process:

```python
@patch("socat_manager.process.subprocess.run")
@patch("socat_manager.process.os.kill", side_effect=OSError)
def test_stop(self, mock_kill, mock_run, sample_session, paths):
    mock_run.return_value = MagicMock(returncode=0, stdout="")
    result = stop_session(sample_session)
    assert result is True
```

**Mode handler tests** — mock at the mode module level:

```python
@patch("socat_manager.modes.listen.launch_socat_session", return_value=("abcd1234", 54321))
@patch("socat_manager.modes.listen.check_port_available", return_value=True)
def test_mode_listen(self, mock_port, mock_launch, paths):
    mode_listen(args)
    mock_launch.assert_called_once()
```

---

## Coding Standards

### Module Structure

Every module follows this order:

```python
# 1. Module header (synopsis, description, version)
# 2. from __future__ import annotations
# 3. Standard library imports
# 4. Internal imports
# 5. Constants
# 6. Classes
# 7. Functions (ordered by dependency — called functions before callers)
```

### Function Documentation

All public functions require Google-style docstrings:

```python
def my_function(port: int, proto: str = "tcp4") -> tuple[str, int]:
    """Brief description of what this function does.

    Longer description explaining behavior, design rationale, and
    any non-obvious logic. Include security annotations if the
    function handles user input or subprocess calls.

    Args:
        port: Port number (must be 1-65535, validated before call).
        proto: Protocol string (default: tcp4).

    Returns:
        Tuple of (session_id, pid) where session_id is the 8-char
        hex string and pid is the socat process PID.

    Raises:
        RuntimeError: If launch fails (port busy, socat not found).
        ValidationError: If inputs fail validation.
    """
```

### Type Hints

All function signatures must have complete type hints:

```python
def session_find_by_port(target_port: int | str) -> list[str]:
def launch_socat_session(name: str, mode: str, ...) -> tuple[str, int]:
def validate_hostname(host: str) -> str:
```

### Input Validation

All user-controlled strings must pass through a whitelist validator before reaching any command builder, file operation, or subprocess call. The validators are in `validation.py`:

- `validate_port()` for port numbers
- `validate_hostname()` for hosts/IPs
- `validate_protocol()` for protocol strings
- `validate_socat_opts()` for extra socat options
- `validate_session_name()` for session names
- `validate_file_path()` for file paths

### Error Handling

- `ValidationError` for all input validation failures
- `RuntimeError` for launch/stop failures
- `OSError` for filesystem and signal failures — catch and log, never propagate to crash
- `SystemExit` caught by menu to prevent mode handler exits from killing interactive session
- `KeyboardInterrupt` caught by menu for graceful return

### Security Requirements

These are **non-negotiable** for any contribution:

- **No `shell=True`** on any subprocess call — argument lists only
- **No `eval()`, `exec()`, `compile()`** on any data
- **No `os.system()` or `os.popen()`** — use subprocess with argument lists
- All user input through whitelist validators before subprocess
- All file creation with explicit permission modes (0o600 for files, 0o700 for directories)

### CLI Flag Checklist

When adding a new CLI flag:

1. Add to the relevant subparser(s) in `cli.py`
2. Extract from `args` in the mode handler(s)
3. Validate the value through an appropriate validator
4. Pass through to the relevant core function
5. Add to the help epilog examples
6. Add to the menu prompt flow (if interactive)
7. Add unit tests for the CLI parser
8. Add integration tests for the mode handler
9. Update documentation (USAGE_GUIDE, wiki Usage-Guide, CHANGELOG)

---

## Submitting Changes

### Branch Naming

```
feature/my-new-feature
fix/watchdog-crash-loop
docs/update-usage-guide
security/validate-cn-parameter
```

### Commit Messages

```
<type>: <description>

Types: feat, fix, refactor, docs, test, chore, security
Examples:
  feat: add IPv6-only listener support
  fix: watchdog crash loop on duplicate port binding
  security: add whitelist validation on tunnel CN parameter
  docs: expand USAGE_GUIDE with operational scenarios
  test: add dual-stack stop isolation tests
```

### Pull Request Process

1. Fork the repository
2. Create a feature branch from `main`
3. Make your changes with tests
4. Run `make test` — all 510 tests must pass, 0 lint errors
5. Update documentation and CHANGELOG
6. Push to your fork
7. Open a Pull Request with:
   - Clear description of the change
   - Motivation and context
   - Testing performed
   - Screenshots/output if applicable

### Code Review Checklist

Before requesting review, verify:

- [ ] All tests pass (`make test`)
- [ ] Zero lint errors (`make lint`)
- [ ] Type hints on all new functions
- [ ] Google-style docstrings on all public functions
- [ ] No `eval()`, `exec()`, or `shell=True`
- [ ] All user input validated through whitelist validators
- [ ] File permissions explicitly set (0o600/0o700)
- [ ] Documentation updated (USAGE_GUIDE, wiki, CHANGELOG)
- [ ] New CLI flags follow the CLI Flag Checklist above

---

## Reporting Bugs

1. Check [existing issues](https://github.com/Sandler73/Socat-Network-Operations-Manager/issues) first
2. Open a new issue with:
   - Python version (`python3 --version`)
   - Operating system and version
   - socat version (`socat -V | head -2`)
   - Exact command run
   - Full error output (stderr)
   - Steps to reproduce
   - Expected vs actual behavior

---

## Security Vulnerabilities

**Do NOT** open public GitHub issues for security vulnerabilities.

Report security issues privately per the [Security Policy](SECURITY.md):
1. Use GitHub Security Advisory
2. Or contact the maintainer directly

Include: affected version, component, description, reproduction steps, and impact assessment.
