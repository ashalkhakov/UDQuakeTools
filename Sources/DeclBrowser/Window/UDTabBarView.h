#import <AppKit/AppKit.h>

@class UDTabBarView, UDTabBarItem;

NS_ASSUME_NONNULL_BEGIN

@protocol UDTabBarViewDelegate <NSObject>

/** The user clicked a tab. */
- (void)tabBarView:(UDTabBarView *)tabBarView didSelectItem:(UDTabBarItem *)item;

/** The user clicked a tab's close button. The delegate decides (possibly
    after a save prompt) and calls -removeItem: itself. */
- (void)tabBarView:(UDTabBarView *)tabBarView requestsCloseForItem:(UDTabBarItem *)item;

@optional
/** The user toggled a tab's pin (the bar already re-sorted itself). */
- (void)tabBarView:(UDTabBarView *)tabBarView didTogglePinForItem:(UDTabBarItem *)item;

/** The user dragged a tab to a new position. */
- (void)tabBarView:(UDTabBarView *)tabBarView didMoveItem:(UDTabBarItem *)item toIndex:(NSUInteger)index;

@end

/**
 * Model object for one tab. Mutating title / dirty / pinned automatically
 * refreshes (and if needed re-sorts) the bar the item currently belongs to.
 */
@interface UDTabBarItem : NSObject

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *toolTip;
@property (nonatomic, strong, nullable) id representedObject;

/** Unsaved-changes indicator: a dot on the tab (turns into the close glyph
    while hovered, Xcode-style). */
@property (nonatomic, assign, getter=isDirty) BOOL dirty;

/** Pinned tabs sort to the front of the bar and cannot be closed until
    unpinned. */
@property (nonatomic, assign, getter=isPinned) BOOL pinned;

+ (instancetype)itemWithTitle:(nullable NSString *)title representedObject:(nullable id)representedObject;

@end

/**
 * Xcode-like editor tab bar: a flat strip of titled tabs over a (tabless)
 * NSTabView. Tabs show a dirty dot, a close button (on hover) and a pin
 * button; pinned tabs sort first; tabs can be reordered by dragging within
 * their pinned/unpinned group; the strip scrolls horizontally when the tabs
 * no longer fit.
 *
 * Designed to be placed in a xib as a custom view (everything is built in
 * initWithCoder:/initWithFrame:); each tab's view is loaded from
 * UDTabItemView.xib.
 */
@interface UDTabBarView : NSView

@property (nonatomic, weak, nullable) IBOutlet id<UDTabBarViewDelegate> delegate;

/** Items in display order (pinned prefix first). */
@property (nonatomic, readonly) NSArray<UDTabBarItem *> *items;

/** Programmatic selection: highlights the tab and scrolls it visible. Does
    NOT call the delegate (only user clicks do). */
@property (nonatomic, strong, nullable) UDTabBarItem *selectedItem;

- (void)addItem:(UDTabBarItem *)item;
- (void)removeItem:(UDTabBarItem *)item;
- (nullable UDTabBarItem *)itemWithRepresentedObject:(id)representedObject;

@end

NS_ASSUME_NONNULL_END
