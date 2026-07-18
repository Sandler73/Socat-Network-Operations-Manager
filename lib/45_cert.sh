#======================================================================
# CERTIFICATE GENERATION
# Self-signed certificate generation for tunnel mode when no cert
# is provided. Uses OpenSSL to generate a temporary keypair.
#======================================================================

# Function: generate_self_signed_cert
# Description: Generate a self-signed certificate and key for TLS tunnels.
#              Files are placed in the certs/ directory with restrictive
#              permissions on the private key (600). The certificate carries a
#              subjectAltName (modern TLS clients ignore CN), is signed with
#              SHA-256 explicitly, and can use an RSA-2048 or an EC (prime256v1)
#              key. Requires OpenSSL 1.1.1+ for the -addext option.
# Parameters:
#   $1 - Common Name for the certificate (default: localhost)
#   $2 - Key type: "rsa" (default, RSA-2048) or "ec" (prime256v1)
# Outputs: Echoes "CERT_PATH KEY_PATH" space-separated
# Returns: 0 on success, 1 on failure
generate_self_signed_cert() {
    local cn="${1:-localhost}"
    local key_type="${2:-rsa}"
    local cert_file="${CERT_DIR}/socat-tunnel-${EXEC_TIMESTAMP}.pem"
    local key_file="${CERT_DIR}/socat-tunnel-${EXEC_TIMESTAMP}.key"

    if ! command -v openssl &>/dev/null; then
        log_error "openssl not found. Required for tunnel mode." "cert"
        log_info "Install with: sudo apt-get install -y openssl" "cert"
        return 1
    fi

    # Build the subjectAltName from the CN. An IP literal becomes an IP SAN, a
    # name becomes a DNS SAN; localhost identities are always included so a
    # locally terminated tunnel validates without extra configuration.
    local san
    if [[ "${cn}" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || [[ "${cn}" == *:* ]]; then
        san="IP:${cn}"
    else
        san="DNS:${cn}"
    fi
    san="${san},DNS:localhost,IP:127.0.0.1"

    # Select the key algorithm. EC (prime256v1) yields a smaller, faster key;
    # RSA-2048 remains the default for broad compatibility.
    local -a newkey_args
    if [[ "${key_type}" == "ec" ]]; then
        newkey_args=(-newkey ec -pkeyopt ec_paramgen_curve:prime256v1)
        log_info "Generating self-signed certificate (CN=${cn}, EC prime256v1)..." "cert"
    else
        newkey_args=(-newkey rsa:2048)
        log_info "Generating self-signed certificate (CN=${cn}, RSA 2048)..." "cert"
    fi

    # -x509 self-signed cert, -nodes no key passphrase, -sha256 explicit digest,
    # -subj non-interactive subject, -addext carries the subjectAltName.
    if openssl req -x509 "${newkey_args[@]}" -nodes -sha256 \
        -keyout "${key_file}" \
        -out "${cert_file}" \
        -days 365 \
        -subj "/CN=${cn}/O=socat_manager/OU=tunnel" \
        -addext "subjectAltName=${san}" \
        2>/dev/null; then

        # Restrict permissions on key file (private key protection)
        chmod 600 "${key_file}" 2>/dev/null
        chmod 644 "${cert_file}" 2>/dev/null

        log_success "Certificate generated: ${cert_file}" "cert"
        log_debug "Key generated: ${key_file}" "cert"

        echo "${cert_file} ${key_file}"
        return 0
    else
        log_error "Certificate generation failed" "cert"
        return 1
    fi
}

