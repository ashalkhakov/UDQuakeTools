# Building UDQuakeTools

UDQuakeTools builds with Xcode on macOS and with GNUstep's make on Linux, and
CI does both on every push (`.github/workflows/build.yml`, with
[gnustep-release-actions](https://github.com/ashalkhakov/gnustep-release-actions)'
workflows). Archives need nothing beyond zlib on either system: the minizip
reader that came with the Doom 3 file system reads them, and `UDZipWriter`
writes them.

What a build takes from elsewhere is pinned in `.github/pins.env`:

- [UDCodeKit](https://github.com/ashalkhakov/UDCodeKit): Quarry's text
  editor, its tabs and the debugger's views, with its grammar bundles. It's
  unpacked into the GNUstep prefix on Linux and into `.deps/` on macOS.
- The patched GNUstep stack from
  [gnustep-patches](https://github.com/ashalkhakov/gnustep-patches), on Linux.
- [FreeCoreData](https://github.com/ashalkhakov/FreeCoreData), the Core Data
  that Quarry's decl layer is built on, on Linux.
- Sparkle, on macOS.

gnustep-release-actions' `scripts/deps.sh` fetches the pinned releases:
`deps.sh apple` for `.deps/`, `deps.sh linux` for the GNUstep prefix.

## macOS

With Xcode and its command line tools, and the frameworks in `.deps/`:

```sh
make -f Makefile.apple           # UDLauncher, Quarry, Pak Manager (Release)
make -f Makefile.apple check     # the unit tests and Quarry's
```

Or open `PakManager.xcodeproj` and build a scheme: `UDLauncher`, `Quarry`,
`Pak Manager` or `udpaktool`. The `Libraries` scheme runs the unit tests and
`QuarryTests` Quarry's.

## Linux (GNUstep)

The stack is the patched GNUstep the gnustep-patches release publishes (an
archive that unpacks into `/opt/gnustep`; its `Scripts/build-gnustep.sh`
builds the same on a machine of your own), with FreeCoreData and UDCodeKit
on it. Then:

```sh
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
make && make check && make install   # the libraries, the apps, the tools; the tests
```

`make check` runs under `xvfb-run` when there is no display.

FreeCoreData provides `momc` and `coredata-model.make`, which compile
`DeclModel.xcdatamodeld` into the apps' and test bundles' resources as Xcode
does. To build it yourself:

```sh
git clone https://github.com/ashalkhakov/FreeCoreData
cd FreeCoreData
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
make && sudo -E make install
```

## Tests

XCTest bundles, the same on both systems:

- `Tests/<library>`: each library's unit tests. They cover:
  - the archive codecs, and `UDZipWriter` against the Doom 3 reader;
  - the ported file system and decl manager, and the decl incremental store;
  - the GUI code and its editor;
  - the script index, the language server and the debug adapter, against a
    fake game.
- `Tests/Quarry`: Quarry, driven through its own windows. A workspace opens,
  rows are selected, fields are typed into, sheets are filled in and OKed,
  File > Save is sent, and then what was written and a freshly opened
  workspace are checked. Three kinds of case:
  - **PDA cases** run on a small loose fixture.
  - **Pak cases** run on a made-up install that the tests write themselves:
    two pk4s holding PDAs, emails, materials, a table, a skin, a GUI and a
    script, one overriding the other.
  - **Doom 3 cases** browse a retail install and edit `admin_moses` out of
    `pak000.pk4`. They read `$UD_DOOM3_PATH` (default
    `/Volumes/ExtraSSD/games/DOOM 3`), check that its `base/` comes out
    unchanged, and check nothing when there is no install, as on CI.

The tests never copy game data; their fixtures are written from scratch.

To include the Doom 3 cases in docker, mount the install read-only:

```sh
docker run --rm -v "$PWD:/src" -v "/path/to/DOOM 3:/doom3:ro" -e UD_DOOM3_PATH=/doom3 <image> \
  sh -c '. /opt/gnustep/System/Library/Makefiles/GNUstep.sh && cd /src && make && make check'
```

## The AppImage

`UDQuakeTools-<version>-x86_64.AppImage` is made by gnustep-release-actions'
`appimage` job, the same as every app's image. The launcher is its entry
point, and it also carries Quarry, Pak Manager, the libraries, FreeCoreData
and the GNUstep runtime. What is UDQuakeTools' own:

- `.github/release/appimage.conf`: what goes in, and the names that start each
  app (`… quarry`, `… pakmanager`);
- the desktop entry in `Scripts/appimage`;
- its smoke test, `Scripts/appimage-smoke.sh`.

CI makes and smoke-tests the image on every push, and a `v*` tag releases it
with update information, for Gear Lever, AppImageUpdate and AppImagePool.

## Releases

A `v*` tag releases everything: the AppImage, and the macOS apps zipped, with
the Sparkle appcasts the apps update from.
