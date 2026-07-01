#!/bin/bash
set -euo pipefail

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="/opt/gnustep-prefix"
APP_ID="${APP_ID:-PakManager}"

# 1. Copy tracked AppImage metadata/runtime assets into AppDir.
"${WORKSPACE_DIR}/Scripts/appimage/install-assets.sh" "${WORKSPACE_DIR}" "AppDir" "${APP_ID}"

# 3. Gather executable inputs for linuxdeploy.
mapfile -t ELF_BINS < <("${WORKSPACE_DIR}/Scripts/appimage/collect-elf-binaries.sh" "AppDir" "${APP_ID}")
ELF_ARGS=()
for bin in "${ELF_BINS[@]}"; do
    ELF_ARGS+=(--executable "$bin")
done

# 4. Run the linuxdeploy process.
export OUTPUT="${APP_ID}-Linux-${APP_VERSION:-dev}.AppImage"
export APPIMAGE_EXTRACT_AND_RUN=1
export NO_VALIDATE=1

LD_LIBRARY_PATH="${LOCAL_PREFIX}/System/Library/Libraries:${LOCAL_PREFIX}/Local/Library/Libraries:${WORKSPACE_DIR}/AppDir/usr/lib:${LD_LIBRARY_PATH:-}" \
    /usr/local/lib/linuxdeploy/AppRun --appdir AppDir "${ELF_ARGS[@]}" --output appimage
