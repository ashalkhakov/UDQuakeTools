# UDQuakeTools

A GNUstep/macOS toolkit for browsing and editing idTech archive and decl
formats. On Linux it ships as one AppImage (the launcher and Decl Browser);
on macOS as UDLauncher. Archives need nothing beyond zlib: the minizip that
came with the Doom 3 file system port reads them, `UDZipWriter` writes them.
Decl Browser's text editor and tab bar are UDCodeKit's (`../UDPieceTable`,
github.com/ashalkhakov/UDCodeKit), with its grammar bundles (idScript for
`.script`) in the app's PlugIns; the release `.github/pins.env` names is
unpacked into the prefix on GNUstep and into `.deps/` on macOS.

## GNUstep patches live elsewhere

This repository carries none. Anything new belongs in `../gnustep-patches`,
which this machine's GNUstep projects share — read its `CLAUDE.md` first:
reproduce in the docker container, fix, turn the reproduction into a test in
GNUstep's own suite, and push it there, which is where patches are kept and
sent upstream from.

## Testing

Two XCTest suites, run on both systems:

- `Tests` — UDCore (codecs, the ported file system and decl manager, the
  decl incremental store).
- `Tests/DeclBrowser` — the app driven through its own windows. The PDA and
  pak cases build their own fixtures and run everywhere; the Doom 3 cases
  need a retail install at `$UD_DOOM3_PATH` (default
  `/Volumes/ExtraSSD/games/DOOM 3`) and check nothing without one. Never copy
  game data into fixtures; write original content instead.

GNUstep: `make && make check` from the root, in docker, under `xvfb-run -a`
(the root `GNUmakefile` adds it when there is no display). Mount the Doom 3
install read-only and set `UD_DOOM3_PATH` to include those cases. macOS:
`make -f Makefile.apple check`, or the `UDCore` and `DeclBrowserTests`
schemes.

Run a change on both systems before calling it done: they differ (bindings
rewrite placeholders on macOS, directory listing order differs, modal loops
need an event to notice `stopModal`).
