/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDInspectorController.h — Inspector panel controller for the GUI editor.
 *
 * Owns all inspector panel logic: common-info, size, and typed attribute
 * panels (edit/choice/bind/list/slider/render). The window controller wires
 * outlet references and the context after XIB loading.
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"

@class UDGuiWindowNode;
@class UDEditDefWindowNode;
@class UDChoiceDefWindowNode;
@class UDBindDefWindowNode;
@class UDListDefWindowNode;
@class UDSliderDefWindowNode;
@class UDRenderDefWindowNode;

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, UDGuiAttributeTypeTab) {
    UDGuiAttributeTypeTabEdit = 0,
    UDGuiAttributeTypeTabChoice,
    UDGuiAttributeTypeTabBind,
    UDGuiAttributeTypeTabList,
    UDGuiAttributeTypeTabSlider,
    UDGuiAttributeTypeTabRender,
};

@interface UDInspectorController : NSObject <NSTextFieldDelegate> {
    NSView *_view;
    NSView *_identityView;
    NSView *_sizeView;
    NSTextField *_classNameField;
    NSTextField *_windowNameField;
}

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — loaded programmatically from XIB

@property (nonatomic, strong, nullable) IBOutlet NSView *view;
@property (nonatomic, strong, nullable) IBOutlet NSView *identityView;
@property (nonatomic, strong, nullable) IBOutlet NSView *sizeView;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *classNameField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *windowNameField;

// Tab container for typed attribute panels
@property (nonatomic, weak, nullable) NSTabView *attributeTypeTabView;

// Size section
@property (nonatomic, weak, nullable) NSTextField *sizeRectField;
@property (nonatomic, weak, nullable) NSTextField *sizeRotateField;
@property (nonatomic, weak, nullable) NSTextField *sizeScaleField;
@property (nonatomic, weak, nullable) NSTextField *sizeTranslateField;
@property (nonatomic, weak, nullable) NSTextField *sizeTextScaleField;
@property (nonatomic, weak, nullable) NSTextField *sizeRectHintLabel;
@property (nonatomic, weak, nullable) NSTextField *sizeRotateHintLabel;

// Common info — boolean flags
@property (nonatomic, weak, nullable) NSButton *infoShowTimeButton;
@property (nonatomic, weak, nullable) NSButton *infoShowCoordsButton;
@property (nonatomic, weak, nullable) NSButton *infoVisibleButton;
@property (nonatomic, weak, nullable) NSButton *infoNoEventsButton;
@property (nonatomic, weak, nullable) NSButton *infoNoWrapButton;
@property (nonatomic, weak, nullable) NSButton *infoShadowButton;
@property (nonatomic, weak, nullable) NSButton *infoWantEnterButton;
@property (nonatomic, weak, nullable) NSButton *infoNaturalMatScaleButton;
@property (nonatomic, weak, nullable) NSButton *infoNoClipButton;
@property (nonatomic, weak, nullable) NSButton *infoNoCursorButton;
@property (nonatomic, weak, nullable) NSButton *infoMenuGUIButton;
@property (nonatomic, weak, nullable) NSButton *infoModalButton;
@property (nonatomic, weak, nullable) NSButton *infoInvertRectButton;

// Common info — numeric and string fields
@property (nonatomic, weak, nullable) NSTextField *infoForceAspectWidthField;
@property (nonatomic, weak, nullable) NSTextField *infoForceAspectHeightField;
@property (nonatomic, weak, nullable) NSTextField *infoMatScaleXField;
@property (nonatomic, weak, nullable) NSTextField *infoMatScaleYField;
@property (nonatomic, weak, nullable) NSTextField *infoBorderSizeField;
@property (nonatomic, weak, nullable) NSTextField *infoTextAlignField;
@property (nonatomic, weak, nullable) NSTextField *infoTextAlignXField;
@property (nonatomic, weak, nullable) NSTextField *infoTextAlignYField;
@property (nonatomic, weak, nullable) NSTextField *infoForeColorField;
@property (nonatomic, weak, nullable) NSTextField *infoHoverColorField;
@property (nonatomic, weak, nullable) NSTextField *infoBackColorField;
@property (nonatomic, weak, nullable) NSTextField *infoBorderColorField;
@property (nonatomic, weak, nullable) NSTextField *infoMatColorField;
@property (nonatomic, weak, nullable) NSTextField *infoShearField;
@property (nonatomic, weak, nullable) NSTextField *infoNameOverrideField;
@property (nonatomic, weak, nullable) NSTextField *infoTextField;
@property (nonatomic, weak, nullable) NSTextField *infoBackgroundField;
@property (nonatomic, weak, nullable) NSTextField *infoVarBackgroundField;
@property (nonatomic, weak, nullable) NSTextField *infoRunScriptField;
@property (nonatomic, weak, nullable) NSTextField *infoPlayField;
@property (nonatomic, weak, nullable) NSTextField *infoCommentField;
@property (nonatomic, weak, nullable) NSTextField *infoFontField;

// Typed panel — edit
@property (nonatomic, weak, nullable) NSTextField *attrEditCvarField;
@property (nonatomic, weak, nullable) NSTextField *attrEditSourceField;
@property (nonatomic, weak, nullable) NSTextField *attrEditCvarGroupField;
@property (nonatomic, weak, nullable) NSTextField *attrEditMaxCharsField;
@property (nonatomic, weak, nullable) NSButton    *attrEditNumericButton;
@property (nonatomic, weak, nullable) NSButton    *attrEditWrapButton;
@property (nonatomic, weak, nullable) NSButton    *attrEditReadOnlyButton;
@property (nonatomic, weak, nullable) NSButton    *attrEditForceScrollButton;
@property (nonatomic, weak, nullable) NSButton    *attrEditPasswordButton;
@property (nonatomic, weak, nullable) NSButton    *attrEditLiveUpdateButton;

// Typed panel — bind
@property (nonatomic, weak, nullable) NSTextField *attrBindField;

// Typed panel — choice
@property (nonatomic, weak, nullable) NSTextField *attrChoiceCvarField;
@property (nonatomic, weak, nullable) NSTextField *attrChoiceChoiceTypeField;
@property (nonatomic, weak, nullable) NSTextField *attrChoiceChoicesField;
@property (nonatomic, weak, nullable) NSTextField *attrChoiceValuesField;
@property (nonatomic, weak, nullable) NSTextField *attrChoiceCurrentField;
@property (nonatomic, weak, nullable) NSTextField *attrChoiceGuiField;
@property (nonatomic, weak, nullable) NSTextField *attrChoiceCvarGroupField;
@property (nonatomic, weak, nullable) NSButton    *attrChoiceLiveUpdateButton;

// Typed panel — list
@property (nonatomic, weak, nullable) NSButton    *attrListHorizontalButton;
@property (nonatomic, weak, nullable) NSTextField *attrListNameField;
@property (nonatomic, weak, nullable) NSTextField *attrListTabStopsField;
@property (nonatomic, weak, nullable) NSTextField *attrListTabAlignsField;
@property (nonatomic, weak, nullable) NSButton    *attrListMultipleSelButton;
@property (nonatomic, weak, nullable) NSTextField *attrListTabStopsHintLabel;
@property (nonatomic, weak, nullable) NSTextField *attrListTabAlignsHintLabel;

// Typed panel — slider
@property (nonatomic, weak, nullable) NSTextField *attrSliderCvarField;
@property (nonatomic, weak, nullable) NSTextField *attrSliderLowField;
@property (nonatomic, weak, nullable) NSTextField *attrSliderHighField;
@property (nonatomic, weak, nullable) NSTextField *attrSliderStepField;
@property (nonatomic, weak, nullable) NSButton    *attrSliderVerticalButton;
@property (nonatomic, weak, nullable) NSButton    *attrSliderScrollBarButton;
@property (nonatomic, weak, nullable) NSTextField *attrSliderThumbShaderField;
@property (nonatomic, weak, nullable) NSButton    *attrSliderLiveUpdateButton;
@property (nonatomic, weak, nullable) NSTextField *attrSliderCvarGroupField;

// Typed panel — render
@property (nonatomic, weak, nullable) NSTextField *attrRenderModelField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderAnimField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderAnimClassField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderLightOriginField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderLightColorField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderModelOriginField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderModelRotateField;
@property (nonatomic, weak, nullable) NSTextField *attrRenderViewOffsetField;
@property (nonatomic, weak, nullable) NSButton    *attrRenderNeedsRenderButton;

// MARK: - Sync (model → UI)

/// Sync all inspector panels from the given window node (may be nil for none).
- (void)syncFromWindow:(nullable UDGuiWindowNode *)window;

/// Update the visibility / selection of the typed-attribute tab group.
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

// MARK: - Helpers

- (UDGuiAttributeTypeTab)attributeTypeTabForWindow:(nullable UDGuiWindowNode *)window;

@end

NS_ASSUME_NONNULL_END
