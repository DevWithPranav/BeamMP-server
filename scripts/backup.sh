#!/usr/bin/env bash
set -euo pipefail

# Backs up the parts of beammp-data that aren't easily replaceable:
# ServerConfig.toml, server-side Lua plugins, the dashboard, and logs.
# Resources/Client (vehicle mods/maps) is excluded by default since it's
# often hundreds of MB and can be re-copied from wherever the mods came
# from; pass --with-mods to include it anyway.
#
# Usage: scripts/backup.sh [--with-mods]
# Env:   BACKUP_DIR (default: ./backups), RETAIN (default: 14, backups kept)

cd "$(dirname "$0")/.."

data_dir="beammp-data"
backup_dir="${BACKUP_DIR:-backups}"
retain="${RETAIN:-14}"
with_mods=false

for arg in "$@"; do
  case "$arg" in
    --with-mods) with_mods=true ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

if [[ ! -d "$data_dir" ]]; then
  echo "No $data_dir directory found; nothing to back up." >&2
  exit 1
fi

mkdir -p "$backup_dir"
stamp="$(date +%Y%m%d-%H%M%S)"
archive="$backup_dir/beammp-backup-$stamp.tar.gz"

exclude_args=()
if [[ "$with_mods" == false ]]; then
  exclude_args+=(--exclude="$data_dir/Resources/Client")
fi

tar -czf "$archive" "${exclude_args[@]}" "$data_dir"
echo "Wrote $archive ($(du -h "$archive" | cut -f1))"

# Retention: keep the most recent $retain archives, delete the rest.
mapfile -t old_backups < <(ls -1t "$backup_dir"/beammp-backup-*.tar.gz 2>/dev/null | tail -n +$((retain + 1)))
if [[ ${#old_backups[@]} -gt 0 ]]; then
  rm -f "${old_backups[@]}"
  echo "Pruned ${#old_backups[@]} backup(s) older than the most recent $retain."
fi
