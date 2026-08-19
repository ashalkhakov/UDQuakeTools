#import <AppKit/AppKit.h>

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
