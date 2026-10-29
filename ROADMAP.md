# UDQuakeTools roadmap

The goal: author an idTech 4 mod entirely in this toolkit — every decl, GUI and
script (maps through external tools), with the editors Doom 3 shipped (the MFC tools under
`neo/tools` in dhewm3) recreated in Objective-C/AppKit — on macOS, Linux and
Windows, and publish the result without leaving it.

What exists today (October 2026): Quarry, a workspace over a game install
or mod (an outline, filter and search of every registered decl type, tabs,
undo, saving into `fs_savepath`), with a structured editor for each decl type
(PDA, material with its lit preview, particle and FX with theirs, AF,
entityDef, sound shader, skin, table), pickers and an expression editor, the
GUI editor (the GUI run on the game's clock, designed on a canvas), the script
editor over `udscript-lsp`, and the script debugger over `udscript-dap`; Pak
Manager (PAK/PAK2/Daikatana/PK3/PK4); the ported Doom 3 file system, decl
manager and GUI code with a Core Data layer over the decls; and XCTest suites
driving the apps on macOS and GNUstep in CI.

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
   script debugger already uses, with a client in the libraries. The editors stay
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
5. **Windows comes from gnustep-release-actions,** whose Windows build
   (MSYS2's GNUstep: clang64, gnustep-2.0 runtime) and installer this
   repository adopted in 0.6.0; what differs here is in each system's folder
   (`posix/`, `windows/`).
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
- [x] UDLauncher still offers "GUI Editor"; Quarry's menu still says
      "QuakeEditor" (bundle id `org.underivable.QuakeEditor`).
- [x] README: drop `ARCHITECTURE.md` / `CLASS_STUBS.md` links (missing), the
      GUI Editor entry, and the list of shared schemes that are not shared.
- [x] Bring Pak Manager and udpaktool into the root build and CI (they build
      against the installed libraries today), and ship Pak Manager in the
      AppImage and on the Mac.
- [x] Ship Quarry on the Mac next to UDLauncher (libzip no longer
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
- [x] **Register the remaining Doom 3 decl types and folders** — as
      dhewm3's `idDeclManagerLocal::Init` and `idGameLocal::Init` do:
      `sound` (`sound/*.sndshd`), `entityDef`, `mapDef`, `model`, `export`
      (`def/*.def`), `fx` (`fx/*.fx`), `articulatedFigure` (`af/*.af`), each
      folder listed alone as `ListFiles` does. Which decls a workspace has is
      its game's, a workspace setting (Doom 3's the only one so far). They
      open as text; a Core Data entity per type as its editor arrives.

## Grown with the editors that need them

Built when the first editor needs each one, not up front:

- Errors reach the user: the "TODO: throw" / "FIXME: error out" paths in
  idDeclManager swallow failures; parse errors become diagnostics on the decl.
- Reload on external change (watch the mod folder; prompt when a dirty tab is
  affected).
- Reference checking and a Problems panel (a PDA's emails exist, a material's
  images exist, an entityDef's `inherit` resolves).
- New / Delete / Duplicate / Rename decl in the browser (only Save As exists).
- A decl's source beside its structured editor — done: Editor | Source
  beside the tabs switches the PDA, table and skin editors to the decl's
  text and back, an edited text read into the decl as one undoable edit.
- A decl's text is its braced body: the decl manager is openQ4's, whose
  idDeclFile keeps the section after the name. Doom 3's keeps the
  `type name` header with it (`LoadAndParse`'s startMarker), so its
  editor showed and renamed through it.
- Lookup dialogs wherever a decl refers to another: see *Pickers and the
  expression editor* below.
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

## Pickers and the expression editor

Wherever an editor checks a reference (its Issues), it offers a picker for
it too; wherever a value may be an expression, an expression editor. Both
are ported and adapted from RDLKit and XFormsKit, which have them.

- [x] **A picker**: a sheet (modal, a sheet in Eau) with a table of the
      candidates and a quick filter by name (contains the text typed), the
      current value chosen; a button beside each field that takes a
      reference opens it.
- [x] Pickers wherever a reference is checked today:
      - material: a stage's map, cube map, video map; editor image; light
        falloff image (images and materials);
      - particle: a stage's material; its speed, rotation, size and aspect
        tables;
      - FX: an action's particle, model, decal and light materials, sound
        shader, entityDef, and the earlier actions it uses or fires;
      - AF: the modelDef and skin; a body's joint (the model's joints); a
        constraint's bodies;
      - skin: its materials; entityDef: its inherit and the decls its keys
        name;
      - GUI: a window's background, border and font; a script's windows and
        variables (set, transition, setFocus, resetTime), sounds and
        named events;
      - PDA: picked inline, as it owns its emails, audio logs and videos.
- [x] **An expression editor**: a field's expression in a larger editor
      with highlighting (the GUI's and the material's expression grammar),
      its tables, parms and variables offered, and checked as the engine
      parses it. For a material's registers (scroll, translate, scale,
      centerScale, shear, rotate, color, red, green, blue, alpha, rgb, rgba,
      alphaTest, if), checked by idMaterial::Parse; for a GUI's if
      conditions and variables, by idWindow::ParseExpression.
- [x] **At once**: the file pickers list from the paks' entries, read once
      (idFileSystem's `filesUnder:extensions:`), and the decl pickers from
      the decl manager's index, as the decl tree does: a retail install's
      13k materials and images in tens of milliseconds.
- [x] **Typed entry**: a material's texGen, sort and deform offer their
      keywords (and take arguments); its cube map and programs are picked;
      an entityDef's or mapDef's spawn arg is edited in the inspector as
      its type has it (its editor_* key's, else its name's, else its
      value's): a vector, a number, on or off, a colour, or a reference
      picked.

## 2. Offline editors (no engine needed)

In order of value against cost; LOC is the MFC original's size.

- [x] **PDA** (0.7k) — fields, emails, audio logs and videos added, edited
      (double-click) and taken off through their sheets, with undo; what the
      PDA references but no decl defines, as errors in the Issues tab before
      saving (a click shows the row); File > New PDA… makes one in a file of
      its own (`newpdas/<name>.pda`).
- [x] **Decl editor** (3.2k) — DialogDeclEditor and DialogDeclNew: a
      decl's text highlighted by a grammar of its own (`tree-sitter-iddecl`,
      LoadAndParse's shape over idLexer's tokens); Edit > Test Declaration,
      the braces and the lexer, then the decl's own parser over the text,
      into its Issues; File > New Declaration… with a type, a name and a
      file, the decl starting from its engine class's DefaultDefinition.
- [ ] Keywords from `editors/<type>.def`, as CSyntaxRichEditCtrl's
      LoadKeyWordsFromFile reads them (a colour and a description each).
      Neither Doom 3 nor Quake 4 ships them, so they are written here, from
      what each type's ported parser reads, with descriptions of our own —
      once the rest of the decls' editors (and so their parsers) are in.
- [x] **Table** and **Skin** — structured editors over the existing
      entities, patterned on the PDA's: a table's Snap and Clamp, its values
      in a list and the curve they make; a skin's mappings and models in
      lists, what it names that is not there in the Issues tab, File > New
      Skin…. Their codecs are the engine's parsers, ported.
- [x] **entityDef editor** — DialogEntityDefEditor's, for mapDefs too:
      what it inherits, its own spawnArgs in a list edited in place, what
      it inherits through the chain (resolved as idDeclEntityDef::Parse
      merges it) read-only and overridable; the entity's and the selected
      key's help from the `editor_*` keys, as Radiant's EClass_InitFromDict
      reads them; an unknown inherit and a key set twice in the Issues tab.
      Its model, skin and sound pickers come with the lookup dialogs.
- [x] **Sound shader editor** — idSoundShader::ParseShader ported (where
      it gives up, MakeDefault's values, as the engine has them; five retail
      shaders it gives up on): description and parameters (unset is the
      engine's default, shown), flags and speakers, samples and leadins in
      lists; a sample the engine plays its default sound for, and an alt
      sound no shader defines, in the Issues tab. Play comes with sound
      playback through idFileSystem (Doom 3's samples are Ogg Vorbis).
- [x] **Particle editor** (1.7k) — DialogParticleEditor's: the stages in a
      list (AddStage's default stage, or a copy with Option), the selected
      stage's every parameter with the dialog's sliders and their ranges,
      the depth hack; a material the engine makes a default of and a table
      no decl defines in the Issues tab. idDeclParticle's Parse and
      ParseParticleStage are ported again, directly (one retail particle
      they give up on: bfg_wallmark), and WriteStage writes it.
- [x] Particle preview: the system playing as the engine makes it
      (idRenderModelPrt::InstantiateDynamicModel, idParticleStage's
      CreateParticle and friends, GetStageBounds, idRandom, idMath's 16-bit
      trigonometry, ported), drawn as its ambient pass draws it
      (RB_STD_T_RenderShaderPasses' stages, the material's registers, ported;
      GL's texturing and blending done in software). The material picker
      comes with the lookup dialogs.
- [x] FX preview: idEntityFx's Setup, Start, Run, ApplyFade and CleanUp,
      ported and stepped at the game's frames; its particle systems in the
      particle preview, its actions on a timeline. Its lights and other
      models come with the bridge. Its lights light a wall behind it
      (the material preview's lit pass).
- [x] **FX editor** — idDeclFX::Parse and ParseSingleFXAction ported (every
      retail FX parses): the joint it binds to, its actions in a list, the
      selected action's every keyword; in the Issues tab, what the engine
      would not find (a material, a model of a type it does not load — 52
      retail actions name a .particle or .ips model — a particle, entityDef
      or sound, a light or model to use no earlier action names).
- [x] **AF editor** — idDeclAF's parser and writer ported (every retail
      figure parses and writes the same twice): settings, bodies and
      constraints, each with an inspector pane of its own (the selected
      body's or constraint's every keyword); + and − are NewBody/DeleteBody/NewConstraint/DeleteConstraint,
      and a body renamed renames it in its constraints. Joints come from the
      model's `.md5mesh`, found through its modelDef as idDeclModelDef::Parse
      finds it; in the Issues tab, what idAF::Load refuses (no body on the
      origin joint, no or a defaulted modelDef or model, a body on a joint
      the mesh lacks, a constraint on a body the figure lacks).
- [ ] **AF simulation preview** — comes with the bridge.
- [x] **Material editor** — Material.cpp's parse ported literally
      (idMaterial's state, expressions, EvaluateRegisters with
      idDeclTable::TableLookup): every retail material goes through it, the
      14 the engine itself defaults named. A material is its tokens as
      idLexer reads them, with the whitespace and comments before each
      (UDSourceTokens): written back, byte for byte; the parse says which
      tokens are which keyword and stage, and an edit puts tokens in,
      changes or takes them out. The editor: the material's keywords and
      flags; its stages (add, bump/diffuse/specular, reorder, copy/paste),
      each stage's keywords; a 2D preview of its image, as the renderer
      loads it (R_LoadImage's TGA/BMP/JPG, image programs); Issues from the
      parse and "Couldn't load image".
- [x] Material preview: the material on a square, lit by a point light as
      the ARB2 interaction pass lights it (RB_CreateSingleDrawInteractions,
      RB_ARB2_DrawInteraction, R_DeriveLightData's point light, the
      normalization cube map and specular table, ported; the game's own
      glprogs/interaction.vfp run by an ARB program interpreter that knows
      just what it uses), then its ambient stages; its time on a slider.
- [ ] **Material 3D preview** — on models, through the bridge.
- [x] **GUI editor** (12.8k) — on a port of dhewm3's GUI code (`neo/ui`,
      20k: `idUserInterface`, `idWindow` and its item types, `idWinVar`, the
      GUI scripts) to Objective-C, in the style of the file system, parser
      and decl manager already ported in the libraries. The render system is
      replaced: `idDeviceContext` draws into the GUI model, whose surfaces
      the software renderer draws as the ambient pass would, its images
      loaded through idFileSystem; a renderDef's 3D view comes through the
      bridge (4). The port is in (UDUI; every retail GUI loads and
      draws, the main menu and PDA as in the game), and so is the viewer:
      a .gui's tab runs it on the game's clock, drawn with GL (in software
      where there is none), the mouse and keys sent as the game sends them,
      its named events, its state and its log in the window's new
      inspector pane (Xcode's three panes, as RDLKit's designer has them).
      The editor is under way, on tools/guied ported: a GUI loaded for
      editing writes back as the engine's editor writes it (every retail
      GUI reads back the same), and a .gui's Design mode is its canvas —
      select (shift adds), move and size with the eight handles, snap to
      the grid, each drag one Undo; Source and Run follow its edits. The
      GUI's windows are a navigator in the left pane (a window's eye hides
      it in the design), and its Properties and Scripts are inspector
      panes, each edit one Undo; and the design's menu (the engine's popup)
      and keys make, delete, arrange, align, size alike, parent, nudge, copy
      and paste windows. Under the canvas is a video editor's transport:
      its time slider takes Run and Design alike to any time (the GUI run
      there, the named events sent on the way sent again), so the main
      menu, sent NoIntro, is designed as it shows at 2 s, not behind its
      black curtain.
      The rest of tools/guied is in too: its item properties dialog is the
      Properties pane (General, Image, Text, and the keys as Keys), its
      transformer the Layout pane (Xcode's Size inspector), its options a
      sheet kept with the workspace, its status bar (triangles, zoom) under
      the canvas, and its zoom levels (⌘-wheel, a pinch, the View menu).
      The port interprets as well as draws: GUI scripts, named events,
      `onTime` timelines, transitions, mouse and keys run as in the game,
      so a GUI is fully interactive in the editor. Raven's editor only drew
      them, and its users named that as its main shortcoming. On the port: a
      canvas like a storyboard, the screens a GUI shows (and the GUIs it
      leads to) side by side with what moves between them, and
      move/size/align/group on it; navigator, inspector, state/event script
      editing, edits with undo.
- [x] **Script editor** (0.9k) — `.script` editing with highlighting,
      completion of events and functions, go to definition across the mod.
      UDCodeKit's editor with its idScript grammar (a port of idCompiler's,
      its parse errors in the Issues tab), and the old tools' helpers over a
      language server of our own (`udscript-lsp`, on LSPServerKit): names
      complete as they are typed, calls with their arguments as
      placeholders; an event's parameters from its '(' to its ')'; help on
      hover; Jump to Definition across the mod (v0.2.0).

## 3. Script debugger

The debugger speaks the Debug Adapter Protocol, and this toolkit's own script
editor is its client, through UDCodeKit (no VS Code extension: the idScript
bundle brings the adapter as it brings the language server).

- [x] UDCodeKit is a DAP client with Xcode's debugger UI: breakpoints in the
      gutter, the debug bar (continue, step over/in/out), the debug navigator
      (threads and their call stacks), the variables view and the console.
      A grammar bundle brings its own debug adapter the way it brings its
      language server, and the UI is the same for every language (UDCodeKit
      0.4.0 to 0.6.1).
- [ ] **Next:** a simple C and Objective-C IDE for GNUstep, UDCode used
      every day: boot it up, open a project, build, run, debug and change
      it. Objective-C as a mode whose bundle brings an adapter over gdb or
      lldb (lldb-dap) alongside its language server (clangd), with build
      and run from the editor. Not live coding: editing, building and
      debugging a GNUstep project.
- [x] Quarry debugs scripts with UDCodeKit's debugger UI (UDScriptDebugger):
      Debug > Run starts the workspace's game (Workspace Settings > Debugging:
      its executable and arguments), Attach a running one; breakpoints in the
      script tabs' gutters (a pak's script named where it would be in the
      mod's folder, as the adapter names it), the debug navigator tab, the
      debug bar and area under the editors (UDCodeKit 0.4.0).
- [x] VS Code's debugging, in Xcode's views (UDCodeKit 0.5.0):
      hover values, watch expressions, conditional breakpoints, hit counts and
      logpoints (edited from the gutter), the Breakpoints navigator, Run to
      Cursor; breakpoints and watches kept as the workspace's state.
- [x] Steps that stay in their thread and step out, a method's `self`
      opening to its fields (and its superclasses', as VS Code's `this`): the
      adapter does them with stock dhewm3 1.5.5 (temporary breakpoints, the
      scripts' object declarations), and our dhewm3 fork itself with its
      fixes (ashalkhakov/dhewm3#1: step over that stops, steps scoped to
      their thread, a caller's locals, entities; protocol 2's
      DBMSG_VERSION, DBMSG_STEPOUT, DBMSG_INSPECTVARIABLES).
- [x] **udscript-dap**, a DAP adapter for dhewm3's debugger protocol (UDP
      27980/27981, `idBitMsg`, `DBMSG_*`, as `neo/tools/debugger`'s client
      speaks it: `UDScriptDebuggerConnection`): breakpoints (unverified where
      the game finds no code), break/resume/step over/step in (the game has
      no step out), threads, the call stack (a script in a pak served by
      reference), a frame's variables (its function's parameters and locals,
      read from the script, each asked of the game, which cannot list them),
      hovers and watches, the console both ways (the game's output; a command
      typed). Checked against upstream dhewm3 1.5.5 on the retail data.
- [x] Launch and attach: launch starts the game with its debugger server on
      (`+set com_enableDebuggerServer 1`) on the workspace's paths, its own
      output forwarded; attach asks a running one.

Polish, against Xcode's debugger. First what the adapter and Quarry can do
alone (UDCodeKit has the client side of each already):

- [x] Expressions in watches, hovers and the console, not only a variable's
      name: `UDScriptExpression` (the breakpoints' conditions) evaluates
      them, `self.field` and a vector's `.x` included, the variables asked of
      the game as a condition's are. In the console, what is no expression
      (or a name that is no variable here: `noclip`) is the game's command.
- [x] Restart (⌘R while debugging, as Xcode's): Quarry ends the session, the
      adapter answering once the game has quit (its debugger's port free),
      and runs it again, the breakpoints kept.
- [x] The variables view as Xcode's (UDCodeKit 0.6.0): values that changed
      since the last stop blue, what was expanded (`self`) kept so across
      steps, a filter field.
- [x] Behaviors: Quarry comes forward and shows the debug navigator when the
      game stops, and gives the game back the focus when it goes on (the
      adapter's `process` event: a game it launched).

Then what needs dhewm3, in our fork's protocol 2 (ashalkhakov/dhewm3#1; the
adapter goes on without it on stock 1.5.5, which refuses them):

- [x] Stop on script errors (Xcode's exception breakpoints): the client asks
      (`DBMSG_BREAKONERRORS`), the game stops in `idInterpreter::Error` and
      `::Warning` before it handles them, saying why (`DBMSG_SCRIPTERROR`);
      Script Errors and Script Warnings are the adapter's exception filters.
- [x] Every thread's call stack and variables (`DBMSG_INSPECTTHREADCALLSTACK`,
      `DBMSG_INSPECTVARIABLES` naming the thread), not only the stopped one's.
- [x] Threads' states in the debug navigator (waiting, ending), which the
      game already said.
- [x] An entity opens to its script object's fields and its spawn args
      (`DBMSG_INSPECTENTITY`), self too.
- [x] Setting a variable from the variables view (`DBMSG_SETVARIABLE`): a
      parameter, local or field.
- [x] Jump to line (Debug > Jump to Cursor, `DBMSG_SETNEXTSTATEMENT`): a line
      of the function the thread is in.

Stock dhewm3 1.5.5's own gaps, which the adapter works around and our fork
fixes: `GetRegisterValue` aborts the game (`idTypeDef::SuperClass` throws)
for a name it does not find in a namespace's function, so the adapter asks
for those functions' variables only; a caller's locals are read at the
wrong stack base; a call's frame shows the line after the call.

## 4. Live edit bridge (needs the dhewm3 fork)

- [ ] Engine side, in the fork: serve `idGameEdit` (entity selection,
      spawnArgs, map entities, AF spawn/update, player position), decl and
      GUI reload, console commands and console output over the debugger's
      transport; versioned messages; off unless a cvar enables it.
- [ ] A client in the libraries, and a connection UI (launch or attach, status, log).
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

- [x] Adopt gnustep-release-actions' Windows build (#24): built and tested
      in MSYS2's CLANG64 on every push; released as an MSI and a portable zip.
- [x] Keep this code portable: what each system does its own way (the
      debugger's socket, the crash reporter, the language tools' standard
      streams) in `posix/` and `windows/`, chosen by `Libraries.make`.
- [ ] Automatic updates on Windows (WinSparkle, as Sparkle on the Mac).

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
- A test in `Tests/Quarry` drives the editor through its own window on
  a fixture written for the test (never game data), on macOS and GNUstep.
