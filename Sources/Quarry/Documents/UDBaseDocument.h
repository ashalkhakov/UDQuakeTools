#import <AppKit/AppKit.h>

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

/**
 * Posted (object = the document) whenever the document's change count is
 * updated, i.e. whenever isDocumentEdited may have flipped. The editor tab
 * bar listens to this to show/hide the per-tab dirty indicator.
 */
extern NSString * const UDBaseDocumentEditedStateDidChangeNotification;

@interface UDBaseDocument : NSDocument

@property (nonatomic, strong) UDWorkspace *workspace;

/** Wire the document's text storage into the given NSTextView. */
- (void)setTextView:(NSTextView *)textView;

/**
 * Save this document's own changes (and nothing else). Workspace documents
 * are not file-URL backed — they live inside idDeclManager / the virtual
 * file system — so the normal NSDocument save panel machinery does not
 * apply; this funnels into -writeToURL:ofType:error: with a placeholder URL.
 * Subclasses override -writeToURL:ofType:error:, not this.
 */
- (BOOL)ud_save:(NSError **)error;

/**
 * The editor sees one line ending, "\n": a file's "\r\n" (Doom 3's scripts
 * and decls have them) would otherwise be two places on GNUstep, the caret
 * between them, typing and Return going in after the "\r". A text read for
 * the editor loses its "\r"s, the document noting which ending the file had;
 * the editor's text gets that ending back to be written.
 */
- (NSString *)editorTextFromFileText:(NSString *)text;
- (NSString *)fileTextFromEditorText:(NSString *)text;

@end

NS_ASSUME_NONNULL_END
