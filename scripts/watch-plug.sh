#!/usr/bin/env bash
# Polls the Tuya plug and reports every state change, so you can see exactly when
# the battery automation fires without staring at the phone.
#
#   ./scripts/watch-plug.sh [seconds_to_watch] [poll_interval]
#
# Exits 0 as soon as it observes an ON -> OFF transition (the automation firing).

set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

DURATION="${1:-7200}"   # default: watch for 2 hours
INTERVAL="${2:-60}"     # default: poll every 60s

deadline=$(( $(date +%s) + DURATION ))
prev=""
seen_on=0

echo "$(date '+%H:%M:%S')  watching plug (every ${INTERVAL}s, up to $((DURATION/60)) min)"

while [ "$(date +%s)" -lt "$deadline" ]; do
  out="$(python3 scripts/tuya.py status 2>&1)"
  case "$out" in
    *"currently ON"*)  cur="ON"  ;;
    *"currently OFF"*) cur="OFF" ;;
    *)                 cur="ERROR" ;;
  esac

  if [ "$cur" != "$prev" ]; then
    if [ "$cur" = "ERROR" ]; then
      echo "$(date '+%H:%M:%S')  ERROR: $out"
    else
      echo "$(date '+%H:%M:%S')  plug $cur"
    fi
    prev="$cur"
  fi

  if [ "$cur" = "ON" ]; then
    seen_on=1
  elif [ "$cur" = "OFF" ] && [ "$seen_on" -eq 1 ]; then
    echo "$(date '+%H:%M:%S')  ✅ automation fired — plug cut while charging"
    exit 0
  fi

  sleep "$INTERVAL"
done

echo "$(date '+%H:%M:%S')  watch window ended without an ON -> OFF transition"
exit 1
