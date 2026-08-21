#import "UDTabItemView.h"
#import "UDTabBarView.h"

// The bar calls these; declared in UDTabBarView.m's class extension, redeclared
// here to keep the compiler informed without exposing them publicly.
@interface UDTabBarView (UDTabItemViewCallbacks)
- (void)_itemViewClicked:(UDTabItemView *)itemView;
- (void)_itemViewBeganDrag:(UDTabItemView *)itemView;
- (void)_itemView:(UDTabItemView *)itemView draggedToOriginX:(CGFloat)originX;
- (void)_itemViewEndedDrag:(UDTabItemView *)itemView;
- (void)_itemViewRequestedClose:(UDTabItemView *)itemView;
- (void)_itemViewRequestedPinToggle:(UDTabItemView *)itemView;
@end

@interface UDTabItemView () {
    NSTrackingRectTag _hoverTag; // classic tracking rect (GNUstep has no NSTrackingArea on NSView)
    BOOL _hovered;
}
@end

@implementation UDTabItemView

+ (instancetype)loadFromNib {
    NSArray *topLevelObjects = nil;
    NSNib *nib = [[NSNib alloc] initWithNibNamed:@"UDTabItemView" bundle:[NSBundle bundleForClass:self]];
    if (![nib instantiateWithOwner:nil topLevelObjects:&topLevelObjects]) {
        NSLog(@"UDTabItemView: could not load UDTabItemView.xib");
        return nil;
    }
    for (id object in topLevelObjects) {
        if ([object isKindOfClass:[UDTabItemView class]]) {
            return object;
        }
    }
    NSLog(@"UDTabItemView: UDTabItemView.xib has no top-level UDTabItemView");
    return nil;
}

#pragma mark - Appearance

- (void)drawRect:(NSRect)dirtyRect {
    NSRect bounds = self.bounds;

    // Flat Xcode-editor-tab colors: the selected tab matches the editor
    // background so it visually merges with the content below; the others
    // recede into the bar color.
    NSColor *fill = self.selected ? [NSColor controlBackgroundColor]
                                  : [NSColor windowBackgroundColor];
    [fill setFill];
    NSRectFill(bounds);

    NSColor *separator = [NSColor gridColor];
    [separator setFill];

    // Right hairline separator between tabs.
    NSRectFill(NSMakeRect(NSMaxX(bounds) - 1.0, 0.0, 1.0, NSHeight(bounds)));

    // Bottom hairline under unselected tabs only — the selected tab opens
    // into the editor area.
    if (!self.selected) {
        NSRectFill(NSMakeRect(0.0, 0.0, NSWidth(bounds), 1.0));
    }
}

- (void)setSelected:(BOOL)selected {
    if (_selected != selected) {
        _selected = selected;
        [self setNeedsDisplay:YES];
    }
}

- (void)refresh {
    self.titleLabel.stringValue = self.item.title ?: @"";
    self.toolTip = self.item.toolTip;

    if (self.item.pinned) {
        // Pinned tabs can't be closed: the left slot only ever shows the
        // (non-clickable) dirty dot.
        self.closeButton.title = @"●";
        self.closeButton.enabled = NO;
        self.closeButton.hidden = !self.item.dirty;
    } else {
        self.closeButton.title = _hovered ? @"✕" : @"●";
        self.closeButton.enabled = YES;
        self.closeButton.hidden = !(_hovered || self.item.dirty);
    }

    self.pinButton.title = self.item.pinned ? @"⚑" : @"⚐";
    self.pinButton.hidden = !(_hovered || self.item.pinned);

    [self setNeedsDisplay:YES];
}

#pragma mark - Hover tracking

// Classic tracking RECT, not NSTrackingArea: GNUstep's NSView has no
// tracking-area methods, and the legacy API works on both platforms. The
// rect must be re-registered whenever the view's geometry or window changes.

- (void)_rebuildHoverTracking {
    if (_hoverTag != 0) {
        [self removeTrackingRect:_hoverTag];
        _hoverTag = 0;
    }
    if (self.window == nil) {
        return;
    }
    _hoverTag = [self addTrackingRect:self.bounds owner:self userData:NULL assumeInside:NO];
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self _rebuildHoverTracking];
}

// Tracking rects do NOT follow the view around — they are registered in
// window space at add time — and the bar moves/resizes tabs constantly
// (layout, drag-to-reorder). Re-register on every geometry change.
- (void)setFrame:(NSRect)frame {
    [super setFrame:frame];
    [self _rebuildHoverTracking];
}

- (void)setFrameOrigin:(NSPoint)newOrigin {
    [super setFrameOrigin:newOrigin];
    [self _rebuildHoverTracking];
}

- (void)setFrameSize:(NSSize)newSize {
    [super setFrameSize:newSize];
    [self _rebuildHoverTracking];
}

- (void)mouseEntered:(NSEvent *)event {
    _hovered = YES;
    [self refresh];
}

- (void)mouseExited:(NSEvent *)event {
    _hovered = NO;
    [self refresh];
}

#pragma mark - Selection & drag-to-reorder

// The whole click-or-drag interaction runs as a classic event-tracking loop:
// we pull the dragged/up events straight from the window instead of relying
// on the responder machinery. That matters because reordering raises this
// view (remove + re-add) — which would silently cut off the window's
// mouseDragged/mouseUp routing to the mouse-down view, freezing the drag at
// the first swap and leaving the bar with a stuck, unresponsive "dragged"
// tab. The loop also guarantees the mouse-up is always observed, so the
// bar's drag state can never leak.
- (void)mouseDown:(NSEvent *)event {
    [self.tabBarView _itemViewClicked:self];

    NSPoint startInContainer = [self.superview convertPoint:event.locationInWindow fromView:nil];
    CGFloat startOriginX = self.frame.origin.x;
    BOOL dragging = NO;

    NSWindow *window = self.window;
    while (YES) {
        NSEvent *next = [window nextEventMatchingMask:(NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
        if (next == nil || next.type != NSLeftMouseDragged) {
            break; // mouse-up (or the window went away)
        }

        NSPoint inContainer = [self.superview convertPoint:next.locationInWindow fromView:nil];
        CGFloat delta = inContainer.x - startInContainer.x;

        if (!dragging && fabs(delta) > 4.0) {
            dragging = YES;
            [self.tabBarView _itemViewBeganDrag:self];
        }
        if (dragging) {
            [self.tabBarView _itemView:self draggedToOriginX:startOriginX + delta];
        }
    }

    if (dragging) {
        [self.tabBarView _itemViewEndedDrag:self];
    }
}

#pragma mark - Actions

- (IBAction)closeClicked:(id)sender {
    [self.tabBarView _itemViewRequestedClose:self];
}

- (IBAction)pinClicked:(id)sender {
    [self.tabBarView _itemViewRequestedPinToggle:self];
}

@end
