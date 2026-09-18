#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo."
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl git gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc

. /etc/os-release
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  ${VERSION_CODENAME} stable" > /etc/apt/sources.list.d/docker.list

curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.noarmor.gpg -o /usr/share/keyrings/tailscale-archive-keyring.gpg
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/${VERSION_CODENAME}.tailscale-keyring.list -o /etc/apt/sources.list.d/tailscale.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin tailscale

systemctl enable --now docker
systemctl enable --now tailscaled

# Bigger UDP/TCP socket buffers help WireGuard (Tailscale) and BeamMP's
# UDP traffic avoid drops/retransmits under load with multiple players.
# tcp_rmem/wmem and BBR specifically target bulk TCP transfers (mod/resource
# downloads when a player joins), which BeamMP-Server sends via a plain
# sendfile() over TCP with no throttle of its own - the tunnel's window
# size and congestion control are what actually cap that throughput.
# These are host-wide sysctls; Docker won't let a container set them itself
# because net.core.*/net.ipv4.tcp_* isn't namespaced, so they have to be
# applied here.
cat > /etc/sysctl.d/99-beammp-net.conf <<'EOF'
net.core.rmem_max = 8388608
net.core.wmem_max = 8388608
net.core.rmem_default = 1048576
net.core.wmem_default = 1048576
net.core.netdev_max_backlog = 4096
net.ipv4.tcp_rmem = 4096 1048576 8388608
net.ipv4.tcp_wmem = 4096 1048576 8388608
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
EOF
modprobe tcp_bbr 2>/dev/null || true
sysctl --system

echo "Bootstrap complete. Next: run 'tailscale up', clone the repo, create .env, and start 'docker compose up -d --build'."
echo "If players report lag, check whether Tailscale is relaying instead of connecting directly:"
echo "  docker compose exec tailscale tailscale status"
echo "  docker compose exec tailscale tailscale ping <player-tailscale-ip>"
echo "A 'relay \"...\"' result instead of 'direct' means traffic is bouncing through a DERP server,"
echo "which caps throughput well below a direct link. Forwarding UDP 41641 from your router to this"
echo "host (and disabling any CGNAT on your ISP connection) is usually what fixes that."

