#import <AppKit/AppKit.h>

@class UDWorkspace;

NS_ASSUME_NONNULL_BEGIN

@interface UDBaseDocument : NSDocument

@property (nonatomic, strong) UDWorkspace *workspace;

/** Wire the document's text storage into the given NSTextView. */
- (void)setTextView:(NSTextView *)textView;

@end

NS_ASSUME_NONNULL_END
