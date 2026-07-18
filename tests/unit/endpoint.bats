#!/usr/bin/env bats
#======================================================================
# TEST SUITE : endpoint.bats
#======================================================================
# Synopsis   : IPv6 endpoint bracketing for socat remote addresses.
#
# Description: socat requires IPv6 literal hosts in bracket form so the
#              address parser can separate host from port (TCP6:[fe80::1]:443).
#              The remote command builders previously concatenated
#              host:port directly, producing the malformed TCP6:fe80::1:443.
#              These tests cover the format_socat_endpoint helper and verify
#              every remote builder (forward, tunnel, redirect) brackets IPv6
#              literals while leaving hostnames and IPv4 untouched.
#
# Version    : 2.3.3
#======================================================================

load ../helpers/test_helper

setup() { helper_setup; }
teardown() { helper_teardown; }

# --- format_socat_endpoint --------------------------------------------

@test "format_socat_endpoint: brackets an IPv6 literal" {
    run format_socat_endpoint "TCP6" "fe80::1" "443"
    [ "$output" = "TCP6:[fe80::1]:443" ]
}

@test "format_socat_endpoint: leaves an IPv4 address unbracketed" {
    run format_socat_endpoint "TCP4" "10.0.0.1" "80"
    [ "$output" = "TCP4:10.0.0.1:80" ]
}

@test "format_socat_endpoint: leaves a hostname unbracketed" {
    run format_socat_endpoint "TCP4" "example.com" "443"
    [ "$output" = "TCP4:example.com:443" ]
}

@test "format_socat_endpoint: does not double-bracket an already-bracketed host" {
    run format_socat_endpoint "UDP6" "[2001:db8::5]" "53"
    [ "$output" = "UDP6:[2001:db8::5]:53" ]
}

# --- Remote builders bracket IPv6 -------------------------------------

@test "build_socat_forward_cmd: brackets IPv6 remote (F-04)" {
    run build_socat_forward_cmd "tcp6" "8080" "fe80::1" "443" "tcp6" "false"
    [[ "$output" == *"TCP6:[fe80::1]:443"* ]]
    [[ "$output" != *"TCP6:fe80::1:443"* ]]
}

@test "build_socat_redirect_cmd: brackets IPv6 remote (F-04)" {
    run build_socat_redirect_cmd "tcp6" "8080" "2001:db8::10" "9090" "false"
    [[ "$output" == *"TCP6:[2001:db8::10]:9090"* ]]
}

@test "build_socat_tunnel_cmd: brackets IPv6 remote (F-04)" {
    run build_socat_tunnel_cmd "4443" "2001:db8::20" "22" "/tmp/c.pem" "/tmp/k.pem" "false"
    [[ "$output" == *"[2001:db8::20]:22"* ]]
}

@test "build_socat_forward_cmd: IPv4 remote is unchanged" {
    run build_socat_forward_cmd "tcp4" "8080" "10.0.0.1" "443" "tcp4" "false"
    [[ "$output" == *"TCP4:10.0.0.1:443"* ]]
}

# --- F-05: tunnel remote leg family selection --------------------------

@test "build_socat_tunnel_cmd: default remote leg is TCP4" {
    run build_socat_tunnel_cmd "4443" "10.0.0.9" "22" "/tmp/c.pem" "/tmp/k.pem" "false"
    [[ "$output" == *"TCP4:10.0.0.9:22"* ]]
}

@test "build_socat_tunnel_cmd: tcp6 remote leg uses TCP6 and brackets literal (F-05)" {
    run build_socat_tunnel_cmd "4443" "2001:db8::7" "22" "/tmp/c.pem" "/tmp/k.pem" "false" "tcp6"
    [[ "$output" == *"TCP6:[2001:db8::7]:22"* ]]
    [[ "$output" != *"TCP4:"* ]]
}

@test "build_socat_tunnel_cmd: OpenSSL listener side is preserved" {
    run build_socat_tunnel_cmd "4443" "host.example" "22" "/tmp/c.pem" "/tmp/k.pem" "false" "tcp4"
    [[ "$output" == *"OPENSSL-LISTEN:4443,cert=/tmp/c.pem,key=/tmp/k.pem,verify=0,reuseaddr,fork"* ]]
}
