#!/usr/bin/env bash
set -euo pipefail

cd /srv/beammp

private_mode="${BEAMMP_PRIVATE:-true}"
auth_key="${BEAMMP_AUTH_KEY:-}"

if [[ -z "$auth_key" && "$private_mode" == "true" ]]; then
  auth_key="private-direct-connect-placeholder"
  echo "BEAMMP_AUTH_KEY not set; using a private-mode placeholder key for direct connect." >&2
elif [[ -z "$auth_key" ]]; then
  echo "BEAMMP_AUTH_KEY is required when BEAMMP_PRIVATE is false." >&2
  exit 1
fi

mkdir -p "${BEAMMP_RESOURCE_FOLDER:-Resources}"
mkdir -p "${BEAMMP_RESOURCE_FOLDER:-Resources}/Client"
mkdir -p "${BEAMMP_RESOURCE_FOLDER:-Resources}/Server"

if [[ ! -f ServerConfig.toml ]]; then
  cat > ServerConfig.toml <<EOF
[General]
Port = ${BEAMMP_PORT:-30814}
AuthKey = "${auth_key}"
Private = ${private_mode}
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

exec /usr/local/bin/BeamMP-Server
