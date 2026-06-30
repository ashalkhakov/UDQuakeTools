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

# Copy app icon from shared source-controlled app resources.
cp "$workspace_dir/Sources/PakManager/PakManager.png" "$appdir/PakManager.png"
