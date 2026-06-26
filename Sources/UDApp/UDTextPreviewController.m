/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDTextPreviewController implementation.
 */

#import "UDTextPreviewController.h"

@implementation UDTextPreviewController

@synthesize textView = _textView;
@synthesize titleLabel = _titleLabel;

- (instancetype)initWithText:(NSString *)text title:(NSString *)title {
    NSRect frame = NSMakeRect(0, 0, 600, 440);
    NSWindow *window = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskResizable
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    [window setTitle:title];

    self = [super initWithWindow:window];
    if (self) {
        NSView *contentView = [window contentView];

        // 1. Title/Header Label
        NSRect titleFrame = NSMakeRect(10, 405, 580, 24);
        NSTextField *label = [[NSTextField alloc] initWithFrame:titleFrame];
        [label setStringValue:[NSString stringWithFormat:@"Viewing: %@", title]];
        [label setBezeled:NO];
        [label setDrawsBackground:NO];
        [label setEditable:NO];
        [label setSelectable:YES];
        [label setFont:[NSFont boldSystemFontOfSize:13]];
        [label setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
        [contentView addSubview:label];
        _titleLabel = label;

        // 2. ScrollView + TextView
        NSRect scrollFrame = NSMakeRect(10, 48, 580, 345);
        NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:scrollFrame];
        [scroll setHasVerticalScroller:YES];
        [scroll setHasHorizontalScroller:YES];
        [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        NSSize contentSize = [scroll contentSize];
        NSTextView *tv = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)];
        [tv setMinSize:NSMakeSize(0.0, contentSize.height)];
        [tv setMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
        [tv setVerticallyResizable:YES];
        [tv setHorizontallyResizable:YES];
        [tv setAutoresizingMask:NSViewWidthSizable];
        [[tv textContainer] setContainerSize:NSMakeSize(contentSize.width, FLT_MAX)];
        [[tv textContainer] setWidthTracksTextView:YES];
        [tv setEditable:NO];
        [tv setSelectable:YES];
        [tv setString:text];
        [tv setFont:[NSFont userFixedPitchFontOfSize:11]];

        [scroll setDocumentView:tv];
        [contentView addSubview:scroll];
        _textView = tv;

        // 3. Close Button
        NSRect buttonFrame = NSMakeRect(500, 10, 90, 28);
        NSButton *closeButton = [[NSButton alloc] initWithFrame:buttonFrame];
        [closeButton setTitle:@"Close"];
        [closeButton setBezelStyle:NSBezelStylePush];
        [closeButton setTarget:self];
        [closeButton setAction:@selector(closePreview:)];
        [closeButton setAutoresizingMask:NSViewMinXMargin | NSViewMaxYMargin];
        [contentView addSubview:closeButton];
    }
    return self;
}

- (void)closePreview:(id)sender {
    [NSApp endSheet:[self window]];
    [[self window] orderOut:nil];
}

@end
