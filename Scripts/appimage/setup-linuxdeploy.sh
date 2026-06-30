#!/bin/bash
set -euo pipefail

# If the patched linuxdeploy is already there (from cache/artifact), do nothing
if [ -d "squashfs-root" ]; then
    echo "Linuxdeploy already provisioned. Skipping download."
    exit 0
fi

wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget -q https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage
chmod +x linuxdeploy*.AppImage

./linuxdeploy-x86_64.AppImage --appimage-extract >/dev/null 2>&1

# Replace the problematic strip utility used inside linuxdeploy.
printf '#!/bin/sh\nexit 0\n' > squashfs-root/usr/bin/strip
chmod +x squashfs-root/usr/bin/strip
