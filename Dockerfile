FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive
ARG BEAMMP_VERSION=v3.9.3
ARG BEAMMP_ASSET=BeamMP-Server.ubuntu.24.04.x86_64

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl jq liblua5.3-0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt/beammp

RUN curl -fsSL -o /tmp/beammp-server \
      "https://github.com/BeamMP/BeamMP-Server/releases/download/${BEAMMP_VERSION}/${BEAMMP_ASSET}" \
    && chmod +x /tmp/beammp-server \
    && mv /tmp/beammp-server /usr/local/bin/BeamMP-Server

COPY scripts/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

WORKDIR /srv/beammp

EXPOSE 30814/tcp
EXPOSE 30814/udp

ENTRYPOINT ["/entrypoint.sh"]

