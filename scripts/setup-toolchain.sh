#!/usr/bin/env bash
# Installs JDK 21 and the Android SDK pieces Leitor needs into ~/.local/opt (no sudo).
set -euo pipefail

OPT="$HOME/.local/opt"
JDK="$OPT/jdk-21"
SDK="$OPT/android-sdk"
PLATFORM_TOOLS="$OPT/platform-tools"
TOOLS_ZIP=commandlinetools-linux-16111833_latest.zip
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OPT"
if [ ! -x "$PLATFORM_TOOLS/adb" ]; then
  curl -fL -o "$TMP/platform-tools.zip" \
    "https://dl.google.com/android/repository/platform-tools-latest-linux.zip"
  unzip -q "$TMP/platform-tools.zip" -d "$OPT"
fi

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

# This cmdline-tools build replaces sdkmanager with a newer "android" CLI
# that no longer reads from stdin for --licenses (it auto-accepts and exits
# immediately); the leftover `yes` then dies of SIGPIPE, which pipefail
# would otherwise treat as a failure of this no-op step.
yes | "$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" --licenses >/dev/null || true
"$SDK/cmdline-tools/latest/bin/sdkmanager" --sdk_root="$SDK" "platforms;android-15" "build-tools;34.0.0"

"$JDK/bin/javac" -version
ls "$SDK/platforms/android-15/android.jar" "$SDK/build-tools/34.0.0/aapt2"
