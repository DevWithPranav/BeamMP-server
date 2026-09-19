#!/usr/bin/env bash
set -euo pipefail

port="${BEAMMP_PORT:-30814}"

pgrep -x BeamMP-Server >/dev/null || exit 1

# A hung process would still pass the pgrep check above forever, so also
# confirm the TCP listener is actually accepting connections.
timeout 3 bash -c "exec 3<>/dev/tcp/127.0.0.1/${port}" 2>/dev/null || exit 1
