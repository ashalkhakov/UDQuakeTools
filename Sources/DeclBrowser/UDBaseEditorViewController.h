#import <AppKit/AppKit.h>

@class UDWorkspace;
@class UDWorkspaceItem;

NS_ASSUME_NONNULL_BEGIN

@class UDBaseDocument;

/**
 * Protocol / base class all editor view controllers must conform to.
 * The workspace window controller embeds -view into an NSTabViewItem.
 */
@interface UDBaseEditorViewController : NSViewController

/** The file item being edited/viewed. Set before the view is loaded. */
@property (nonatomic, strong, nullable) UDWorkspaceItem *item;
@property (nonatomic, weak) UDWorkspace *workspace;

/**
 * The backing document of this editor, if it has one. Subclasses that
 * declare a typed `document` property (text editor, PDA editor, image
 * viewer) are picked up automatically; editors without a document return
 * nil. This is what the Save / Save All / Save As menu plumbing talks to.
 */
@property (nonatomic, readonly, nullable) __kindof UDBaseDocument *editorDocument;

/**
 * Factory: returns the right editor view controller subclass for the given file item,
 * using the fileUTI to dispatch.
 */
+ (instancetype)editorViewControllerForWorkspaceItem:(UDWorkspaceItem *)item inWorkspace:(UDWorkspace *)workspace;

@end

NS_ASSUME_NONNULL_END
