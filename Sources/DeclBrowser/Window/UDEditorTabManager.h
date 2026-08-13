#import <AppKit/AppKit.h>

@class UDBaseEditorViewController, UDWorkspace, UDWorkspaceItem;

NS_ASSUME_NONNULL_BEGIN

/**
 * Manages the set of open editor tabs in the workspace window.
 * Prevents duplicate tabs by keying on file path.
 * Wraps an NSTabView (or NSTabViewController) that the workspace window controller owns.
 */
@interface UDEditorTabManager : NSObject

@property (nonatomic, weak) NSTabView *tabView;

- (instancetype)initWithTabView:(NSTabView *)tabView workspace:(UDWorkspace *)workspace NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
 * Open (or activate) an editor tab for the given file item.
 * Returns the editor view controller that was created or reused.
 */
- (UDBaseEditorViewController *)openEditorForWorkspaceItem:(UDWorkspaceItem *)item;

/** Close the tab for the given file path. */
- (void)closeTabForPath:(NSString *)path;

/** Close all tabs. */
- (void)closeAllTabs;

@end

NS_ASSUME_NONNULL_END
