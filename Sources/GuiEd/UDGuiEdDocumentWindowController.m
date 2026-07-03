/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEdDocumentWindowController.m
 *
 * Thin orchestration layer: creates and wires collaborator controllers, handles
 * window lifecycle, inspector-section switching, and identity-field commits.
 */

#import "UDGuiEdDocumentWindowController.h"
#import "UDInspectorController.h"
#import "UDEventsController.h"
#import "UDVariablesController.h"
#import "UDOutlinePaneController.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

typedef NS_ENUM(NSInteger, UDGuiInspectorSection) {
    UDGuiInspectorSectionIdentity = 0,
    UDGuiInspectorSectionAttributes,
    UDGuiInspectorSectionSize,
    UDGuiInspectorSectionVariables,
    UDGuiInspectorSectionEvents,
};

// ---------------------------------------------------------------------------
// Private extension — all IBOutlets (set by XIB) and collaborator instances
// ---------------------------------------------------------------------------

@interface UDGuiEdDocumentWindowController ()

// MARK: Collaborators
@property (nonatomic, strong) UDInspectorController   *inspectorController;
@property (nonatomic, strong) UDEventsController      *eventsController;
@property (nonatomic, strong) UDVariablesController   *variablesController;
@property (nonatomic, strong) UDOutlinePaneController *outlinePaneController;

// MARK: Document reference
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;

// MARK: Inspector state
@property (nonatomic, assign) UDGuiInspectorSection activeInspectorSection;

// MARK: Layout / structural outlets
@property (nonatomic, strong) IBOutlet NSView            *editorContainerView;
@property (nonatomic, strong) IBOutlet NSTextField       *statusLabel;
@property (nonatomic, strong) IBOutlet NSOutlineView     *outlineView;
@property (nonatomic, strong) IBOutlet NSTextField       *breadcrumbLabel;
@property (nonatomic, strong) IBOutlet NSTextField       *classNameField;
@property (nonatomic, strong) IBOutlet NSTextField       *windowNameField;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *inspectorSectionTabs;
@property (nonatomic, strong) IBOutlet NSTabView         *inspectorSectionTabView;
@property (nonatomic, strong) IBOutlet NSView            *identityPanelView;
@property (nonatomic, strong) IBOutlet NSView            *attributesPanelView;
@property (nonatomic, strong) IBOutlet NSView            *sizePanelView;
@property (nonatomic, strong) IBOutlet NSView            *variablesPanelView;
@property (nonatomic, strong) IBOutlet NSView            *eventsPanelView;

// MARK: Inspector — typed attribute tab
@property (nonatomic, strong) IBOutlet NSTabView         *attributeTypeTabView;

// MARK: Inspector — size section
@property (nonatomic, strong) IBOutlet NSTextField *sizeRectField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeRotateField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeScaleField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeTranslateField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeTextScaleField;
@property (nonatomic, strong) IBOutlet NSTextField *sizeRectHintLabel;
@property (nonatomic, strong) IBOutlet NSTextField *sizeRotateHintLabel;

// MARK: Inspector — common info flags
@property (nonatomic, strong) IBOutlet NSButton *infoShowTimeButton;
@property (nonatomic, strong) IBOutlet NSButton *infoShowCoordsButton;
@property (nonatomic, strong) IBOutlet NSButton *infoVisibleButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoEventsButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoWrapButton;
@property (nonatomic, strong) IBOutlet NSButton *infoShadowButton;
@property (nonatomic, strong) IBOutlet NSButton *infoWantEnterButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNaturalMatScaleButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoClipButton;
@property (nonatomic, strong) IBOutlet NSButton *infoNoCursorButton;
@property (nonatomic, strong) IBOutlet NSButton *infoMenuGUIButton;
@property (nonatomic, strong) IBOutlet NSButton *infoModalButton;
@property (nonatomic, strong) IBOutlet NSButton *infoInvertRectButton;

// MARK: Inspector — common info numeric / string fields
@property (nonatomic, strong) IBOutlet NSTextField *infoForceAspectWidthField;
@property (nonatomic, strong) IBOutlet NSTextField *infoForceAspectHeightField;
@property (nonatomic, strong) IBOutlet NSTextField *infoMatScaleXField;
@property (nonatomic, strong) IBOutlet NSTextField *infoMatScaleYField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBorderSizeField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextAlignField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextAlignXField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextAlignYField;
@property (nonatomic, strong) IBOutlet NSTextField *infoForeColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoHoverColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBackColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBorderColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoMatColorField;
@property (nonatomic, strong) IBOutlet NSTextField *infoShearField;
@property (nonatomic, strong) IBOutlet NSTextField *infoNameOverrideField;
@property (nonatomic, strong) IBOutlet NSTextField *infoTextField;
@property (nonatomic, strong) IBOutlet NSTextField *infoBackgroundField;
@property (nonatomic, strong) IBOutlet NSTextField *infoVarBackgroundField;
@property (nonatomic, strong) IBOutlet NSTextField *infoRunScriptField;
@property (nonatomic, strong) IBOutlet NSTextField *infoPlayField;
@property (nonatomic, strong) IBOutlet NSTextField *infoCommentField;
@property (nonatomic, strong) IBOutlet NSTextField *infoFontField;

// MARK: Typed panel — edit
@property (nonatomic, strong) IBOutlet NSTextField *attrEditCvarField;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditSourceField;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditCvarGroupField;
@property (nonatomic, strong) IBOutlet NSTextField *attrEditMaxCharsField;
@property (nonatomic, strong) IBOutlet NSButton    *attrEditNumericButton;
@property (nonatomic, strong) IBOutlet NSButton    *attrEditWrapButton;
@property (nonatomic, strong) IBOutlet NSButton    *attrEditReadOnlyButton;
@property (nonatomic, strong) IBOutlet NSButton    *attrEditForceScrollButton;
@property (nonatomic, strong) IBOutlet NSButton    *attrEditPasswordButton;
@property (nonatomic, strong) IBOutlet NSButton    *attrEditLiveUpdateButton;

// MARK: Typed panel — bind
@property (nonatomic, strong) IBOutlet NSTextField *attrBindField;

// MARK: Typed panel — choice
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceCvarField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceChoiceTypeField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceChoicesField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceValuesField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceCurrentField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceGuiField;
@property (nonatomic, strong) IBOutlet NSTextField *attrChoiceCvarGroupField;
@property (nonatomic, strong) IBOutlet NSButton    *attrChoiceLiveUpdateButton;

// MARK: Typed panel — list
@property (nonatomic, strong) IBOutlet NSButton    *attrListHorizontalButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrListNameField;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabStopsField;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabAlignsField;
@property (nonatomic, strong) IBOutlet NSButton    *attrListMultipleSelButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabStopsHintLabel;
@property (nonatomic, strong) IBOutlet NSTextField *attrListTabAlignsHintLabel;

// MARK: Typed panel — slider
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderCvarField;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderLowField;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderHighField;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderStepField;
@property (nonatomic, strong) IBOutlet NSButton    *attrSliderVerticalButton;
@property (nonatomic, strong) IBOutlet NSButton    *attrSliderScrollBarButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderThumbShaderField;
@property (nonatomic, strong) IBOutlet NSButton    *attrSliderLiveUpdateButton;
@property (nonatomic, strong) IBOutlet NSTextField *attrSliderCvarGroupField;

// MARK: Typed panel — render
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderModelField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderAnimField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderAnimClassField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderLightOriginField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderLightColorField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderModelOriginField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderModelRotateField;
@property (nonatomic, strong) IBOutlet NSTextField *attrRenderViewOffsetField;
@property (nonatomic, strong) IBOutlet NSButton    *attrRenderNeedsRenderButton;

// MARK: Variables section
@property (nonatomic, strong) IBOutlet NSTableView        *variablesTableView;
@property (nonatomic, strong) IBOutlet NSSegmentedControl *variablesTypeControl;

// MARK: Events section — table views
@property (nonatomic, strong) IBOutlet NSTableView   *eventHandlersTableView;
@property (nonatomic, strong) IBOutlet NSTableView   *eventCommandsTableView;

// MARK: Events section — command editor
@property (nonatomic, strong) IBOutlet NSPopUpButton *eventCommandTypePopup;
@property (nonatomic, strong) IBOutlet NSTabView     *eventCommandEditorTabView;
@property (nonatomic, strong) IBOutlet NSTextField   *eventSetVariableField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventSetValueField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventSetFocusWindowField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventResetTimeWindowField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventResetTimeValueField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventTransitionVariableField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventTransitionFromField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventTransitionToField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventTransitionTimeField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventTransitionAccelField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventTransitionDecelField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventLocalSoundField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventRunScriptField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventShowCursorField;
@property (nonatomic, strong) IBOutlet NSTextField   *eventFallbackArgumentsField;

@end

// ---------------------------------------------------------------------------

@implementation UDGuiEdDocumentWindowController

// MARK: - Init

- (instancetype)initWithDocument:(UDGuiEdDocument *)document {
    self = [super initWithWindowNibName:@"UDGuiEdDocument"];
    if (!self) { return nil; }
    _ownerDocument = document;
    _activeInspectorSection = UDGuiInspectorSectionAttributes;
    return self;
}

// MARK: - UDEditorControllerContext

- (UDGuiEdDocument *)ownerDocument {
    return _ownerDocument;
}

- (void)notifyModelChangedAndRefresh {
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

// MARK: - Lifecycle

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.delegate = self;

    [self createCollaborators];
    [self wireCollaboratorOutlets];
    [self wireTableDelegates];

    if (self.inspectorSectionTabs) {
        [self.inspectorSectionTabs setSelectedSegment:(NSInteger)self.activeInspectorSection];
    }
    [self.eventsController registerDragTypes];
    [self refreshFromDocument];
}

// MARK: - Collaborator wiring

- (void)createCollaborators {
    self.inspectorController   = [[UDInspectorController alloc] init];
    self.eventsController      = [[UDEventsController alloc] init];
    self.variablesController   = [[UDVariablesController alloc] init];
    self.outlinePaneController = [[UDOutlinePaneController alloc] init];

    self.inspectorController.context   = self;
    self.eventsController.context      = self;
    self.variablesController.context   = self;
    self.outlinePaneController.context = self;
}

- (void)wireCollaboratorOutlets {
    // Inspector outlets
    self.inspectorController.attributeTypeTabView     = self.attributeTypeTabView;
    self.inspectorController.sizeRectField            = self.sizeRectField;
    self.inspectorController.sizeRotateField          = self.sizeRotateField;
    self.inspectorController.sizeScaleField           = self.sizeScaleField;
    self.inspectorController.sizeTranslateField       = self.sizeTranslateField;
    self.inspectorController.sizeTextScaleField       = self.sizeTextScaleField;
    self.inspectorController.sizeRectHintLabel        = self.sizeRectHintLabel;
    self.inspectorController.sizeRotateHintLabel      = self.sizeRotateHintLabel;
    // Info — buttons
    self.inspectorController.infoShowTimeButton       = self.infoShowTimeButton;
    self.inspectorController.infoShowCoordsButton     = self.infoShowCoordsButton;
    self.inspectorController.infoVisibleButton        = self.infoVisibleButton;
    self.inspectorController.infoNoEventsButton       = self.infoNoEventsButton;
    self.inspectorController.infoNoWrapButton         = self.infoNoWrapButton;
    self.inspectorController.infoShadowButton         = self.infoShadowButton;
    self.inspectorController.infoWantEnterButton      = self.infoWantEnterButton;
    self.inspectorController.infoNaturalMatScaleButton= self.infoNaturalMatScaleButton;
    self.inspectorController.infoNoClipButton         = self.infoNoClipButton;
    self.inspectorController.infoNoCursorButton       = self.infoNoCursorButton;
    self.inspectorController.infoMenuGUIButton        = self.infoMenuGUIButton;
    self.inspectorController.infoModalButton          = self.infoModalButton;
    self.inspectorController.infoInvertRectButton     = self.infoInvertRectButton;
    // Info — numeric/string fields
    self.inspectorController.infoForceAspectWidthField  = self.infoForceAspectWidthField;
    self.inspectorController.infoForceAspectHeightField = self.infoForceAspectHeightField;
    self.inspectorController.infoMatScaleXField         = self.infoMatScaleXField;
    self.inspectorController.infoMatScaleYField         = self.infoMatScaleYField;
    self.inspectorController.infoBorderSizeField        = self.infoBorderSizeField;
    self.inspectorController.infoTextAlignField         = self.infoTextAlignField;
    self.inspectorController.infoTextAlignXField        = self.infoTextAlignXField;
    self.inspectorController.infoTextAlignYField        = self.infoTextAlignYField;
    self.inspectorController.infoForeColorField         = self.infoForeColorField;
    self.inspectorController.infoHoverColorField        = self.infoHoverColorField;
    self.inspectorController.infoBackColorField         = self.infoBackColorField;
    self.inspectorController.infoBorderColorField       = self.infoBorderColorField;
    self.inspectorController.infoMatColorField          = self.infoMatColorField;
    self.inspectorController.infoShearField             = self.infoShearField;
    self.inspectorController.infoNameOverrideField      = self.infoNameOverrideField;
    self.inspectorController.infoTextField              = self.infoTextField;
    self.inspectorController.infoBackgroundField        = self.infoBackgroundField;
    self.inspectorController.infoVarBackgroundField     = self.infoVarBackgroundField;
    self.inspectorController.infoRunScriptField         = self.infoRunScriptField;
    self.inspectorController.infoPlayField              = self.infoPlayField;
    self.inspectorController.infoCommentField           = self.infoCommentField;
    self.inspectorController.infoFontField              = self.infoFontField;
    // Typed — edit
    self.inspectorController.attrEditCvarField          = self.attrEditCvarField;
    self.inspectorController.attrEditSourceField        = self.attrEditSourceField;
    self.inspectorController.attrEditCvarGroupField     = self.attrEditCvarGroupField;
    self.inspectorController.attrEditMaxCharsField      = self.attrEditMaxCharsField;
    self.inspectorController.attrEditNumericButton      = self.attrEditNumericButton;
    self.inspectorController.attrEditWrapButton         = self.attrEditWrapButton;
    self.inspectorController.attrEditReadOnlyButton     = self.attrEditReadOnlyButton;
    self.inspectorController.attrEditForceScrollButton  = self.attrEditForceScrollButton;
    self.inspectorController.attrEditPasswordButton     = self.attrEditPasswordButton;
    self.inspectorController.attrEditLiveUpdateButton   = self.attrEditLiveUpdateButton;
    // Typed — bind
    self.inspectorController.attrBindField              = self.attrBindField;
    // Typed — choice
    self.inspectorController.attrChoiceCvarField        = self.attrChoiceCvarField;
    self.inspectorController.attrChoiceChoiceTypeField  = self.attrChoiceChoiceTypeField;
    self.inspectorController.attrChoiceChoicesField     = self.attrChoiceChoicesField;
    self.inspectorController.attrChoiceValuesField      = self.attrChoiceValuesField;
    self.inspectorController.attrChoiceCurrentField     = self.attrChoiceCurrentField;
    self.inspectorController.attrChoiceGuiField         = self.attrChoiceGuiField;
    self.inspectorController.attrChoiceCvarGroupField   = self.attrChoiceCvarGroupField;
    self.inspectorController.attrChoiceLiveUpdateButton = self.attrChoiceLiveUpdateButton;
    // Typed — list
    self.inspectorController.attrListHorizontalButton   = self.attrListHorizontalButton;
    self.inspectorController.attrListNameField          = self.attrListNameField;
    self.inspectorController.attrListTabStopsField      = self.attrListTabStopsField;
    self.inspectorController.attrListTabAlignsField     = self.attrListTabAlignsField;
    self.inspectorController.attrListMultipleSelButton  = self.attrListMultipleSelButton;
    self.inspectorController.attrListTabStopsHintLabel  = self.attrListTabStopsHintLabel;
    self.inspectorController.attrListTabAlignsHintLabel = self.attrListTabAlignsHintLabel;
    // Typed — slider
    self.inspectorController.attrSliderCvarField        = self.attrSliderCvarField;
    self.inspectorController.attrSliderLowField         = self.attrSliderLowField;
    self.inspectorController.attrSliderHighField        = self.attrSliderHighField;
    self.inspectorController.attrSliderStepField        = self.attrSliderStepField;
    self.inspectorController.attrSliderVerticalButton   = self.attrSliderVerticalButton;
    self.inspectorController.attrSliderScrollBarButton  = self.attrSliderScrollBarButton;
    self.inspectorController.attrSliderThumbShaderField = self.attrSliderThumbShaderField;
    self.inspectorController.attrSliderLiveUpdateButton = self.attrSliderLiveUpdateButton;
    self.inspectorController.attrSliderCvarGroupField   = self.attrSliderCvarGroupField;
    // Typed — render
    self.inspectorController.attrRenderModelField       = self.attrRenderModelField;
    self.inspectorController.attrRenderAnimField        = self.attrRenderAnimField;
    self.inspectorController.attrRenderAnimClassField   = self.attrRenderAnimClassField;
    self.inspectorController.attrRenderLightOriginField = self.attrRenderLightOriginField;
    self.inspectorController.attrRenderLightColorField  = self.attrRenderLightColorField;
    self.inspectorController.attrRenderModelOriginField = self.attrRenderModelOriginField;
    self.inspectorController.attrRenderModelRotateField = self.attrRenderModelRotateField;
    self.inspectorController.attrRenderViewOffsetField  = self.attrRenderViewOffsetField;
    self.inspectorController.attrRenderNeedsRenderButton= self.attrRenderNeedsRenderButton;

    // Events outlets
    self.eventsController.eventHandlersTableView        = self.eventHandlersTableView;
    self.eventsController.eventCommandsTableView        = self.eventCommandsTableView;
    self.eventsController.eventCommandTypePopup         = self.eventCommandTypePopup;
    self.eventsController.eventCommandEditorTabView     = self.eventCommandEditorTabView;
    self.eventsController.eventSetVariableField         = self.eventSetVariableField;
    self.eventsController.eventSetValueField            = self.eventSetValueField;
    self.eventsController.eventSetFocusWindowField      = self.eventSetFocusWindowField;
    self.eventsController.eventResetTimeWindowField     = self.eventResetTimeWindowField;
    self.eventsController.eventResetTimeValueField      = self.eventResetTimeValueField;
    self.eventsController.eventTransitionVariableField  = self.eventTransitionVariableField;
    self.eventsController.eventTransitionFromField      = self.eventTransitionFromField;
    self.eventsController.eventTransitionToField        = self.eventTransitionToField;
    self.eventsController.eventTransitionTimeField      = self.eventTransitionTimeField;
    self.eventsController.eventTransitionAccelField     = self.eventTransitionAccelField;
    self.eventsController.eventTransitionDecelField     = self.eventTransitionDecelField;
    self.eventsController.eventLocalSoundField          = self.eventLocalSoundField;
    self.eventsController.eventRunScriptField           = self.eventRunScriptField;
    self.eventsController.eventShowCursorField          = self.eventShowCursorField;
    self.eventsController.eventFallbackArgumentsField   = self.eventFallbackArgumentsField;

    // Variables outlets
    self.variablesController.variablesTableView         = self.variablesTableView;
    self.variablesController.variablesTypeControl       = self.variablesTypeControl;

    // Outline outlets
    self.outlinePaneController.outlineView              = self.outlineView;
}

- (void)wireTableDelegates {
    self.outlineView.dataSource   = self.outlinePaneController;
    self.outlineView.delegate     = self.outlinePaneController;

    self.variablesTableView.dataSource = self.variablesController;
    self.variablesTableView.delegate   = self.variablesController;

    self.eventHandlersTableView.dataSource = self.eventsController;
    self.eventHandlersTableView.delegate   = self.eventsController;
    self.eventCommandsTableView.dataSource = self.eventsController;
    self.eventCommandsTableView.delegate   = self.eventsController;
}

// MARK: - Window delegate

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self updateInspectorSectionLayout];
}

// MARK: - Inspector section layout

- (NSRect)frameForInspectorSection:(UDGuiInspectorSection)section {
    NSView *containerView = self.inspectorSectionTabView.superview;
    if (!containerView) { return NSZeroRect; }

    CGFloat availableWidth  = NSWidth(containerView.bounds);
    CGFloat availableHeight = NSMinY(self.inspectorSectionTabs.frame);
    if (availableHeight <= 0.0) {
        availableHeight = NSHeight(containerView.bounds);
    }

    if (section == UDGuiInspectorSectionAttributes || section == UDGuiInspectorSectionEvents) {
        return NSMakeRect(0.0, 0.0, availableWidth, availableHeight);
    }

    CGFloat compactHeight = 168.0;
    return NSMakeRect(0.0, MAX(0.0, availableHeight - compactHeight), availableWidth, compactHeight);
}

- (void)updateInspectorSectionLayout {
    if (!self.inspectorSectionTabView || !self.inspectorSectionTabs) { return; }

    NSRect sectionFrame = [self frameForInspectorSection:self.activeInspectorSection];
    if (NSEqualRects(sectionFrame, NSZeroRect)) { return; }

    self.inspectorSectionTabView.frame = sectionFrame;

    CGFloat compactHeight = 168.0;
    CGFloat fullHeight    = NSHeight(sectionFrame);
    CGFloat panelWidth    = NSWidth(sectionFrame);

    self.identityPanelView.frame   = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.attributesPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
    self.sizePanelView.frame       = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.variablesPanelView.frame  = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.eventsPanelView.frame     = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
}

// MARK: - Refresh

- (void)refreshFromDocument {
    [self.outlinePaneController refreshOutlinePane];
    [self refreshDetailPaneForSelectedWindow];

    NSUInteger rootCount = self.ownerDocument.viewModel.rootWindows.count;
    if (self.statusLabel) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu root window%@",
                                        (unsigned long)rootCount, rootCount == 1 ? @"" : @"s"];
    }
    self.window.title = self.ownerDocument.displayName ?: @"GuiEd";
}

- (void)refreshDetailPaneForSelectedWindow {
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;

    if (self.breadcrumbLabel) {
        self.breadcrumbLabel.stringValue = self.ownerDocument.viewModel.selectedWindowBreadcrumb ?: @"";
    }
    if (self.classNameField) {
        self.classNameField.stringValue  = selectedWindow.className ?: @"";
    }
    if (self.windowNameField) {
        self.windowNameField.stringValue = selectedWindow.name ?: @"";
    }

    [self updateInspectorPresentationForWindow:selectedWindow];
}

- (void)updateInspectorPresentationForWindow:(nullable UDGuiWindowNode *)selectedWindow {
    BOOL hasWindow      = selectedWindow != nil;
    BOOL identitySection= self.activeInspectorSection == UDGuiInspectorSectionIdentity;

    self.classNameField.enabled  = identitySection && hasWindow;
    self.windowNameField.enabled = identitySection && hasWindow;

    if (!hasWindow) {
        self.classNameField.stringValue  = @"";
        self.windowNameField.stringValue = @"";
    }

    if (self.inspectorSectionTabView) {
        NSInteger sectionIndex = (NSInteger)self.activeInspectorSection;
        if (sectionIndex >= 0 && sectionIndex < (NSInteger)self.inspectorSectionTabView.numberOfTabViewItems) {
            [self.inspectorSectionTabView selectTabViewItemAtIndex:sectionIndex];
        }
    }
    [self updateInspectorSectionLayout];

    // Delegate panel sync to collaborators
    [self.inspectorController updateAttributeGroupVisibilityForWindow:selectedWindow];
    [self.inspectorController syncFromWindow:selectedWindow];
    [self.inspectorController refreshValidationHintsForWindow:selectedWindow];

    [self.variablesController reloadForWindow:selectedWindow
                             preserveSelection:YES
                                     selectRow:NSNotFound
                                  beginEditing:NO];
    [self.eventsController reloadForWindow:selectedWindow preserveSelection:YES];
}

// MARK: - Actions

- (IBAction)changeInspectorSection:(id)sender {
    (void)sender;
    self.activeInspectorSection = (UDGuiInspectorSection)self.inspectorSectionTabs.selectedSegment;
    [self refreshFromDocument];
}

- (IBAction)commitTypedAttributesPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    if (![self.inspectorController validateTypedPanelsForWindow:window]) {
        [self.inspectorController refreshValidationHintsForWindow:window];
        return;
    }
    [self.inspectorController applyTypedPanelsToWindow:window];
    [self notifyModelChangedAndRefresh];
}

- (IBAction)commitWindowInfoPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    [self.inspectorController applyInfoPanelToWindow:window];
    [self notifyModelChangedAndRefresh];
}

- (IBAction)commitTypedSizePanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    if (![self.inspectorController validateSizePanelForWindow:window]) {
        [self.inspectorController refreshValidationHintsForWindow:window];
        return;
    }
    [self.inspectorController applySizePanelToWindow:window];
    [self notifyModelChangedAndRefresh];
}

- (IBAction)commitTypedVariablesPanel:(id)sender {
    (void)sender;
}

- (IBAction)commitTypedEventsPanel:(id)sender {
    (void)sender;
    // Events are committed through the handlers/commands table editor actions.
}

// Identity editing — delegated to by controlTextDidEndEditing:
- (BOOL)isWindowIdentityField:(id)sender {
    return sender == self.classNameField || sender == self.windowNameField;
}

- (void)commitWindowIdentityEdit:(id)sender {
    (void)sender;
    if (self.inspectorSectionTabs.selectedSegment != 0) { return; }

    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) { return; }

    if (self.classNameField.stringValue.length > 0) {
        [self.ownerDocument.editorService updateWindow:selectedWindow
                                             className:self.classNameField.stringValue];
    }
    if (self.windowNameField.stringValue.length > 0) {
        [self.ownerDocument.editorService updateWindow:selectedWindow
                                                  name:self.windowNameField.stringValue];
    }
    [self notifyModelChangedAndRefresh];
}

- (IBAction)beginEditingSelectedWindowIdentity:(id)sender {
    (void)sender;
    if (!self.ownerDocument.viewModel.selectedWindow) { return; }
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.window makeFirstResponder:self.windowNameField];
        [self.windowNameField selectText:nil];
    }];
}

// MARK: - NSTextFieldDelegate

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    id field = notification.object;
    if ([self isWindowIdentityField:field]) {
        [self commitWindowIdentityEdit:field];
    }
}

// MARK: - Forwarded outlet-based actions to collaborators

- (IBAction)addRootWindow:(id)sender {
    [self.outlinePaneController addRootWindow:sender];
}

- (IBAction)addChildWindow:(id)sender {
    [self.outlinePaneController addChildWindow:sender];
}

- (IBAction)deleteSelectedWindow:(id)sender {
    [self.outlinePaneController deleteSelectedWindow:sender];
}

- (IBAction)changeVariablesActionButtons:(id)sender {
    [self.variablesController changeVariablesActionButtons:sender];
}

- (IBAction)changeSelectedVariableType:(id)sender {
    [self.variablesController changeSelectedVariableType:sender];
}

- (IBAction)eventCommandEditorChanged:(id)sender {
    [self.eventsController eventCommandEditorChanged:sender];
}

- (IBAction)changeEventHandlersActionButtons:(id)sender {
    [self.eventsController changeEventHandlersActionButtons:sender];
}

- (IBAction)changeEventCommandsActionButtons:(id)sender {
    [self.eventsController changeEventCommandsActionButtons:sender];
}

@end