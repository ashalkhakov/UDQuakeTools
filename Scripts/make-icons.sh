#!/bin/sh
# The apps' icons, from Scripts/icons/<App>.svg: each app's asset catalog
# (macOS) and <App>.png (GNUstep, the AppImage), and the Windows installer's,
# which is Pak Manager's. Run it after changing one and
# commit what it writes; it needs rsvg-convert.
set -e
cd "$(dirname "$0")/.."
for app in PakManager Quarry UDLauncher; do
    svg="Scripts/icons/$app.svg"
    catalog="Sources/$app/Assets.xcassets"
    set_dir="$catalog/AppIcon.appiconset"
    mkdir -p "$set_dir"
    [ -f "$catalog/Contents.json" ] || printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' > "$catalog/Contents.json"
    images=""
    for size in 16 32 128 256 512; do
        for scale in 1 2; do
            file="icon_${size}x${size}@${scale}x.png"
            rsvg-convert -w $((size * scale)) -h $((size * scale)) "$svg" -o "$set_dir/$file"
            images="$images    {\n      \"filename\" : \"$file\",\n      \"idiom\" : \"mac\",\n      \"scale\" : \"${scale}x\",\n      \"size\" : \"${size}x${size}\"\n    },\n"
        done
    done
    printf '{\n  "images" : [\n%b  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' "$(printf '%s' "$images" | sed '$ s/},\\n$/}\\n/')" > "$set_dir/Contents.json"
    rsvg-convert -w 512 -h 512 "$svg" -o "Sources/$app/$app.png"
done
rsvg-convert -w 256 -h 256 Scripts/icons/PakManager.svg -o Scripts/windows/UDQuakeTools.png
