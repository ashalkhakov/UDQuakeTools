# UDQuakeTools

A GNUstep/macOS toolkit for browsing and editing idTech archive and decl
formats, shipped as one UDCode extension (`ashalkhakov.udquaketools`,
`UDQuakeTools.bundle`, docs/UDCODE.md): Quarry and Pak Manager have no app
of their own. UDCode (github.com/ashalkhakov/UDCodeKit, `../UDCodeKit-projects`)
is the window, the tabs, the text editor and the debugger; the extension is
the project (a folder with a `.qworkspace`), its `quarry:` file system, the
custom documents (decls as Core Data objects, GUIs, paks) and their editors,
idScript's language server (`udscript-lsp`) and debug adapter
(`udscript-dap`). The bundle builds against UDCode's SDK (the release
`.github/pins.env` names: in the prefix on GNUstep, `.deps/` on macOS) and
never carries it, nor GNUstep or FreeCoreData (the stack's): one copy of
each in UDCode's process. Archives need nothing beyond zlib: the minizip that
came with the Doom 3 file system port reads them, `UDZipWriter` writes them.
A release ships each platform's `.udcx` and UDCode with it in
(gnustep-release-actions, `.github/release/udcode.conf`).

## Layout

The libraries are `Sources/Libraries/<library>`, each its own (a GNUstep
library, an Xcode framework), bottom up: `UDIdLib`, `UDCommon` (the engine's
framework), `UDArchives` (with the codecs, `Formats/`), `UDImages`,
`UDDecls`, `UDRenderer`, `UDUI`, `UDGUIEditor`, `UDScripts`, `UDWorkspace`.
`Sources/Libraries/Libraries.make` says what each depends on, and a library
sees only its own headers and its dependencies' (Xcode: its target's header
search paths): nothing refers upward. Where a lower layer needs something of
a higher one, it declares a protocol the higher one adopts (`idFileAccess.h`,
`UDEngineSettings.h`, `idWindowEditorWrapper.h`), as the engine does. A new
library goes in `Libraries.make`, `Sources/Libraries/GNUmakefile` and the
Xcode project (a framework target, embedded in the bundle).

`Sources/Quarry` is the extension. `Extension/` is what UDCode calls
(`UQExtension`, the principal class; `UQProject`; the `UQ*Document` custom
documents; `UQEditorHost`, which puts a Quarry editor in a UDCode tab;
`UQCommands`, the Editor menu; `UQRunning`); Quarry's own parts are in
folders: `Model`, `Documents`, `Window`, `Editors`, `Editors/Decls`,
`Preview`, `GUIEditor`, `Scripts`, `Compat`. A new file goes in its part's
folder, in `Sources/Quarry/files.make` (the GNUmakefiles' lists) and in
the `UDQuakeTools` and `QuarryTests` targets' phases, which list the same
files. Imports name the header alone; its GNUmakefiles take its folders from
`Sources/Quarry/Quarry.include.make`. The UI is in XIBs, loaded from the
bundle (`[NSBundle bundleForClass:]`), never the main bundle: that is
UDCode's. A class name must not clash with UDCode's (the runtime aborts on a
duplicate): Quarry's workspace is `UDGameWorkspace` for that reason.

## GNUstep patches live elsewhere

This repository carries none. Anything new belongs in `../gnustep-patches`,
which this machine's GNUstep projects share — read its `CLAUDE.md` first:
reproduce in the docker container, fix, turn the reproduction into a test in
GNUstep's own suite, and push it there, which is where patches are kept and
sent upstream from.

## Testing

XCTest bundles, run on both systems:

- `Tests/<library>` — each library's unit tests (`UDCommonTests`,
  `UDArchivesTests`, ...; `Tests/LSPServerKit` too), sharing
  `Tests/Support` and `Tests/UnitTests.make`. A library's tests go in its
  bundle; a library without tests has none yet.
- `Tests/Extension` — what UDCode calls: the project, the provider, the
  custom documents, the editors' host.
- `Tests/Quarry` — the editors driven through the extension in
  `UQTestWindow` (a window standing in for UDCode's workbench). The PDA and
  pak cases build their own fixtures and run everywhere; the Doom 3 cases
  need a retail install at `$UD_DOOM3_PATH` (default
  `/Volumes/ExtraSSD/games/DOOM 3`) and check nothing without one. Never copy
  game data into fixtures; write original content instead.

GNUstep: `make && make check` from the root, in docker, under `xvfb-run -a`
(the root `GNUmakefile` adds it when there is no display). Mount the Doom 3
install read-only and set `UD_DOOM3_PATH` to include those cases. macOS:
`make -f Makefile.apple check`, or the `Libraries` and `QuarryTests`
schemes (the `UDQuakeTools` scheme builds the bundle).

Run a change on both systems before calling it done: they differ (bindings
rewrite placeholders on macOS, directory listing order differs, modal loops
need an event to notice `stopModal`).
