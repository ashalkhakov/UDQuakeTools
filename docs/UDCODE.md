# UDQuakeTools in UDCode

Quarry and Pak Manager are one UDCode extension, `ashalkhakov.udquaketools`
(`UDQuakeTools.bundle`, built from `Sources/Quarry`). There is no app of
their own: UDCode is the window, its tabs, its text editor, its debugger and
its Extensions window, and the extension brings the rest. UDCode's
[docs/extensions.md](https://github.com/ashalkhakov/UDCodeKit/blob/master/docs/extensions.md)
says what an extension can do; this says what this one does with it.

## A Quarry workspace

A window whose folder has a `.qworkspace` in it is a Quarry workspace
(`UQExtension -projectOfWorkbench:`, a `UQProject`); any other window is
UDCode's as it was. The `.qworkspace` names the game's install (its
`fs_basepath`), the mod (`fs_game`), where edits are saved (`fs_savepath`),
and the game to run. **Editor > Workspace Settings…** edits it; **Editor >
New Quarry Workspace…** writes one into a folder.

The workspace starts the game's file system and decl manager once, in the
background, and then:

- **The Decls navigator** (the Quarry icon in the navigator's bar) lists
  every declaration, GUI and script the game has, loose or in its paks, as
  the engine reads them: a later pak overrides an earlier one.
- **Its file system is UDCode's.** A decl is `quarry:/<type>/<name>`, a game
  file `quarry:/file/<path>`; UDCode opens, saves and searches them through
  the extension (`UDFileSystemProvider`), and an edit goes to the savepath,
  never into a pak. A file's CRLF line endings are kept.
- **Find in Decls…** searches the decls' text.

## Documents and editors

What the game edits structurally is a custom document (VS Code's
`CustomEditorProvider`): the model is Quarry's, and UDCode holds it.

| Opened | Its document | Its editor |
|---|---|---|
| A material, particle, FX, articulated figure, entityDef, mapDef, PDA, sound shader, skin or table | `UQDeclDocument`: the decl as Core Data objects, through the decl manager and the decl store (`UDDeclIncrementalStore`); undo is its context's | the decl's editor, with its inspector panes |
| A GUI (`.gui`) | `UQGuiDocument`: its text, which the canvas edits | the GUI editor; its windows in the left pane, its inspectors on the right |
| A pak (`.pk4`, `.pk3`, `.pak`) | `UQPakDocument` | Pak Manager's browser |
| A script, or any other decl | UDCode's own text document | UDCode's editor, idScript's or idDecl's mode |

`UQEditorHost` puts a Quarry editor in a UDCode tab: its navigator panes in
a split on the left, its inspector panes in UDCode's inspector, its issues
in the tab's Issues. **View > Open as Text** shows a custom document's text
(a decl as it would be saved, a GUI's source); typed there, it is one edit
of the document.

The Editor menu has the workspace's commands (New Declaration…, New PDA…,
New Skin…, Test Declaration, Find in Decls…, Workspace Settings…) and the
front editor's (the GUI editor's grid and zoom).

## Scripts: the language server and the debugger

idScript's mode (`UDCodeExtension/Resources/LanguageInfo.plist`) has
`udscript-lsp`, which the bundle carries, for its language server: it takes
`file:` and `quarry:` documents, so a script inside a pak has completion,
hover and Jump to Definition too. **Run** starts the game (`UQBuildSystem`);
debugging starts it under `udscript-dap` (`UQScriptDebugger`), with the
breakpoints set in loose scripts and in paks alike. See
[Debugging scripts](debugging.md).

## What the bundle carries

The libraries (`Sources/Libraries`), LSPServerKit, and the tools it starts:
`udscript-lsp`, `udscript-dap`, `udpaktool`. What UDCode has (GNUstep and
its Core Data, FreeCoreData; UDCodeKit, UDPieceTable, LSPKit) is never
carried: the running UDCode's is used, so there is one copy of each in the
process. On GNUstep, FreeCoreData is the stack's (gnustep-patches carries it
since 2026.10.20.45).

## Packages and updates

`Scripts/udcx.sh` packages the bundle for each platform as a `.udcx`;
gnustep-release-actions runs it (`.github/release/udcode.conf`) and writes
beside each package the feed UDCode updates the extension from,
`ashalkhakov.udquaketools-<platform>.json`, which `package.json`'s
`updates` names. The same release also carries UDCode with the extension in
it (`UDCODE_PACKAGE`): UDCode's own package, the `.udcx` in its
`Resources/Extensions`, installed the first time UDCode starts.

The extension's version is the release tag's; `package.json`'s `engines`
says which UDCode it needs, and `.github/pins.env`'s `UDCODEKIT_VERSION`
which UDCode's SDK it builds against. Move them together.

## Tests

`Tests/Extension` tests what UDCode calls: the project, the provider, the
custom documents and the editors' host. `Tests/Quarry` drives the editors
through the extension, in `UQTestWindow`, a window that is UDCode's
workbench as far as the extension asks one.
