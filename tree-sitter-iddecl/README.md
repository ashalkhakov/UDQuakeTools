# TreeSitterIdDecl Grammar Bundle

Doom 3's decl files (`.mtr`, `.skin`, `.sndshd`, `.def`, `.fx`, `.prt`,
`.af`, `.pda`), and a decl's text in Quarry's editor: a tree-sitter
grammar written here, and the loadable bundle that gives it to UDCodeKit's
editor (the app's PlugIns folder, beside idScript's and UDCodeKit's own).

`grammar.js` reads a file as `idDeclFile::LoadAndParse`
(`neo/framework/DeclManager.cpp`) does: an optional type, the decl's name,
and a braced section. Its tokens are idLexer's under `DECL_LEXER_FLAGS`
(path names, no escapes in strings). What is inside the braces is only
tokens and nested braces: each type's own parser, ported in UDDecls, is the
one that reads it.

The generated `src/` is committed. The bundle needs no tree-sitter runtime
of its own: the app's UDCodeKit has it. It is built by `GNUmakefile` on
GNUstep and `TreeSitterIdDecl.xcodeproj` on macOS (a sub-project of
`PakManager.xcodeproj`). After changing `grammar.js`:

```bash
tree-sitter generate      # rewrites src/
tree-sitter test          # test/corpus, original snippets
```

Every decl file Doom 3 ships parses without an error but
`newpdas/mc1_berneche.pda`, which ends without its last `}`; `tree-sitter
parse --quiet --stat` over a retail install's decl files, unpacked
somewhere outside the repository, checks that.

`Resources/highlights.scm` is the highlights query (`queries/highlights.scm`
links to it, for the tree-sitter CLI).
