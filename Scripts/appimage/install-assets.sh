#!/bin/bash
set -euo pipefail

workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}

mkdir -p "$appdir"
cp "$workspace_dir/Scripts/appimage/PakManager.desktop" "$appdir/PakManager.desktop"
cp "$workspace_dir/Scripts/appimage/AppRun" "$appdir/AppRun"
chmod +x "$appdir/AppRun"

mkdir -p "$appdir/usr/etc/fonts"
cp "$workspace_dir/Scripts/appimage/fonts.conf" "$appdir/usr/etc/fonts/fonts.conf"

# Keep a tiny placeholder icon for linuxdeploy metadata checks.
python3 -c "open('$appdir/PakManager.png', 'wb').write(bytes.fromhex('89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000a49444154789cc3070000020001737501170000000049454e44ae426082'))" || true
