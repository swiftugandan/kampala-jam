#!/usr/bin/env bash
# Builds every platform into build/. Android is release-signed when the key file
# (kept outside the repo) exists; otherwise it falls back to a debug signature.
# Usage: bash tools/export_all.sh [Web macOS Windows Linux Android]
set -u
cd "$(dirname "$0")/.."
PRESETS=("$@")
[ ${#PRESETS[@]} -eq 0 ] && PRESETS=(Web macOS Windows Linux Android)
godot --headless --path . --import >/dev/null 2>&1
status=0
for preset in "${PRESETS[@]}"; do
  case "$preset" in
    Web) out=build/web/index.html ;;
    macOS) out=build/macos/KampalaJam.zip ;;
    Windows) out=build/windows/KampalaJam.exe ;;
    Linux) out=build/linux/KampalaJam.x86_64 ;;
    Android) out=build/android/KampalaJam.apk ;;
    *) echo "unknown preset $preset"; exit 2 ;;
  esac
  mkdir -p "$(dirname "$out")"
  KEY_ENV="$HOME/.android/keystores/kampala-jam-release.env"
  if [ "$preset" = Android ] && [ ! -f "$KEY_ENV" ]; then
    godot --headless --path . --export-debug "$preset" "$out" 2>&1 | grep -E 'ERROR|error:|No export' | head -8
  elif [ "$preset" = Android ]; then
    ( set -a; . "$KEY_ENV"; set +a; godot --headless --path . --export-release "$preset" "$out" 2>&1 | grep -E 'ERROR|error:|No export' | head -8 )
  else
    godot --headless --path . --export-release "$preset" "$out" 2>&1 | grep -E 'ERROR|error:|No export' | head -8
  fi
  if [ -s "$out" ]; then echo "ok  $preset  $(du -sh "$(dirname "$out")" | cut -f1)  $out"; else echo "FAILED $preset"; status=1; fi
done
exit $status
