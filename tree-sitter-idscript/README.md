# TreeSitterIdScript Grammar Bundle

idScript, Doom 3's script language (`.script`): a tree-sitter grammar written
here, and the loadable bundle that gives it to UDCodeKit's editor in Decl
Browser (its PlugIns folder, beside UDCodeKit's own grammars).

`grammar.js` follows idCompiler (`neo/game/script/Script_Compiler.cpp`) rule
for rule, its operator priorities included: `&&` and `||` bind looser than
assignment, `*`, `/`, `%`, `&` and `|` share a level, and `!`, `~` and unary
`-` take a whole comparison. The preprocessor runs before the compiler, so
`#` lines are extras here; the one rule the compiler does not have is for a
macro standing for a loop's head, as `eachFrame { ... }` does.

The generated `src/` is committed. The bundle needs no tree-sitter runtime
of its own: the app's UDCodeKit has it, and the parser uses only the macros
in `src/tree_sitter/parser.h`. It is built by `GNUmakefile` on GNUstep and
`TreeSitterIdScript.xcodeproj` on macOS (a sub-project of
`PakManager.xcodeproj`, against UDCodeKit's headers in `.deps/`). After
changing `grammar.js`:

```bash
tree-sitter generate      # rewrites src/
tree-sitter test          # test/corpus, original snippets
```

Every script Doom 3 and Resurrection of Evil ship parses without an error;
`tree-sitter parse --quiet --stat <your install's script/*.script>` checks
that against a retail install (whose scripts are not copied here).

`Resources/highlights.scm` is the highlights query (`queries/highlights.scm`
links to it, for the tree-sitter CLI).
