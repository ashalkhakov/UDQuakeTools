#import <AppKit/AppKit.h>
#import "UDTabBarView.h"

@class UDBaseEditorViewController, UDWorkspace, UDWorkspaceItem;

NS_ASSUME_NONNULL_BEGIN

/**
 * Manages the set of open editor tabs in the workspace window.
 * Prevents duplicate tabs by keying on file path.
 *
 * The visible tab strip is a UDTabBarView (Xcode-like editor tabs, with
 * per-tab dirty indicator, close and pin buttons, drag-to-reorder and
 * horizontal scrolling); the actual view swapping is done by a tabless
 * NSTabView. Both live in UDWorkspaceWindow.xib. Pinned tabs sort to the
 * front of the bar and cannot be closed until unpinned; closing a dirty tab
 * asks to save/discard first.
 */
@interface UDEditorTabManager : NSObject <UDTabBarViewDelegate>

@property (nonatomic, weak) NSTabView *tabView;
@property (nonatomic, strong, readonly) UDTabBarView *tabBar;

- (instancetype)initWithTabView:(NSTabView *)tabView tabBar:(UDTabBarView *)tabBar workspace:(UDWorkspace *)workspace NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/**
 * Open (or activate) an editor tab for the given file item.
 * Returns the editor view controller that was created or reused.
 */
- (UDBaseEditorViewController *)openEditorForWorkspaceItem:(UDWorkspaceItem *)item;

/** The editor in the currently selected tab, or nil when no tab is open. */
- (nullable UDBaseEditorViewController *)selectedEditor;

/** All currently open editors (one per tab), in no particular order. */
- (NSArray<UDBaseEditorViewController *> *)allEditors;

/** Close the tab for the given file path (unconditionally, no save prompt). */
- (void)closeTabForPath:(NSString *)path;

/** Close all tabs. */
- (void)closeAllTabs;

@end

NS_ASSUME_NONNULL_END
