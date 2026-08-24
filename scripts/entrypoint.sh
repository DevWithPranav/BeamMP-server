#!/usr/bin/env bash
set -euo pipefail

cd /srv/beammp

mkdir -p "${BEAMMP_RESOURCE_FOLDER:-Resources}"
mkdir -p "${BEAMMP_RESOURCE_FOLDER:-Resources}/Client"
mkdir -p "${BEAMMP_RESOURCE_FOLDER:-Resources}/Server"

if [[ ! -f ServerConfig.toml ]]; then
  cat > ServerConfig.toml <<EOF
[General]
Port = ${BEAMMP_PORT:-30814}
AuthKey = "${BEAMMP_AUTH_KEY:-}"
Private = ${BEAMMP_PRIVATE:-true}
Name = "${BEAMMP_NAME:-Private BeamMP Server}"
Description = "${BEAMMP_DESCRIPTION:-BeamMP server over Tailscale}"
Map = "${BEAMMP_MAP:-/levels/gridmap_v2/info.json}"
MaxPlayers = ${BEAMMP_MAX_PLAYERS:-8}
MaxCars = ${BEAMMP_MAX_CARS:-2}
Tags = "${BEAMMP_TAGS:-Freeroam,Private}"
AllowGuests = ${BEAMMP_ALLOW_GUESTS:-false}
LogChat = ${BEAMMP_LOG_CHAT:-false}
ResourceFolder = "${BEAMMP_RESOURCE_FOLDER:-Resources}"
EOF
fi

if [[ -z "${BEAMMP_AUTH_KEY:-}" ]]; then
  echo "BEAMMP_AUTH_KEY is required." >&2
  exit 1
fi

exec /usr/local/bin/BeamMP-Server

