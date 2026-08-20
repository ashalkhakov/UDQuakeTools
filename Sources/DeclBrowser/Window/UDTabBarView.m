#import "UDTabBarView.h"
#import "UDTabItemView.h"

static const CGFloat kUDTabBarItemMinWidth   = 110.0;
static const CGFloat kUDTabBarItemMaxWidth   = 220.0;
static const CGFloat kUDTabBarItemPadding    = 58.0; // room for close/pin overlays
static const CGFloat kUDTabBarScrollerHeight = 12.0; // our own hover scroller

#pragma mark - UDTabBarItem

// Private bar hooks the item setters call (implemented further down).
@interface UDTabBarView (UDTabBarItemCallbacks)
- (void)_itemAppearanceChanged:(UDTabBarItem *)item;
- (void)_itemLayoutChanged:(UDTabBarItem *)item;
- (void)_itemOrderingChanged:(UDTabBarItem *)item;
@end

@interface UDTabBarItem ()
@property (nonatomic, weak) UDTabBarView *ud_bar; // the bar this item belongs to
@end

@implementation UDTabBarItem

+ (instancetype)itemWithTitle:(NSString *)title representedObject:(id)representedObject {
    UDTabBarItem *item = [[self alloc] init];
    item.title = title;
    item.representedObject = representedObject;
    return item;
}

// Property mutations refresh the owning bar. Title affects layout (width),
// pinned affects ordering, dirty only the indicator.

- (void)setTitle:(NSString *)title {
    _title = [title copy];
    [self.ud_bar _itemLayoutChanged:self];
}

- (void)setDirty:(BOOL)dirty {
    if (_dirty != dirty) {
        _dirty = dirty;
        [self.ud_bar _itemAppearanceChanged:self];
    }
}

- (void)setPinned:(BOOL)pinned {
    if (_pinned != pinned) {
        _pinned = pinned;
        [self.ud_bar _itemOrderingChanged:self];
    }
}

@end

#pragma mark - Container (flipped document view of the scrolling strip)

@interface UDTabBarContainerView : NSView
@end

@implementation UDTabBarContainerView
- (BOOL)isFlipped { return YES; }
@end

#pragma mark - Scroll view (vertical wheel → horizontal strip scrolling)

// A mouse without a horizontal wheel can still scroll the tab strip: plain
// vertical wheel motion is translated into horizontal scrolling.
@interface UDTabBarScrollView : NSScrollView
@end

@implementation UDTabBarScrollView

- (void)scrollWheel:(NSEvent *)event {
    if (fabs(event.deltaX) < 0.001 && fabs(event.deltaY) > 0.001) {
        NSClipView *clipView = self.contentView;
        NSView *documentView = self.documentView;
        CGFloat maxOffset = NSWidth(documentView.frame) - NSWidth(clipView.bounds);
        if (maxOffset > 0.5) {
            CGFloat offset = clipView.bounds.origin.x - event.deltaY * 12.0;
            offset = MAX(0.0, MIN(offset, maxOffset));
            [clipView scrollToPoint:NSMakePoint(offset, 0.0)];
            [self reflectScrolledClipView:clipView];
            return;
        }
    }
    [super scrollWheel:event];
}

@end

#pragma mark - UDTabBarView

@interface UDTabBarView () {
    NSMutableArray<UDTabBarItem *> *_items;
    NSMapTable<UDTabBarItem *, UDTabItemView *> *_viewsByItem;
    NSScrollView *_scrollView;
    UDTabBarContainerView *_container;
    UDTabItemView *_draggedView;    // non-nil during a reorder drag
    NSScroller *_scroller;          // our own hover scroller (bottom half)
    NSTrackingArea *_hoverArea;
    BOOL _mouseInLowerHalf;
}
@end

@implementation UDTabBarView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self _setup];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self _setup];
    }
    return self;
}

- (void)_setup {
    _items = [NSMutableArray array];
    _viewsByItem = [NSMapTable strongToStrongObjectsMapTable];

    _container = [[UDTabBarContainerView alloc] initWithFrame:self.bounds];

    // No AppKit-managed scroller: the system overlay scroller only flashes
    // after scroll events and fades before it can be grabbed. We overlay our
    // OWN NSScroller (below) and show it while the cursor is in the lower
    // half of the bar.
    _scrollView = [[UDTabBarScrollView alloc] initWithFrame:self.bounds];
    _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.borderType = NSNoBorder;
    _scrollView.drawsBackground = NO;
    _scrollView.hasVerticalScroller = NO;
    _scrollView.hasHorizontalScroller = NO;
    // 10.7+ nicety, absent on (some) GNUstep versions:
    if ([_scrollView respondsToSelector:@selector(setHorizontalScrollElasticity:)]) {
        _scrollView.horizontalScrollElasticity = NSScrollElasticityNone;
    }
    _scrollView.documentView = _container;
    [self addSubview:_scrollView];

    // Our own always-interactable scroller, overlaid on the bottom half of
    // the strip (frame is wider than tall → NSScroller comes up horizontal).
    _scroller = [[NSScroller alloc] initWithFrame:NSMakeRect(0.0, 0.0, 100.0, kUDTabBarScrollerHeight)];
    if ([_scroller respondsToSelector:@selector(setScrollerStyle:)]) {
        _scroller.scrollerStyle = NSScrollerStyleLegacy;
    }
    _scroller.controlSize = NSSmallControlSize;
    _scroller.target = self;
    _scroller.action = @selector(_scrollerChanged:);
    _scroller.enabled = YES;
    _scroller.hidden = YES;
    [self addSubview:_scroller]; // after the scroll view → stays on top

    // Keep the scroller's knob in sync with every scroll, from any source.
    _scrollView.contentView.postsBoundsChangedNotifications = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_clipViewBoundsChanged:)
                                                 name:NSViewBoundsDidChangeNotification
                                               object:_scrollView.contentView];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)isFlipped {
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect {
    // The empty part of the bar: same recessed color as unselected tabs,
    // with a bottom hairline continuing the tab row.
    [[NSColor windowBackgroundColor] setFill];
    NSRectFill(self.bounds);
    [[NSColor gridColor] setFill];
    NSRectFill(NSMakeRect(0.0, NSHeight(self.bounds) - 1.0, NSWidth(self.bounds), 1.0));
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
    [super resizeSubviewsWithOldSize:oldSize];
    [self _layoutItemViews];
}

#pragma mark - Hover scroller

// The bar tracks the mouse itself (tracking areas are geometric, so the item
// views on top don't interfere): while the cursor is in the LOWER half of
// the bar and the tabs overflow, our scroller appears there, fully
// interactable — akin to a browser's tab strip scroller.

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_hoverArea != nil) {
        [self removeTrackingArea:_hoverArea];
    }
    _hoverArea = [[NSTrackingArea alloc] initWithRect:self.bounds
                                              options:(NSTrackingMouseEnteredAndExited |
                                                       NSTrackingMouseMoved |
                                                       NSTrackingActiveInActiveApp)
                                                owner:self
                                             userInfo:nil];
    [self addTrackingArea:_hoverArea];
}

- (void)_updateMouseLocationFromEvent:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    // Flipped view: larger y = lower on screen.
    BOOL inLowerHalf = point.y > NSHeight(self.bounds) / 2.0;
    if (inLowerHalf != _mouseInLowerHalf) {
        _mouseInLowerHalf = inLowerHalf;
        [self _updateScroller];
    }
}

- (void)mouseEntered:(NSEvent *)event {
    [self _updateMouseLocationFromEvent:event];
}

- (void)mouseMoved:(NSEvent *)event {
    [self _updateMouseLocationFromEvent:event];
}

- (void)mouseExited:(NSEvent *)event {
    if (_mouseInLowerHalf) {
        _mouseInLowerHalf = NO;
        [self _updateScroller];
    }
}

- (void)_clipViewBoundsChanged:(NSNotification *)notification {
    [self _updateScroller];
}

// Repositions the scroller along the bottom of the bar and syncs its knob
// with the strip's scroll state; visible only while it is useful (overflow)
// AND wanted (cursor in the lower half).
- (void)_updateScroller {
    CGFloat visibleWidth = NSWidth(_scrollView.contentView.bounds);
    CGFloat contentWidth = NSWidth(_container.frame);
    CGFloat maxOffset = contentWidth - visibleWidth;
    BOOL overflows = maxOffset > 0.5;

    if (overflows) {
        CGFloat offset = _scrollView.contentView.bounds.origin.x;
        _scroller.knobProportion = visibleWidth / contentWidth;
        _scroller.doubleValue = MAX(0.0, MIN(offset / maxOffset, 1.0));
    }

    // Flipped coords: the bottom edge of the bar is at maxY.
    _scroller.frame = NSMakeRect(0.0,
                                 NSHeight(self.bounds) - kUDTabBarScrollerHeight,
                                 NSWidth(self.bounds),
                                 kUDTabBarScrollerHeight);
    _scroller.hidden = !(overflows && _mouseInLowerHalf);
}

- (void)_scrollerChanged:(NSScroller *)sender {
    NSClipView *clipView = _scrollView.contentView;
    CGFloat visibleWidth = NSWidth(clipView.bounds);
    CGFloat maxOffset = NSWidth(_container.frame) - visibleWidth;
    if (maxOffset <= 0.0) {
        return;
    }

    CGFloat offset = clipView.bounds.origin.x;
    switch (sender.hitPart) {
        case NSScrollerDecrementPage:
            offset -= visibleWidth * 0.8;
            break;
        case NSScrollerIncrementPage:
            offset += visibleWidth * 0.8;
            break;
        case NSScrollerDecrementLine:
            offset -= 30.0;
            break;
        case NSScrollerIncrementLine:
            offset += 30.0;
            break;
        case NSScrollerKnob:
        case NSScrollerKnobSlot:
        default:
            offset = sender.doubleValue * maxOffset;
            break;
    }

    offset = MAX(0.0, MIN(offset, maxOffset));
    [clipView scrollToPoint:NSMakePoint(offset, 0.0)];
    [_scrollView reflectScrolledClipView:clipView];
    [self _updateScroller];
}

#pragma mark - Public API

- (NSArray<UDTabBarItem *> *)items {
    return [_items copy];
}

- (void)addItem:(UDTabBarItem *)item {
    if (item == nil || [_items containsObject:item]) {
        return;
    }
    item.ud_bar = self;
    [_items addObject:item];

    UDTabItemView *view = [UDTabItemView loadFromNib];
    view.tabBarView = self;
    view.item = item;
    [_viewsByItem setObject:view forKey:item];
    [_container addSubview:view];
    [view refresh];

    [self _sortItemsPinnedFirst];
    [self _layoutItemViews];
}

- (void)removeItem:(UDTabBarItem *)item {
    if (item == nil || ![_items containsObject:item]) {
        return;
    }
    if (_draggedView == [_viewsByItem objectForKey:item]) {
        _draggedView = nil; // defensive: never let drag state outlive its item
    }
    [[_viewsByItem objectForKey:item] removeFromSuperview];
    [_viewsByItem removeObjectForKey:item];
    [_items removeObject:item];
    item.ud_bar = nil;

    if (_selectedItem == item) {
        _selectedItem = nil;
    }
    [self _layoutItemViews];
}

- (UDTabBarItem *)itemWithRepresentedObject:(id)representedObject {
    for (UDTabBarItem *item in _items) {
        if (item.representedObject == representedObject ||
            [item.representedObject isEqual:representedObject]) {
            return item;
        }
    }
    return nil;
}

- (void)setSelectedItem:(UDTabBarItem *)selectedItem {
    if (selectedItem != nil && ![_items containsObject:selectedItem]) {
        return;
    }
    _selectedItem = selectedItem;
    for (UDTabBarItem *item in _items) {
        [_viewsByItem objectForKey:item].selected = (item == selectedItem);
    }
    if (selectedItem != nil) {
        [_container scrollRectToVisible:[[_viewsByItem objectForKey:selectedItem] frame]];
    }
}

#pragma mark - Item change notifications (from UDTabBarItem setters)

- (void)_itemAppearanceChanged:(UDTabBarItem *)item {
    [[_viewsByItem objectForKey:item] refresh];
}

- (void)_itemLayoutChanged:(UDTabBarItem *)item {
    [[_viewsByItem objectForKey:item] refresh];
    [self _layoutItemViews];
}

- (void)_itemOrderingChanged:(UDTabBarItem *)item {
    [[_viewsByItem objectForKey:item] refresh];
    [self _sortItemsPinnedFirst];
    [self _layoutItemViews];
}

#pragma mark - Item view callbacks (from UDTabItemView)

- (void)_itemViewClicked:(UDTabItemView *)itemView {
    UDTabBarItem *item = itemView.item;
    if (item == nil) {
        return;
    }
    self.selectedItem = item;
    [self.delegate tabBarView:self didSelectItem:item];
}

- (void)_itemViewRequestedClose:(UDTabItemView *)itemView {
    if (itemView.item != nil && !itemView.item.pinned) {
        [self.delegate tabBarView:self requestsCloseForItem:itemView.item];
    }
}

- (void)_itemViewRequestedPinToggle:(UDTabItemView *)itemView {
    UDTabBarItem *item = itemView.item;
    if (item == nil) {
        return;
    }
    item.pinned = !item.pinned; // setter re-sorts and relayouts through us
    if ([self.delegate respondsToSelector:@selector(tabBarView:didTogglePinForItem:)]) {
        [self.delegate tabBarView:self didTogglePinForItem:item];
    }
}

// Drag started (called from the item view's tracking loop, which owns event
// delivery — so raising the view here is safe). The dragged view is raised
// to the top of the sibling order ONCE so it slides over its neighbors.
- (void)_itemViewBeganDrag:(UDTabItemView *)itemView {
    _draggedView = itemView;
    [itemView removeFromSuperview];
    [_container addSubview:itemView];
}

// Drag-to-reorder: the dragged view follows the mouse horizontally (clamped
// to its pinned/unpinned group's span); whenever its midpoint crosses into a
// neighbor's slot the items array is reordered and everything else is
// re-laid out around it.
- (void)_itemView:(UDTabItemView *)itemView draggedToOriginX:(CGFloat)originX {
    UDTabBarItem *item = itemView.item;
    NSUInteger currentIndex = [_items indexOfObject:item];
    if (currentIndex == NSNotFound) {
        return;
    }

    NSRange group = [self _groupRangeForItem:item];

    // Clamp the dragged view inside its group's horizontal span.
    CGFloat groupMinX = 0.0;
    for (NSUInteger i = 0; i < group.location; i++) {
        groupMinX += [self _widthForItem:_items[i]];
    }
    CGFloat groupWidth = 0.0;
    for (NSUInteger i = group.location; i < NSMaxRange(group); i++) {
        groupWidth += [self _widthForItem:_items[i]];
    }
    CGFloat itemWidth = [self _widthForItem:item];
    CGFloat clampedX = MAX(groupMinX, MIN(originX, groupMinX + groupWidth - itemWidth));
    [itemView setFrameOrigin:NSMakePoint(clampedX, 0.0)];

    // Find which slot the dragged midpoint falls into (within the group).
    CGFloat draggedMidX = clampedX + itemWidth / 2.0;
    NSUInteger targetIndex = group.location;
    CGFloat x = groupMinX;
    for (NSUInteger i = group.location; i < NSMaxRange(group); i++) {
        CGFloat width = [self _widthForItem:_items[i]];
        if (draggedMidX < x + width) {
            targetIndex = i;
            break;
        }
        x += width;
        targetIndex = i;
    }

    if (targetIndex != currentIndex) {
        [_items removeObjectAtIndex:currentIndex];
        [_items insertObject:item atIndex:targetIndex];
        [self _layoutItemViews]; // skips the dragged view
    }
}

- (void)_itemViewEndedDrag:(UDTabItemView *)itemView {
    _draggedView = nil;
    [self _layoutItemViews]; // snap into the final slot

    UDTabBarItem *item = itemView.item;
    NSUInteger index = [_items indexOfObject:item];
    if (index != NSNotFound &&
        [self.delegate respondsToSelector:@selector(tabBarView:didMoveItem:toIndex:)]) {
        [self.delegate tabBarView:self didMoveItem:item toIndex:index];
    }
}

#pragma mark - Layout

- (CGFloat)_widthForItem:(UDTabBarItem *)item {
    NSFont *font = [NSFont systemFontOfSize:11.0];
    CGFloat textWidth = ceil([(item.title ?: @"") sizeWithAttributes:@{ NSFontAttributeName: font }].width);
    return MIN(MAX(textWidth + kUDTabBarItemPadding, kUDTabBarItemMinWidth), kUDTabBarItemMaxWidth);
}

// Stable partition: pinned items keep their relative order in front of the
// (equally order-preserving) unpinned items.
- (void)_sortItemsPinnedFirst {
    NSMutableArray *pinned = [NSMutableArray array];
    NSMutableArray *unpinned = [NSMutableArray array];
    for (UDTabBarItem *item in _items) {
        [(item.pinned ? pinned : unpinned) addObject:item];
    }
    [pinned addObjectsFromArray:unpinned];
    [_items setArray:pinned];
}

- (void)_layoutItemViews {
    CGFloat barHeight = NSHeight(self.bounds);
    CGFloat x = 0.0;
    for (UDTabBarItem *item in _items) {
        CGFloat width = [self _widthForItem:item];
        UDTabItemView *view = [_viewsByItem objectForKey:item];
        if (view != _draggedView) {
            view.frame = NSMakeRect(x, 0.0, width, barHeight);
        } else {
            // Keep the dragged view under the mouse; only adopt the width.
            [view setFrameSize:NSMakeSize(width, barHeight)];
        }
        x += width;
    }

    [_container setFrameSize:NSMakeSize(MAX(x, NSWidth(self.bounds)), barHeight)];
    [self _updateScroller];

    // NOTE: no z-order games here. The dragged view is raised ONCE in
    // _itemViewBeganDrag:; removing/re-adding it on every relayout used to
    // sever the window's mouse-event routing mid-drag (frozen drags, stuck
    // unresponsive tabs). The drag runs in the item view's own tracking
    // loop, but relayouts still must not churn the view hierarchy.
}

// The contiguous index range of the pinned or unpinned group `item` is in
// (the array is always pinned-first).
- (NSRange)_groupRangeForItem:(UDTabBarItem *)item {
    NSUInteger pinnedCount = 0;
    for (UDTabBarItem *candidate in _items) {
        if (!candidate.pinned) {
            break;
        }
        pinnedCount++;
    }
    return item.pinned ? NSMakeRange(0, pinnedCount)
                       : NSMakeRange(pinnedCount, _items.count - pinnedCount);
}

@end
