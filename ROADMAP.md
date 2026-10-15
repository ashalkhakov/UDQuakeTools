# UDQuakeTools roadmap

The goal: author an idTech 4 mod entirely in this toolkit — every decl, GUI and
script (maps through external tools), with the editors Doom 3 shipped (the MFC tools under
`neo/tools` in dhewm3) recreated in Objective-C/AppKit — on macOS, Linux and
Windows, and publish the result without leaving it.

What exists today (October 2026): Decl Browser (workspace over a game
install, outline/filter/search of every registered decl type, tabs, undo,
Save/Save All/Save As into `fs_savepath`), a structured PDA editor, raw text
editing for everything else, Pak Manager (PAK/PAK2/Daikatana/PK3/PK4), the
ported Doom 3 file system and decl manager with a Core Data layer over it,
and XCTest suites driving the apps on macOS and GNUstep in CI.

Reference material for every editor below: the MFC originals in dhewm3's
`neo/tools/<tool>` (layouts in `neo/sys/win32/rc/*.rc`) and the Dear ImGui
ports on the `tools-porting` branch of `../older-projects/dhewm3`, which have
already shed the Win32 code. Both are GPLv3, like this project.

## Decisions

These shape everything after them; each has a recommendation.

1. **Offline first.** Editors work on files through the ported file system
   and decl manager, with no engine in the process. PDA, Decl, Script,
   Table, Skin, entityDef, sound shader, particle, FX and AF *data* all edit
   this way, and so does the script debugger client (it is a UDP client).
2. **Live editing goes through a running engine, not an embedded one.** The
   Light, Sound, AF and Particle editors (and the shoot-to-edit flow) drive a
   running game through `idGameEdit`. Rather than link the engine into the
   apps, add an *edit bridge* to the dhewm3 fork, the same idea
   the script debugger already follows,: `idGameEdit` (plus reload
   and console commands) served over the same `idBitMsg`/UDP transport the
   script debugger already uses, with a client in UDCore. The editors stay
   portable, and the game stays the preview.
3. **2D previews in AppKit, 3D in the engine.** Materials get a 2D
   stage/image preview natively and a 3D one through the bridge. GUIs are
   2D, so they are drawn here, by dhewm3's own GUI code (`neo/ui`) ported
   to Objective-C with the render system replaced (see the GUI editor). A
   3D renderer of our own is the last resort, not the plan.
4. **No map editing here.** Maps are edited in DarkRadiant (GPL-2.0-or-
   later, wxWidgets, Windows/macOS/Linux; edits Doom 3 and Quake 4 maps) and
   compiled by an existing dmap (dhewm3's, or RBDOOM's `rbdmap`); this
   toolkit launches them on the workspace's paths and shows their results.
5. **Windows comes from gnustep-release-actions,** which is taking on the
   Windows build (MSYS2's GNUstep: clang64, gnustep-2.0 runtime, cairo back
   end). This repository stays portable and adopts it when it lands; little
   work here.
6. **A workspace becomes a mod project.** It knows its mod folder
   (`fs_game`, `fs_game_base`), writes into it, and carries a manifest
   (name, version, author, target engines). Publishing builds from that.

## 0. Housekeeping (from the October audit)

- [x] SPDX headers say `GPL-2.0-or-later` in 37 files, but `LICENSE` is GPLv3
      and the ported Doom 3 code is GPLv3 with id's additional terms: switch
      them to `GPL-3.0-or-later` and say so in the README.
- [x] Delete dead code: `UDDeclManager.{h,m}` and `UDDeclPersistence.{h,m}`
      (import the deleted VFS), `ObjectiveC2/blocks_runtime.h`, `idMath.h`,
      `Sources/GuiEd/GNUmakefile`, the empty GuiEd and QuakeEditor Xcode
      targets. (`.forgejo/` was never tracked.)
- [x] UDLauncher still offers "GUI Editor"; Decl Browser's menu still says
      "QuakeEditor" (bundle id `org.underivable.QuakeEditor`).
- [x] README: drop `ARCHITECTURE.md` / `CLASS_STUBS.md` links (missing), the
      GUI Editor entry, and the list of shared schemes that are not shared.
- [x] Bring Pak Manager and udpaktool into the root build and CI (they build
      against an installed UDCore today), and ship Pak Manager in the
      AppImage and on the Mac.
- [x] Ship Decl Browser on the Mac next to UDLauncher (libzip no longer
      blocks it): `Makefile.apple` `all`/`install`, the macos.yml `apps`.
- [x] `addScriptsToTree` drops the `.script` extension that `addGUIsToTree`
      keeps; check which one opening the item expects.


## 1. Blockers

Most of the platform already works (workspace, file system, decl manager,
Core Data layer, tabs, undo, save). Two gaps block the editors after it:

- [x] **Decl files are written the way Doom 3 writes them.** Still whole
      (a mod's file replaces the game's), but spliced like
      `idDeclLocal::ReplaceSourceFileText`: the file as last read is copied
      through and only changed decls are replaced, so other decls, their
      order, comments and blank lines come out byte for byte. Extends Doom 3
      to everything the editors batch between saves: renames (the name token
      only), removals (with the comment attached to the decl), moves, new
      decls (appended in creation order). Refuses to overwrite a file changed
      outside the editor. `Tests/idDeclFileWriteTests.m`.
- [ ] **Register the remaining Doom 3 decl types and folders** — commented
      out today: `entityDef`, `mapDef`, `model` (`def/*.def`), `sound`
      (`sound/*.sndshd`), `fx`, `articulatedFigure` (`af/*.af`),
      `materialType`, `playback`, `lipSync` — so their editors have something
      to open; a Core Data entity per type as its editor arrives.

## Grown with the editors that need them

Built when the first editor needs each one, not up front:

- Errors reach the user: the "TODO: throw" / "FIXME: error out" paths in
  idDeclManager swallow failures; parse errors become diagnostics on the decl.
- Reload on external change (watch the mod folder; prompt when a dirty tab is
  affected).
- Reference checking and a Problems panel (a PDA's emails exist, a material's
  images exist, an entityDef's `inherit` resolves).
- New / Delete / Duplicate / Rename decl in the browser (only Save As exists).
- Image loading through idFileSystem (TGA, DDS, JPG, PNG, inside pk4s) — the
  material, GUI and particle editors; the image viewer reads OS paths only.
- Sound playback through idFileSystem — the sound shader editor, PDA audio.
- An editor kit, the comafx/PropTree equivalent: property inspector driven
  by a per-type description (the MFC material editor reads
  `editors/material.def`), decl and file pickers, key/value table with
  inheritance, highlighting text editor, colour and vector widgets.
- Mod project: the workspace writes into the mod folder and carries a
  manifest (decision 6); a view of what the mod overrides.
- idFileSystem leaks idFile objects (`:5186`); the decl manager's
  `+shutdown` does not work (`:1020`).

## 2. Offline editors (no engine needed)

In order of value against cost; LOC is the MFC original's size.

- [ ] **PDA** (0.7k) — finish: video editor covered by tests, editing an
      existing email/audio/video (double-click opens the sheet; untested),
      reference validation, creating a new PDA with its file.
- [ ] **Decl editor** (3.2k) — highlighting, "test" re-parse with
      diagnostics, per-type templates for New.
- [ ] **Table** and **Skin** — small structured editors (values/clamp/snap;
      model and surface mappings) over the existing entities.
- [ ] **entityDef editor** — inherit chain, key/value table, spawnArg
      documentation from `editor_*` keys, model/skin/sound pickers.
- [ ] **Sound shader editor** — the decl side of the MFC sound editor:
      parameters, sample list, play.
- [ ] **Particle editor** (1.7k) — decl editing over the existing stage
      model (`UDParticleStage`): stages list, every stage parameter with
      sliders, material picker; a 2D animated preview is possible, the 3D
      one comes with the bridge.
- [ ] **FX editor** — fx actions (sound, light, particle, decal, model…).
- [ ] **AF editor** (8.1k) — bodies and constraints as data (the dialog
      pages map one-to-one to inspector sections); joints from the model's
      `.md5mesh`. Simulation preview comes with the bridge.
- [ ] **Material editor** (10.9k) — material tree by file, stage list
      (add bump/diffuse/specular, reorder, copy/paste), inspector driven by
      material keywords, source view kept in sync, 2D preview of stage
      images; 3D preview through the bridge.
- [ ] **GUI editor** (12.8k) — on a port of dhewm3's GUI code (`neo/ui`,
      20k: `idUserInterface`, `idWindow` and its item types, `idWinVar`, the
      GUI scripts) to Objective-C, in the style of the file system, parser
      and decl manager already ported in UDCore. The render system is
      replaced: `idDeviceContext` draws with AppKit, its images loaded
      through idFileSystem; a renderDef's 3D view comes through the bridge
      (4). The port interprets as well as draws: GUI scripts, named events,
      `onTime` timelines, transitions, mouse and keys run as in the game,
      so a GUI is fully interactive in the editor. Raven's editor only drew
      them, and its users named that as its main shortcoming. On the port: a
      canvas like a storyboard, the screens a GUI shows (and the GUIs it
      leads to) side by side with what moves between them, and
      move/size/align/group on it; navigator, inspector, state/event script
      editing, edits with undo.
- [ ] **Script editor** (0.9k) — `.script` editing with highlighting,
      completion of events and functions, go to definition across the mod.
      Done: the editor is UDCodeKit's, highlighting `.script` with its
      idScript grammar (a port of idCompiler's); and the helpers of the
      tools' script editor, ported: the events of doom_events.script after
      a '.', an event's parameters from its '(' to its ')', its help on
      Option-click. Left: go to definition across the mod.

## 3. Script debugger

The debugger speaks the Debug Adapter Protocol, so VS Code (and any DAP
client) debugs idScript, and so does this toolkit's own script editor,
through UDCodeKit.

- [ ] UDCodeKit is a DAP client with Xcode's debugger UI: breakpoints in the
      gutter, the debug bar (continue, step over/in/out), the debug navigator
      (threads and their call stacks), the variables view and the console.
      A grammar bundle brings its own debug adapter the way it brings its
      language server, as VS Code's extensions do, and the UI is the same
      for every language.
- [ ] Objective-C as a mode UDCode can be used for every day on GNUstep:
      its bundle brings an adapter over gdb or lldb (lldb-dap) alongside its
      language server (clangd), with build and run from the editor.
- [ ] idScript's bundle brings the adapter below, and Decl Browser debugs
      scripts with UDCodeKit's debugger UI.
- [ ] A DAP adapter for dhewm3's debugger protocol (UDP 27980/27981,
      `idBitMsg`, `DBMSG_*` — documented only by the source:
      `neo/tools/debugger/DebuggerMessages.h`, `DebuggerClient.cpp`):
      breakpoints, break/resume/step, call stack, threads, variables and
      watches, the console mirrored as output. `UDBitMsg` is already ported.
- [ ] Launch and attach configurations: start the game for debugging from
      the workspace (`+set fs_game … +set com_enableDebuggerServer 1`), or
      attach to one running.
- [ ] A VS Code extension packaging the adapter, with idScript syntax.

## 4. Live edit bridge (needs the dhewm3 fork)

- [ ] Engine side, in the fork: serve `idGameEdit` (entity selection,
      spawnArgs, map entities, AF spawn/update, player position), decl and
      GUI reload, console commands and console output over the debugger's
      transport; versioned messages; off unless a cvar enables it.
- [ ] UDCore client and a connection UI (launch or attach, status, log).
- [ ] Quick win before the full bridge: the debugger protocol already has
      `EXECCOMMAND` — use it for `reloadDecls`, `reloadGuis`, `map …` from
      the editors.
- [ ] **Light editor** (1k): the ImGui port's fields, applied live; save to
      the `.map`.
- [ ] **Sound editor** (1.3k): speakers in the running map, place/move,
      play, save.
- [ ] Live previews for the particle, AF and material editors; "show GUI in
      game".
- [ ] Shoot-to-edit (`g_editEntityMode`) opening the matching editor here.

## 5. Maps and the build pipeline (external tools)

- [ ] Launch DarkRadiant on a map with a game/project configuration
      generated from the workspace.
- [ ] Run dmap, AAS (`runAAS`) and `roq` through an existing build (a dhewm3
      binary, `+dmap <map> +quit`, or RBDOOM's `rbdmap`): progress, the leak
      `.lin`, errors in the Problems panel.
- [ ] A "build mod" command: compile what changed, then package (6).

## 6. Packaging and publishing

- [ ] Export the mod to pk4s (`UDZipWriter` and the PK4 codec are ready):
      choose loose vs packed, lowercase names, exclude work files,
      reproducible archives (fixed timestamps and order).
- [ ] Per-target layouts: dhewm3 (`<mod>/` beside `base/`, `fs_game_base
      d3xp` for RoE mods, game library naming if the mod has one), Doom 3
      retail (`description.txt`), openQ4 (`mod.json` with `name`, `version`,
      `releaseDate`, `website`, `author`, `requiredopenQ4Version`).
- [ ] Pre-publish checks: every reference resolves inside the mod or the
      base game, nothing ships from the base game's paks, sizes.
- [ ] A command-line front end (extend `udpaktool`, which only lists and
      extracts today) so CI can build and publish a mod.
- [ ] Publish targets:
  - GitHub Releases (REST API, token; the easiest to automate).
  - Nexus Mods (Upload API, API key; adds versions to an existing mod page,
    the first upload is by hand; there is an official GitHub Action).
  - ModDB has no upload API: produce the archive and the page text, upload
    by hand.
  - Steam Workshop has no Doom 3 or Quake 4 support, and mod.io has neither
    game; revisit if that changes.

## 7. Windows

- [ ] Adopt gnustep-release-actions' Windows build when it lands (the
      workflow and packaging live there).
- [ ] Keep this code portable meanwhile: Windows paths in idFileSystem
      (`c:` handling, `idFileSystem.m:1125`), no POSIX-only calls outside
      the ports' existing `#ifdef`s.

## 8. Quake 4 and openQ4

- [ ] A Quake 4 game type (`q4base` detection) and Raven's decl types
      (materialType, lipSync, playback, effect, playerModel), guides, and the
      matrix parse flag in idParser.
- [ ] Packed `.decls` files: the loader and writer exist but nothing calls
      them and nothing tests them.
- [ ] openQ4 mods: re-enable the `mod.json` manifest code (`#if 0` in
      `idFileSystem.m`) for reading and writing.

## Definition of done, per editor

- Open, edit, save, reopen round-trips the decl or file losslessly.
- Dirty state, undo and redo work, including across saves.
- Errors and broken references are shown before save.
- A test in `Tests/DeclBrowser` drives the editor through its own window on
  a fixture written for the test (never game data), on macOS and GNUstep.
