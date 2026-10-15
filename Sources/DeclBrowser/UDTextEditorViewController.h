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

@end

NS_ASSUME_NONNULL_END
