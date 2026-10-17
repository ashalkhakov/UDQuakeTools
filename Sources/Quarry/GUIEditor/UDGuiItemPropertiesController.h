/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGuiItemPropertiesController.h — the GUI editor's item properties
 * (tools/guied/GEItemPropsDlg.cpp), ported as the inspector's Properties:
 * its General, Image and Text pages, as groups in one scrolled column (the
 * Attributes inspector's way), laid out in UDGuiViewerView.xib; its Keys
 * page, a list of the raw keys, is left to the source. The engine's sheet applied its
 * pages on OK; here a page is applied as one of its controls changes, an
 * "Item Properties" edit of the selected window's state each time.
 */

#import <Cocoa/Cocoa.h>

@class rvGEWorkspace, idFileSystem;

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiItemPropertiesController : NSObject

/// The design whose one selected window the pages show and edit.
@property (nonatomic, weak, nullable) rvGEWorkspace *workspace;
/// Where the fonts are listed from (rvGEItemPropsTextPage::Init).
@property (nonatomic, weak, nullable) idFileSystem *fileSystem;

/// SetActive, every page: the selected window's state in the controls;
/// NO when not just one window is selected (nothing shown).
- (BOOL)update;

// General (IDD_GUIED_ITEMPROPS_GENERAL)
@property (weak) IBOutlet NSTextField *nameField;
@property (weak) IBOutlet NSTextField *typeField;
@property (weak) IBOutlet NSButton *visibleButton;
@property (weak) IBOutlet NSButton *noTimeButton;
@property (weak) IBOutlet NSButton *noEventsButton;
@property (weak) IBOutlet NSButton *noClipButton;
@property (weak) IBOutlet NSButton *noCursorButton;
- (IBAction)generalChanged:(nullable id)sender;

// Image (IDD_GUIED_ITEMPROPS_IMAGE)
@property (weak) IBOutlet NSButton *useMaterialButton;
@property (weak) IBOutlet NSTextField *backgroundField;
@property (weak) IBOutlet NSButton *variableBackgroundButton;
@property (weak) IBOutlet NSTextField *matScaleXField;
@property (weak) IBOutlet NSTextField *matScaleYField;
@property (weak) IBOutlet NSTextField *xScaleLabel;
@property (weak) IBOutlet NSTextField *yScaleLabel;
@property (weak) IBOutlet NSButton *useBackColorButton;
@property (weak) IBOutlet NSColorWell *backColorWell;
@property (weak) IBOutlet NSTextField *borderSizeField;
@property (weak) IBOutlet NSButton *useBorderColorButton;
@property (weak) IBOutlet NSButton *useBorderMaterialButton;
@property (weak) IBOutlet NSColorWell *borderColorWell;
@property (weak) IBOutlet NSTextField *borderMaterialField;
@property (weak) IBOutlet NSTextField *matColorLabel;
@property (weak) IBOutlet NSColorWell *matColorWell;
- (IBAction)imageChanged:(nullable id)sender;
/// The border's color or material (the two radio buttons).
- (IBAction)borderKindChanged:(nullable id)sender;

// Text (IDD_GUIED_ITEMPROPS_TEXT)
@property (weak) IBOutlet NSButton *useTextButton;
@property (weak) IBOutlet NSColorWell *foreColorWell;
@property (weak) IBOutlet NSTextField *textField;
@property (weak) IBOutlet NSTextField *textScaleField;
@property (weak) IBOutlet NSPopUpButton *textAlignPopUp;
@property (weak) IBOutlet NSTextField *textAlignXField;
@property (weak) IBOutlet NSTextField *textAlignYField;
@property (weak) IBOutlet NSPopUpButton *fontPopUp;
@property (weak) IBOutlet NSButton *noWrapButton;
@property (weak) IBOutlet NSTextField *colorLabel;
@property (weak) IBOutlet NSTextField *scaleLabel;
@property (weak) IBOutlet NSTextField *alignmentLabel;
@property (weak) IBOutlet NSTextField *alignXLabel;
@property (weak) IBOutlet NSTextField *alignYLabel;
@property (weak) IBOutlet NSTextField *fontLabel;
- (IBAction)textChanged:(nullable id)sender;

@end

NS_ASSUME_NONNULL_END
