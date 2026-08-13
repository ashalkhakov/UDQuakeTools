#import "UDBaseEditorViewController.h"
@class UDBaseDocument;

NS_ASSUME_NONNULL_BEGIN

/**
 * Editor view controller for text/source files.
 * Embeds an NSTextView backed by a TextFileDocument (NSDocument subclass).
 */
@interface UDTextEditorViewController : UDBaseEditorViewController

/** The backing NSDocument (handles undo/save/dirty). Created lazily in viewDidLoad. */
@property (nonatomic, strong, nullable) UDBaseDocument *document;

@end

NS_ASSUME_NONNULL_END
