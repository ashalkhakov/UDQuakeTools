#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * "Opening <workspace>…", with a spinner, while a workspace starts in the
 * background (UDWorkspace -startupInBackgroundWithTarget:action:): reading
 * its paks and decls takes a while from a hard disk. A plain window, over
 * the workspace's own when it restarts.
 */
@interface UDWorkspaceOpeningController : NSWindowController

@property (nonatomic, weak) IBOutlet NSTextField *messageField;
@property (nonatomic, weak) IBOutlet NSProgressIndicator *progressIndicator;

- (instancetype)initWithWorkspaceName:(NSString *)name;

/// Shows it, centred over @a window, or on the screen when nil.
- (void)showOverWindow:(nullable NSWindow *)window;
- (void)close;

@end

NS_ASSUME_NONNULL_END
