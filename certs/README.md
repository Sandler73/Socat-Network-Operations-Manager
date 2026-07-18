# certs/ - TLS certificates for tunnel mode

`tunnel` mode terminates TLS with socat's `OPENSSL-LISTEN` address, which needs a
certificate and a private key. This directory is where the tool writes the
certificates it generates, and a convenient place to keep your own.

## Automatic generation (default)

If you run `tunnel` without supplying a certificate, the tool generates a
self-signed pair automatically and uses it for that session:

```bash
socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22
```

Generated files are written here as:

- `socat-tunnel-<timestamp>.pem` - the X.509 certificate (mode 644)
- `socat-tunnel-<timestamp>.key` - the unencrypted private key (mode 600)

The certificate is signed with SHA-256, valid for 365 days, and carries a
`subjectAltName` built from the tunnel identity plus `DNS:localhost` and
`IP:127.0.0.1`, so a locally terminated tunnel validates without extra setup.
The key algorithm is RSA-2048 by default, or EC (prime256v1) with `--key-type`:

```bash
socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 --key-type ec
```

Self-signed certificates are not trusted by clients out of the box; a connecting
client must trust the certificate or disable verification on its side.

## Bringing your own certificate

Point `--cert` and `--key` at an existing PEM certificate and key:

```bash
socat_manager.sh tunnel --port 4443 --rhost 10.0.0.5 --rport 22 \
    --cert certs/mytunnel.pem --key certs/mytunnel.key
```

Both files must be PEM encoded. The private key must be unencrypted (no
passphrase), since the listener starts non-interactively. Keep the key readable
only by its owner:

```bash
chmod 600 certs/mytunnel.key
```

## Generating a pair manually

To produce a pair yourself with the same parameters the tool uses:

```bash
openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
    -keyout certs/mytunnel.key \
    -out    certs/mytunnel.pem \
    -days 365 \
    -subj "/CN=tunnel.example.com/O=socat_manager/OU=tunnel" \
    -addext "subjectAltName=DNS:tunnel.example.com,DNS:localhost,IP:127.0.0.1"
chmod 600 certs/mytunnel.key
```

For an EC key, swap the `-newkey` argument:

```bash
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes -sha256 \
    -keyout certs/mytunnel.key -out certs/mytunnel.pem -days 365 \
    -subj "/CN=tunnel.example.com/O=socat_manager/OU=tunnel" \
    -addext "subjectAltName=DNS:tunnel.example.com,DNS:localhost,IP:127.0.0.1"
```

Inspect a certificate at any time:

```bash
openssl x509 -in certs/mytunnel.pem -noout -text
```

## Files here

- `example-tunnel.pem.sample` - a sample self-signed **public** certificate
  (`CN=example.invalid`) showing the PEM format the tool produces. It is a
  demonstration only and ships without a private key, so it cannot be used for a
  real tunnel. Generate your own pair as shown above.

## Security notes

- Never commit real private keys to version control. `.key` files hold secret
  material; treat them like passwords.
- Private keys are written mode 600; keep it that way.
- Self-signed certificates are appropriate for testing and closed environments.
  For production, use certificates from a trusted CA.
