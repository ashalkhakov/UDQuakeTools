#!/bin/bash
set -euo pipefail

workspace_dir=${1:-$(pwd)}
appdir=${2:-AppDir}
app_id=${3:-${APP_ID:-PakManager}}

case "$app_id" in
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
	*)
		echo "Error: unsupported APP_ID '$app_id'"
		exit 1
		;;
esac

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

cat > "$appdir/AppRun" <<EOF
#!/bin/sh
set -eu

HERE="\$(dirname "\$(readlink -f "\$0")")"
APP_ID="${app_id}"
APP_BUNDLE_ID="${app_bundle_id}"

# Write runtime GNUstep config to a private temp file.
export GNUSTEP_CONFIG_FILE="/tmp/GNUstep-\${APP_ID}-\$\$.conf"
cat << IN_EOF > "\$GNUSTEP_CONFIG_FILE"
GNUSTEP_USER_CONFIG_FILE=.GNUstep.conf
GNUSTEP_USER_DEFAULTS_DIR=GNUstep/Defaults
GNUSTEP_SYSTEM_USERS_DIR=/home
GNUSTEP_NETWORK_USERS_DIR=/home
GNUSTEP_LOCAL_USERS_DIR=/home
GNUSTEP_SYSTEM_ROOT=\$HERE/usr/System
GNUSTEP_SYSTEM_LIBRARIES=\$HERE/usr/System/Library
GNUSTEP_SYSTEM_LIBRARY=\$HERE/usr/System/Library
GNUSTEP_SYSTEM_TOOLS=\$HERE/usr/System/Tools
GNUSTEP_SYSTEM_APPS=\$HERE/usr/System/Applications
GNUSTEP_LOCAL_ROOT=\$HERE/usr/Local
GNUSTEP_LOCAL_LIBRARY=\$HERE/usr/Local/Library
GNUSTEP_LOCAL_TOOLS=\$HERE/usr/Local/Tools
GNUSTEP_LOCAL_APPS=\$HERE/usr/Local/Applications
IN_EOF
chmod 600 "\$GNUSTEP_CONFIG_FILE"

export GNUSTEP_SYSTEM_ROOT="\$HERE/usr/System"
export GNUSTEP_SYSTEM_LIBRARY="\$HERE/usr/System/Library"
export GNUSTEP_SYSTEM_TOOLS="\$HERE/usr/System/Tools"
export GNUSTEP_SYSTEM_APPS="\$HERE/usr/System/Applications"

export GNUSTEP_LOCAL_ROOT="\$HERE/usr/Local"
export GNUSTEP_LOCAL_LIBRARY="\$HERE/usr/Local/Library"
export GNUSTEP_LOCAL_TOOLS="\$HERE/usr/Local/Tools"
export GNUSTEP_LOCAL_APPS="\$HERE/usr/Local/Applications"

export LD_LIBRARY_PATH="\$HERE/usr/lib:\${LD_LIBRARY_PATH:-}"
export PATH="\$HERE/usr/local/bin:\$HERE/usr/bin:\$PATH"

export FONTCONFIG_FILE="\$HERE/usr/etc/fonts/fonts.conf"
export XDG_CACHE_HOME="/tmp/fc-cache-\${APP_ID}-\$\$"
mkdir -p "\$XDG_CACHE_HOME"

trap 'rm -rf "\$XDG_CACHE_HOME" "\$GNUSTEP_CONFIG_FILE"' EXIT

DEFAULTS_TOOL=\$(find "\$HERE" -name defaults -type f -perm -111 | head -n 1)
if [ -n "\$DEFAULTS_TOOL" ]; then
	"\$DEFAULTS_TOOL" write "\$APP_BUNDLE_ID" GSTheme Eau
	"\$DEFAULTS_TOOL" write "\$APP_BUNDLE_ID" NSFont LiberationSans
	"\$DEFAULTS_TOOL" write "\$APP_BUNDLE_ID" NSBoldFont LiberationSans-Bold
	"\$DEFAULTS_TOOL" write "\$APP_BUNDLE_ID" NSUserFont LiberationSans
	"\$DEFAULTS_TOOL" write "\$APP_BUNDLE_ID" NSUserFixedPitchFont LiberationMono
fi

REAL_BIN=\$(find "\$HERE" -type f -name "\$APP_ID" -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print \$1; exit}')
if [ -z "\$REAL_BIN" ]; then
	REAL_BIN="\$HERE/usr/Local/Applications/\$APP_ID.app/\$APP_ID"
fi

exec "\$REAL_BIN" "\$@"
EOF
chmod +x "$appdir/AppRun"

mkdir -p "$appdir/usr/etc/fonts"
cp "$workspace_dir/Scripts/appimage/fonts.conf" "$appdir/usr/etc/fonts/fonts.conf"

# Copy app icon from source-controlled app resources, with a sane fallback.
if [ -f "$workspace_dir/Sources/${app_source_dir}/${app_id}.png" ]; then
	cp "$workspace_dir/Sources/${app_source_dir}/${app_id}.png" "$appdir/${app_id}.png"
else
	cp "$workspace_dir/Sources/PakManager/PakManager.png" "$appdir/${app_id}.png"
fi
