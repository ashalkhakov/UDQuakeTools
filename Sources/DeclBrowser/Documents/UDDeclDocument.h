#import <AppKit/AppKit.h>
#import "UDWorkspace.h"
#import "idDeclManager.h"
#import "UDBaseDocument.h"

@class idDecl;

NS_ASSUME_NONNULL_BEGIN

/**
 * NSDocument subclass for text/source files.
 * Manages undo/redo and save for a single text file.
 * The view controller calls -setTextView: after the view is loaded so
 * this document can wire the text storage to NSUndoManager.
 */
@interface UDDeclDocument : UDBaseDocument

- (instancetype)initWithType:(declType_t)type name:(NSString *)name inWorkspace:(UDWorkspace *)workspace error:(NSError **)error;

@property (nonatomic, strong) idDecl *decl;

/** The raw text content loaded from disk. */
@property (nonatomic, copy, nullable) NSString *textContent;

/** Wire the document's text storage into the given NSTextView. */
- (void)setTextView:(NSTextView *)textView;

@end

NS_ASSUME_NONNULL_END
