#!/usr/bin/env bash
# Applies one action to every package listed in a file.
source "$(dirname "$0")/lib.sh"

action="${1:?uso: apply-packages.sh <uninstall|disable|enable> <arquivo>}"
file="${2:?uso: apply-packages.sh <uninstall|disable|enable> <arquivo>}"
require_device

grep -v -E '^\s*(#|$)' "$file" | while read -r pkg; do
  case "$action" in
    uninstall) result=$("$ADB" uninstall "$pkg" </dev/null | tr -d '\r') ;;
    disable|enable) result=$("$ADB" shell "pm $action $pkg" </dev/null | tr -d '\r') ;;
    *) die "ação inválida: $action" ;;
  esac
  echo "$pkg: $result"
  case "$result" in
    *Success*|*"new state"*) ;;
    *) die "$action falhou para $pkg" ;;
  esac
done
