# conf/ - Batch configuration files

This directory holds batch configuration files: plain-text lists of ports for
`batch` mode. It is also the default location the tool resolves for its own
runtime configuration data. Files you place here are yours to keep; the tool
does not overwrite them.

## What a config file is

A batch config file is a newline-delimited list of ports. It is consumed with:

```bash
socat_manager.sh batch --config conf/example-ports.conf
```

The parser applies these rules:

- One port per line.
- A `#` begins a comment; the rest of the line is ignored. Inline comments after
  a port are supported (for example `8080   # HTTP alternate`).
- Blank lines and surrounding whitespace are ignored.
- Each entry is a single port, `1-65535`. Ports below `1024` are privileged and
  require root/sudo to bind.
- Port ranges are not written in the file; pass them with `--range` instead
  (for example `batch --range 8000-8010`).
- Duplicate ports are removed automatically, keeping the first occurrence.

## Combining with command-line options

The file lists only ports. Protocol and behavior come from the command line and
apply to every port in the file:

```bash
# TCP + UDP on every listed port, with a readable traffic capture
socat_manager.sh batch --config conf/example-ports.conf --dual-stack --capture

# UDP only, restarting on crash, restricted to one source network
socat_manager.sh batch --config conf/example-ports.conf \
    --proto udp4 --watchdog --allow 10.0.0.0/24
```

## Files here

- `example-ports.conf` - an annotated example you can copy and edit.

Create as many config files as you need (for example `web.conf`, `staging.conf`)
and select one per invocation with `--config`.
