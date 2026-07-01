# UDQuakeTools

UDQuakeTools is a GNUstep/macOS toolkit for browsing and editing idTech archive formats.
The main GUI app is Pak Manager, and the repository also includes a small command-line utility and tests.

## Pak Manager

This app helps you manage pak/pk3/pk4 files.

![Mac OS X](Screenshots/pakmanager-mac.png)
![Linux / GNUstep](Screenshots/pakmanager-gs.png)

## Project Layout

- `Sources/PakManager`: GUI app (GNUstep + Cocoa/AppKit)
- `Sources/UDCore`: Format-agnostic archive domain model and editor logic
- `Sources/UDFormats`: Archive codecs (PAK, PK3, PK4, etc.)
- `Sources/Tools/udpaktool`: CLI utility target
- `Tests`: Unit tests
- `Scripts`: Build and packaging scripts (GNUstep stack, AppDir, AppImage)

## Prerequisites

### macOS (Xcode build)

- Xcode with command line tools

### GNUstep/Linux build

- clang / clang++
- cmake
- make
- git
- python3
- GNUstep dependencies required by your distro

## Build

### macOS (Xcode)

Open `PakManager.xcodeproj` and build the `Pak Manager` scheme.

### GNUstep stack and app

From the repository root:

```bash
./Scripts/build-gnustep.sh
APP_ID=PakManager APP_SOURCE_DIR=PakManager APP_BUNDLE_NAME=PakManager.app ./Scripts/prepare-appdir.sh
```

For Decl Browser:

```bash
APP_ID=DeclBrowser APP_SOURCE_DIR=DeclBrowser APP_BUNDLE_NAME=DeclBrowser.app ./Scripts/prepare-appdir.sh
```

## AppImage Packaging

From the repository root:

```bash
APP_ID=PakManager ./Scripts/package-appimage.sh
```

For Decl Browser:

```bash
APP_ID=DeclBrowser ./Scripts/package-appimage.sh
```

AppImage assets are tracked in `Scripts/appimage`.
Each deliverable is packaged into its own AppImage file:

- `PakManager-Linux-<version>.AppImage`
- `DeclBrowser-Linux-<version>.AppImage`

## Tests

Run tests using your active build system/scheme:

- Xcode: run the `UDQuakeToolsTests` target
- GNUstep: use the test makefile in `Tests/GNUmakefile`

## Notes

- Architecture notes: `ARCHITECTURE.md`
- Early interface stubs: `CLASS_STUBS.md`
- Doom 3 editor roadmap: `EDITOR_TOOLS_ROADMAP.md`
- License: `LICENSE`
