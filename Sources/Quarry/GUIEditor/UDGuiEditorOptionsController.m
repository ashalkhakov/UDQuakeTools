/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGuiEditorOptionsController.m
 */

#import "UDGuiEditorOptionsController.h"
#import "rvGEOptions.h"

static NSColor *UDColorFromVec4(idVec4 v) {
    return [NSColor colorWithCalibratedRed:v.x green:v.y blue:v.z alpha:1.0];
}

/// ConvertColor: a COLORREF's, its alpha 1.
static idVec4 UDVec4FromColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] ?: [NSColor blackColor];
    return idVec4_Make((float)rgb.redComponent, (float)rgb.greenComponent, (float)rgb.blueComponent, 1.0f);
}

@interface UDGuiEditorOptionsController ()
@property (nonatomic, strong, nullable) rvGEOptions *options;
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;
@property (nonatomic, weak, nullable) NSWindow *parent;
@end

@implementation UDGuiEditorOptionsController

- (instancetype)init {
    return [super initWithWindowNibName:@"UDGuiEditorOptions" owner:self];
}

- (void)beginSheetForWindow:(NSWindow *)window options:(rvGEOptions *)options target:(id)target action:(SEL)action {
    (void)self.window;
    self.options = options;
    self.target = target;
    self.action = action;
    self.parent = window;

    // GEOptionsDlg_GeneralProc's and GEOptionsDlg_GridProc's WM_INITDIALOG
    self.selectionColorWell.color = UDColorFromVec4(options.selectionColor);
    self.ignoreDesktopButton.state = options.ignoreDesktopSelect ? NSControlStateValueOn : NSControlStateValueOff;
    self.gridColorWell.color = UDColorFromVec4(options.gridColor);
    self.gridWidthField.stringValue = [NSString stringWithFormat:@"%d", options.gridWidth];
    self.gridHeightField.stringValue = [NSString stringWithFormat:@"%d", options.gridHeight];
    self.gridVisibleButton.state = options.gridVisible ? NSControlStateValueOn : NSControlStateValueOff;
    self.gridSnapButton.state = options.gridSnap ? NSControlStateValueOn : NSControlStateValueOff;
    // nStartPage
    NSInteger page = options.lastOptionsPage;
    if (page >= 0 && page < self.tabView.numberOfTabViewItems) {
        [self.tabView selectTabViewItemAtIndex:page];
    }

    [NSApp beginSheet:self.window modalForWindow:window modalDelegate:self
       didEndSelector:@selector(_sheetDidEnd:returnCode:contextInfo:) contextInfo:NULL];
}

/// The sheet down, and the target told (the sender nil on Cancel). (On
/// GNUstep -beginSheet:… runs the sheet modally, and calls this as it
/// returns.)
- (void)_sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
    [sheet orderOut:self];
    id target = self.target;
    if (target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:returnCode == NSModalResponseOK ? self : nil];
    }
}

- (IBAction)ok:(id)sender {
    // the fields' typing finished before they are read
    [self.window makeFirstResponder:nil];
    rvGEOptions *options = self.options;
    // PSN_APPLY, the General page's and the Grid page's
    options.lastOptionsPage = (int)[self.tabView indexOfTabViewItem:self.tabView.selectedTabViewItem];
    options.selectionColor = UDVec4FromColor(self.selectionColorWell.color);
    options.ignoreDesktopSelect = self.ignoreDesktopButton.state == NSControlStateValueOn;
    options.gridWidth = (int)atol(self.gridWidthField.stringValue.UTF8String);
    options.gridHeight = (int)atol(self.gridHeightField.stringValue.UTF8String);
    options.gridVisible = self.gridVisibleButton.state == NSControlStateValueOn;
    options.gridSnap = self.gridSnapButton.state == NSControlStateValueOn;
    options.gridColor = UDVec4FromColor(self.gridColorWell.color);
    [self _end:NSModalResponseOK];
}

- (IBAction)cancel:(id)sender {
    [self _end:NSModalResponseCancel];
}

/// Escape, through the panel's responders (a key equivalent of the
/// button's cannot be written in the XIB).
- (void)cancelOperation:(id)sender {
    [self cancel:sender];
}

- (void)_end:(NSModalResponse)code {
    if ([NSColorPanel sharedColorPanelExists]) [[NSColorPanel sharedColorPanel] orderOut:nil];
    [NSApp endSheet:self.window returnCode:code];
}

@end
