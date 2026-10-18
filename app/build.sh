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
# -Xlint:-options: silences the "source/target 8 is obsolete" notices from
#   running a JDK 21 javac at --release 8, so output stays clean.
# -parameters: javac always emits a MethodParameters attribute for an inner
#   class's synthetic outer-instance constructor parameter; without this
#   flag that entry has no name, which crashes d8/r8 (NullPointerException:
#   "<parameter1>" is null, reproduced with both build-tools 34.0.0 and
#   33.0.3). Naming the parameter avoids the crash.
javac -Xlint:-options -parameters --release 8 -classpath "$ANDROID_JAR" -d "$B/classes" \
  $(find "$APP/src" "$B/gen" -name '*.java')
[ -f "$B/classes/br/com/luan/leitor/MainActivity.class" ] || { echo "javac falhou" >&2; exit 1; }
"$BT/d8" --min-api 15 --lib "$ANDROID_JAR" --output "$B/dex" \
  $(find "$B/classes" -name '*.class')
(cd "$B/dex" && zip -q "$B/unsigned.apk" classes.dex)

# 4. Align and sign (v1 signature is what Android 4.0 checks).
# keytool prints its "gerando par de chaves..." banner to stderr (locale-
# dependent), so redirect both streams to keep first-run output pristine too.
[ -f "$KEYSTORE" ] || keytool -genkeypair -keystore "$KEYSTORE" -storepass android \
  -keypass android -alias leitor -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Leitor" >/dev/null 2>&1
"$BT/zipalign" -f -p 4 "$B/unsigned.apk" "$B/aligned.apk"
"$BT/apksigner" sign --ks "$KEYSTORE" --ks-pass pass:android \
  --v1-signing-enabled true --out "$B/leitor.apk" "$B/aligned.apk"
"$BT/apksigner" verify --min-sdk-version 15 "$B/leitor.apk"
echo "ok: $B/leitor.apk"
