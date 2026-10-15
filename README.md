# UDQuakeTools

UDQuakeTools is a GNUstep/macOS toolkit for browsing and editing idTech archives and
idTech 4 (Doom 3) decls, on the way to authoring whole mods (`ROADMAP.md`).
It ships as a single AppImage on Linux containing the launcher and Decl Browser,
and for macOS as UDLauncher, which updates itself (UDLauncher ▸ Check for
Updates…). Decl Browser builds and is tested on the Mac as well; archives
need nothing beyond zlib on either system (the minizip reader that came with
the Doom 3 file system reads them, UDZipWriter writes them).

## Applications

- **UDLauncher** — entry point: a simple window with buttons to launch the other tools
- **Pak Manager** — manage pak/pk3/pk4 archive files
- **Decl Browser** — browse, search and edit the decls of a Doom 3 install or mod
  (a structured PDA editor; the other decl types as text), saving overrides
- **udpaktool** — command-line listing and extraction of archives

## Project Layout

- `Sources/UDCore`: the Doom 3 file system and decl manager (ported), a Core Data layer over the decls, the workspace, and the archive model (built as `libUDCore`; `UDCore.framework` in Xcode)
- `Sources/UDFormats`: archive codecs — PAK, PAK2, Daikatana PAK, PK3, PK4 (compiled into UDCore)
- `Sources/UDLauncher`: Launcher application linking bundled tools
- `Sources/PakManager`: Pak Manager GUI app (GNUstep + Cocoa/AppKit)
- `Sources/DeclBrowser`: Decl Browser GUI app
- `Sources/Tools/udpaktool`: CLI utility target
- `Tests`: UDCore unit tests; `Tests/DeclBrowser`: tests driving the Decl Browser app
- `Scripts`: the AppImage desktop entry and smoke test (the build and packaging
  themselves are gnustep-release-actions')

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
  (`ADDITIONAL_NATIVE_LIBS += CoreData`). FreeCoreData also provides `momc` and
  `coredata-model.make`, which compile `DeclModel.xcdatamodeld` into the
  apps' and test bundles' resources as Xcode does.

## Build

### macOS (Xcode)

Open `PakManager.xcodeproj` and build the desired scheme (e.g. `Pak Manager`,
`Decl Browser`, `udpaktool` or `UDLauncher`), with Sparkle's XCFramework in
`.deps/` (gnustep-release-actions' `scripts/deps.sh apple` fetches the version
`.github/pins.env` names). What CI builds and checks there is
`Makefile.apple`: `make -f Makefile.apple`, `check`, `install`.

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

Two suites, on both systems:

- `Tests` — UDCore: the archive codecs (and `UDZipWriter` against the Doom 3
  reader), the ported file system and decl manager, the decl incremental
  store.
- `Tests/DeclBrowser` — Decl Browser, driven through its own windows: a
  workspace opens, the outline is expanded and a row selected, fields are
  typed into, the PDA editor's email sheet is filled in and OKed, File ▸
  Save is sent; then the decl file written and a freshly opened workspace
  are checked. The PDA cases run on a small loose fixture; the pak cases on
  a made-up install the tests write themselves (two pk4s holding PDAs,
  emails, materials, a table, a skin, a GUI and a script), covering the same
  ground as the Doom 3 cases on every machine, plus a later pak overriding an
  earlier one. The Doom 3 cases
  browse a retail install and edit `admin_moses` out of `pak000.pk4`; they
  read `$UD_DOOM3_PATH` (default `/Volumes/ExtraSSD/games/DOOM 3`), check
  that its `base/` comes out unchanged (saves go to a scratch `fs_savepath`),
  and check nothing when there is no install, as on CI.

Running them:

- macOS: `make -f Makefile.apple check`, or the `UDCore` (unit) and
  `DeclBrowserTests` schemes in Xcode.
- GNUstep: `make check` (under `xvfb-run` when there is no display), after
  `make`. To include the Doom 3 cases in docker, mount the install read-only
  and point at it:

  ```bash
  docker run --rm -v "$PWD:/src" -v "/path/to/DOOM 3:/doom3:ro" -e UD_DOOM3_PATH=/doom3 <image> \
    sh -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh && cd /src && make && make check'
  ```

## Notes

- Roadmap and todo list: `ROADMAP.md`
- License: GPL-3.0-or-later (`LICENSE`). UDCore's idFileSystem, idDeclManager,
  lexer and parser are ported from the Doom 3 GPL source (via openQ4), which
  is GPLv3 with id Software's additional terms; see the headers of those files.

