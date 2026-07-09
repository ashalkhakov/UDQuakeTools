#!/bin/bash
set -euo pipefail

appdir=${1:-AppDir}
app_id=${2:-${APP_ID:-UDQuakeTools}}

find_first_elf() {
    local name="$1"
    find "$appdir" -type f -name "$name" -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1; exit}'
}

if [ "$app_id" = "UDQuakeTools" ]; then
    # Collect all bundled app binaries for the consolidated AppImage.
    for bin_name in UDLauncher PakManager DeclBrowser GuiEd; do
        bin=$(find_first_elf "$bin_name" || true)
        if [ -n "${bin:-}" ]; then
            printf '%s\n' "$bin"
        fi
    done
else
    main_bin=$(find_first_elf "$app_id" || true)
    if [ -n "${main_bin:-}" ]; then
        printf '%s\n' "$main_bin"
    fi
fi

for tool in gdnc gpbs make_services; do
    if [ -f "$appdir/usr/lib/$tool" ]; then
        printf '%s\n' "$appdir/usr/lib/$tool"
    fi
done

find "$appdir/usr" -path '*/Bundles/*' -type f -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1}'
find "$appdir/usr" -path '*/Themes/*' -type f -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1}'

