# Foston FS-M787S e-reader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Foston FS-M787S (Android 4.0.4) into a dedicated reader that boots straight into KOReader, with a full NAND backup taken first and unneeded apps removed or disabled.

**Architecture:** Everything is driven from the PC through `adb` (the tablet's adbd already runs as root). Shell scripts in `scripts/` hold every device operation so each step is repeatable and reviewable. A tiny Android app, "Leitor" (`br.com.luan.leitor`), registers as the HOME screen, opens KOReader once per boot and otherwise shows two big buttons: "Ler" and "Configurações". The app is built with plain SDK command-line tools (`aapt2`, `javac`, `d8`, `apksigner`) from `build.sh`, no Gradle.

**Tech Stack:** bash, adb (platform-tools 37), busybox 1.31.0 armv7l (pushed to `/data/local/tmp`, not installed in `/system`), JDK 21 (Temurin), Android SDK `platforms;android-15` + `build-tools;34.0.0`, Java 8 language level, KOReader v2023.06.

**Spec:** `docs/superpowers/specs/2026-10-16-foston-ereader-design.md`

## Global Constraints

- Device: Foston FS-M787S, Android 4.0.4, API 15, `armeabi-v7a`, adb serial `20080411413fc082`.
- adb binary: `$HOME/.local/opt/platform-tools/adb`. Every script uses `ADB="${ADB:-$HOME/.local/opt/platform-tools/adb}"`.
- Never write to `nanda`, `nandb`, `nandc`, or `/system`. All app changes go through `pm`/`adb install`/`adb uninstall`, which only touch `/data`.
- Backups live in `~/foston-backup/2026-10-16/` (outside the repo; never commit images).
- KOReader: exactly `koreader-android-arm-v2023.06.apk`, 32 648 511 bytes, package `org.koreader.launcher`.
- Leitor: package `br.com.luan.leitor`, `minSdkVersion 15`, `targetSdkVersion 15`, Java language level 8.
- `com.android.launcher` is disabled only in the last task, after Leitor passes its tests.
- Books folder: `/mnt/sdcard/Livros`.
- Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Steps marked **[manual]** need the user to look at or touch the tablet. Ask, then wait for the answer.

## Spec deviations (found while planning)

- The spec says "Wi-Fi desligado ao abrir" inside KOReader. KOReader on Android cannot switch Wi-Fi by itself on 4.0. Plan: switch system Wi-Fi off once with `svc wifi disable`; it stays off until the user turns it on in Configurações.
- The spec says "tela cheia" in KOReader. Android 4.0 tablets cannot hide the system bar (it holds Back/Home). Plan: no fullscreen setting; KOReader runs with the system bar visible.
- `adb exec-out` is not supported by the 4.0 adbd, so the backup copies each partition in 64 MiB chunks to `/data/local/tmp` and pulls them, with busybox `md5sum` for verification.

## File structure

```
foston-leitor/
├── scripts/
│   ├── lib.sh                 # ADB var, die(), require_device(), sdcard_mount()
│   ├── backup.sh              # chunked dd backup of nanda..nandj + md5 check
│   ├── health.sh              # boot/RAM/process snapshot written to logs/
│   ├── apply-packages.sh      # uninstall or disable a package list file
│   ├── install-koreader.sh    # download, verify, install, configure KOReader
│   └── setup-toolchain.sh     # JDK 21 + Android SDK into ~/.local/opt
├── packages/
│   ├── remove.txt             # user apps to uninstall
│   ├── disable-1-google.txt
│   ├── disable-2-apps.txt
│   ├── disable-3-visual.txt
│   └── disable-4-launcher.txt
├── app/
│   ├── AndroidManifest.xml
│   ├── res/layout/main.xml
│   ├── res/values/strings.xml
│   ├── src/br/com/luan/leitor/AutoLaunchPolicy.java
│   ├── src/br/com/luan/leitor/MainActivity.java
│   ├── test/br/com/luan/leitor/AutoLaunchPolicyTest.java
│   └── build.sh               # test + build + sign → app/build/leitor.apk
├── logs/                      # health snapshots (committed, small text)
└── .gitignore
```

---

### Task 1: Full NAND backup

**Files:**
- Create: `.gitignore`, `scripts/lib.sh`, `scripts/backup.sh`

**Interfaces:**
- Produces: `scripts/lib.sh` with `ADB`, `BB=/data/local/tmp/busybox`, `die "msg"`, `require_device`, `sdcard_mount` (unshares USB mass storage and mounts `/mnt/sdcard` on the tablet). Every later script starts with `source "$(dirname "$0")/lib.sh"`.
- Produces: `~/foston-backup/2026-10-16/{nanda..nandj}.img`, `*.md5`, `packages.txt`, `getprop.txt`, `build.prop`, `vold.fstab`.

- [ ] **Step 1: Reconnect the tablet [manual]**

The tablet dropped off USB after the spec session. Ask the user to plug it in, unlock it, and charge it above 50%. Then run:

Run: `~/.local/opt/platform-tools/adb devices`
Expected: a line `20080411413fc082	device`. If `unauthorized`, the user accepts the USB-debugging prompt on the tablet.

- [ ] **Step 2: Write `.gitignore` and `scripts/lib.sh`**

`.gitignore`:
```
app/build/
*.img
*.apk
*.keystore
```

`scripts/lib.sh`:
```bash
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
```

Note: if the PC still has the tablet's 1,7 GB disk mounted, unmount it first (`udisksctl unmount -b /dev/sdX`), otherwise `unshare` fails.

- [ ] **Step 3: Write `scripts/backup.sh`**

```bash
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
```

Note: `nandd`, `nande`, `nandh` and `nandj` are mounted read-write. Their md5 can differ if Android writes during the copy. If only one of those fails, run the script again with the tablet idle. If it fails twice, record the mismatch in the report and keep going only with the user's approval: `nanda`–`nandc` (the boot chain) must always match.

- [ ] **Step 4: Run the backup**

Run: `chmod +x scripts/*.sh && scripts/backup.sh`
Expected: ten lines `ok nandX (...) <md5>` and `backup completo em /home/luanbonetto/foston-backup/2026-10-16`. Takes roughly 15–30 minutes over USB 2.0.

- [ ] **Step 5: Check the result**

Run: `ls -l ~/foston-backup/2026-10-16/ && du -sh ~/foston-backup/2026-10-16`
Expected: ten `.img` files, about 3,8 GB in total, plus `.md5`, `packages.txt`, `getprop.txt`, `build.prop`, `vold.fstab`.

- [ ] **Step 6: Commit**

```bash
git add .gitignore scripts/lib.sh scripts/backup.sh
git commit -m "feat: backup completo da NAND via adb

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Health snapshot and removal of user apps

**Files:**
- Create: `scripts/health.sh`, `scripts/apply-packages.sh`, `packages/remove.txt`, `logs/01-antes.txt`, `logs/02-apos-remove.txt`

**Interfaces:**
- Consumes: `scripts/lib.sh` (`ADB`, `die`, `require_device`).
- Produces: `scripts/health.sh <label>` writes `logs/<label>.txt` and prints it. `scripts/apply-packages.sh <uninstall|disable|enable> <file>` reads one package per line (`#` comments and blank lines ignored), and fails on the first error.

- [ ] **Step 1: Write `scripts/health.sh`**

```bash
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
```

- [ ] **Step 2: Take the "before" snapshot**

Run: `chmod +x scripts/health.sh && scripts/health.sh 01-antes`
Expected: `boot_completed: 1`, `MemTotal: 361936 kB`, a process count, and a list that includes `com.skype.raider` or other user apps.

- [ ] **Step 3: Write `scripts/apply-packages.sh`**

```bash
#!/usr/bin/env bash
# Applies one action to every package listed in a file.
source "$(dirname "$0")/lib.sh"

action="${1:?uso: apply-packages.sh <uninstall|disable|enable> <arquivo>}"
file="${2:?uso: apply-packages.sh <uninstall|disable|enable> <arquivo>}"
require_device

grep -v -E '^\s*(#|$)' "$file" | while read -r pkg; do
  case "$action" in
    uninstall) result=$("$ADB" uninstall "$pkg" | tr -d '\r') ;;
    disable|enable) result=$("$ADB" shell "pm $action $pkg" | tr -d '\r') ;;
    *) die "ação inválida: $action" ;;
  esac
  echo "$pkg: $result"
  case "$result" in
    *Success*|*"new state"*) ;;
    *) die "$action falhou para $pkg" ;;
  esac
done
```

On Android 4.0, `pm disable` prints `Package <pkg> new state: disabled`; `adb uninstall` prints `Success`.

- [ ] **Step 4: Write `packages/remove.txt`**

```
# Apps instalados em /data/app. Saem de vez com adb uninstall.
com.adobe.flashplayer
com.android.vending
com.dataviz.docstogo
com.google.android.gms
com.google.android.voicesearch
com.google.android.youtube
com.instagram.android
com.opera.mini.native
com.skype.raider
com.spb.shell3d
miyowa.android.microsoft.wlm
yuku.mp3recorder.full
```

- [ ] **Step 5: Uninstall**

Run: `chmod +x scripts/apply-packages.sh && scripts/apply-packages.sh uninstall packages/remove.txt`
Expected: twelve lines `<pkg>: Success`.

Note: `com.android.vending` is a `/data/app` update over no system copy here (only `MarketUpdater.apk` is in `/system/app`), so uninstall removes it fully. If any package reports `Failure [DELETE_FAILED_INTERNAL_ERROR]`, move it to `packages/disable-1-google.txt` instead and rerun the remaining lines.

- [ ] **Step 6: Reboot and check**

Run: `~/.local/opt/platform-tools/adb reboot && ~/.local/opt/platform-tools/adb wait-for-device && until [ "$(~/.local/opt/platform-tools/adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done && scripts/health.sh 02-apos-remove`
Expected: `boot_completed: 1`, no removed package in `apps_ativos`, `MemFree + Cached` higher than in `logs/01-antes.txt`.

- [ ] **Step 7: Confirm with the user [manual]**

Ask the user to confirm: the tablet shows the home screen, Wi-Fi connects to their network, touch responds, rotating the tablet rotates the screen.

- [ ] **Step 8: Commit**

```bash
git add scripts/health.sh scripts/apply-packages.sh packages/remove.txt logs/
git commit -m "feat: remove apps de usuário e registra uso de memória

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Disable system apps in batches

**Files:**
- Create: `packages/disable-1-google.txt`, `packages/disable-2-apps.txt`, `packages/disable-3-visual.txt`, `logs/03-lote-1.txt`, `logs/04-lote-2.txt`, `logs/05-lote-3.txt`

**Interfaces:**
- Consumes: `scripts/apply-packages.sh`, `scripts/health.sh`.

- [ ] **Step 1: Write the three batch files**

`packages/disable-1-google.txt`:
```
# Google: contas, sincronização, busca, localização.
com.google.android.gm
com.google.android.syncadapters.calendar
com.google.android.syncadapters.contacts
com.google.android.feedback
com.google.android.gsf.login
com.google.android.gsf
com.google.android.partnersetup
com.google.android.googlequicksearchbox
com.google.android.apps.uploader
com.google.android.location
com.android.vending.updater
```

`packages/disable-2-apps.txt`:
```
# Apps de uso geral que o leitor não precisa.
com.android.email
com.android.exchange
com.android.camera
com.android.gallery3d
com.android.music
com.android.musicfx
com.android.music.tests
com.android.calendar
com.android.calculator2
com.android.deskclock
com.android.browser
com.android.quicksearchbox
```

`packages/disable-3-visual.txt`:
```
# Desbloqueio por rosto e papéis de parede animados.
com.android.facelock
com.android.wallpaper
com.android.wallpaper.livepicker
```

- [ ] **Step 2: Apply batch 1, reboot, snapshot**

Run: `scripts/apply-packages.sh disable packages/disable-1-google.txt && ~/.local/opt/platform-tools/adb reboot && ~/.local/opt/platform-tools/adb wait-for-device && until [ "$(~/.local/opt/platform-tools/adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done && scripts/health.sh 03-lote-1`
Expected: eleven `new state: disabled` lines, `boot_completed: 1`, no `com.google.*` process in `apps_ativos`.

If the tablet shows repeated "O processo ... parou" dialogs: run `scripts/apply-packages.sh enable packages/disable-1-google.txt`, reboot, and report the dialog text to the user before trying again.

- [ ] **Step 3: Apply batch 2, reboot, snapshot**

Run: `scripts/apply-packages.sh disable packages/disable-2-apps.txt && ~/.local/opt/platform-tools/adb reboot && ~/.local/opt/platform-tools/adb wait-for-device && until [ "$(~/.local/opt/platform-tools/adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done && scripts/health.sh 04-lote-2`
Expected: twelve `new state: disabled` lines and `boot_completed: 1`. Same rollback as step 2 with `disable-2-apps.txt`.

- [ ] **Step 4: Apply batch 3, reboot, snapshot**

Run: `scripts/apply-packages.sh disable packages/disable-3-visual.txt && ~/.local/opt/platform-tools/adb reboot && ~/.local/opt/platform-tools/adb wait-for-device && until [ "$(~/.local/opt/platform-tools/adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done && scripts/health.sh 05-lote-3`
Expected: three `new state: disabled` lines and `boot_completed: 1`. Same rollback as step 2 with `disable-3-visual.txt`.

- [ ] **Step 5: Confirm with the user [manual]**

Ask the user to confirm: Launcher2 home screen still shows, Configurações opens, Wi-Fi connects, touch and rotation work, no error dialog appears within one minute of use.

- [ ] **Step 6: Commit**

```bash
git add packages/disable-1-google.txt packages/disable-2-apps.txt packages/disable-3-visual.txt logs/
git commit -m "feat: desativa apps de sistema em três lotes

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: KOReader install and configuration

**Files:**
- Create: `scripts/install-koreader.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh` (`ADB`, `die`, `require_device`, `sdcard_mount`).
- Produces: package `org.koreader.launcher` installed; `/mnt/sdcard/Livros/` with two sample books; `/mnt/sdcard/koreader/settings.reader.lua` containing `["home_dir"] = "/mnt/sdcard/Livros"`. Task 5 launches KOReader by the package name `org.koreader.launcher`.

- [ ] **Step 1: Write `scripts/install-koreader.sh`**

```bash
#!/usr/bin/env bash
# Installs KOReader v2023.06 (last release for Android 4.0) and points it at Livros/.
source "$(dirname "$0")/lib.sh"

VERSION=v2023.06
APK_URL="https://github.com/koreader/koreader/releases/download/$VERSION/koreader-android-arm-$VERSION.apk"
APK_SIZE=32648511
PKG=org.koreader.launcher
CACHE="$HOME/.cache/foston-leitor"
SETTINGS=/mnt/sdcard/koreader/settings.reader.lua

require_device
mkdir -p "$CACHE"
apk="$CACHE/koreader-$VERSION.apk"
[ -f "$apk" ] || curl -fL -o "$apk" "$APK_URL"
[ "$(stat -c %s "$apk")" -eq "$APK_SIZE" ] || die "APK com tamanho inesperado"

"$ADB" install -r "$apk" | tr -d '\r' | grep -q Success || die "adb install falhou"

sdcard_mount
"$ADB" shell "mkdir -p /mnt/sdcard/Livros"
curl -fsSL -o "$CACHE/alice.epub" https://www.gutenberg.org/ebooks/11.epub.noimages
curl -fsSL -o "$CACHE/exemplo.pdf" https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf
"$ADB" push "$CACHE/alice.epub" /mnt/sdcard/Livros/alice.epub
"$ADB" push "$CACHE/exemplo.pdf" /mnt/sdcard/Livros/exemplo.pdf

# First start creates /mnt/sdcard/koreader and its settings file.
if ! "$ADB" shell "ls $SETTINGS" | grep -q settings.reader.lua; then
  "$ADB" shell "am start -n $PKG/.MainActivity" >/dev/null
  for _ in $(seq 1 60); do
    "$ADB" shell "ls $SETTINGS" | grep -q settings.reader.lua && break
    sleep 2
  done
fi
"$ADB" shell "am force-stop $PKG"
sleep 2

"$ADB" pull "$SETTINGS" "$CACHE/settings.reader.lua"
if ! grep -q '"home_dir"' "$CACHE/settings.reader.lua"; then
  sed -i 's|^return {|return {\n    ["home_dir"] = "/mnt/sdcard/Livros",|' "$CACHE/settings.reader.lua"
  "$ADB" push "$CACHE/settings.reader.lua" "$SETTINGS"
fi
"$ADB" shell "cat $SETTINGS" | grep -q '"/mnt/sdcard/Livros"' || die "home_dir não gravado"

# Wi-Fi stays off until the user turns it on in Configurações.
"$ADB" shell "svc wifi disable"
echo "KOReader $VERSION instalado"
```

If `am start -n org.koreader.launcher/.MainActivity` fails with "Activity class does not exist", read the activity name with `$ADB shell pm dump org.koreader.launcher | grep -A1 MAIN` and use the name it prints; record it in the script.

If `settings.reader.lua` never appears, the user may need to open KOReader once by hand and accept its first-run dialog **[manual]**; then rerun the script.

- [ ] **Step 2: Run it**

Run: `chmod +x scripts/install-koreader.sh && scripts/install-koreader.sh`
Expected: last line `KOReader v2023.06 instalado`.

- [ ] **Step 3: Check the install from adb**

Run: `~/.local/opt/platform-tools/adb shell "pm list packages org.koreader; ls /mnt/sdcard/Livros"`
Expected: `package:org.koreader.launcher`, `alice.epub`, `exemplo.pdf`.

- [ ] **Step 4: Read test [manual]**

Ask the user to open KOReader from the app drawer and check:
1. The file browser opens in `Livros` and shows both files.
2. `alice.epub` opens; tapping the right edge turns pages.
3. `exemplo.pdf` opens and shows its page.
4. Menu (top) → search icon → "Catálogo OPDS" lists Project Gutenberg (comes by default in KOReader).

- [ ] **Step 5: Commit**

```bash
git add scripts/install-koreader.sh
git commit -m "feat: instala e configura KOReader v2023.06

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Build toolchain and Leitor app

**Files:**
- Create: `scripts/setup-toolchain.sh`, `app/AndroidManifest.xml`, `app/res/layout/main.xml`, `app/res/values/strings.xml`, `app/src/br/com/luan/leitor/AutoLaunchPolicy.java`, `app/src/br/com/luan/leitor/MainActivity.java`, `app/test/br/com/luan/leitor/AutoLaunchPolicyTest.java`, `app/build.sh`

**Interfaces:**
- Consumes: KOReader package name `org.koreader.launcher` (Task 4).
- Produces: `AutoLaunchPolicy.shouldAutoLaunch(long nowElapsedMs, long lastLaunchElapsedMs)` → `boolean`; constant `AutoLaunchPolicy.NEVER = -1L`. `app/build.sh` writes `app/build/leitor.apk`. Task 6 relies on the activity `br.com.luan.leitor/.MainActivity` being a HOME activity.

- [ ] **Step 1: Write `scripts/setup-toolchain.sh`**

```bash
#!/usr/bin/env bash
# Installs JDK 21 and the Android SDK pieces Leitor needs into ~/.local/opt (no sudo).
set -euo pipefail

OPT="$HOME/.local/opt"
JDK="$OPT/jdk-21"
SDK="$OPT/android-sdk"
TOOLS_ZIP=commandlinetools-linux-16111833_latest.zip
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OPT"
if [ ! -x "$JDK/bin/javac" ]; then
  curl -fL -o "$TMP/jdk.tar.gz" \
    "https://api.adoptium.net/v3/binary/latest/21/ga/linux/x64/jdk/hotspot/normal/eclipse"
  mkdir -p "$JDK"
  tar -xzf "$TMP/jdk.tar.gz" -C "$JDK" --strip-components=1
fi
export JAVA_HOME="$JDK" PATH="$JDK/bin:$PATH"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  curl -fL -o "$TMP/tools.zip" "https://dl.google.com/android/repository/$TOOLS_ZIP"
  mkdir -p "$SDK/cmdline-tools"
  unzip -q "$TMP/tools.zip" -d "$TMP"
  mv "$TMP/cmdline-tools" "$SDK/cmdline-tools/latest"
fi

yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null
"$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" "platforms;android-15" "build-tools;34.0.0"

"$JDK/bin/javac" -version
ls "$SDK/platforms/android-15/android.jar" "$SDK/build-tools/34.0.0/aapt2"
```

- [ ] **Step 2: Run it**

Run: `chmod +x scripts/setup-toolchain.sh && scripts/setup-toolchain.sh`
Expected: `javac 21.x.x` and the two paths printed with no error.

- [ ] **Step 3: Write the failing test**

`app/test/br/com/luan/leitor/AutoLaunchPolicyTest.java`:
```java
package br.com.luan.leitor;

/** Plain-Java test runner; no JUnit so it runs with javac/java only. */
public final class AutoLaunchPolicyTest {
    private static int failures = 0;

    private static void check(String name, boolean actual, boolean expected) {
        if (actual == expected) {
            System.out.println("ok   " + name);
        } else {
            failures++;
            System.out.println("FAIL " + name + ": esperado " + expected + ", veio " + actual);
        }
    }

    public static void main(String[] args) {
        check("primeira vez desde a instalação abre",
                AutoLaunchPolicy.shouldAutoLaunch(30_000L, AutoLaunchPolicy.NEVER), true);
        check("mesmo boot, depois de abrir, não abre de novo",
                AutoLaunchPolicy.shouldAutoLaunch(90_000L, 30_000L), false);
        check("mesmo boot, mesmo instante, não abre de novo",
                AutoLaunchPolicy.shouldAutoLaunch(30_000L, 30_000L), false);
        check("novo boot (relógio desde o boot voltou) abre",
                AutoLaunchPolicy.shouldAutoLaunch(20_000L, 3_600_000L), true);
        if (failures > 0) {
            System.exit(1);
        }
    }
}
```

- [ ] **Step 4: Run it to see it fail**

Run: `mkdir -p app/build/test && ~/.local/opt/jdk-21/bin/javac -d app/build/test app/test/br/com/luan/leitor/AutoLaunchPolicyTest.java`
Expected: compile error `cannot find symbol ... AutoLaunchPolicy`.

- [ ] **Step 5: Write `AutoLaunchPolicy.java`**

`app/src/br/com/luan/leitor/AutoLaunchPolicy.java`:
```java
package br.com.luan.leitor;

/**
 * Decides whether the reader should open by itself.
 *
 * Times come from SystemClock.elapsedRealtime(), which restarts at zero on
 * every boot. If the stored launch time is later than "now", the tablet has
 * rebooted since, so the reader opens once more.
 */
final class AutoLaunchPolicy {
    static final long NEVER = -1L;

    private AutoLaunchPolicy() {
    }

    static boolean shouldAutoLaunch(long nowElapsedMs, long lastLaunchElapsedMs) {
        return lastLaunchElapsedMs == NEVER || nowElapsedMs < lastLaunchElapsedMs;
    }
}
```

- [ ] **Step 6: Run the test to see it pass**

Run: `~/.local/opt/jdk-21/bin/javac -d app/build/test app/src/br/com/luan/leitor/AutoLaunchPolicy.java app/test/br/com/luan/leitor/AutoLaunchPolicyTest.java && ~/.local/opt/jdk-21/bin/java -cp app/build/test br.com.luan.leitor.AutoLaunchPolicyTest`
Expected: four `ok` lines, exit code 0.

- [ ] **Step 7: Write the manifest and resources**

`app/AndroidManifest.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="br.com.luan.leitor"
    android:versionCode="1"
    android:versionName="1.0">

    <uses-sdk android:minSdkVersion="15" android:targetSdkVersion="15" />

    <application
        android:label="@string/app_name"
        android:theme="@android:style/Theme.Holo.NoActionBar">
        <activity
            android:name=".MainActivity"
            android:launchMode="singleTask"
            android:stateNotNeeded="true"
            android:clearTaskOnLaunch="true"
            android:screenOrientation="unspecified">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.HOME" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>
    </application>
</manifest>
```

`app/res/values/strings.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <string name="app_name">Leitor</string>
    <string name="read">Ler</string>
    <string name="settings">Configurações</string>
    <string name="koreader_missing">KOReader não está instalado.</string>
</resources>
```

`app/res/layout/main.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    android:gravity="center"
    android:orientation="vertical"
    android:padding="32dp">

    <TextView
        android:id="@+id/status"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:layout_marginBottom="24dp"
        android:textSize="20sp"
        android:visibility="gone" />

    <Button
        android:id="@+id/read"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_marginBottom="24dp"
        android:layout_weight="2"
        android:text="@string/read"
        android:textSize="40sp" />

    <Button
        android:id="@+id/settings"
        android:layout_width="match_parent"
        android:layout_height="0dp"
        android:layout_weight="1"
        android:text="@string/settings"
        android:textSize="28sp" />
</LinearLayout>
```

- [ ] **Step 8: Write `MainActivity.java`**

`app/src/br/com/luan/leitor/MainActivity.java`:
```java
package br.com.luan.leitor;

import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.os.SystemClock;
import android.provider.Settings;
import android.view.View;
import android.widget.TextView;

/** Home screen: opens KOReader once per boot, then offers "Ler" and "Configurações". */
public class MainActivity extends Activity {
    static final String KOREADER_PACKAGE = "org.koreader.launcher";
    private static final String PREFS = "leitor";
    private static final String KEY_LAST_LAUNCH = "last_launch_elapsed_ms";

    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.main);
        status = (TextView) findViewById(R.id.status);

        findViewById(R.id.read).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                openReader();
            }
        });
        findViewById(R.id.settings).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View v) {
                startActivity(new Intent(Settings.ACTION_SETTINGS));
            }
        });
    }

    @Override
    protected void onResume() {
        super.onResume();
        SharedPreferences prefs = getSharedPreferences(PREFS, MODE_PRIVATE);
        long now = SystemClock.elapsedRealtime();
        long last = prefs.getLong(KEY_LAST_LAUNCH, AutoLaunchPolicy.NEVER);
        if (AutoLaunchPolicy.shouldAutoLaunch(now, last)) {
            prefs.edit().putLong(KEY_LAST_LAUNCH, now).commit();
            openReader();
        }
    }

    private void openReader() {
        Intent intent = getPackageManager().getLaunchIntentForPackage(KOREADER_PACKAGE);
        if (intent == null) {
            status.setText(R.string.koreader_missing);
            status.setVisibility(View.VISIBLE);
            return;
        }
        status.setVisibility(View.GONE);
        startActivity(intent);
    }
}
```

- [ ] **Step 9: Write `app/build.sh`**

```bash
#!/usr/bin/env bash
# Runs the tests, then builds and signs app/build/leitor.apk.
set -euo pipefail

APP="$(cd "$(dirname "$0")" && pwd)"
JDK="$HOME/.local/opt/jdk-21"
SDK="$HOME/.local/opt/android-sdk"
BT="$SDK/build-tools/34.0.0"
ANDROID_JAR="$SDK/platforms/android-15/android.jar"
B="$APP/build"
KEYSTORE="$APP/debug.keystore"
export JAVA_HOME="$JDK" PATH="$JDK/bin:$PATH"

rm -rf "$B"
mkdir -p "$B/test" "$B/gen" "$B/classes" "$B/dex"

# 1. Unit tests (plain JVM).
javac -d "$B/test" "$APP/src/br/com/luan/leitor/AutoLaunchPolicy.java" \
  "$APP/test/br/com/luan/leitor/AutoLaunchPolicyTest.java"
java -cp "$B/test" br.com.luan.leitor.AutoLaunchPolicyTest

# 2. Resources and manifest.
"$BT/aapt2" compile --dir "$APP/res" -o "$B/res.zip"
"$BT/aapt2" link -I "$ANDROID_JAR" --manifest "$APP/AndroidManifest.xml" \
  --min-sdk-version 15 --target-sdk-version 15 \
  --java "$B/gen" -o "$B/unsigned.apk" "$B/res.zip"

# 3. Java to dex.
javac --release 8 -classpath "$ANDROID_JAR" -d "$B/classes" \
  $(find "$APP/src" "$B/gen" -name '*.java') 2>&1 | grep -v 'warning: \[options\]' || true
[ -f "$B/classes/br/com/luan/leitor/MainActivity.class" ] || { echo "javac falhou" >&2; exit 1; }
"$BT/d8" --min-api 15 --lib "$ANDROID_JAR" --output "$B/dex" \
  $(find "$B/classes" -name '*.class')
(cd "$B/dex" && zip -q "$B/unsigned.apk" classes.dex)

# 4. Align and sign (v1 signature is what Android 4.0 checks).
[ -f "$KEYSTORE" ] || keytool -genkeypair -keystore "$KEYSTORE" -storepass android \
  -keypass android -alias leitor -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Leitor" >/dev/null
"$BT/zipalign" -f -p 4 "$B/unsigned.apk" "$B/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android \
  --v1-signing-enabled true --out "$B/leitor.apk" "$B/aligned.apk"
"$BT/apksigner" verify --min-sdk-version 15 "$B/leitor.apk"
echo "ok: $B/leitor.apk"
```

The keystore stays local (`*.keystore` is in `.gitignore`). Keep it: a reinstall with a different key needs an uninstall first.

- [ ] **Step 10: Build**

Run: `chmod +x app/build.sh && app/build.sh`
Expected: four `ok` test lines, then `ok: /home/luanbonetto/code/foston-leitor/app/build/leitor.apk`. `apksigner verify` prints nothing on success.

- [ ] **Step 11: Install with Launcher2 still active**

Run: `~/.local/opt/platform-tools/adb install -r app/build/leitor.apk && ~/.local/opt/platform-tools/adb shell "am start -n br.com.luan.leitor/.MainActivity"`
Expected: `Success`, then KOReader opens on the tablet (first launch since install).

- [ ] **Step 12: Behavior test [manual]**

Ask the user to:
1. Press Back inside KOReader until it closes. Expected: the Leitor screen with "Ler" and "Configurações".
2. Tap "Configurações". Expected: Android settings. Press Back. Expected: Leitor screen.
3. Tap "Ler". Expected: KOReader opens.
4. Press Home. Expected: Android asks which home app to use (Launcher vs Leitor), because Launcher2 is still enabled. Choose "Leitor" **only this time** (not "sempre").

- [ ] **Step 13: Commit**

```bash
git add scripts/setup-toolchain.sh app/AndroidManifest.xml app/res app/src app/test app/build.sh
git commit -m "feat: app Leitor como tela inicial que abre o KOReader

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Make Leitor the only home screen

**Files:**
- Create: `packages/disable-4-launcher.txt`, `logs/06-final.txt`

**Interfaces:**
- Consumes: Leitor installed and tested (Task 5); `scripts/apply-packages.sh`; `scripts/health.sh`.

- [ ] **Step 1: Write `packages/disable-4-launcher.txt`**

```
# Só depois que o Leitor passou nos testes da Task 5.
com.android.launcher
```

- [ ] **Step 2: Disable Launcher2 and reboot**

Run: `scripts/apply-packages.sh disable packages/disable-4-launcher.txt && ~/.local/opt/platform-tools/adb reboot && ~/.local/opt/platform-tools/adb wait-for-device && until [ "$(~/.local/opt/platform-tools/adb shell getprop sys.boot_completed | tr -d '\r')" = 1 ]; do sleep 2; done && scripts/health.sh 06-final`
Expected: `com.android.launcher: Package com.android.launcher new state: disabled`, `boot_completed: 1`, `br.com.luan.leitor` and `org.koreader.launcher` in `apps_ativos`.

Rollback if the tablet boots to a black screen or a home-app chooser loop: `scripts/apply-packages.sh enable packages/disable-4-launcher.txt` and reboot.

- [ ] **Step 3: Final test [manual]**

Ask the user to check, unplugged from the PC:
1. After boot, KOReader opens by itself.
2. Home from inside KOReader shows the Leitor screen, with no chooser dialog.
3. Back from KOReader shows the Leitor screen.
4. "Configurações" → Wi-Fi on → KOReader → OPDS → Project Gutenberg downloads one book → Wi-Fi off.
5. Plug into the PC, turn on "Armazenamento USB" on the tablet, copy a file into `Livros/` from the PC, eject, turn storage off; the file shows in KOReader.

- [ ] **Step 4: Compare memory**

Run: `grep -E 'MemFree|Cached|processos' logs/01-antes.txt logs/06-final.txt`
Expected: `MemFree + Cached` and the process count improve from `01-antes` to `06-final`. Report both numbers to the user.

- [ ] **Step 5: Commit**

```bash
git add packages/disable-4-launcher.txt logs/
git commit -m "feat: Leitor vira a única tela inicial

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```
