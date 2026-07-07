/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * IconTabBarView.m
 * Icon-based tab bar for inspector-style UI. Supports vertical/horizontal.
 * Works with hidden NSTabView for content switching.
 */

#import "UDIconTabBarView.h"

@implementation UDIconTabBarView
{
    NSMutableArray<NSButton *> *_buttons;
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
    _buttons = [NSMutableArray array];
    _vertical = NO;
    _iconSize = 32.0;
    _spacing = 4.0;
    _selectedIndex = -1;
    self.autoresizingMask = NSViewHeightSizable | NSViewWidthSizable;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    [self rebuildButtons];
    if (self.selectedIndex >= 0) {
        [self selectTabAtIndex:self.selectedIndex];
    }
}

- (void)setupWithIcons:(NSArray<NSImage *> *)icons
{
    self.icons = icons;
    [self rebuildButtons];
}

#pragma mark - Button Management

- (void)rebuildButtons
{
    // Remove old buttons
    for (NSButton *btn in _buttons) {
        [btn removeFromSuperview];
    }
    [_buttons removeAllObjects];

    if (self.icons.count == 0) return;

    CGFloat currentPos = self.vertical ? self.spacing : self.spacing;
    for (NSUInteger i = 0; i < self.icons.count; i++) {
        NSButton *button = [[NSButton alloc] initWithFrame:NSZeroRect];
        button.bezelStyle = NSBezelStyleRegularSquare; // or NSBezelStyleShadowlessSquare for flatter
        button.image = self.icons[i];
        button.alternateImage = (self.alternateIcons && i < self.alternateIcons.count) ? self.alternateIcons[i] : self.icons[i];
        button.imagePosition = NSImageOnly;
        button.imageScaling = NSImageScaleProportionallyUpOrDown;
        [button setButtonType:NSButtonTypeToggle];
        button.tag = (NSInteger)i;
        [button setTarget:self];
        [button setAction:@selector(buttonClicked:)];

        // Size
        CGFloat size = self.iconSize;
        [button setFrameSize:NSMakeSize(size, size)];

        [self addSubview:button];
        [_buttons addObject:button];

        // Position (will be adjusted in layout)
    }

    [self layoutButtons];
    if (self.selectedIndex >= 0 && self.selectedIndex < _buttons.count) {
        [self selectTabAtIndex:self.selectedIndex];
    }
}

- (void)layoutButtons
{
    if (_buttons.count == 0) return;

    CGFloat pos = self.vertical ? self.spacing : self.spacing;
    CGFloat buttonSize = self.iconSize;

    for (NSButton *button in _buttons) {
        if (self.vertical) {
            button.frame = NSMakeRect((NSWidth(self.bounds) - buttonSize)/2.0,
                                      pos,
                                      buttonSize, buttonSize);
            pos += buttonSize + self.spacing;
        } else {
            button.frame = NSMakeRect(pos,
                                      (NSHeight(self.bounds) - buttonSize)/2.0,
                                      buttonSize, buttonSize);
            pos += buttonSize + self.spacing;
        }
    }
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self layoutButtons];
}

#pragma mark - Selection

- (void)buttonClicked:(NSButton *)sender
{
    NSInteger index = sender.tag;
    [self selectTabAtIndex:index];
}

- (void)selectTabAtIndex:(NSInteger)index
{
    if (index < 0 || index >= _buttons.count) return;

    self.selectedIndex = index;

    // Update button states
    for (NSUInteger i = 0; i < _buttons.count; i++) {
        NSButton *btn = _buttons[i];
        btn.state = (i == (NSUInteger)index) ? NSControlStateValueOn : NSControlStateValueOff;
    }

    // Switch content tab if connected
    if (self.contentTabView) {
        [self.contentTabView selectTabViewItemAtIndex:index];
    }

    if ([self.delegate respondsToSelector:@selector(iconTabBar:didSelectTabAtIndex:)]) {
        [self.delegate iconTabBar:self didSelectTabAtIndex:index];
    }
}

#pragma mark - Properties

- (void)setIcons:(NSArray<NSImage *> *)icons
{
    _icons = [icons copy];
    [self rebuildButtons];
}

- (void)setAlternateIcons:(NSArray<NSImage *> *)alternateIcons
{
    _alternateIcons = [alternateIcons copy];
    [self rebuildButtons];
}

- (void)setVertical:(BOOL)vertical
{
    _vertical = vertical;
    [self rebuildButtons];
}

@end
