#!/bin/sh
set -eu

webhook="${DISCORD_WEBHOOK_URL:-}"
if [ -z "$webhook" ]; then
  echo "DISCORD_WEBHOOK_URL not set; monitor container will just log events locally." >&2
fi

notify() {
  msg="$1"
  echo "$msg"
  if [ -n "$webhook" ]; then
    payload=$(printf '{"content":"%s"}' "$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')")
    wget -q -O- --header="Content-Type: application/json" --post-data="$payload" "$webhook" >/dev/null 2>&1 || \
      echo "Failed to post to Discord webhook" >&2
  fi
}

notify "BeamMP monitor started, watching for container health changes and crashes."

# docker's --format Go-template avoids needing jq/curl (not present in the
# docker:*-cli image), and filtering in shell by container name substring
# covers any compose project name instead of hardcoding one.
docker events \
  --filter 'event=die' \
  --filter 'event=health_status' \
  --filter 'event=start' \
  --format '{{.Time}}|{{.Action}}|{{.Actor.Attributes.name}}' |
while IFS='|' read -r ts action name; do
  case "$name" in
    *beammp*|*tailscale*) ;;
    *) continue ;;
  esac
  case "$action" in
    die)
      notify "🔴 Container **$name** stopped/crashed (die event)." ;;
    start)
      notify "🟢 Container **$name** started." ;;
    health_status:\ unhealthy)
      notify "⚠️ Container **$name** is unhealthy." ;;
    health_status:\ healthy)
      notify "✅ Container **$name** is healthy again." ;;
  esac
done
