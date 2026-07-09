//
//  FormContainerView.m
//  Dynamic form layout container - portable between Cocoa and GNUstep.
//  No external dependencies. Uses manual layout for maximum compatibility.
//

#import "FormContainerView.h"
#include <CoreFoundation/CFCGTypes.h>

@implementation FormContainerView
{
    NSMutableArray<NSString *> *_labelTexts;
    NSMutableArray<NSTextField *> *_labelFields;
    NSMutableArray<NSView *> *_controlViews;
    id _lastChainedControl;   // for key view chain tracking
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self _commonInit];
    }
    return self;
}

- (void)_commonInit
{
    _labelTexts   = [NSMutableArray array];
    _labelFields  = [NSMutableArray array];
    _controlViews = [NSMutableArray array];

    _topMargin         = 12.0;
    _bottomMargin      = 12.0;
    _leftMargin        = 12.0;
    _rightMargin       = 12.0;
    _interlineSpacing  = 8.0;
    _labelControlGap   = 8.0;
    _autoLabelWidth    = YES;
    _fixedLabelWidth   = 140.0;
    _labelAlignment    = NSTextAlignmentRight; // Classic form look; change to Left if preferred
    _chainsKeyViews    = YES;

    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable | NSViewMinYMargin;
}

#pragma mark - Public API

- (void)addEntryWithLabel:(NSString *)labelText control:(NSView *)control
{
    if (!control) return;

    NSTextField *label = [self _makeLabelWithText:labelText];
    [_labelTexts addObject:labelText ?: @""];
    [_labelFields addObject:label];
    [_controlViews addObject:control];

    [self addSubview:label];
    [self addSubview:control];

    if (self.chainsKeyViews) {
        [self rebuildKeyViewChain];
    }

    [self layoutEntries];
    [self invalidateIntrinsicContentSize];
}

- (void)insertEntryAtIndex:(NSUInteger)index label:(NSString *)labelText control:(NSView *)control
{
    if (!control || index > _controlViews.count) return;

    NSTextField *label = [self _makeLabelWithText:labelText];
    [_labelTexts insertObject:labelText ?: @"" atIndex:index];
    [_labelFields insertObject:label atIndex:index];
    [_controlViews insertObject:control atIndex:index];

    [self addSubview:label];
    [self addSubview:control];

    if (self.chainsKeyViews) {
        [self rebuildKeyViewChain];
    }

    [self layoutEntries];
    [self invalidateIntrinsicContentSize];
}

- (void)removeEntryAtIndex:(NSUInteger)index
{
    if (index >= _controlViews.count) return;

    NSView *label = _labelFields[index];
    NSView *ctrl  = _controlViews[index];

    [label removeFromSuperview];
    [ctrl removeFromSuperview];

    [_labelTexts removeObjectAtIndex:index];
    [_labelFields removeObjectAtIndex:index];
    [_controlViews removeObjectAtIndex:index];

    if (self.chainsKeyViews) {
        [self rebuildKeyViewChain];
    }

    [self layoutEntries];
    [self invalidateIntrinsicContentSize];
}

- (void)removeAllEntries
{
    for (NSView *v in _labelFields) [v removeFromSuperview];
    for (NSView *v in _controlViews) [v removeFromSuperview];

    [_labelTexts removeAllObjects];
    [_labelFields removeAllObjects];
    [_controlViews removeAllObjects];

    _lastChainedControl = nil;

    [self layoutEntries];
    [self invalidateIntrinsicContentSize];
}

- (NSUInteger)numberOfEntries
{
    return _controlViews.count;
}

- (NSView *)controlAtIndex:(NSUInteger)index
{
    if (index >= _controlViews.count) return nil;
    return _controlViews[index];
}

- (NSString *)labelTextAtIndex:(NSUInteger)index
{
    if (index >= _labelTexts.count) return nil;
    return _labelTexts[index];
}

- (void)focusFirstField
{
    if (_controlViews.count > 0) {
        [[self window] makeFirstResponder:_controlViews[0]];
    }
}

#pragma mark - Layout

- (void)layoutEntries
{
    if (_labelFields.count == 0) {
        return;
    }

    CGFloat left = self.leftMargin;
    CGFloat right = self.rightMargin;
    CGFloat top = self.topMargin;
    CGFloat bottom = self.bottomMargin;
    CGFloat contentWidth = NSWidth(self.bounds) - left - right;
    CGFloat contentHeight = NSHeight(self.bounds) - top - bottom;
    //if (contentWidth < 120.0) contentWidth = 300.0;

    // Pass 1: label column width
    CGFloat maxLabelWidth = 0.0;
    for (NSTextField *label in _labelFields) {
        [label sizeToFit];
        maxLabelWidth = MAX(maxLabelWidth, NSWidth(label.frame));
    }
    CGFloat labelColWidth = self.autoLabelWidth ? maxLabelWidth : self.fixedLabelWidth;

    // Start from the TOP and move DOWN
    CGFloat y = contentHeight;

    for (NSUInteger i = 0; i < _labelFields.count; i++) {
        NSTextField *label = _labelFields[i];
        NSView *ctrl = _controlViews[i];

        [label sizeToFit];
        CGFloat labelW = MIN(NSWidth(label.frame), labelColWidth);
        CGFloat labelH = NSHeight(label.frame);

        if ([ctrl isKindOfClass:[NSControl class]]) {
            [(NSControl *)ctrl sizeToFit];
        }
        CGFloat ctrlH = NSHeight(ctrl.frame) > 1.0 ? NSHeight(ctrl.frame) : 22.0;

        CGFloat rowH = MAX(labelH, ctrlH);

        // Label
        CGFloat labelX = left;
        if (self.labelAlignment == NSTextAlignmentRight) {
            labelX = left + (labelColWidth - labelW);
        } else if (self.labelAlignment == NSTextAlignmentCenter) {
            labelX = left + (labelColWidth - labelW) / 2.0;
        }
        label.frame = NSMakeRect(labelX, y + (rowH - labelH)/2.0, labelW, labelH);

        // Control
        CGFloat ctrlX = left + labelColWidth + self.labelControlGap;
        CGFloat ctrlW = contentWidth - (ctrlX - left);

        BOOL shouldStretch = YES;
        if ([ctrl isKindOfClass:[NSButton class]] || [ctrl isKindOfClass:[NSImageView class]]) {
            shouldStretch = NO;
            if ([ctrl respondsToSelector:@selector(sizeToFit)]) {
                [(id)ctrl sizeToFit];
            }
            ctrlW = MIN(ctrlW, NSWidth(ctrl.frame));
        }

        ctrl.frame = NSMakeRect(ctrlX, y + (rowH - ctrlH)/2.0, ctrlW, ctrlH);

        // move down
        y -= rowH + self.interlineSpacing;
    }

    [self setNeedsDisplay:YES];
}

- (NSSize)intrinsicContentSize
{
    if (_labelFields.count == 0) {
        return NSMakeSize(NSViewNoIntrinsicMetric, 60.0);
    }

    CGFloat totalH = self.topMargin + self.bottomMargin;
    CGFloat maxLabelW = 0.0;

    for (NSTextField *lab in _labelFields) {
        [lab sizeToFit];
        maxLabelW = MAX(maxLabelW, NSWidth(lab.frame));
    }

    // Rough estimate for control width contribution
    CGFloat estimatedControlW = 200.0;
    CGFloat totalW = self.leftMargin + self.rightMargin + maxLabelW + self.labelControlGap + estimatedControlW;

    totalH += _labelFields.count * 24.0; // average row height
    if (_labelFields.count > 1) {
        totalH += (_labelFields.count - 1) * self.interlineSpacing;
    }
    
    return NSMakeSize(NSViewNoIntrinsicMetric, totalH);
}

- (void)invalidateIntrinsicContentSize
{
#if !GNUSTEP
    [super invalidateIntrinsicContentSize];
    // On GNUstep or older systems this may be a no-op; layoutEntries still works.
#endif
}

#pragma mark - Key View Chain

- (void)rebuildKeyViewChain
{
    if (!self.chainsKeyViews || _controlViews.count == 0) {
        _lastChainedControl = nil;
        return;
    }

    id previous = nil;

    for (NSView *ctrl in _controlViews) {
        if (previous && [previous respondsToSelector:@selector(setNextKeyView:)]) {
            [(id)previous setNextKeyView:ctrl];
        }
        previous = ctrl;
    }

    if (previous && [previous respondsToSelector:@selector(setNextKeyView:)]) {
        [(id)previous setNextKeyView:nil];
    }

    _lastChainedControl = previous;
}

#pragma mark - Helper

- (NSTextField *)_makeLabelWithText:(NSString *)text
{
    NSTextField *tf = [[NSTextField alloc] initWithFrame:NSZeroRect];
    [tf setStringValue:text ?: @""];
    [tf setBezeled:NO];
    [tf setBordered:NO];
    [tf setEditable:NO];
    [tf setSelectable:YES]; // allow users to copy labels if desired
    [tf setFont:[NSFont labelFontOfSize:0]];
    [tf setAlignment:self.labelAlignment];
    [tf setAutoresizingMask:NSViewNotSizable];
    return tf;
}

#pragma mark - IB / Subview Collection Support

// Automatically detect and pair labels + controls that were dropped directly into the container in Interface Builder.
// Assumes subviews are in sequential order: label1, control1, label2, control2, ...
// Standalone labels (headers) or lone controls are also supported.
- (void)_collectSubviewsAsFormEntries
{
    [self removeAllEntries];  // clear any previous programmatic ones

    NSArray *subviews = [self subviews];
    NSUInteger i = 0;

    while (i < subviews.count) {
        NSView *view1 = subviews[i];

        // Heuristic for label: NSTextField that is non-editable
        BOOL isLabel = [view1 isKindOfClass:[NSTextField class]] &&
                       ![(NSTextField *)view1 isEditable];

        if (isLabel && i + 1 < subviews.count) {
            NSView *control = subviews[i + 1];
            NSString *labelText = [(NSTextField *)view1 stringValue];

            // Keep the existing label and control (don't recreate)
            [_labelTexts addObject:labelText ?: @""];
            [_labelFields addObject:(NSTextField *)view1];
            [_controlViews addObject:control];

            i += 2;  // skip the pair
        } else {
            // Standalone item (header label or lone control)
            if (isLabel) {
                [_labelTexts addObject:[(NSTextField *)view1 stringValue] ?: @""];
                [_labelFields addObject:(NSTextField *)view1];
                [_controlViews addObject:view1];  // treat label as both for now
            } else {
                [_labelTexts addObject:@""];
                [_labelFields addObject:(id)[[NSTextField alloc] init]]; // dummy, or handle differently in layout
                [_controlViews addObject:view1];
            }
            i += 1;
        }
    }

    if (self.chainsKeyViews) {
        [self rebuildKeyViewChain];
    }
}

- (void)layoutSubtreeIfNeeded
{
    [super layoutSubtreeIfNeeded];
    [self layoutEntries];
}

- (void)viewDidMoveToSuperview
{
    [super viewDidMoveToSuperview];
    [self layoutEntries];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self layoutEntries];
    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];   // ensure children update
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    // Ensure it respects top alignment when embedded
    self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable | NSViewMinYMargin;
    [self _collectSubviewsAsFormEntries];
    [self layoutEntries];
    [self invalidateIntrinsicContentSize];
}


@end
