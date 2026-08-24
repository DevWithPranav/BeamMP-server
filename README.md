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
- `BEAMMP_AUTH_KEY`: BeamMP Keymaster auth key.
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

Recommended values on August 24, 2026:

- `BEAMMP_VERSION`: `v3.9.2`
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

Put client mods in `beammp-data/Resources/Client` and server Lua plugins in `beammp-data/Resources/Server`.

## Notes

- The entrypoint creates `ServerConfig.toml` on first boot if it does not already exist.
- Environment variables can still override config values supported by BeamMP.
- This is aimed at private hosting over Tailscale, not a public internet-facing server list setup.

## Source notes

This setup follows BeamMP's current Linux server guidance and release naming, and Tailscale's Docker-sidecar model as verified on August 24, 2026:

- BeamMP server setup docs: https://docs.beammp.com/server/create-a-server/
- BeamMP server manual: https://docs.beammp.com/server/manual/
- BeamMP releases: https://github.com/BeamMP/BeamMP-Server/releases
- Docker + Tailscale docs: https://tailscale.com/
