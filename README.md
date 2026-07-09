# UDQuakeTools

UDQuakeTools is a GNUstep/macOS toolkit for browsing and editing idTech archive formats.
It ships as a single AppImage on Linux containing a launcher and all tools.

## Applications

- **UDLauncher** — entry point: a simple window with buttons to launch the other tools
- **Pak Manager** — manage pak/pk3/pk4 archive files
- **Decl Browser** — browse and inspect DOOM 3 / Quake 4 declaration files
- **GUI Editor** — GUI script editor for idTech 4-style GUI definitions

## Project Layout

- `Sources/UDCore`: Foundation-only domain model and editor logic (built as `libUDCore`)
- `Sources/UDFormats`: Archive codecs — PAK, PK3, PK4, … (built as `libUDFormats`)
- `Sources/UDLauncher`: Launcher application linking bundled tools
- `Sources/PakManager`: Pak Manager GUI app (GNUstep + Cocoa/AppKit)
- `Sources/DeclBrowser`: Decl Browser GUI app
- `Sources/GuiEd`: GUI Editor app
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

Open `PakManager.xcodeproj` and build the desired scheme (e.g. `Pak Manager`,
`Decl Browser`, `GuiEd`, or `UDLauncher`).

### GNUstep stack and apps

From the repository root (after running `./Scripts/build-gnustep.sh`):

```bash
# 1. Build and install shared libraries
cd Sources/UDCore   && make && make install && cd -
cd Sources/UDFormats && make && make install && cd -

# 2. Build all apps
for app in UDLauncher PakManager DeclBrowser GuiEd; do
    cd "Sources/$app" && make && cd -
done

# 3. Prepare the combined AppDir
./Scripts/prepare-appdir.sh
```

## AppImage Packaging

From the repository root (after building):

```bash
./Scripts/package-appimage.sh
```

This produces a single `UDQuakeTools-Linux-<version>.AppImage` that launches
UDLauncher as the entry point. The launcher lets users open any of the
bundled tools (Pak Manager, Decl Browser, GUI Editor).

AppImage assets are tracked in `Scripts/appimage`.

## Tests

Run tests using your active build system/scheme:

- Xcode: run the `UDQuakeToolsTests` target
- GNUstep: `cd Tests && make run-tests`
  (requires UDCore and UDFormats libraries to be installed first)

## Notes

- Architecture notes: `ARCHITECTURE.md`
- Early interface stubs: `CLASS_STUBS.md`
- Doom 3 editor roadmap: `EDITOR_TOOLS_ROADMAP.md`
- License: `LICENSE`

