#!/bin/bash
set -euo pipefail

appdir=${1:-AppDir}

find_first_elf() {
    local name="$1"
    find "$appdir" -type f -name "$name" -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1; exit}'
}

main_bin=$(find_first_elf PakManager || true)
if [ -n "${main_bin:-}" ]; then
    printf '%s\n' "$main_bin"
fi

for tool in gdnc gpbs make_services; do
    if [ -f "$appdir/usr/lib/$tool" ]; then
        printf '%s\n' "$appdir/usr/lib/$tool"
    fi
done

find "$appdir/usr" -path '*/Bundles/*' -type f -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1}'
find "$appdir/usr" -path '*/Themes/*' -type f -exec file {} \; 2>/dev/null | awk -F: '/ELF/{print $1}'
