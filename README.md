# UDQuakeTools

UDQuakeTools is a GNUstep/macOS toolkit for browsing and editing idTech archive formats.
It ships as a single AppImage on Linux containing a launcher and all tools.

## Applications

- **UDLauncher** — entry point: a simple window with buttons to launch the other tools
- **Pak Manager** — manage pak/pk3/pk4 archive files
- **Decl Browser** — browse and inspect DOOM 3 / Quake 4 declaration files
- **GUI Editor** — GUI script editor for idTech 4-style GUI definitions

## Project Layout

- `Sources/UDCore`: Foundation-only domain model, editor logic and archive codecs — PAK, PK3, PK4, … (built as `libUDCore`)
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
- [FreeCoreData](https://github.com/ashalkhakov/FreeCoreData) — the CoreData
  implementation for GNUstep. The decl editing layer (UDDeclIncrementalStore
  and the decl entity classes in UDCore) is built on CoreData, so FreeCoreData
  **must be installed before building UDCore**:

  ```bash
  git clone https://github.com/ashalkhakov/FreeCoreData
  cd FreeCoreData
  . /usr/share/GNUstep/Makefiles/GNUstep.sh
  make && sudo make install
  ```

  The makefiles link it as the `CoreData` framework
  (`ADDITIONAL_NATIVE_LIBS += CoreData`). Note that there is no `momc` on
  GNUstep: `DeclModel.xcdatamodeld` is bundled uncompiled with the apps and
  FreeCoreData reads the model XML directly at runtime.

## Build

### macOS (Xcode)

Open `PakManager.xcodeproj` and build the desired scheme (e.g. `Pak Manager`,
`Decl Browser`, `GuiEd`, or `UDLauncher`).

### GNUstep stack and apps

The stack is the patched GNUstep every app here builds on, the release
[gnustep-patches](https://github.com/ashalkhakov/gnustep-patches) publishes
and `.github/pins.env` names (an archive that unpacks into `/opt/gnustep`; its
`Scripts/build-gnustep.sh` builds the same on a machine of your own), with
FreeCoreData's release on it (gnustep-release-actions' `scripts/deps.sh
linux` unpacks both). Then:

```bash
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
make && make check && make install   # UDCore, the launcher, Decl Browser; the tests
```

## AppImage Packaging

`UDQuakeTools-<version>-x86_64.AppImage` is made by
[gnustep-release-actions](https://github.com/ashalkhakov/gnustep-release-actions)'
`appimage`, the same as every app's image: the launcher (UDLauncher) as the
entry point, Decl Browser, UDCore, FreeCoreData and the GNUstep runtime. What
is UDQuakeTools' own is `.github/release/appimage.conf` (what `make install`
put in the prefix goes in it) and its smoke test, `Scripts/appimage-smoke.sh`;
the desktop entry is in `Scripts/appimage`. CI makes and
smoke-tests it on every push (`.github/workflows/build.yml`); a `v*` tag
releases it, with update information.

## Tests

Run tests using your active build system/scheme:

- Xcode: run the `UDQuakeToolsTests` target
- GNUstep: `cd Tests && make run-tests`
  (requires the UDCore library to be installed first)

## Notes

- Architecture notes: `ARCHITECTURE.md`
- Early interface stubs: `CLASS_STUBS.md`
- Doom 3 editor roadmap: `EDITOR_TOOLS_ROADMAP.md`
- License: `LICENSE`

