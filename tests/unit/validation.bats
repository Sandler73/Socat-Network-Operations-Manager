#!/usr/bin/env bats
#======================================================================
# TEST FILE  : tests/unit/validation.bats
#======================================================================
# Synopsis   : Unit tests for all input validation functions in
#              socat_manager.sh.
#
# Description: Tests the validate_port, validate_port_range,
#              validate_port_list, validate_hostname, validate_protocol,
#              validate_file_path, and validate_session_id functions.
#              Each function is tested for acceptance of valid inputs,
#              rejection of invalid inputs, and proper handling of
#              edge cases and injection attempts.
#
# Execution  : bats tests/unit/validation.bats
#
# Notes      : - Loads test_helper.bash for setup/teardown
#              - Each test runs in its own subshell (BATS default)
#              - No external dependencies (pure function tests)
#
# Version    : 1.0.0
#======================================================================

# =====================================================================
# SETUP / TEARDOWN
# =====================================================================

setup() {
    load '../helpers/test_helper'
    helper_setup
}

teardown() {
    helper_teardown
}

# =====================================================================
# validate_port
# =====================================================================

@test "validate_port: accepts valid port 8080" {
    run validate_port 8080
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts minimum valid port 1" {
    run validate_port 1
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts maximum valid port 65535" {
    run validate_port 65535
    [ "$status" -eq 0 ]
}

@test "validate_port: accepts mid-range port 443" {
    run validate_port 443
    [ "$status" -eq 0 ]
}

@test "validate_port: rejects port 0 (below range)" {
    run validate_port 0
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects port 65536 (above range)" {
    run validate_port 65536
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects port 99999 (far above range)" {
    run validate_port 99999
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects non-numeric string" {
    run validate_port "abc"
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects empty string" {
    run validate_port ""
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects negative number" {
    run validate_port "-1"
    [ "$status" -eq 1 ]
}

@test "validate_port: rejects port with injection characters" {
    run validate_port "80;ls"
    [ "$status" -eq 1 ]
}

# =====================================================================
# validate_port_range
# =====================================================================

@test "validate_port_range: accepts valid range 8000-8010" {
    run validate_port_range "8000-8010"
    [ "$status" -eq 0 ]
    # Should output 11 ports (8000 through 8010)
    local line_count
    line_count="$(echo "${output}" | wc -l)"
    [ "${line_count}" -eq 11 ]
}

@test "validate_port_range: accepts minimal range 8080-8081" {
    run validate_port_range "8080-8081"
    [ "$status" -eq 0 ]
    local line_count
    line_count="$(echo "${output}" | wc -l)"
    [ "${line_count}" -eq 2 ]
}

@test "validate_port_range: rejects start >= end (8010-8000)" {
    run validate_port_range "8010-8000"
    [ "$status" -eq 1 ]
}

@test "validate_port_range: rejects equal start and end (8080-8080)" {
    run validate_port_range "8080-8080"
    [ "$status" -eq 1 ]
}

@test "validate_port_range: rejects malformed format (no dash)" {
    run validate_port_range "8000"
    [ "$status" -eq 1 ]
}

@test "validate_port_range: rejects range exceeding 1000 ports" {
    run validate_port_range "1000-3000"
    [ "$status" -eq 1 ]
}

@test "validate_port_range: rejects range with invalid port" {
    run validate_port_range "0-100"
    [ "$status" -eq 1 ]
}

# =====================================================================
# validate_port_list
# =====================================================================

@test "validate_port_list: accepts valid comma-separated list" {
    run validate_port_list "21,22,80,443"
    [ "$status" -eq 0 ]
    local line_count
    line_count="$(echo "${output}" | grep -c '^[0-9]')"
    [ "${line_count}" -eq 4 ]
}

@test "validate_port_list: accepts single port" {
    run validate_port_list "8080"
    [ "$status" -eq 0 ]
}

@test "validate_port_list: handles semicolons (sanitizes to commas)" {
    run validate_port_list "8080;8443"
    [ "$status" -eq 0 ]
}

@test "validate_port_list: handles spaces (strips them)" {
    run validate_port_list "8080, 8443, 9090"
    [ "$status" -eq 0 ]
}

@test "validate_port_list: rejects entirely invalid list" {
    run validate_port_list "abc,def,ghi"
    [ "$status" -eq 1 ]
}

@test "validate_port_list: skips invalid entries but accepts valid ones" {
    run validate_port_list "8080,abc,8443"
    [ "$status" -eq 0 ]
    # Should output 2 valid ports
    local line_count
    line_count="$(echo "${output}" | grep -c '^[0-9]')"
    [ "${line_count}" -eq 2 ]
}

# =====================================================================
# validate_hostname
# =====================================================================

@test "validate_hostname: accepts valid IPv4 address" {
    run validate_hostname "192.168.1.10"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts loopback IPv4" {
    run validate_hostname "127.0.0.1"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts all-zeros IPv4" {
    run validate_hostname "0.0.0.0"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: rejects IPv4 with octet > 255" {
    run validate_hostname "192.168.1.256"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: accepts valid IPv6 address" {
    run validate_hostname "::1"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts full IPv6 address" {
    run validate_hostname "2001:0db8:85a3:0000:0000:8a2e:0370:7334"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts valid hostname" {
    run validate_hostname "example.com"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts hostname with hyphens" {
    run validate_hostname "my-host.internal.example.com"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: accepts single-label hostname" {
    run validate_hostname "localhost"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: rejects hostname with semicolon (injection)" {
    run validate_hostname "host;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects hostname with pipe (injection)" {
    run validate_hostname "host|cat /etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects hostname with backtick (injection)" {
    run validate_hostname 'host`id`'
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects hostname with dollar sign (injection)" {
    run validate_hostname 'host$(id)'
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects empty string" {
    run validate_hostname ""
    [ "$status" -eq 1 ]
}

# =====================================================================
# validate_protocol
# =====================================================================

@test "validate_protocol: normalizes 'tcp' to 'tcp4'" {
    run validate_protocol "tcp"
    [ "$status" -eq 0 ]
    [ "$output" = "tcp4" ]
}

@test "validate_protocol: accepts 'tcp4' unchanged" {
    run validate_protocol "tcp4"
    [ "$status" -eq 0 ]
    [ "$output" = "tcp4" ]
}

@test "validate_protocol: accepts 'tcp6'" {
    run validate_protocol "tcp6"
    [ "$status" -eq 0 ]
    [ "$output" = "tcp6" ]
}

@test "validate_protocol: normalizes 'udp' to 'udp4'" {
    run validate_protocol "udp"
    [ "$status" -eq 0 ]
    [ "$output" = "udp4" ]
}

@test "validate_protocol: accepts 'udp4' unchanged" {
    run validate_protocol "udp4"
    [ "$status" -eq 0 ]
    [ "$output" = "udp4" ]
}

@test "validate_protocol: accepts 'udp6'" {
    run validate_protocol "udp6"
    [ "$status" -eq 0 ]
    [ "$output" = "udp6" ]
}

@test "validate_protocol: normalizes uppercase 'TCP' to 'tcp4'" {
    run validate_protocol "TCP"
    [ "$status" -eq 0 ]
    [ "$output" = "tcp4" ]
}

@test "validate_protocol: rejects invalid protocol" {
    run validate_protocol "sctp"
    [ "$status" -eq 1 ]
}

@test "validate_protocol: rejects empty string" {
    run validate_protocol ""
    [ "$status" -eq 0 ]
    # Empty defaults to "tcp" which normalizes to "tcp4"
    [ "$output" = "tcp4" ]
}

# =====================================================================
# validate_file_path
# =====================================================================

@test "validate_file_path: accepts valid absolute path" {
    run validate_file_path "/var/log/socat.log"
    [ "$status" -eq 0 ]
}

@test "validate_file_path: accepts valid relative path" {
    run validate_file_path "logs/capture.log"
    [ "$status" -eq 0 ]
}

@test "validate_file_path: rejects path traversal (..)" {
    run validate_file_path "../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_file_path: rejects path with semicolon (injection)" {
    run validate_file_path "/tmp/file;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_file_path: rejects path with pipe (injection)" {
    run validate_file_path "/tmp/file|cat"
    [ "$status" -eq 1 ]
}

@test "validate_file_path: rejects path with backtick (injection)" {
    run validate_file_path '/tmp/file`id`'
    [ "$status" -eq 1 ]
}

@test "validate_file_path: rejects empty string" {
    run validate_file_path ""
    [ "$status" -eq 1 ]
}

# =====================================================================
# validate_session_id
# =====================================================================

@test "validate_session_id: accepts valid 8-char hex ID" {
    run validate_session_id "a1b2c3d4"
    [ "$status" -eq 0 ]
}

@test "validate_session_id: accepts all-lowercase hex" {
    run validate_session_id "deadbeef"
    [ "$status" -eq 0 ]
}

@test "validate_session_id: accepts all-numeric hex" {
    run validate_session_id "12345678"
    [ "$status" -eq 0 ]
}

@test "validate_session_id: rejects uppercase hex (must be lowercase)" {
    run validate_session_id "ABCD1234"
    [ "$status" -eq 1 ]
}

@test "validate_session_id: rejects too-short ID (7 chars)" {
    run validate_session_id "a1b2c3d"
    [ "$status" -eq 1 ]
}

@test "validate_session_id: rejects too-long ID (9 chars)" {
    run validate_session_id "a1b2c3d4e"
    [ "$status" -eq 1 ]
}

@test "validate_session_id: rejects non-hex characters" {
    run validate_session_id "a1b2g3h4"
    [ "$status" -eq 1 ]
}

@test "validate_session_id: rejects empty string" {
    run validate_session_id ""
    [ "$status" -eq 1 ]
}

# =====================================================================
# generate_session_id
# =====================================================================

@test "generate_session_id: produces 8-character hex string" {
    run generate_session_id
    [ "$status" -eq 0 ]
    # Output should be exactly 8 lowercase hex characters
    [[ "${output}" =~ ^[a-f0-9]{8}$ ]]
}

@test "generate_session_id: produces unique IDs on consecutive calls" {
    local id1 id2
    id1="$(generate_session_id)"
    id2="$(generate_session_id)"
    [ "${id1}" != "${id2}" ]
}

# =====================================================================
# get_alt_protocol
# =====================================================================

@test "get_alt_protocol: tcp4 returns udp4" {
    run get_alt_protocol "tcp4"
    [ "$output" = "udp4" ]
}

@test "get_alt_protocol: udp4 returns tcp4" {
    run get_alt_protocol "udp4"
    [ "$output" = "tcp4" ]
}

@test "get_alt_protocol: tcp6 returns udp6" {
    run get_alt_protocol "tcp6"
    [ "$output" = "udp6" ]
}

@test "get_alt_protocol: udp6 returns tcp6" {
    run get_alt_protocol "udp6"
    [ "$output" = "tcp6" ]
}

# =====================================================================
# validate_socat_opts (C-2 audit remediation)
# Whitelist: [a-zA-Z0-9=,.:/_-]
# =====================================================================

@test "validate_socat_opts: accepts valid socat options" {
    run validate_socat_opts "reuseaddr,fork,backlog=128"
    [ "$status" -eq 0 ]
}

@test "validate_socat_opts: accepts options with equals and dots" {
    run validate_socat_opts "bind=192.168.1.10,keepalive"
    [ "$status" -eq 0 ]
}

@test "validate_socat_opts: accepts options with colons and slashes" {
    run validate_socat_opts "cert=/path/to/cert.pem"
    [ "$status" -eq 0 ]
}

@test "validate_socat_opts: accepts options with hyphens and underscores" {
    run validate_socat_opts "tcp-keepidle=60,so_keepalive"
    [ "$status" -eq 0 ]
}

@test "validate_socat_opts: accepts empty string (no extra opts)" {
    run validate_socat_opts ""
    [ "$status" -eq 0 ]
}

@test "validate_socat_opts: rejects semicolon (command injection)" {
    run validate_socat_opts "reuseaddr;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_socat_opts: rejects pipe (command injection)" {
    run validate_socat_opts "fork|cat /etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_socat_opts: rejects backtick (command injection)" {
    run validate_socat_opts 'fork,`whoami`'
    [ "$status" -eq 1 ]
}

@test "validate_socat_opts: rejects dollar sign (variable expansion)" {
    run validate_socat_opts 'fork,$HOME'
    [ "$status" -eq 1 ]
}

@test "validate_socat_opts: rejects parentheses (subshell)" {
    run validate_socat_opts "fork,(echo pwned)"
    [ "$status" -eq 1 ]
}

@test "validate_socat_opts: rejects spaces" {
    run validate_socat_opts "fork reuseaddr"
    [ "$status" -eq 1 ]
}

@test "validate_socat_opts: rejects angle brackets (redirection)" {
    run validate_socat_opts "fork,>/tmp/evil"
    [ "$status" -eq 1 ]
}

# =====================================================================
# validate_session_name (C-4 audit remediation)
# Whitelist: [a-zA-Z0-9._-], max 64 characters
# =====================================================================

@test "validate_session_name: accepts alphanumeric name" {
    run validate_session_name "mylistener01"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: accepts name with hyphens" {
    run validate_session_name "listen-tcp4-8080"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: accepts name with underscores and dots" {
    run validate_session_name "web_server.prod"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: accepts maximum length name (64 chars)" {
    local name
    name="$(printf 'a%.0s' $(seq 1 64))"
    run validate_session_name "${name}"
    [ "$status" -eq 0 ]
}

@test "validate_session_name: rejects empty name" {
    run validate_session_name ""
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name exceeding 64 characters" {
    local name
    name="$(printf 'a%.0s' $(seq 1 65))"
    run validate_session_name "${name}"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with spaces" {
    run validate_session_name "my listener"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with semicolon (injection)" {
    run validate_session_name "test;rm -rf /"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with slash (path traversal)" {
    run validate_session_name "../../../etc/passwd"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with equals (session file corruption)" {
    run validate_session_name "name=injected"
    [ "$status" -eq 1 ]
}

@test "validate_session_name: rejects name with newline attempt" {
    run validate_session_name $'name\nPID=99999'
    [ "$status" -eq 1 ]
}

# =====================================================================
# Enhanced IPv6 validation (M-6 audit remediation)
# Added: length check (2-39), colon count (max 7)
# =====================================================================

@test "validate_hostname: accepts abbreviated IPv6" {
    run validate_hostname "fe80::1"
    [ "$status" -eq 0 ]
}

@test "validate_hostname: rejects IPv6 with too many colons (8+)" {
    run validate_hostname "1:2:3:4:5:6:7:8:9"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects IPv6 exceeding max length (40+ chars)" {
    run validate_hostname "2001:0db8:85a3:0000:0000:8a2e:0370:7334a"
    [ "$status" -eq 1 ]
}

@test "validate_hostname: rejects degenerate colons-only string" {
    run validate_hostname "::::::::"
    [ "$status" -eq 1 ]
}
