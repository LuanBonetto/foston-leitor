#!/usr/bin/env bash
# Snapshot of boot state, memory and running processes.
source "$(dirname "$0")/lib.sh"

label="${1:?uso: health.sh <rotulo>}"
require_device
out="$REPO/logs/$label.txt"
mkdir -p "$REPO/logs"
{
  echo "rotulo: $label"
  echo "data: $(date -Iseconds)"
  echo "boot_completed: $("$ADB" shell getprop sys.boot_completed | tr -d '\r')"
  echo "wifi: $("$ADB" shell getprop wlan.driver.status | tr -d '\r')"
  "$ADB" shell cat /proc/meminfo | tr -d '\r' | grep -E '^(MemTotal|MemFree|Cached):'
  echo "processos: $("$ADB" shell ps | tr -d '\r' | tail -n +2 | wc -l)"
  echo "apps_ativos:"
  "$ADB" shell ps | tr -d '\r' | awk 'NR > 1 && $NF ~ /\./ {print "  " $NF}' | sort
} > "$out"
cat "$out"
