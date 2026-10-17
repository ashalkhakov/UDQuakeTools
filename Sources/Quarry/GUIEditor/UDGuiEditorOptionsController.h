/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGuiEditorOptionsController.h — the GUI editor's options dialog
 * (tools/guied/GEOptionsDlg.cpp), ported: a sheet with its two pages,
 * General (the selection's color, the desktop not chosen) and Grid (its
 * color, spacing, shown, snapped to), laid out in UDGuiEditorOptions.xib.
 * OK applies both pages to the options (PSN_APPLY), the page shown kept.
 */

#import <Cocoa/Cocoa.h>

@class rvGEOptions;

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEditorOptionsController : NSWindowController

/// Loads UDGuiEditorOptions.xib.
- (instancetype)init;

/// GEOptionsDlg_DoModal: the sheet over @a window, its controls from
/// @a options; on OK the options set from them, and @a action sent to
/// @a target (the sender the controller), as the engine saves them then;
/// on Cancel @a action sent with nil.
- (void)beginSheetForWindow:(NSWindow *)window options:(rvGEOptions *)options target:(id)target action:(SEL)action;

@property (weak) IBOutlet NSTabView *tabView;
@property (weak) IBOutlet NSColorWell *selectionColorWell;
@property (weak) IBOutlet NSButton *ignoreDesktopButton;
@property (weak) IBOutlet NSColorWell *gridColorWell;
@property (weak) IBOutlet NSTextField *gridWidthField;
@property (weak) IBOutlet NSTextField *gridHeightField;
@property (weak) IBOutlet NSButton *gridVisibleButton;
@property (weak) IBOutlet NSButton *gridSnapButton;

- (IBAction)ok:(nullable id)sender;
- (IBAction)cancel:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
