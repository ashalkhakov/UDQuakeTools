/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import <AppKit/AppKit.h>

NS_ASSUME_NONNULL_BEGIN

@class UDGuiEdDocument;

@interface UDGuiEdDocumentWindowController : NSWindowController <NSOutlineViewDataSource, NSOutlineViewDelegate, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSWindowDelegate>

@property (nonatomic, strong) IBOutlet NSView *editorContainerView;
@property (nonatomic, strong) IBOutlet NSTextField *statusLabel;
@property (nonatomic, strong) IBOutlet NSOutlineView *outlineView;
@property (nonatomic, strong) IBOutlet NSTextField *breadcrumbLabel;
@property (nonatomic, strong) IBOutlet NSTextField *classNameField;
@property (nonatomic, strong) IBOutlet NSTextField *windowNameField;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *inspectorSectionTabs;
@property (nonatomic, strong) IBOutlet NSTabView *inspectorSectionTabView;
@property (nonatomic, strong) IBOutlet NSTabView *attributeTypeTabView;
@property (nonatomic, strong) IBOutlet NSView *identityPanelView;
@property (nonatomic, strong) IBOutlet NSView *attributesPanelView;
@property (nonatomic, strong) IBOutlet NSScrollView *attributesScrollView;
@property (nonatomic, strong) IBOutlet NSView *sizePanelView;
@property (nonatomic, strong) IBOutlet NSView *variablesPanelView;
@property (nonatomic, strong) IBOutlet NSView *eventsPanelView;

@property (nonatomic, strong) IBOutlet NSTextField *attrEditCvarField;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditSourceField;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditCvarGroupField;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditMaxCharsField;
@property (nonatomic, strong) IBOutlet NSButton *attrEditNumericButton;
@property (nonatomic, strong) IBOutlet NSButton *attrEditWrapButton;
@property (nonatomic, strong) IBOutlet NSButton *attrEditReadOnlyButton;
@property (nonatomic, strong) IBOutlet NSButton *attrEditForceScrollButton;
@property (nonatomic, strong) IBOutlet NSButton *attrEditPasswordButton;
@property (nonatomic, strong) IBOutlet NSButton *attrEditLiveUpdateButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditGroupLabel;
@property (nonatomic, strong) IBOutlet NSTextField *attrBindField;
@property (nonatomic, strong) IBOutlet NSTextField *attrBindGroupLabel;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceCvarField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceChoiceTypeField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceChoicesField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceValuesField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceCurrentField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceGuiField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceCvarGroupField;
@property (nonatomic, strong) IBOutlet NSButton *attrChoiceLiveUpdateButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceGroupLabel;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderCvarField;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderLowField;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderHighField;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderStepField;
@property (nonatomic, strong) IBOutlet NSButton *attrSliderVerticalButton;
@property (nonatomic, strong) IBOutlet NSButton *attrSliderScrollBarButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderThumbShaderField;
@property (nonatomic, strong) IBOutlet NSButton *attrSliderLiveUpdateButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderCvarGroupField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderModelField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderAnimField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderAnimClassField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderLightOriginField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderLightColorField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderModelOriginField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderModelRotateField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderViewOffsetField;
@property (nonatomic, strong) IBOutlet NSButton *attrRenderNeedsRenderButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderRenderGroupLabel;
@property (nonatomic, strong) IBOutlet NSTextField *attrListGroupLabel;
@property (nonatomic, strong) IBOutlet NSButton *attrListHorizontalButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrListNameField;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabStopsField;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabAlignsField;
@property (nonatomic, strong) IBOutlet NSButton *attrListMultipleSelButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabStopsHintLabel;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabAlignsHintLabel;

@property (nonatomic, strong) IBOutlet NSTextField *sizeRectField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeRotateField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeScaleField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeTranslateField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeTextScaleField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeRectHintLabel;
@property (nonatomic, strong) IBOutlet NSTextField *sizeRotateHintLabel;

@property (nonatomic, strong) IBOutlet NSTableView *variablesTableView;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *variablesTypeControl;

@property (nonatomic, strong) IBOutlet NSButton *infoShowTimeButton;
@property (nonatomic, strong) IBOutlet NSButton *infoShowCoordsButton;
@property (nonatomic, strong) IBOutlet NSButton *infoVisibleButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoEventsButton;
@property (nonatomic, strong) IBOutlet NSTextField *infoForceAspectWidthField;
@property (nonatomic, strong) IBOutlet NSTextField *infoForceAspectHeightField;
@property (nonatomic, strong) IBOutlet NSTextField *infoMatScaleXField;
@property (nonatomic, strong) IBOutlet NSTextField *infoMatScaleYField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBorderSizeField;
@property (nonatomic, strong) IBOutlet NSTextField *infoForeColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoHoverColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBackColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBorderColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoMatColorField;
@property (nonatomic, strong) IBOutlet NSButton *infoNoWrapButton;
@property (nonatomic, strong) IBOutlet NSButton *infoShadowButton;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextAlignField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextAlignXField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextAlignYField;
@property (nonatomic, strong) IBOutlet NSTextField *infoShearField;
@property (nonatomic, strong) IBOutlet NSButton *infoWantEnterButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNaturalMatScaleButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoClipButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoCursorButton;
@property (nonatomic, strong) IBOutlet NSButton *infoMenuGUIButton;
@property (nonatomic, strong) IBOutlet NSButton *infoModalButton;
@property (nonatomic, strong) IBOutlet NSButton *infoInvertRectButton;
@property (nonatomic, strong) IBOutlet NSTextField *infoNameOverrideField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBackgroundField;
@property (nonatomic, strong) IBOutlet NSTextField *infoVarBackgroundField;
@property (nonatomic, strong) IBOutlet NSTextField *infoRunScriptField;
@property (nonatomic, strong) IBOutlet NSTextField *infoPlayField;
@property (nonatomic, strong) IBOutlet NSTextField *infoCommentField;
@property (nonatomic, strong) IBOutlet NSTextField *infoFontField;

- (instancetype)initWithDocument:(UDGuiEdDocument *)document;
- (void)refreshFromDocument;

@end

NS_ASSUME_NONNULL_END