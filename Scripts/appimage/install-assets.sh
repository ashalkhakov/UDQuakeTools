#!/bin/bash
set -euo pipefail

workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}
app_id=${3:-${APP_ID:-UDQuakeTools}}

case "$app_id" in
	UDQuakeTools)
		app_display_name="UDQuakeTools"
		app_bundle_id="com.udquake.launcher"
		app_source_dir="UDLauncher"
		;;
	PakManager)
		app_display_name="Pak Manager"
		app_bundle_id="com.udquake.pakmanager"
		app_source_dir="PakManager"
		;;
	DeclBrowser)
		app_display_name="Decl Browser"
		app_bundle_id="com.udquake.declbrowser"
		app_source_dir="DeclBrowser"
		;;
    GuiEd)
        app_display_name="GUI Editor"
        app_bundle_id="com.udquake.guied"
        app_source_dir="GuiEd"
        ;;
	*)
		echo "Error: unsupported APP_ID '$app_id'"
		exit 1
		;;
esac

app_id_lower=$(echo "$app_id" | tr '[:upper:]' '[:lower:]')

mkdir -p "$appdir"

cat > "$appdir/${app_id}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${app_display_name}
Exec=AppRun
Icon=${app_id}
Categories=Utility;
Terminal=false
X-UDQT-AppId=${app_id}
X-UDQT-BundleId=${app_bundle_id}
EOF

# Emit the common GNUstep environment setup portion of AppRun.
cat > "$appdir/AppRun" <<'APPRUN_HEADER'
#!/bin/sh
set -eu

HERE="$(dirname "$(readlink -f "$0")")"

# Write runtime GNUstep config to a private temp file.
export GNUSTEP_CONFIG_FILE="/tmp/GNUstep-udquaketools-$$.conf"
cat << IN_EOF > "$GNUSTEP_CONFIG_FILE"
GNUSTEP_USER_CONFIG_FILE=.GNUstep.conf
GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults
GNUSTEP_SYSTEM_USERS_DIR=/home
GNUSTEP_NETWORK_USERS_DIR=/home
GNUSTEP_LOCAL_USERS_DIR=/home
GNUSTEP_SYSTEM_ROOT=$HERE/usr/System
GNUSTEP_SYSTEM_LIBRARIES=$HERE/usr/System/Library
GNUSTEP_SYSTEM_LIBRARY=$HERE/usr/System/Library
GNUSTEP_SYSTEM_TOOLS=$HERE/usr/System/Tools
GNUSTEP_SYSTEM_APPS=$HERE/usr/System/Applications
GNUSTEP_LOCAL_ROOT=$HERE/usr/Local
GNUSTEP_LOCAL_LIBRARY=$HERE/usr/Local/Library
GNUSTEP_LOCAL_TOOLS=$HERE/usr/Local/Tools
GNUSTEP_LOCAL_APPS=$HERE/usr/Local/Applications
IN_EOF
chmod 600 "$GNUSTEP_CONFIG_FILE"

export GNUSTEP_SYSTEM_ROOT="$HERE/usr/System"
export GNUSTEP_SYSTEM_LIBRARY="$HERE/usr/System/Library"
export GNUSTEP_SYSTEM_TOOLS="$HERE/usr/System/Tools"
export GNUSTEP_SYSTEM_APPS="$HERE/usr/System/Applications"

export GNUSTEP_LOCAL_ROOT="$HERE/usr/Local"
export GNUSTEP_LOCAL_LIBRARY="$HERE/usr/Local/Library"
export GNUSTEP_LOCAL_TOOLS="$HERE/usr/Local/Tools"
export GNUSTEP_LOCAL_APPS="$HERE/usr/Local/Applications"

export LD_LIBRARY_PATH="$HERE/usr/lib:${LD_LIBRARY_PATH:-}"
export PATH="$HERE/usr/local/bin:$HERE/usr/bin:$PATH"

export FONTCONFIG_FILE="$HERE/usr/etc/fonts/fonts.conf"
export XDG_CACHE_HOME="/tmp/fc-cache-udquaketools-$$"
mkdir -p "$XDG_CACHE_HOME"

trap 'rm -rf "$XDG_CACHE_HOME" "$GNUSTEP_CONFIG_FILE"' EXIT

DEFAULTS_TOOL=$(find "$HERE" -name defaults -type f -perm -111 | head -n 1)
APPRUN_HEADER

# Replace the placeholder app-id in the generated AppRun temp-file names with
# the actual lowercase app id (e.g. 'pakmanager' for a PakManager-only image).
# For the default UDQuakeTools case app_id_lower is already 'udquaketools' so
# this sed call is a no-op.
sed -i "s/udquaketools/${app_id_lower}/g" "$appdir/AppRun"

# Emit the defaults-writing section and launcher. For UDQuakeTools, write
# defaults for every bundled app so they all look consistent.
if [ "$app_id" = "UDQuakeTools" ]; then
    cat >> "$appdir/AppRun" <<'APPRUN_DEFAULTS'
if [ -n "$DEFAULTS_TOOL" ]; then
	for BUNDLE_ID in "com.udquake.launcher" "com.udquake.pakmanager" "com.udquake.declbrowser" "com.udquake.guied"; do
		"$DEFAULTS_TOOL" write "$BUNDLE_ID" GSTheme Eau
		"$DEFAULTS_TOOL" write "$BUNDLE_ID" NSFont LiberationSans
		"$DEFAULTS_TOOL" write "$BUNDLE_ID" NSBoldFont LiberationSans-Bold
		"$DEFAULTS_TOOL" write "$BUNDLE_ID" NSUserFont LiberationSans
		"$DEFAULTS_TOOL" write "$BUNDLE_ID" NSUserFixedPitchFont LiberationMono
	done
fi

REAL_BIN=$(find "$HERE" -type f -name "UDLauncher" -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1; exit}')
if [ -z "$REAL_BIN" ]; then
	REAL_BIN="$HERE/usr/Local/Applications/UDLauncher.app/UDLauncher"
fi

exec "$REAL_BIN" "$@"
APPRUN_DEFAULTS
else
    # Per-app AppRun: write defaults only for this app's bundle ID.
    cat >> "$appdir/AppRun" <<EOF
if [ -n "\$DEFAULTS_TOOL" ]; then
	"\$DEFAULTS_TOOL" write "${app_bundle_id}" GSTheme Eau
	"\$DEFAULTS_TOOL" write "${app_bundle_id}" NSFont LiberationSans
	"\$DEFAULTS_TOOL" write "${app_bundle_id}" NSBoldFont LiberationSans-Bold
	"\$DEFAULTS_TOOL" write "${app_bundle_id}" NSUserFont LiberationSans
	"\$DEFAULTS_TOOL" write "${app_bundle_id}" NSUserFixedPitchFont LiberationMono
fi

REAL_BIN=\$(find "\$HERE" -type f -name "${app_id}" -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print \$1; exit}')
if [ -z "\$REAL_BIN" ]; then
	REAL_BIN="\$HERE/usr/Local/Applications/${app_id}.app/${app_id}"
fi

exec "\$REAL_BIN" "\$@"
EOF
fi
chmod +x "$appdir/AppRun"

mkdir -p "$appdir/usr/etc/fonts"
cp "$workspace_dir/Scripts/appimage/fonts.conf" "$appdir/usr/etc/fonts/fonts.conf"

# Copy app icon from source-controlled app resources, with a sane fallback.
if [ -f "$workspace_dir/Sources/${app_source_dir}/${app_id}.png" ]; then
	cp "$workspace_dir/Sources/${app_source_dir}/${app_id}.png" "$appdir/${app_id}.png"
else
	cp "$workspace_dir/Sources/PakManager/PakManager.png" "$appdir/${app_id}.png"
fi

