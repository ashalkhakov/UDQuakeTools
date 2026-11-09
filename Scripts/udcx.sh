#!/bin/bash
# UDCode's UDQuakeTools extension as a package (a .udcx, laid out as VS Code's
# .vsix: UDCode's docs/extensions.md), for this platform, from the tree as
# `make` built it:
#
#   Scripts/udcx.sh <version> <directory>   writes <directory>/udquaketools-<version>-<platform>.udcx
#
# On a Mac, from the Release build (make -f Makefile.apple), one for each of
# darwin-arm64 and darwin-x64 (the bundle is universal), signed with
# $CODESIGN_IDENTITY when it is set: UDCode loads only code its own team
# signed (UDCode's docs/extensions.md).
#
# extension/ holds package.json (its version <version>), UDQuakeTools.bundle
# with what it carries beside its binary (the libraries of Sources/Libraries,
# LSPServerKit, and the tools it starts: udscript-lsp, udscript-dap,
# udpaktool), and the licences: UDQuakeTools' (GPL-3.0) and DMTabBar's
# (MIT). What UDCode has itself (GNUstep, its Core Data, UDCodeKit) and the
# system's are left out: the running UDCode's are used.
set -euo pipefail
version=${1:?version}
out=${2:?directory}
root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root"

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) platform=linux-x64 ;;
  Linux:aarch64|Linux:arm64) platform=linux-arm64 ;;
  MINGW*:x86_64|MSYS*:x86_64) platform=win32-x64 ;;
  Darwin:*) platform=darwin ;;
  *) echo "udcx: no package for $(uname -s) $(uname -m)" >&2; exit 1 ;;
esac

if [ "$platform" = darwin ]; then
  bundle=${UDQUAKETOOLS_BUNDLE:-build/DerivedData/Build/Products/Release/UDQuakeTools.bundle}
else
  bundle=Sources/Quarry/UDQuakeTools.bundle
fi
[ -d "$bundle" ] || { echo "udcx: no $bundle: make builds it where UDCode's SDK is installed" >&2; exit 1; }
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ext=$stage/extension
mkdir -p "$ext/Licenses"
if [ "$platform" = darwin ]; then
  ditto "$bundle" "$ext/UDQuakeTools.bundle"
  if [ -n "${CODESIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --options runtime --deep --sign "$CODESIGN_IDENTITY" "$ext/UDQuakeTools.bundle"
  fi
else
  cp -R "$bundle" "$ext/UDQuakeTools.bundle"
  rm -f "$ext/UDQuakeTools.bundle/stamp.make"
  inside=$ext/UDQuakeTools.bundle

  # What it carries: what its binary and its tools link that the tree built
  # or the stack's Local domain holds, but UDCode's own.
  own='^(lib)?(gnustep-base|gnustep-gui|gnustep-corebase|objc|dispatch|BlocksRuntime|DiagramKit|UDCodeKit|UDPieceTable|LSPKit|CoreData)'
  dirs=$(ls -d "$root"/Sources/Libraries/*/obj "$root"/Sources/LSPServerKit/obj 2>/dev/null | tr '\n' ':')
  for var in GNUSTEP_LOCAL_LIBRARIES GNUSTEP_SYSTEM_LIBRARIES; do
    dir=$(gnustep-config --variable=$var 2>/dev/null || true)
    [ -n "$dir" ] && dirs="$dirs:$dir"
  done
  if [ "$platform" = win32-x64 ]; then
    binaries=$(ls "$inside"/*.dll "$inside"/*.exe 2>/dev/null)
  else
    binaries="$inside/UDQuakeTools $(ls "$inside"/udscript-lsp "$inside"/udscript-dap "$inside"/udpaktool 2>/dev/null)"
  fi
  for binary in $binaries; do
    if [ "$platform" = win32-x64 ]; then
      linked=$(PATH="$dirs:$PATH" ldd "$binary")
      carried=$(echo "$linked" | awk '{print $3}' | grep -iE "/GNUstep/Local/|^$root/|/Sources/" || true)
    else
      linked=$(LD_LIBRARY_PATH="$dirs${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ldd "$binary")
      carried=$(echo "$linked" | awk '$3 ~ /^\// {print $3}' | grep -E "/gnustep/Local/|^$root/" || true)
    fi
    if echo "$linked" | grep -v "api-ms-win-" | grep -q "not found"; then
      echo "udcx: what $(basename "$binary") links is not all found:" >&2
      echo "$linked" | grep -v "api-ms-win-" | grep "not found" >&2
      exit 1
    fi
    for lib in $carried; do
      name=$(basename "$lib")
      if echo "$name" | grep -qE "$own"; then continue; fi
      [ -e "$inside/$name" ] && continue
      cp -L "$lib" "$inside/$name"
      echo "udcx: carries $name"
    done
  done

  # On Linux each carried library, and each tool, finds the others beside it,
  # as the bundle's binary does: a runpath is only its own file's.
  if [ "$platform" != win32-x64 ]; then
    command -v patchelf >/dev/null || { echo "udcx: patchelf is needed (apt install patchelf)" >&2; exit 1; }
    for file in "$inside"/lib*.so* "$inside"/udscript-lsp "$inside"/udscript-dap "$inside"/udpaktool; do
      [ -e "$file" ] && patchelf --set-rpath '$ORIGIN' "$file"
    done
  fi
fi

sed "s/\"version\": \"0.0.0\"/\"version\": \"$version\"/" UDCodeExtension/package.json > "$ext/package.json"
cp LICENSE "$ext/LICENSE"
cp Sources/Quarry/ThirdParty/README.md "$ext/Licenses/ThirdParty.md"

mkdir -p "$out"
targets=$platform
[ "$platform" = darwin ] && targets="darwin-arm64 darwin-x64"
for target in $targets; do
  cat > "$stage/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="udquaketools" Version="$version" Publisher="ashalkhakov" TargetPlatform="$target"/>
    <DisplayName>UDQuakeTools</DisplayName>
    <Description xml:space="preserve">Doom 3 mods in UDCode: Quarry and Pak Manager</Description>
    <License>extension/LICENSE</License>
  </Metadata>
  <Installation><InstallationTarget Id="UDCode"/></Installation>
</PackageManifest>
XML
  package=$(cd "$out" && pwd)/udquaketools-$version-$target.udcx
  rm -f "$package"
  (cd "$stage" && if command -v zip >/dev/null; then zip -qry "$package" extension extension.vsixmanifest;
    else python3 -m zipfile -c "$package" extension extension.vsixmanifest; fi)
  echo "udcx: $package"
done
