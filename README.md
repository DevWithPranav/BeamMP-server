# BeamMP Server on Ubuntu with Docker, Tailscale, and GitHub Actions

This repo is set up to run a private BeamMP server on an Ubuntu laptop, reachable over your Tailscale tailnet, and deployed from GitHub Actions.

## What this does

- Builds a Docker image with the official BeamMP Linux server binary.
- Runs Tailscale as a sidecar container.
- Runs BeamMP in the Tailscale network namespace so players connect over the Tailscale IPv4 address.
- Keeps secrets in GitHub Actions secrets instead of in Git.
- Deploys to your Ubuntu laptop over SSH whenever `main` changes.

## Architecture

- Old Ubuntu laptop: the actual host machine for the server.
- This repo: infrastructure, config, and deployment automation.
- GitHub Actions: pushes updates to the Ubuntu laptop.
- Tailscale: private network path so you do not need public port forwarding for friends already in your tailnet.

Important: BeamMP currently supports IPv4. Tailscale gives each device a tailnet IPv4 address, which is why this setup works for a private server.

## Local files

- `Dockerfile`: builds the BeamMP server image.
- `docker-compose.yml`: runs Tailscale and BeamMP together.
- `scripts/bootstrap-ubuntu.sh`: installs Docker, Docker Compose, and Tailscale on the Ubuntu host.
- `deploy/sync-and-run.sh`: what GitHub Actions runs remotely on the Ubuntu host.
- `.github/workflows/validate.yml`: verifies compose and image build.
- `.github/workflows/deploy.yml`: deploys to the Ubuntu laptop.

## First-time Ubuntu host setup

Run these steps on the Ubuntu laptop:

```bash
sudo bash scripts/bootstrap-ubuntu.sh
sudo tailscale up
```

Then:

1. Install Git if it is not already installed.
2. Enable SSH access on the Ubuntu laptop.
3. Make sure the laptop is online and signed into Tailscale.
4. Add the laptop's Tailscale IPv4 or MagicDNS name as `DEPLOY_HOST` in GitHub secrets.

If you want to test locally on the Ubuntu host before wiring GitHub Actions:

```bash
cp .env.example .env
docker compose up -d --build
docker compose logs -f beammp
```

## GitHub repo setup

Create a new GitHub repo, then from this folder:

```bash
git init
git add .
git commit -m "Initial BeamMP server infra"
git branch -M main
git remote add origin <your-github-repo-url>
git push -u origin main
```

## Required GitHub secrets

Set these in your GitHub repo settings:

- `DEPLOY_HOST`: Ubuntu laptop Tailscale IP or MagicDNS hostname.
- `DEPLOY_USER`: SSH username on the Ubuntu laptop.
- `DEPLOY_SSH_PRIVATE_KEY`: private key used by GitHub Actions to SSH into the Ubuntu laptop.
- `REPO_URL`: GitHub clone URL for this repo.
- `APP_DIR`: optional target path on the Ubuntu laptop, for example `/home/youruser/apps/beammp-server`.
- `TS_AUTHKEY`: Tailscale auth key for the containerized node.
- `TS_HOSTNAME`: Tailscale hostname for the server container.
- `BEAMMP_AUTH_KEY`: BeamMP Keymaster auth key. Optional only for private direct-connect use in this repo.
- `BEAMMP_NAME`
- `BEAMMP_DESCRIPTION`
- `BEAMMP_PRIVATE`
- `BEAMMP_PORT`
- `BEAMMP_MAP`
- `BEAMMP_MAX_PLAYERS`
- `BEAMMP_MAX_CARS`
- `BEAMMP_TAGS`
- `BEAMMP_ALLOW_GUESTS`
- `BEAMMP_LOG_CHAT`
- `BEAMMP_VERSION`
- `BEAMMP_ASSET`

Recommended values on September 5, 2026:

- `BEAMMP_VERSION`: `v3.9.3`
- `BEAMMP_ASSET`: `BeamMP-Server.ubuntu.24.04.x86_64`

## How players connect

For a private server:

1. Add your friends to your Tailscale tailnet, or use another arrangement where they can reach the tailnet node.
2. Start the server.
3. On the host, check the Tailscale IP:

```bash
docker compose exec tailscale tailscale ip -4
```

4. In BeamMP, use Direct Connect with that IPv4 address and port `30814` unless you changed it.

## Server data

Persistent data is stored in `beammp-data/`, including:

- `ServerConfig.toml`
- `Resources/Client`
- `Resources/Server`
- log files

Put client mods in `beammp-data/Resources/Client` and server Lua plugins in `beammp-data/Resources/Server`. These folders are gitignored (only `.gitkeep` is tracked) — copy mod files directly onto the host at that path instead of committing them, since mods can be hundreds of MB and would bloat the repo.

## Performance and resource limits

- `docker-compose.yml` sets memory limits (`beammp`: 1536M, `tailscale`: 256M) so a runaway process can't take down the whole laptop, plus soft CPU/memory reservations so `beammp` is prioritized over the sidecar under load. These are not tight caps — they're headroom guards, not throttles.
- Both services use the `json-file` logging driver with `max-size`/`max-file` limits, so container logs can't slowly fill the disk on a laptop that stays up for weeks.
- The image has a `HEALTHCHECK` that verifies the `BeamMP-Server` process is still running (`docker compose ps` will show `unhealthy` if it crashes without exiting the container).
- `scripts/bootstrap-ubuntu.sh` raises host-wide UDP/TCP socket buffer sizes and switches TCP to the BBR congestion control algorithm via `/etc/sysctl.d/99-beammp-net.conf`. The UDP buffer changes help gameplay sync avoid drops under load with several players; the TCP window (`tcp_rmem`/`tcp_wmem`) and BBR changes specifically help bulk transfer speed for mod/resource downloads when a player joins (see below). Re-run the bootstrap script (or `sysctl --system`) on an existing host to pick these up.

### Diagnosing lag / "not enough bandwidth"

BeamMP-Server itself has no tick-rate, thread-count, or bandwidth-limit setting to tune — `ServerConfig.toml` only controls things like map, player/car limits, and auth. If players are lagging or rubber-banding, the actual levers are:

1. **Check whether Tailscale is relaying instead of connecting directly:**
   ```bash
   docker compose exec tailscale tailscale status
   docker compose exec tailscale tailscale ping <player-tailscale-ip>
   ```
   `direct` means a peer-to-peer link at your real connection speed. `relay "<name>"` means traffic is bouncing through a DERP server, which is much lower throughput and higher latency. This usually happens because of NAT/CGNAT on one side. Forwarding UDP `41641` from your router to this host (and asking laggy players to do the same) is the usual remedy; carrier-grade NAT (common on mobile data) often can't be fixed at all and will always relay.
2. **The host's actual uplink speed** is the real ceiling — an old laptop on a slow or asymmetric home connection will bottleneck before any server setting does.
3. **`BEAMMP_MAX_PLAYERS`/`BEAMMP_MAX_CARS`** in `.env` control how much simulation state gets synced per tick; lowering `MaxCars` reduces per-player upload/download load if the connection is the bottleneck.

### Slow mod/resource downloads on join

This is a different bottleneck from gameplay lag. BeamMP-Server sends mods to a joining player with a plain `sendfile()` over TCP — there's no throttle or chunk-delay in the server itself, confirmed by reading `TNetwork.cpp` in the BeamMP-Server source. So a slow download always comes down to the network path, not a setting:

1. A player stuck on the Tailscale relay (see above) will have very slow downloads — relay bandwidth is shared and capped, and this is usually the biggest single cause.
2. The bootstrap script's `tcp_rmem`/`tcp_wmem`/BBR sysctls (above) give the TCP connection a bigger window and better throughput over the Tailscale tunnel, which specifically helps this kind of one-shot bulk transfer.
3. The server laptop's actual upload speed is still the hard ceiling — a large mod pack over a slow home upload will always take a while, and there's nothing to configure around that.

## Notes

- The entrypoint creates `ServerConfig.toml` on first boot if it does not already exist.
- If `BEAMMP_PRIVATE=true` and `BEAMMP_AUTH_KEY` is empty, the container uses a placeholder auth key so a private direct-connect server can still boot while Keymaster is unavailable.
- If you later want public listing, set `BEAMMP_PRIVATE=false`, add a real `BEAMMP_AUTH_KEY`, and redeploy.
- `BEAMMP_ALLOW_GUESTS` defaults to `true` here. BeamMP-Server checks every connecting player against its auth backend regardless of `Private`, and kicks anyone without a linked BeamMP forum account when `AllowGuests=false` — even on a direct-connect server. Keep it `true` unless you specifically want to require forum accounts.
- `BEAMMP_MAX_PLAYERS` defaults to `8`, which already covers a 5-player group with headroom; no change needed for that group size.
- Environment variables can still override config values supported by BeamMP.
- This is aimed at private hosting over Tailscale, not a public internet-facing server list setup.

## Source notes

This setup follows BeamMP's current Linux server guidance and release naming, and Tailscale's Docker-sidecar model as verified on August 24, 2026:

- BeamMP server setup docs: https://docs.beammp.com/server/create-a-server/
- BeamMP server manual: https://docs.beammp.com/server/manual/
- BeamMP releases: https://github.com/BeamMP/BeamMP-Server/releases
- Docker + Tailscale docs: https://tailscale.com/
