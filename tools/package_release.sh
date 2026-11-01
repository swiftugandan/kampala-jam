#!/usr/bin/env bash
# Zips the exports in build/ into build/release/, ready to attach to a GitHub release.
set -eu
cd "$(dirname "$0")/.."
rm -rf build/release; mkdir -p build/release
cp build/android/KampalaJam.apk build/release/kampala-jam-android.apk
cp build/macos/KampalaJam.zip build/release/kampala-jam-macos.zip
(cd build/windows && zip -q -9 ../release/kampala-jam-windows.zip KampalaJam.exe)
(cd build/linux && zip -q -9 ../release/kampala-jam-linux.zip KampalaJam.x86_64)
(cd build/web && zip -q -9 -r ../release/kampala-jam-web.zip . -x '.gdignore')
(cd build/release && shasum -a 256 kampala-jam-* > SHA256SUMS.txt)
ls -la build/release | awk 'NR>3{printf "%6.1f MB  %s\n",$5/1e6,$NF}'
