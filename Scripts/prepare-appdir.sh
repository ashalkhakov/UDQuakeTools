#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

WORKSPACE_DIR=$(pwd)
LOCAL_PREFIX="/opt/gnustep-prefix"

# 1. Recreate clean AppDir structural root
rm -rf AppDir
mkdir -p AppDir/usr/bin
mkdir -p AppDir/usr/lib
mkdir -p AppDir/usr/etc
mkdir -p AppDir/usr/local/bin

# 2. Source GNUstep environment once
. "${LOCAL_PREFIX}/System/Library/Makefiles/GNUstep.sh"

# 3. Install each app into AppDir
for APP_SOURCE_DIR in UDLauncher DeclBrowser; do
    cd "Sources/${APP_SOURCE_DIR}"
    make install DESTDIR="${WORKSPACE_DIR}/AppDir"
    cd "${WORKSPACE_DIR}"
done

if [ -d "${LOCAL_PREFIX}/System/Library/Themes" ]; then
mkdir -p AppDir/usr/System/Library/Themes
cp -Rp "${LOCAL_PREFIX}/System/Library/Themes/"* AppDir/usr/System/Library/Themes/
fi

# 4. Dynamically locate the background tools
for tool in gdnc gpbs make_services; do
FOUND_TOOL=$(find "${LOCAL_PREFIX}" -type f -name "$tool" 2>/dev/null | head -n 1 || true)
if [ -n "$FOUND_TOOL" ]; then
    cp -p "$FOUND_TOOL" AppDir/usr/lib/
    cp -p "$FOUND_TOOL" AppDir/usr/local/bin/
fi
done

# 5. Pull BOTH System and Local hierarchies into AppDir/usr/
if [ -d "${LOCAL_PREFIX}/System" ]; then
mkdir -p AppDir/usr/System
cp -Rp "${LOCAL_PREFIX}/System/"* AppDir/usr/System/
fi
if [ -d "${LOCAL_PREFIX}/Local" ]; then
mkdir -p AppDir/usr/Local
cp -Rp "${LOCAL_PREFIX}/Local/"* AppDir/usr/Local/
fi

# Bundle libobjc from the prefix base lib directory
if [ -f "${LOCAL_PREFIX}/lib/libobjc.so.4.6" ]; then
cp -p "${LOCAL_PREFIX}/lib/libobjc.so.4.6" AppDir/usr/lib/
ln -sf libobjc.so.4.6 AppDir/usr/lib/libobjc.so.4
ln -sf libobjc.so.4.6 AppDir/usr/lib/libobjc.so
fi

# Bundle libdispatch and its BlocksRuntime dependency safely
echo "=== Manually staging libdispatch and BlocksRuntime ==="
if ls "${LOCAL_PREFIX}/lib"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
elif ls "${LOCAL_PREFIX}/lib64"/libdispatch.so* 1> /dev/null 2>&1; then
cp -p "${LOCAL_PREFIX}/lib64"/libdispatch.so* AppDir/usr/lib/
cp -p "${LOCAL_PREFIX}/lib64"/libBlocksRuntime.so* AppDir/usr/lib/ 2>/dev/null || true
fi

# Bundle OpenSSL 3 runtime libs for distro portability (e.g. AppImage on Bazzite)
echo "=== Manually staging OpenSSL 3 runtime libs ==="
for ssl_lib in libssl.so.3 libcrypto.so.3; do
    FOUND_SSL_LIB=""
    for search_dir in \
        "${LOCAL_PREFIX}/lib" \
        "${LOCAL_PREFIX}/lib64" \
        "/usr/lib" \
        "/usr/lib64" \
        "/usr/lib/x86_64-linux-gnu" \
        "/lib" \
        "/lib64" \
        "/lib/x86_64-linux-gnu"
    do
        if [ -f "${search_dir}/${ssl_lib}" ]; then
            FOUND_SSL_LIB="${search_dir}/${ssl_lib}"
            break
        fi
    done

    if [ -n "${FOUND_SSL_LIB}" ]; then
        cp -p "${FOUND_SSL_LIB}" AppDir/usr/lib/
    else
        echo "Warning: ${ssl_lib} was not found on build host; target systems must provide it."
    fi
done

# 6. Maintain versioned and unversioned fallback bundle linking
BACKEND_BUNDLE=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$BACKEND_BUNDLE" ]; then
BUNDLE_DIR=$(dirname "$BACKEND_BUNDLE")
BUNDLE_NAME=$(basename "$BACKEND_BUNDLE")
ln -sfv "$BUNDLE_NAME" "$BUNDLE_DIR/libgnustep-back.bundle" || true
ln -sfv "$BUNDLE_NAME" "$BUNDLE_DIR/back.bundle" || true
fi

# Migrate the nested app bundles safely
for APP_BUNDLE_NAME in UDLauncher.app DeclBrowser.app; do
    DEEP_APP_DIR=$(find AppDir -type d -name "${APP_BUNDLE_NAME}" 2>/dev/null | grep -v "usr/" | head -n 1 || true)
    if [ -n "$DEEP_APP_DIR" ]; then
        mkdir -p AppDir/usr/Local/Applications
        cp -Rp "$DEEP_APP_DIR" AppDir/usr/Local/Applications/
    fi
done

# --- BUNDLE FONTS FOR PORTABILITY ---
mkdir -p AppDir/usr/share/fonts/truetype/liberation
cp -Rp /usr/share/fonts/truetype/liberation/* AppDir/usr/share/fonts/truetype/liberation/

# Clean up residual folders
find AppDir -maxdepth 1 -type d ! -name "AppDir" ! -name "usr" -exec rm -rf {} + 2>/dev/null || true

# Repeat bundle link fix in case migration shifted the target
BACKEND_BUNDLE_TWO=$(find AppDir/usr -name "libgnustep-back-*.bundle" 2>/dev/null | head -n 1 || true)
if [ -n "$BACKEND_BUNDLE_TWO" ]; then
    BUNDLE_DIR=$(dirname "$BACKEND_BUNDLE_TWO")
    ln -sfv $(basename "$BACKEND_BUNDLE_TWO") "$BUNDLE_DIR/libgnustep-back.bundle" || true
fi

