#!/usr/bin/env bash
# Installs KOReader v2023.06 (last release for Android 4.0) and points it at Livros/.
source "$(dirname "$0")/lib.sh"

VERSION=v2023.06
APK_URL="https://github.com/koreader/koreader/releases/download/$VERSION/koreader-android-arm-$VERSION.apk"
APK_SIZE=32648511
APK_SHA256=ae0effe42763938981514349acba3c5eae22b37d855933e6251ed51c41ff8adc
PKG=org.koreader.launcher
ACTIVITY=.MainActivity
CACHE="$HOME/.cache/foston-leitor"
SETTINGS=/mnt/sdcard/koreader/settings.reader.lua

require_device
mkdir -p "$CACHE"
apk="$CACHE/koreader-$VERSION.apk"
if [ ! -f "$apk" ]; then
  curl -fL -o "$apk.part" "$APK_URL"
  mv "$apk.part" "$apk"
fi
[ "$(stat -c %s "$apk")" -eq "$APK_SIZE" ] || die "APK com tamanho inesperado"
[ "$(sha256sum "$apk" | cut -d' ' -f1)" = "$APK_SHA256" ] || die "APK: sha256 não confere"

install_out="$("$ADB" install -r "$apk" </dev/null | tr -d '\r')"
echo "$install_out" | grep -q Success || die "adb install falhou"

sdcard_mount
"$ADB" shell "mkdir -p /mnt/sdcard/Livros" </dev/null
curl -fsSL -o "$CACHE/alice.epub" https://www.gutenberg.org/ebooks/11.epub.noimages
curl -fsSL -o "$CACHE/exemplo.pdf" https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf
"$ADB" push "$CACHE/alice.epub" /mnt/sdcard/Livros/alice.epub </dev/null
"$ADB" push "$CACHE/exemplo.pdf" /mnt/sdcard/Livros/exemplo.pdf </dev/null

# First start creates /mnt/sdcard/koreader and its settings file.
# Note: toolbox `ls` on a missing path prints "<path>: No such file or
# directory", which itself contains the substring "settings.reader.lua" and
# would false-positive a plain `grep -q settings.reader.lua`. Use `test -f`.
settings_exists() {
  [ "$("$ADB" shell "test -f $SETTINGS && echo YES || echo NO" </dev/null | tr -d '\r')" = YES ]
}

if ! settings_exists; then
  start_out="$("$ADB" shell "am start -n $PKG/$ACTIVITY" </dev/null | tr -d '\r')"
  echo "$start_out" | grep -q 'Error' \
    && die "am start falhou para $PKG/$ACTIVITY — rode: $ADB shell pm dump $PKG (sem grep; filtre \"MAIN\" no PC) para achar a Activity correta"
  for _ in $(seq 1 60); do
    settings_exists && break
    sleep 2
  done
  settings_exists || die "settings.reader.lua nunca apareceu — pode ser necessário abrir o KOReader manualmente e aceitar o diálogo inicial, depois rodar o script de novo"
fi
"$ADB" shell "am force-stop $PKG" </dev/null
sleep 2

"$ADB" pull "$SETTINGS" "$CACHE/settings.reader.lua" </dev/null
if ! grep -q '"home_dir"' "$CACHE/settings.reader.lua"; then
  sed -i 's|^return {|return {\n    ["home_dir"] = "/mnt/sdcard/Livros",|' "$CACHE/settings.reader.lua"
  "$ADB" push "$CACHE/settings.reader.lua" "$SETTINGS" </dev/null
fi
settings_out="$("$ADB" shell "cat $SETTINGS" </dev/null | tr -d '\r')"
echo "$settings_out" | grep -q '"/mnt/sdcard/Livros"' || die "home_dir não gravado"

# Wi-Fi stays off until the user turns it on in Configurações.
"$ADB" shell "svc wifi disable" </dev/null
echo "KOReader $VERSION instalado"
