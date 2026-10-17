#!/usr/bin/env bash
# Copies every NAND partition to the PC in 64 MiB chunks and checks md5.
source "$(dirname "$0")/lib.sh"

OUT="${1:-$HOME/foston-backup/2026-10-16}"
CHUNK_MB=64
BUSYBOX_URL=https://busybox.net/downloads/binaries/1.31.0-defconfig-multiarch-musl/busybox-armv7l

require_device
mkdir -p "$OUT"

if ! "$ADB" shell "[ -x $BB ] && echo ok" | grep -q ok; then
  curl -fsSL -o "$OUT/busybox" "$BUSYBOX_URL"
  "$ADB" push "$OUT/busybox" "$BB"
  "$ADB" shell "chmod 755 $BB"
fi

sdcard_mount
"$ADB" shell "pm list packages -f" | tr -d '\r' > "$OUT/packages.txt"
"$ADB" shell getprop | tr -d '\r' > "$OUT/getprop.txt"
"$ADB" pull /system/build.prop "$OUT/build.prop"
"$ADB" pull /system/etc/vold.fstab "$OUT/vold.fstab"

for p in nanda nandb nandc nandd nande nandf nandg nandh nandi nandj; do
  img="$OUT/$p.img"
  kb=$("$ADB" shell "cat /proc/partitions" | tr -d '\r' | awk -v p="$p" '$4==p {print $3}')
  [ -n "$kb" ] || die "partição $p não encontrada"
  chunks=$(( (kb / 1024 + CHUNK_MB - 1) / CHUNK_MB ))
  : > "$img"
  for ((i = 0; i < chunks; i++)); do
    "$ADB" shell "dd if=/dev/block/$p of=/data/local/tmp/chunk bs=1048576 skip=$((i * CHUNK_MB)) count=$CHUNK_MB 2>/dev/null"
    "$ADB" pull /data/local/tmp/chunk "$OUT/chunk" 2>/dev/null
    cat "$OUT/chunk" >> "$img"
  done
  "$ADB" shell "rm -f /data/local/tmp/chunk"; rm -f "$OUT/chunk"

  size=$(stat -c %s "$img")
  [ "$size" -eq $((kb * 1024)) ] || die "$p: tamanho $size != $((kb * 1024))"
  dev_md5=$("$ADB" shell "$BB md5sum /dev/block/$p" | tr -d '\r' | cut -d' ' -f1)
  pc_md5=$(md5sum "$img" | cut -d' ' -f1)
  [ "$dev_md5" = "$pc_md5" ] || die "$p: md5 diferente ($dev_md5 vs $pc_md5)"
  echo "$pc_md5  $p.img" > "$OUT/$p.md5"
  echo "ok $p ($((kb / 1024)) MiB) $pc_md5"
done
echo "backup completo em $OUT"
