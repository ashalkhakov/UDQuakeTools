#import <AppKit/AppKit.h>
#import "UDBaseDocument.h"

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

/**
 * NSDocument subclass for text/source files.
 * Manages undo/redo and save for a single text file.
 * The view controller calls -setTextView: after the view is loaded so
 * this document can wire the text storage to NSUndoManager.
 */
@interface UDTextFileDocument : UDBaseDocument

- (instancetype)initWithPath:(NSString *)path inWorkspace:(UDWorkspace *)workspace error:(NSError **)error;

@property (nonatomic, strong) NSString *path; // qpath, aka workspace-relative path

/** The raw text content loaded from disk. */
@property (nonatomic, copy, nullable) NSString *textContent;

/** Wire the document's text storage into the given NSTextView. */
- (void)setTextView:(NSTextView *)textView;

/** What saving writes, when the text view is not it: a GUI's canvas edited
    since its text was shown asks for its text to be written instead (the
    editor's text, its newlines \n). Nil, and the text view's is. */
@property (nonatomic, weak, nullable) id textSource;
@property (nonatomic, nullable) SEL textSourceAction;

@end

NS_ASSUME_NONNULL_END
