/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDInspectorController.h — Inspector panel controller for the GUI editor.
 *
 * Owns all inspector panel logic: common-info, size, and typed attribute
 * panels. The window controller wires outlet references and the context after
 * XIB loading.
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"
#import "UDGuiAttributeSubcontroller.h"

@class UDGuiWindowNode;

NS_ASSUME_NONNULL_BEGIN

@interface UDInspectorController : NSObject <NSTextFieldDelegate> {
    NSView *_view;
    NSView *_identityView;
    NSView *_sizeView;
    __weak NSPopUpButton *_classNameField;
    __weak NSTextField *_windowNameField;
}

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — loaded programmatically from XIB

@property (nonatomic, strong, nullable) IBOutlet NSView *view;
@property (nonatomic, strong, nullable) IBOutlet NSView *identityView;
@property (nonatomic, strong, nullable) IBOutlet NSView *sizeView;
@property (nonatomic, weak, nullable) IBOutlet NSPopUpButton *classNameField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *windowNameField;

// Container view for typed attribute panels
@property (nonatomic, weak, nullable) IBOutlet NSView *attributeTypeTabView;

// Size section
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeRectField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeRotateField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeScaleField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeTranslateField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeTextScaleField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeRectHintLabel;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *sizeRotateHintLabel;

// Common info — boolean flags
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoShowTimeButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoShowCoordsButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoVisibleButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoNoEventsButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoNoWrapButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoShadowButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoWantEnterButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoNaturalMatScaleButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoNoClipButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoNoCursorButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoMenuGUIButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoModalButton;
@property (nonatomic, weak, nullable) IBOutlet NSButton *infoInvertRectButton;

// Common info — numeric and string fields
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoForceAspectWidthField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoForceAspectHeightField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoMatScaleXField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoMatScaleYField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoBorderSizeField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoTextAlignField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoTextAlignXField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoTextAlignYField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoForeColorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoHoverColorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoBackColorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoBorderColorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoMatColorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoShearField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoNameOverrideField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoTextField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoBackgroundField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoVarBackgroundField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoRunScriptField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoPlayField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoCommentField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *infoFontField;

// MARK: - Dynamic subcontrollers
@property (nonatomic, strong, nullable, readonly) UDGuiAttributeSubcontroller *activeSubcontroller;

// MARK: - Sync (model → UI)

/// Sync all inspector panels from the given window node (may be nil for none).
- (void)syncFromWindow:(nullable UDGuiWindowNode *)window;

/// Update the visibility / selection of the typed-attribute panel container.
- (void)updateAttributeGroupVisibilityForWindow:(nullable UDGuiWindowNode *)window;

/// Refresh the validation-hint label colors without re-reading model state.
- (void)refreshValidationHintsForWindow:(nullable UDGuiWindowNode *)window;

// MARK: - Apply (UI → model)

- (void)applyInfoPanelToWindow:(UDGuiWindowNode *)window;
- (void)applySizePanelToWindow:(UDGuiWindowNode *)window;
- (void)applyTypedPanelsToWindow:(UDGuiWindowNode *)window;

// MARK: - Validate

- (BOOL)validateSizePanelForWindow:(UDGuiWindowNode *)window;
- (BOOL)validateTypedPanelsForWindow:(UDGuiWindowNode *)window;

// MARK: - Actions

- (IBAction)commitWindowIdentityEdit:(id)sender;
- (IBAction)commitTypedAttributesPanel:(id)sender;
- (IBAction)commitWindowInfoPanel:(id)sender;
- (IBAction)commitTypedSizePanel:(id)sender;

@end

NS_ASSUME_NONNULL_END
