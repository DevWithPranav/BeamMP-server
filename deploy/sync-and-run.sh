#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/apps/beammp-server}"
BRANCH="${BRANCH:-main}"

mkdir -p "$(dirname "$APP_DIR")"

if [[ ! -d "$APP_DIR/.git" ]]; then
  git clone --branch "$BRANCH" "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR"
git fetch origin "$BRANCH"
git checkout "$BRANCH"
git reset --hard "origin/$BRANCH"

cat > .env <<EOF
TS_AUTHKEY=${TS_AUTHKEY}
TS_HOSTNAME=${TS_HOSTNAME}
BEAMMP_AUTH_KEY=${BEAMMP_AUTH_KEY}
BEAMMP_NAME=${BEAMMP_NAME}
BEAMMP_DESCRIPTION=${BEAMMP_DESCRIPTION}
BEAMMP_PRIVATE=${BEAMMP_PRIVATE}
BEAMMP_PORT=${BEAMMP_PORT}
BEAMMP_MAP=${BEAMMP_MAP}
BEAMMP_MAX_PLAYERS=${BEAMMP_MAX_PLAYERS}
BEAMMP_MAX_CARS=${BEAMMP_MAX_CARS}
BEAMMP_TAGS=${BEAMMP_TAGS}
BEAMMP_ALLOW_GUESTS=${BEAMMP_ALLOW_GUESTS}
BEAMMP_LOG_CHAT=${BEAMMP_LOG_CHAT}
BEAMMP_VERSION=${BEAMMP_VERSION}
BEAMMP_ASSET=${BEAMMP_ASSET}
EOF

docker compose pull --ignore-pull-failures
docker compose up -d --build

