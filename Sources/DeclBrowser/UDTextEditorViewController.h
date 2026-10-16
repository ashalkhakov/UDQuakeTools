#import "UDBaseEditorViewController.h"
@class UDBaseDocument, UDDiagnosticStore;

NS_ASSUME_NONNULL_BEGIN

/**
 * Editor view controller for text/source files: UDCodeKit's code editor,
 * in UDTextEditorView.xib's editor host, backed by a UDTextFileDocument or
 * UDDeclDocument (NSDocument subclasses) for undo, saving and the dirty
 * state. A file is highlighted by the language its extension names
 * (idScript for .script, the decl grammar for .mtr, .def, ...); a decl, by
 * the decl grammar.
 */
@interface UDTextEditorViewController : UDBaseEditorViewController

/** The backing NSDocument (handles undo/save/dirty). Created lazily in viewDidLoad. */
@property (nonatomic, strong, nullable) UDBaseDocument *document;

/** Edit > Jump to Definition: where the name at the cursor is defined, as
    the workspace's script language server has it (a script's tab only). */
- (IBAction)jumpToDefinition:(nullable id)sender;

/** Edit > Test Declaration: what is wrong with a decl's text as it is now,
    in its Issues, as DialogDeclEditor's Test found it: braces that do not
    balance, what the lexer says, and what the decl's own parser says of it.
    An edit takes the findings away. (A decl's tab only.) */
- (IBAction)testDecl:(nullable id)sender;

/** The tab's diagnostics (its parse errors, its server's), as the Issues
    navigator lists them; nil before the text is in. */
@property (nonatomic, readonly, nullable) UDDiagnosticStore *diagnosticStore;

/** The code editor's text view, once the text is in. */
@property (nonatomic, readonly, nullable) NSTextView *editorTextView;

/** Selects @a length characters from @a line's @a character (0-based; UTF-16). */
- (void)selectLine:(NSInteger)line character:(NSInteger)character length:(NSInteger)length;

@end

NS_ASSUME_NONNULL_END
