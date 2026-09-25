#!/bin/sh
set -eu

# Samples resource usage of the beammp/tailscale containers plus the player
# count logged by the ServerTools plugin, appends it to /metrics/stats.csv,
# and every STATS_REPORT_MINUTES posts a summary to Discord (if configured).

webhook="${DISCORD_WEBHOOK_URL:-}"
sample="${STATS_SAMPLE_SECONDS:-60}"
report_every=$(( ${STATS_REPORT_MINUTES:-60} * 60 ))
csv=/metrics/stats.csv

mkdir -p /metrics
[ -f "$csv" ] || echo "epoch,service,cpu_pct,mem_used,mem_pct,net_io,players,vehicles" > "$csv"

post() {
  echo "$1"
  [ -n "$webhook" ] || return 0
  payload=$(printf '{"content":"%s"}' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s\\n", $0}')")
  wget -q -O- --header="Content-Type: application/json" --post-data="$payload" "$webhook" >/dev/null 2>&1 || \
    echo "Failed to post to Discord webhook" >&2
}

cid() {
  docker ps -q --filter "label=com.docker.compose.service=$1" | head -n1
}

last_report=$(date +%s)

while :; do
  now=$(date +%s)
  players=""; vehicles=""
  beammp=$(cid beammp)
  if [ -n "$beammp" ]; then
    # ServerTools prints e.g. "[stats] players=3 vehicles=5" every interval.
    line=$(docker logs --since "$(( sample * 3 ))s" "$beammp" 2>&1 | grep -o 'players=[0-9]* vehicles=[0-9]*' | tail -n1 || true)
    players=$(echo "$line" | sed -n 's/.*players=\([0-9]*\).*/\1/p')
    vehicles=$(echo "$line" | sed -n 's/.*vehicles=\([0-9]*\).*/\1/p')
  fi

  for svc in beammp tailscale; do
    id=$(cid "$svc")
    [ -n "$id" ] || continue
    docker stats --no-stream --format '{{.CPUPerc}}|{{.MemUsage}}|{{.MemPerc}}|{{.NetIO}}' "$id" |
    while IFS='|' read -r cpu mem memp net; do
      p=""; v=""
      [ "$svc" = beammp ] && { p="$players"; v="$vehicles"; }
      echo "$now,$svc,${cpu%\%},${mem%% /*},${memp%\%},\"$net\",$p,$v" >> "$csv"
    done
  done

  if [ $(( now - last_report )) -ge "$report_every" ]; then
    summary=$(awk -F, -v since="$last_report" '
      $1 >= since && $2 == "beammp" {
        n++; cpu += $3; if ($3 > maxcpu) maxcpu = $3
        if ($5 > maxmem) maxmem = $5
        if ($7 != "" && $7 + 0 > maxp) maxp = $7 + 0
        mem = $4
      }
      END {
        if (n == 0) { print "no samples"; exit }
        printf "CPU avg %.1f%% / peak %.1f%%\nRAM now %s (peak %.1f%% of limit)\nPeak players: %d", cpu / n, maxcpu, mem, maxmem, maxp
      }' "$csv")
    post "📊 **BeamMP stats (last ${STATS_REPORT_MINUTES:-60} min)**
$summary"
    last_report=$now
  fi

  sleep "$sample"
done
