# Building UDQuakeTools

UDQuakeTools is a UDCode extension, `UDQuakeTools.bundle` ([UDCode](UDCODE.md)),
with the libraries and tools it carries. It builds with Xcode on macOS and with GNUstep's make on Linux and
on Windows (in MSYS2's CLANG64 environment), and CI builds and tests all
three on every push (`.github/workflows/build.yml`, with
[gnustep-release-actions](https://github.com/ashalkhakov/gnustep-release-actions)'
workflows). Archives need nothing beyond zlib on any of them: the minizip
reader that came with the Doom 3 file system reads them, and `UDZipWriter`
writes them.

What a build takes from elsewhere is pinned in `.github/pins.env`:

- UDCode's SDK ([UDCodeKit](https://github.com/ashalkhakov/UDCodeKit)'s
  `udcodekit` archives: UDCodeKit, UDPieceTable, LSPKit), which the
  extension builds against and the running UDCode provides; `UDCODEKIT_VERSION`,
  the UDCode its `package.json`'s `engines` names. It's unpacked into the
  GNUstep prefix on Linux and Windows, and into `.deps/` on macOS.
- The patched GNUstep stack from
  [gnustep-patches](https://github.com/ashalkhakov/gnustep-patches), on Linux
  and Windows, the one that UDCode release builds on. It carries
  [FreeCoreData](https://github.com/ashalkhakov/FreeCoreData), the Core Data
  that Quarry's decl layer is built on, with its `momc` and
  `coredata-model.make`.
- On Windows, the DiagramKit that UDCode release carries, which its SDK links.

gnustep-release-actions' `scripts/deps.sh` fetches the pinned releases:
`deps.sh apple` for `.deps/`, `deps.sh linux` for the GNUstep prefix
(`/opt/gnustep`), `deps.sh windows` for Windows' (`C:\GNUstep`).

## macOS

With Xcode and its command line tools, and the frameworks in `.deps/`:

```sh
make -f Makefile.apple           # UDQuakeTools.bundle (Release, universal)
make -f Makefile.apple check     # the unit tests, the extension's and Quarry's
make -f Makefile.apple install DESTDIR=<dir> && make -f Makefile.apple installcheck DESTDIR=<dir>
Scripts/udcx.sh <version> <dir>  # the bundle as darwin-arm64 and darwin-x64 .udcx
```

Or open `PakManager.xcodeproj` and build a scheme: `UDQuakeTools` (the
bundle) or `udpaktool`. The `Libraries` scheme runs the unit tests and
`QuarryTests` the extension's and Quarry's. The bundle links UDCode's SDK
from `.deps/` and embeds none of it.

To try it, install the package into a UDCode
(`UDCode --install-extension <package>.udcx`) signed by the same team as
the bundle: `CODESIGN_IDENTITY` signs it in `udcx.sh`.

## Linux (GNUstep)

The stack is the patched GNUstep the gnustep-patches release publishes (an
archive that unpacks into `/opt/gnustep`; its `Scripts/build-gnustep.sh`
builds the same on a machine of your own), FreeCoreData in it, with
UDCode's SDK on it. Then:

```sh
. /opt/gnustep/System/Library/Makefiles/GNUstep.sh
make && make check && make install   # the libraries, the tools, the extension; the tests
Scripts/udcx.sh <version> <dir>      # Sources/Quarry/UDQuakeTools.bundle as a linux-x64 .udcx
```

`make check` runs under `xvfb-run` when there is no display. FreeCoreData's
`momc` and `coredata-model.make` compile `DeclModel.xcdatamodeld` into the
bundle's and the test bundles' resources as Xcode does.

## Windows (MSYS2)

The same make, in an MSYS2 CLANG64 shell, on the stack's Windows archive,
which unpacks into `C:\GNUstep` with FreeCoreData and UDCodeKit beside it.
The stack lists the MSYS2 packages building on it takes in
`C:\GNUstep\share\gnustep-patches\packages-msys2.txt` (CLANG64's, installed
with pacman); UDQuakeTools adds `sqlite3` and `zlib`. Then:

```sh
. /c/GNUstep/System/Library/Makefiles/GNUstep.sh
export PATH=/c/GNUstep/bin:$PATH     # the stack's DLLs, for the tools and the tests
make && make check
```

What differs between the systems is in a folder of each beside the shared
sources (`posix/`, `windows/`), which `Libraries.make`'s `UD_SYSTEM_DIR`
chooses: the debugger's socket, the crash reporter, the language tools'
standard streams.

## Tests

XCTest bundles, the same on every system:

- `Tests/<library>`: each library's unit tests. They cover:
  - the archive codecs, and `UDZipWriter` against the Doom 3 reader;
  - the ported file system and decl manager, and the decl incremental store;
  - the GUI code and its editor;
  - the script index, the language server and the debug adapter, against a
    fake game.
- `Tests/Extension`: what UDCode calls: the project and its tree, the file
  system provider, the custom documents (their undo, text, save and revert),
  the editors' host and the Editor menu.
- `Tests/Quarry`: the editors, driven through the extension in
  `UQTestWindow`, a window standing in for UDCode's. A workspace opens, rows
  are selected, fields are typed into, sheets are filled in and OKed, Save
  is sent, and then what was written and a freshly opened workspace are
  checked. Three kinds of case:
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

## Packages

`Scripts/udcx.sh` makes this platform's `.udcx` from what `make` built: the
bundle, the libraries of `Sources/Libraries` and LSPServerKit, the tools, and
the licences, leaving out what UDCode has itself. gnustep-release-actions
runs it on each platform (`.github/release/udcode.conf`) and writes the
feeds UDCode updates the extension from beside the packages.

The same `udcode.conf` names `UDCODE_PACKAGE`: gnustep-release-actions'
`scripts/udcode-package.sh` puts the packages into UDCode's own release
packages (the release `UDCODEKIT_VERSION` names), which install it the first
time they start:

- `UDCode-UDQuakeTools-macOS-<version>.zip`, the app signed again and
  notarized on a release;
- `UDCode-UDQuakeTools-<version>-x86_64.AppImage`, with update information on
  a release, for Gear Lever, AppImageUpdate and AppImagePool;
- `UDCode-UDQuakeTools-<version>-win64-portable.zip`.

## Screenshots

The README's screenshots are of UDCode with the extension, opened on a retail
Doom 3 install's folder (one with a `.qworkspace`). The extension sets each
scene up when the environment asks, once the game has started:

| Variable | What it does |
|---|---|
| `UQ_OPEN` | URLs separated by spaces, each opened in a tab, the last in front: `quarry:/material/textures/base_wall/lfwall27d`, `quarry:/particle/flamejet`, `quarry:/file/guis/mainmenu.gui`, a pak's `file:` URL (`DOOM%203`, not `DOOM 3`). The Decls navigator is shown, and the front editor's first inspector |
| `UQ_INSPECTOR` | That inspector instead, by its title (`Stage` for the particle) |
| `UQ_GUI_DESIGN` | A named event: the GUI editor in Design, the event sent (`NoIntro`: the menu, not its intro's black), two seconds into its time |

Then the window alone is captured: on macOS `screencapture -o -l <window id>`;
on GNUstep under a virtual display (`xvfb-run -a -s "-screen 0 1600x1000x24"`,
then `import -window <id>`); on Windows in a logged-on desktop session (a
scheduled task with `/IT`, not over SSH, which has no desktop), the window's
part of the screen.

## Releases

A `v*` tag releases everything: each platform's `.udcx` and its feed, and
UDCode with the extension for each platform. The version is the tag's,
stamped into `package.json` by `udcx.sh`.
