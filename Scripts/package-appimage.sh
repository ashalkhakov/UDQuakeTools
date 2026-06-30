#!/bin/bash
set -euo pipefail

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="/opt/gnustep-prefix"

# 1. Copy tracked AppImage metadata/runtime assets into AppDir.
"${WORKSPACE_DIR}/Scripts/appimage/install-assets.sh" "${WORKSPACE_DIR}" "AppDir"

# 2. Download and patch linuxdeploy internals.
wget -q https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
wget -q https://github.com/linuxdeploy/linuxdeploy-plugin-appimage/releases/download/continuous/linuxdeploy-plugin-appimage-x86_64.AppImage
chmod +x linuxdeploy*.AppImage

#./linuxdeploy-x86_64.AppImage --appimage-extract >/dev/null 2>&1

# 3. Gather executable inputs for linuxdeploy.
mapfile -t ELF_BINS < <("${WORKSPACE_DIR}/Scripts/appimage/collect-elf-binaries.sh" "AppDir")
ELF_ARGS=()
for bin in "${ELF_BINS[@]}"; do
    ELF_ARGS+=(--executable "$bin")
done

# 4. Run the patched linuxdeploy process.
#export PATH="${WORKSPACE_DIR}/squashfs-root/usr/bin:$PATH"
export OUTPUT="PakManager-Linux-${APP_VERSION:-dev}.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1

LD_LIBRARY_PATH="${LOCAL_PREFIX}/System/Library/Libraries:${LOCAL_PREFIX}/Local/Library/Libraries:${WORKSPACE_DIR}/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
    ./linuxdeploy-x86_64.AppImage --appdir AppDir "${ELF_ARGS[@]}" --output appimage

# 5. Cleanup temporary linuxdeploy artifacts.
#rm -rf squashfs-root linuxdeploy*.AppImage
rm -rf linuxdeploy*.AppImage
