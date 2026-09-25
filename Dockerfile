# Download/verify stage: curl and jq are only needed to fetch and checksum
# the binary, so they live here and never ship in the runtime image.
FROM ubuntu:24.04 AS fetch

ARG DEBIAN_FRONTEND=noninteractive
ARG BEAMMP_VERSION=v3.9.3
ARG BEAMMP_ASSET=BeamMP-Server.ubuntu.24.04.x86_64

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

# Verify the downloaded binary's checksum against the digest GitHub's Releases
# API reports for this exact tag+asset, so a compromised mirror or a
# tampered-with download can't silently swap in a different binary.
RUN curl -fsSL -o /tmp/beammp-server \
      "https://github.com/BeamMP/BeamMP-Server/releases/download/${BEAMMP_VERSION}/${BEAMMP_ASSET}" \
    && expected_digest="$(curl -fsSL "https://api.github.com/repos/BeamMP/BeamMP-Server/releases/tags/${BEAMMP_VERSION}" \
         | jq -r --arg name "${BEAMMP_ASSET}" '.assets[] | select(.name == $name) | .digest' | sed 's/^sha256://')" \
    && if [ -z "$expected_digest" ]; then echo "Could not resolve expected digest for ${BEAMMP_ASSET}@${BEAMMP_VERSION} from GitHub API" >&2; exit 1; fi \
    && actual_digest="$(sha256sum /tmp/beammp-server | awk '{print $1}')" \
    && if [ "$expected_digest" != "$actual_digest" ]; then \
         echo "Checksum mismatch for ${BEAMMP_ASSET}@${BEAMMP_VERSION}: expected ${expected_digest}, got ${actual_digest}" >&2; \
         exit 1; \
       fi \
    && chmod +x /tmp/beammp-server \
    && mv /tmp/beammp-server /usr/local/bin/BeamMP-Server

FROM ubuntu:24.04

ARG DEBIAN_FRONTEND=noninteractive

# ca-certificates: BeamMP-Server talks HTTPS to the BeamMP backend.
# procps: pgrep/renice for the healthcheck and entrypoint.
RUN apt-get update     && apt-get install -y --no-install-recommends ca-certificates liblua5.3-0 procps bash     && rm -rf /var/lib/apt/lists/*

COPY --from=fetch /usr/local/bin/BeamMP-Server /usr/local/bin/BeamMP-Server
COPY scripts/entrypoint.sh /entrypoint.sh
COPY scripts/healthcheck.sh /healthcheck.sh

RUN chmod +x /entrypoint.sh /healthcheck.sh \
    && groupadd --system beammp \
    && useradd --system --gid beammp --home-dir /srv/beammp --shell /usr/sbin/nologin beammp

WORKDIR /srv/beammp
RUN chown beammp:beammp /srv/beammp

# Stays root at container start: the entrypoint fixes ownership of the
# bind-mounted /srv/beammp (which may already exist on the host owned by a
# different uid from a previous version of this image) before dropping to
# the unprivileged `beammp` user to actually run the server process.

EXPOSE 30814/tcp
EXPOSE 30814/udp

# Checks the process is alive AND actually accepting TCP connections on its
# configured port - a hung-but-still-running process would pass a bare
# `pgrep` check forever without this.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD /healthcheck.sh

ENTRYPOINT ["/entrypoint.sh"]

