#!/usr/bin/env bash
# Shared helpers for every device script. Source, do not run.
set -euo pipefail

ADB="${ADB:-$HOME/.local/opt/platform-tools/adb}"
BB=/data/local/tmp/busybox
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "ERRO: $*" >&2; exit 1; }

require_device() {
  "$ADB" get-state >/dev/null 2>&1 || die "tablet não encontrado pelo adb"
  [ "$("$ADB" shell id | tr -d '\r' | cut -d' ' -f1)" = "uid=0(root)" ] \
    || die "adb shell não está como root"
}

# Android 4.0 hands /mnt/sdcard to the PC as USB mass storage while the cable
# is plugged in. Take it back so adb and KOReader can see the files.
sdcard_mount() {
  "$ADB" shell "vdc volume unshare /mnt/sdcard ums" >/dev/null || true
  "$ADB" shell "vdc volume mount /mnt/sdcard" >/dev/null || true
  "$ADB" shell "ls /mnt/sdcard" >/dev/null 2>&1 \
    && [ -n "$("$ADB" shell "ls /mnt/sdcard" | tr -d '\r')" ] \
    || die "/mnt/sdcard não montou (desligue 'Armazenamento USB' no tablet)"
}
