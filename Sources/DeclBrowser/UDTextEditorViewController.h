#import "UDBaseEditorViewController.h"
@class UDBaseDocument;

NS_ASSUME_NONNULL_BEGIN

/**
 * Editor view controller for text/source files: UDCodeKit's code editor,
 * in UDTextEditorView.xib's editor host, backed by a UDTextFileDocument or
 * UDDeclDocument (NSDocument subclasses) for undo, saving and the dirty
 * state. A file is highlighted by the language its extension names
 * (idScript for .script); a decl is plain text.
 */
@interface UDTextEditorViewController : UDBaseEditorViewController

/** The backing NSDocument (handles undo/save/dirty). Created lazily in viewDidLoad. */
@property (nonatomic, strong, nullable) UDBaseDocument *document;

/** Edit > Jump to Definition: where the name at the cursor is defined, as
    the workspace's script language server has it (a script's tab only). */
- (IBAction)jumpToDefinition:(nullable id)sender;

/** Selects @a length characters from @a line's @a character (0-based; UTF-16). */
- (void)selectLine:(NSInteger)line character:(NSInteger)character length:(NSInteger)length;

@end

NS_ASSUME_NONNULL_END
