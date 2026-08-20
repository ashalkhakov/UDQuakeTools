#import <AppKit/AppKit.h>

@class UDTabBarView, UDTabBarItem;

NS_ASSUME_NONNULL_BEGIN

/**
 * The view for a single tab in UDTabBarView, loaded from UDTabItemView.xib
 * (top-level object of this class; edit the tab's layout there).
 *
 * Draws the flat Xcode-editor-tab look: selected tab uses the editor
 * background color, unselected tabs the darker bar color, with a hairline
 * separator on the right and a hairline along the bottom of unselected tabs.
 * The close button shows the dirty dot (●) which turns into ✕ on hover;
 * the pin button shows ⚐/⚑ and appears on hover or while pinned.
 *
 * Mouse handling: click selects; dragging horizontally reorders the tab
 * within its pinned/unpinned group (handled by the owning UDTabBarView).
 */
@interface UDTabItemView : NSView

@property (nonatomic, weak) IBOutlet NSTextField *titleLabel;
@property (nonatomic, weak) IBOutlet NSButton *closeButton;
@property (nonatomic, weak) IBOutlet NSButton *pinButton;

@property (nonatomic, weak, nullable) UDTabBarView *tabBarView; // set by the bar
@property (nonatomic, strong, nullable) UDTabBarItem *item;     // set by the bar
@property (nonatomic, assign, getter=isSelected) BOOL selected;

/** Loads a fresh instance from UDTabItemView.xib. */
+ (nullable instancetype)loadFromNib;

/** Re-reads title/dirty/pinned from the item into the subviews. */
- (void)refresh;

- (IBAction)closeClicked:(id)sender;
- (IBAction)pinClicked:(id)sender;

@end

NS_ASSUME_NONNULL_END
