# UDQuakeTools

[![Build](https://github.com/ashalkhakov/UDQuakeTools/actions/workflows/build.yml/badge.svg)](https://github.com/ashalkhakov/UDQuakeTools/actions/workflows/build.yml)

The tools to make a Doom 3 mod, for **macOS, Linux and Windows**. Quarry opens a game
install or a mod, finds every declaration in it, loose or inside its paks,
and edits them in editors of their own: materials lit as the game lights
them, particles and FX playing as the game plays them, GUIs that run and
can be laid out on a canvas. Scripts are written with completion and debugged
in a running game. What you change is saved into your mod, and the game's own
files are left as they are.

The editors are the ones id shipped with Doom 3 (the Windows-only MFC tools in
`neo/tools`), rebuilt in Objective-C and AppKit. Where the engine's code
decides how something looks or behaves, that code is ported, so a material,
particle or GUI looks and runs in the editor as it does in the game.

| | macOS | Linux (GNUstep) |
|---|:---:|:---:|
| The main menu in the GUI editor's design | ![The GUI editor on macOS](Screenshots/quarry-gui-macos.png) | ![The GUI editor on GNUstep](Screenshots/quarry-gui-gnustep.png) |
| A material, lit as the game lights it | ![The material editor on macOS](Screenshots/quarry-material-macos.png) | ![The material editor on GNUstep](Screenshots/quarry-material-gnustep.png) |
| A particle system playing | ![The particle editor on macOS](Screenshots/quarry-particle-macos.png) | ![The particle editor on GNUstep](Screenshots/quarry-particle-gnustep.png) |

![The script debugger, stopped in Mars City](Screenshots/quarry-debugger-gnustep.png)
*The script debugger, stopped at a breakpoint as Mars City starts, `self` opened (Linux).*

## Get it

Download from [Releases](https://github.com/ashalkhakov/UDQuakeTools/releases/latest):

| Platform | Download | |
|---|---|---|
| macOS | `UDLauncher-macOS-*.zip` | The launcher, which opens the other apps; updates itself (UDLauncher > Check for Updates…) |
| macOS | `DeclBrowser-macOS-*.zip`, `PakManager-macOS-*.zip` | Quarry and Pak Manager on their own |
| Linux x86_64 | `UDQuakeTools-*-x86_64.AppImage` | The launcher, Quarry, Pak Manager and the command-line tools in one file; updated by Gear Lever, AppImageUpdate or AppImagePool |
| Windows x64 | `UDQuakeTools-*-win64.msi` | The launcher, Quarry and Pak Manager, installed for you alone (no administrator needed), with a Start menu shortcut to the launcher; a newer installer replaces the version before it |
| Windows x64 | `UDQuakeTools-*-win64-portable.zip` | The same, without installing: unzip it anywhere and run `UDQuakeTools.exe` |

The macOS apps aren't notarized yet. If macOS says an app is damaged, clear
its quarantine once after unzipping:

```sh
xattr -dr com.apple.quarantine UDLauncher.app
```

The AppImage is built on Ubuntu 22.04, so it needs glibc 2.35 or later and a
desktop's usual libraries (fontconfig, X11, OpenGL). CI tests it on Ubuntu,
and it also runs on Fedora 42, which Bazzite is built on. Where there's no
FUSE, `./UDQuakeTools-*.AppImage --appimage-extract-and-run` runs it anyway.

The Windows installer isn't signed yet. If SmartScreen says it
protected your PC, choose **More info**, then **Run anyway**. There are no
automatic updates on Windows yet: install the newer release over the old one.

Every push also uploads builds to its [Actions run](https://github.com/ashalkhakov/UDQuakeTools/actions).
To build from source, see [Building](docs/building.md).

## What's in it

| App | What it's for |
|---|---|
| **Quarry** | Browse, search and edit a game's or mod's declarations, GUIs and scripts, and debug the scripts |
| **Pak Manager** | Open, extract and make archives: Quake's PAK, Daikatana's PAK, PAK2, PK3 and PK4 |
| **UDLauncher** | Opens the others |
| `udpaktool` | Lists and extracts archives from the command line |
| `udscript-lsp`, `udscript-dap` | idScript's language server and debug adapter, which Quarry starts for itself |

| Pak Manager on macOS | Pak Manager on Linux (GNUstep) |
|---|---|
| ![Pak Manager on macOS](Screenshots/pakmanager-mac.png) | ![Pak Manager on GNUstep](Screenshots/pakmanager-gs.png) |

## What Quarry does

- **A workspace over a game.** Open Doom 3, Resurrection of Evil or a mod
  folder. Quarry reads the game's paks as the engine does, a later pak
  overriding an earlier one, and lists every declaration, GUI and script
  in one outline you can filter and search. An edit is saved to your mod's
  folder (`fs_savepath`), never into the paks.
- **An editor for each declaration type**, each with its own Issues tab
  listing what the game wouldn't find or would refuse:
  - **Materials:** keywords and stages, with a preview of the material on a
    square lit as the game's ARB2 interaction pass lights it.
  - **Particles and FX:** every stage parameter, with the system playing in
    a preview as the engine plays it.
  - **Articulated figures:** bodies and constraints, the joints taken from the
    model.
  - **entityDefs and mapDefs:** what they inherit and override.
  - **PDAs** with their emails, audio logs and videos, plus sound shaders,
    skins and tables.

  Anything else opens as highlighted text with Test Declaration. A
  declaration is written back the way the engine wrote it, untouched text
  byte for byte.
- **A GUI editor.** The `.gui` runs on the game's clock, its scripts and
  events working and the mouse and keys going to it, so the main menu or a
  PDA is fully interactive. In Design mode, windows are selected, moved and
  sized on a canvas with handles and a grid. A timeline takes the GUI to
  any moment, and the windows' properties and scripts are edited in
  inspectors.
- **A script editor and debugger.** `.script` files get highlighting, parse
  errors as you type, completion of events and functions with their
  arguments, help on hover, and Jump to Definition across the mod. Run starts
  the game with your breakpoints set, and when it stops you get:
  - the threads and their call stacks;
  - the variables, with `self` opening to its fields;
  - expressions in watches, hovers and the console;
  - conditional breakpoints and logpoints;
  - step over, into and out, and Run to Cursor.

  See [Debugging scripts](docs/debugging.md).
- **Pickers and an expression editor.** Wherever a name is typed (a
  material, image, table, sound, model, skin, entityDef or font) a picker
  lists what the game has, at once even for a retail install's 13,000
  materials and images. A material's registers and a GUI's conditions open
  in an expression editor, checked as the engine parses them.

## Limitations

- **Doom 3 and its expansion only.** Quake 4 and other idTech 4 games are on
  the roadmap. Pak Manager opens archives from Quake, Quake II, Quake III and
  Daikatana, but Quarry edits only Doom 3's declarations.
- **No 3D previews and no map editing yet.** Models, lights and articulated
  figures in motion need a running engine, through a planned edit bridge.
  Maps are DarkRadiant's job.
- **The full script debugger needs our fork of dhewm3**
  ([ashalkhakov/dhewm3](https://github.com/ashalkhakov/dhewm3)): a dhewm3 for
  mod authoring, kept up to date with dhewm3. Stock dhewm3 1.5.5 can be
  debugged too, but without stopping at script errors, other threads'
  variables, entities' spawn args, setting variables or jumping.
- **On Linux and Windows** the apps run on GNUstep, patched by
  [gnustep-patches](https://github.com/ashalkhakov/gnustep-patches) until the
  fixes are upstream; the AppImage and the installer carry it.

The plan, editor by editor: [ROADMAP.md](ROADMAP.md).

## Layout

| Path | What |
|---|---|
| `Sources/Libraries/` | The libraries, bottom up: `UDIdLib` (idLib, ported), `UDCommon` (the engine's file system and decl manager, ported), `UDArchives`, `UDImages`, `UDDecls`, `UDRenderer`, `UDUI` (the GUI code, ported), `UDGUIEditor`, `UDScripts`, `UDWorkspace` |
| `Sources/Quarry/` | Quarry, in folders by part: `App`, `Model`, `Documents`, `Window`, `Editors`, `Preview`, `GUIEditor`, `Scripts` |
| `Sources/PakManager/`, `Sources/UDLauncher/` | Pak Manager and the launcher |
| `Sources/LSPServerKit/`, `Sources/Tools/` | The language-server framework; `udpaktool`, `udscript-lsp`, `udscript-dap` |
| `tree-sitter-iddecl/`, `tree-sitter-idscript/` | The grammars Quarry's editors highlight with |
| `Tests/` | Each library's unit tests; `Tests/Quarry` drives Quarry through its own windows |
| `docs/` | Building, testing, debugging scripts |
| `.github/release/` | What the AppImage and the Windows installer carry |

Quarry's text editor, its tabs and its debugger views come from
[UDCodeKit](https://github.com/ashalkhakov/UDCodeKit).

## Documentation

- [Building](docs/building.md): Xcode, make on GNUstep (Linux, and Windows in
  MSYS2), the tests, the AppImage and the Windows installer
- [Debugging scripts](docs/debugging.md): setting up a game to debug, what
  works with stock dhewm3 and with our fork
- [Roadmap](ROADMAP.md): every editor, done and to do

## License

GPL 3.0 or later (`LICENSE`). The code ported from Doom 3 (idLib, the file
system, the decl manager, the GUI code, the parsers and the renderer's
passes) comes from the Doom 3 GPL source, which is GPLv3 with id Software's
additional terms; see those files' headers.
