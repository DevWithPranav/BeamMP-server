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
- `scripts/entrypoint.sh`: container entrypoint — generates `ServerConfig.toml` on first boot, fixes volume ownership, drops to an unprivileged user.
- `scripts/healthcheck.sh`: the image's `HEALTHCHECK` command.
- `scripts/backup.sh`: backs up `beammp-data/` (config, plugins, logs) with retention.
- `scripts/watch-events.sh`: optional Docker-events-to-Discord watcher, used by the `monitor` compose service.
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
- `DISCORD_WEBHOOK_URL`: optional, only used if you enable the `monitoring` compose profile (see below).

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

- `docker-compose.yml` sets memory limits (`beammp`: 4.5G, `tailscale`: 256M) and a CPU limit on `beammp` (3.5 of the host's 4 cores), plus soft CPU/memory reservations so `beammp` is prioritized over the sidecar under load. These are hard caps sized against this specific host (a 4-core/5.6GB laptop) to leave a sliver of headroom for the OS and the Tailscale sidecar — deliberately aggressive, so watch `docker stats` under real player load and pull them back down if the host itself starts lagging. If you move this to different hardware, resize both figures to match.
- `beammp` also has a `pids` limit (512) as a fork-bomb/runaway-process guard.
- Both services use the `json-file` logging driver with `max-size`/`max-file` limits, so container logs can't slowly fill the disk on a laptop that stays up for weeks.
- The image has a `HEALTHCHECK` that verifies the `BeamMP-Server` process is running **and** actually accepting TCP connections on `BEAMMP_PORT` (`scripts/healthcheck.sh`) — a hung-but-still-running process fails this even though a bare `pgrep` would pass forever. `docker compose ps` shows `unhealthy` when it fails. `tailscale` has its own healthcheck (`tailscale status --json`), and `beammp` won't start until that reports healthy (`depends_on: condition: service_healthy`), so BeamMP never comes up before the tunnel is actually usable.
- `scripts/bootstrap-ubuntu.sh` raises host-wide UDP/TCP socket buffer sizes and switches TCP to the BBR congestion control algorithm via `/etc/sysctl.d/99-beammp-net.conf`. The UDP buffer changes help gameplay sync avoid drops under load with several players; the TCP window (`tcp_rmem`/`tcp_wmem`) and BBR changes specifically help bulk transfer speed for mod/resource downloads when a player joins (see below). Re-run the bootstrap script (or `sysctl --system`) on an existing host to pick these up.

- **Scheduling priority**: the entrypoint renices `BeamMP-Server` to `BEAMMP_NICE` (default `-5`) and gives it best-effort IO priority while still root (via the `SYS_NICE` capability), so it wins CPU contention on a busy host. `oom_score_adj: -500` makes the kernel OOM-kill almost anything else first, `nofile` is raised to 65536, and `/tmp` is a 64MB tmpfs.
- **Slim image**: the Dockerfile is multi-stage; `curl`/`jq` are only used to download and verify the binary and are not in the runtime image.
- **Host tuning** (`scripts/bootstrap-ubuntu.sh`): socket buffers, BBR, TCP fast open, UDP GRO forwarding for Tailscale's WireGuard traffic (re-applied on every interface-up), and the `performance` CPU governor to avoid clock ramp-up jitter. Re-run the script on an existing host to apply these.

## ServerTools plugin

`beammp-data/Resources/Server/ServerTools/main.lua` is loaded automatically. Set `BEAMMP_ADMINS` to a comma-separated list of BeamMP account names (guests can never be admins).

- Everyone: `/help`, `/players`
- Admins: `/kick <name> [reason]`, `/ban <name> [reason]`, `/unban <name>`, `/say <message>`. Names can be partial if unambiguous. Bans persist in `ServerTools/bans.json`.
- `BEAMMP_WELCOME` is sent to each player on join.
- Every `BEAMMP_STATS_INTERVAL` seconds it logs `[stats] players=N vehicles=M`.

## Metrics

`docker compose --profile monitoring up -d` also starts `stats`, which samples CPU/RAM/network of both containers plus the player count every `STATS_SAMPLE_SECONDS`, appends to `metrics/stats.csv`, and posts an average/peak summary to `DISCORD_WEBHOOK_URL` every `STATS_REPORT_MINUTES`. Use the CSV to size the resource limits against real load.

## Security hardening

- **Checksum-verified binary**: the Dockerfile downloads the BeamMP-Server release binary, then looks up the expected SHA-256 digest for that exact version+asset from GitHub's Releases API and fails the build if it doesn't match. This protects against a tampered-with or corrupted download; it does not (and can't) verify BeamMP's own build supply chain.
- **Non-root process**: the container creates an unprivileged `beammp` system user. The entrypoint still starts as root just long enough to `chown` the bind-mounted `beammp-data/` (needed once, for hosts upgrading from an older image that ran as root), then switches to `beammp` via `setpriv --bounding-set=-all` before ever executing `BeamMP-Server`. That explicit bounding-set drop matters: a plain `runuser`/`setuid` switch does *not* reliably clear a process's capabilities when the container's own capability set has been added back to (as below) — verified by inspecting `/proc/<pid>/status` — so `setpriv` is what actually guarantees `BeamMP-Server` ends up with zero capabilities, confirmed by `CapEff: 0000000000000000` at runtime.
- **Minimal container privileges**: `beammp` runs with `cap_drop: ALL` plus a small `cap_add` (`CHOWN`, `FOWNER`, `DAC_OVERRIDE`, `SETUID`, `SETGID`, `SETPCAP`) that exists *only* for the root setup step above (fixing ownership and dropping to `beammp`) — `BeamMP-Server` itself never uses or retains any of them, per the `setpriv` bounding-set drop. `no-new-privileges:true` is also set. `tailscale` keeps `NET_ADMIN`/`SYS_MODULE` (required to manage the tun interface) and also sets `no-new-privileges:true`.
- **No public port exposure**: `beammp` runs with `network_mode: service:tailscale` and there is no `ports:` mapping anywhere in `docker-compose.yml` — the game port is only reachable over the Tailscale interface, never bound to the host's public network interfaces.
- **Graceful shutdown**: `stop_grace_period` is set (30s for `beammp`, 15s for `tailscale`) so `docker compose down`/`restart` give the server time to exit cleanly before Docker sends `SIGKILL`.

## Backups

`scripts/backup.sh` tars up the parts of `beammp-data/` that aren't easily replaceable — `ServerConfig.toml`, `Resources/Server` (Lua plugins), the dashboard, and logs — into `backups/beammp-backup-<timestamp>.tar.gz`, and prunes old archives (default: keep the last 14).

```bash
scripts/backup.sh                # excludes Resources/Client (mods/maps) by default
scripts/backup.sh --with-mods    # include mods/maps too (much bigger archive)
BACKUP_DIR=/mnt/nas/beammp RETAIN=30 scripts/backup.sh
```

`Resources/Client` is skipped by default since mod/map files can be large and are usually easy to re-obtain from wherever they came from; pass `--with-mods` if you'd rather have them in the backup too. Run it via cron for unattended daily backups, e.g. `0 4 * * * cd ~/apps/beammp-server && scripts/backup.sh >> backups/backup.log 2>&1`.

## Monitoring and alerts

An optional `monitor` service (in `docker-compose.yml`, under the `monitoring` profile so it's off by default) watches `docker events` for the `beammp` and `tailscale` containers and posts to a Discord webhook when either one starts, crashes/exits, or flips (un)healthy.

```bash
# .env: set DISCORD_WEBHOOK_URL=https://discord.com/api/webhooks/...
docker compose --profile monitoring up -d
```

This container is granted **read-only access to the Docker socket** so it can watch events — that's still a meaningful privilege (anyone who can reach it can inspect every container and image on the host), so only enable it if you're comfortable with that trade-off. If `DISCORD_WEBHOOK_URL` is unset it just logs events to its own container log instead of posting anywhere.

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
