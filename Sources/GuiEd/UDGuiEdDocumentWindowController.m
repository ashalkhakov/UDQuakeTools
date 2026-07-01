/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"
#import "UDGuiEdDocument.h"
#import "UDInspectableTableView.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"
typedef NS_ENUM(NSInteger, UDGuiInspectorSection) {
    UDGuiInspectorSectionIdentity = 0,
    UDGuiInspectorSectionAttributes,
    UDGuiInspectorSectionSize,
    UDGuiInspectorSectionVariables,
    UDGuiInspectorSectionEvents,
};

typedef NS_ENUM(NSInteger, UDGuiAttributeTypeTab) {
    UDGuiAttributeTypeTabEdit = 0,
    UDGuiAttributeTypeTabChoice,
    UDGuiAttributeTypeTabBind,
    UDGuiAttributeTypeTabList,
    UDGuiAttributeTypeTabSlider,
    UDGuiAttributeTypeTabRender,
};

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@property (nonatomic, assign) UDGuiInspectorSection activeInspectorSection;
@property (nonatomic, copy) NSString *sizeRectHintDefaultText;
@property (nonatomic, copy) NSString *sizeRotateHintDefaultText;
@property (nonatomic, copy) NSString *eventsOnActionHintDefaultText;
@property (nonatomic, copy) NSString *eventsOnTimeHintDefaultText;
@property (nonatomic, copy) NSString *listTabStopsHintDefaultText;
@property (nonatomic, copy) NSString *listTabAlignsHintDefaultText;
@end

@implementation UDGuiEdDocumentWindowController

- (NSRect)frameForInspectorSection:(UDGuiInspectorSection)section {
    NSView *containerView = self.inspectorSectionTabView.superview;
    if (!containerView) {
        return NSZeroRect;
    }

    CGFloat availableWidth = NSWidth(containerView.bounds);
    CGFloat availableHeight = NSMinY(self.inspectorSectionTabs.frame);
    if (availableHeight <= 0.0) {
        availableHeight = NSHeight(containerView.bounds);
    }

    if (section == UDGuiInspectorSectionAttributes) {
        return NSMakeRect(0.0, 0.0, availableWidth, availableHeight);
    }

    CGFloat compactHeight = 168.0;
    return NSMakeRect(0.0, MAX(0.0, availableHeight - compactHeight), availableWidth, compactHeight);
}

- (void)updateInspectorSectionLayout {
    if (!self.inspectorSectionTabView || !self.inspectorSectionTabs) {
        return;
    }

    NSRect sectionFrame = [self frameForInspectorSection:self.activeInspectorSection];
    if (NSEqualRects(sectionFrame, NSZeroRect)) {
        return;
    }

    self.inspectorSectionTabView.frame = sectionFrame;

    CGFloat compactHeight = 168.0;
    CGFloat fullHeight = NSHeight(sectionFrame);
    CGFloat panelWidth = NSWidth(sectionFrame);

    self.identityPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.attributesPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, fullHeight);
    self.sizePanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.variablesPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
    self.eventsPanelView.frame = NSMakeRect(0.0, 0.0, panelWidth, compactHeight);
}

- (instancetype)initWithDocument:(UDGuiEdDocument *)document {
    self = [super initWithWindowNibName:@"UDGuiEdDocument"];
    if (!self) {
        return nil;
    }

    _ownerDocument = document;
    _activeInspectorSection = UDGuiInspectorSectionAttributes;
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    self.window.delegate = (id<NSWindowDelegate>)self;
    if (self.inspectorSectionTabs) {
        [self.inspectorSectionTabs setSegmentCount:5];
        [self.inspectorSectionTabs setLabel:@"Identity & Type" forSegment:UDGuiInspectorSectionIdentity];
        [self.inspectorSectionTabs setLabel:@"Attributes" forSegment:UDGuiInspectorSectionAttributes];
        [self.inspectorSectionTabs setLabel:@"Size" forSegment:UDGuiInspectorSectionSize];
        [self.inspectorSectionTabs setLabel:@"Variables" forSegment:UDGuiInspectorSectionVariables];
        [self.inspectorSectionTabs setLabel:@"Events" forSegment:UDGuiInspectorSectionEvents];
        [self.inspectorSectionTabs setSelectedSegment:(NSInteger)self.activeInspectorSection];
    }

    self.sizeRectHintDefaultText = self.sizeRectHintLabel.stringValue ?: @"";
    self.sizeRotateHintDefaultText = self.sizeRotateHintLabel.stringValue ?: @"";
    self.eventsOnActionHintDefaultText = self.eventsOnActionHintLabel.stringValue ?: @"";
    self.eventsOnTimeHintDefaultText = self.eventsOnTimeHintLabel.stringValue ?: @"";
    self.listTabStopsHintDefaultText = self.attrListTabStopsHintLabel.stringValue ?: @"";
    self.listTabAlignsHintDefaultText = self.attrListTabAlignsHintLabel.stringValue ?: @"";

    [self refreshFromDocument];
}

- (void)windowDidResize:(NSNotification *)notification {
    (void)notification;
    [self updateInspectorSectionLayout];
}

- (IBAction)changeInspectorSection:(id)sender {
    (void)sender;
    self.activeInspectorSection = (UDGuiInspectorSection)self.inspectorSectionTabs.selectedSegment;
    [self refreshFromDocument];
}

- (IBAction)beginEditingSelectedWindowIdentity:(id)sender {
    (void)sender;
    if (!self.ownerDocument.viewModel.selectedWindow) {
        return;
    }

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.window makeFirstResponder:self.windowNameField];
        [self.windowNameField selectText:nil];
    }];
}
- (BOOL)isWindowInspectorField:(id)sender {
    return sender == self.classNameField || sender == self.windowNameField;
}

- (void)refreshFromDocument {
    [self.outlineView reloadData];
    [self restoreOutlineSelection];

    if (self.breadcrumbLabel) {
        self.breadcrumbLabel.stringValue = self.ownerDocument.viewModel.selectedWindowBreadcrumb;
    }

    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;

    if (self.classNameField) {
        self.classNameField.stringValue = selectedWindow ? selectedWindow.className : @"";
    }
    if (self.windowNameField) {
        self.windowNameField.stringValue = selectedWindow ? selectedWindow.name : @"";
    }

    [self updateInspectorPresentationForWindow:selectedWindow];

    NSUInteger rootCount = self.ownerDocument.viewModel.rootWindows.count;
    if (self.statusLabel) {
        self.statusLabel.stringValue = [NSString stringWithFormat:@"%lu root window%@", (unsigned long)rootCount, rootCount == 1 ? @"" : @"s"];
    }
    self.window.title = self.ownerDocument.displayName ?: @"GuiEd";
}

- (void)updateInspectorPresentationForWindow:(UDGuiWindowNode *)selectedWindow {
    BOOL hasWindow = selectedWindow != nil;
    BOOL identitySection = self.activeInspectorSection == UDGuiInspectorSectionIdentity;

    self.classNameField.enabled = identitySection && hasWindow;
    self.windowNameField.enabled = identitySection && hasWindow;

    if (self.inspectorSectionTabView) {
        NSInteger sectionIndex = (NSInteger)self.activeInspectorSection;
        if (sectionIndex >= 0 && sectionIndex < (NSInteger)self.inspectorSectionTabView.numberOfTabViewItems) {
            [self.inspectorSectionTabView selectTabViewItemAtIndex:sectionIndex];
        }
    }

    [self updateInspectorSectionLayout];

    [self updateAttributeGroupVisibilityForWindow:selectedWindow];

    [self syncCommonInfoPanelFromWindow:selectedWindow];
    [self syncTypedPanelsFromWindow:selectedWindow];
    [self refreshTypedValidationHintsForWindow:selectedWindow];

    if (self.activeInspectorSection == UDGuiInspectorSectionAttributes) {
        self.statusLabel.stringValue = selectedWindow ? @"Common and typed attribute editor active. Generic properties are shown first." : self.statusLabel.stringValue;
    }

    if (!hasWindow) {
        self.classNameField.stringValue = @"";
        self.windowNameField.stringValue = @"";
    }
}

- (void)setHintLabel:(NSTextField *)label text:(NSString *)text valid:(BOOL)valid {
    if (!label) {
        return;
    }
    label.stringValue = text ?: @"";
    label.textColor = valid ? [NSColor secondaryLabelColor] : [NSColor systemRedColor];
}

- (void)setHintLabel:(NSTextField *)label defaultText:(NSString *)defaultText invalidText:(NSString *)invalidText valid:(BOOL)valid {
    [self setHintLabel:label text:(valid ? defaultText : invalidText) valid:valid];
}

- (BOOL)isScalarString:(NSString *)value {
    if (value.length == 0) {
        return NO;
    }
    NSScanner *scanner = [NSScanner scannerWithString:value];
    double parsed = 0.0;
    return [scanner scanDouble:&parsed] && scanner.isAtEnd;
}

- (BOOL)isRectString:(NSString *)value {
    NSString *normalized = [[value stringByReplacingOccurrencesOfString:@"," withString:@" "]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (normalized.length == 0) {
        return NO;
    }

    NSArray<NSString *> *parts = [normalized componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSUInteger count = 0;
    for (NSString *part in parts) {
        if (part.length == 0) {
            continue;
        }
        if (![self isScalarString:part]) {
            return NO;
        }
        count++;
    }
    return count == 4;
}

- (BOOL)isCommaSeparatedIntegerList:(NSString *)value {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@","];
    for (NSString *raw in parts) {
        NSString *part = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (part.length == 0) {
            return NO;
        }
        NSScanner *scanner = [NSScanner scannerWithString:part];
        NSInteger parsed = 0;
        if (![scanner scanInteger:&parsed] || !scanner.isAtEnd) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)isCommaSeparatedAlignmentList:(NSString *)value {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return NO;
    }

    NSArray<NSString *> *parts = [trimmed componentsSeparatedByString:@","];
    for (NSString *raw in parts) {
        NSString *part = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (part.length == 0) {
            return NO;
        }
        if (![part isEqualToString:@"0"] && ![part isEqualToString:@"1"] && ![part isEqualToString:@"2"]) {
            return NO;
        }
    }
    return YES;
}

- (void)updateAttributeGroupVisibilityForWindow:(UDGuiWindowNode *)window {
    NSInteger selectedType = -1;
    if ([window isKindOfClass:[UDEditDefWindowNode class]]) {
        selectedType = UDGuiAttributeTypeTabEdit;
    } else if ([window isKindOfClass:[UDChoiceDefWindowNode class]]) {
        selectedType = UDGuiAttributeTypeTabChoice;
    } else if ([window isKindOfClass:[UDBindDefWindowNode class]]) {
        selectedType = UDGuiAttributeTypeTabBind;
    } else if ([window isKindOfClass:[UDListDefWindowNode class]]) {
        selectedType = UDGuiAttributeTypeTabList;
    } else if ([window isKindOfClass:[UDSliderDefWindowNode class]]) {
        selectedType = UDGuiAttributeTypeTabSlider;
    } else if ([window isKindOfClass:[UDRenderDefWindowNode class]]) {
        selectedType = UDGuiAttributeTypeTabRender;
    }

    if (!self.attributeTypeTabView) {
        return;
    }

    if (selectedType < 0 || selectedType >= (NSInteger)self.attributeTypeTabView.numberOfTabViewItems) {
        self.attributeTypeTabView.hidden = YES;
        return;
    }

    self.attributeTypeTabView.hidden = NO;
    [self.attributeTypeTabView selectTabViewItemAtIndex:selectedType];
}

- (void)refreshTypedValidationHintsForWindow:(UDGuiWindowNode *)window {
    UDListDefWindowNode *listNode = [window isKindOfClass:[UDListDefWindowNode class]] ? (UDListDefWindowNode *)window : nil;
    BOOL rectValid = self.sizeRectField.stringValue.length == 0 || [self isRectString:self.sizeRectField.stringValue];
    BOOL rotateValid = self.sizeRotateField.stringValue.length == 0 || [self isScalarString:self.sizeRotateField.stringValue];

    BOOL onActionValid = self.eventsOnActionField.stringValue.length == 0 || [self.eventsOnActionField.stringValue containsString:@"{"];
    BOOL onTimeValid = self.eventsOnTimeField.stringValue.length == 0 || ([self.eventsOnTimeField.stringValue containsString:@"{"] && [self.eventsOnTimeField.stringValue rangeOfCharacterFromSet:[NSCharacterSet decimalDigitCharacterSet]].location != NSNotFound);

    [self setHintLabel:self.sizeRectHintLabel defaultText:self.sizeRectHintDefaultText invalidText:@"Expected 4 numeric values: x, y, w, h" valid:rectValid];
    [self setHintLabel:self.sizeRotateHintLabel defaultText:self.sizeRotateHintDefaultText invalidText:@"Expected numeric rotate value" valid:rotateValid];

    [self setHintLabel:self.eventsOnActionHintLabel defaultText:self.eventsOnActionHintDefaultText invalidText:@"Expected block syntax: { ... }" valid:onActionValid];
    [self setHintLabel:self.eventsOnTimeHintLabel defaultText:self.eventsOnTimeHintDefaultText invalidText:@"Expected: <time> { ... }" valid:onTimeValid];

    BOOL tabStopsValid = !listNode || self.attrListTabStopsField.stringValue.length == 0 || [self isCommaSeparatedIntegerList:self.attrListTabStopsField.stringValue];
    BOOL tabAlignsValid = !listNode || self.attrListTabAlignsField.stringValue.length == 0 || [self isCommaSeparatedAlignmentList:self.attrListTabAlignsField.stringValue];
    [self setHintLabel:self.attrListTabStopsHintLabel defaultText:self.listTabStopsHintDefaultText invalidText:@"tabstops must be comma-separated integers" valid:tabStopsValid];
    [self setHintLabel:self.attrListTabAlignsHintLabel defaultText:self.listTabAlignsHintDefaultText invalidText:@"tabaligns must be 0,1,2 values" valid:tabAlignsValid];
}

- (void)syncCommonInfoPanelFromWindow:(UDGuiWindowNode *)window {
    BOOL hasWindow = window != nil;
    self.infoShowTimeButton.state = hasWindow && [[window valueForKey:@"showTime"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoShowCoordsButton.state = hasWindow && [[window valueForKey:@"showCoords"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoVisibleButton.state = !hasWindow || [[window valueForKey:@"visible"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoNoEventsButton.state = hasWindow && [[window valueForKey:@"noEvents"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoForceAspectWidthField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"forceAspectWidth"] doubleValue]] : @"";
    self.infoForceAspectHeightField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"forceAspectHeight"] doubleValue]] : @"";
    self.infoMatScaleXField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"matScaleX"] doubleValue]] : @"";
    self.infoMatScaleYField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"matScaleY"] doubleValue]] : @"";
    self.infoBorderSizeField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"borderSize"] doubleValue]] : @"";
    self.infoForeColorField.stringValue = hasWindow ? ([window valueForKey:@"foreColor"] ?: @"") : @"";
    self.infoHoverColorField.stringValue = hasWindow ? ([window valueForKey:@"hoverColor"] ?: @"") : @"";
    self.infoBackColorField.stringValue = hasWindow ? ([window valueForKey:@"backColor"] ?: @"") : @"";
    self.infoBorderColorField.stringValue = hasWindow ? ([window valueForKey:@"borderColor"] ?: @"") : @"";
    self.infoMatColorField.stringValue = hasWindow ? ([window valueForKey:@"matColor"] ?: @"") : @"";
    self.infoNoWrapButton.state = hasWindow && [[window valueForKey:@"noWrap"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoShadowButton.state = hasWindow && [[window valueForKey:@"shadow"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoTextAlignField.stringValue = hasWindow ? [NSString stringWithFormat:@"%ld", (long)[[window valueForKey:@"textAlign"] integerValue]] : @"";
    self.infoTextAlignXField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"textAlignX"] doubleValue]] : @"";
    self.infoTextAlignYField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"textAlignY"] doubleValue]] : @"";
    self.infoShearField.stringValue = hasWindow ? ([window valueForKey:@"shear"] ?: @"") : @"";
    self.infoWantEnterButton.state = hasWindow && [[window valueForKey:@"wantEnter"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoNaturalMatScaleButton.state = hasWindow && [[window valueForKey:@"naturalMatScale"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoNoClipButton.state = hasWindow && [[window valueForKey:@"noClip"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoNoCursorButton.state = hasWindow && [[window valueForKey:@"noCursor"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoMenuGUIButton.state = hasWindow && [[window valueForKey:@"menuGUI"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoModalButton.state = hasWindow && [[window valueForKey:@"modal"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoInvertRectButton.state = hasWindow && [[window valueForKey:@"invertRect"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.infoNameOverrideField.stringValue = hasWindow ? ([window valueForKey:@"nameOverride"] ?: @"") : @"";
    self.infoTextField.stringValue = hasWindow ? ([window valueForKey:@"text"] ?: @"") : @"";
    self.infoBackgroundField.stringValue = hasWindow ? ([window valueForKey:@"background"] ?: @"") : @"";
    self.infoVarBackgroundField.stringValue = hasWindow ? ([window valueForKey:@"varBackground"] ?: @"") : @"";
    self.infoRunScriptField.stringValue = hasWindow ? ([window valueForKey:@"runScript"] ?: @"") : @"";
    self.infoPlayField.stringValue = hasWindow ? ([window valueForKey:@"play"] ?: @"") : @"";
    self.infoCommentField.stringValue = hasWindow ? ([window valueForKey:@"comment"] ?: @"") : @"";
    self.infoFontField.stringValue = hasWindow ? ([window valueForKey:@"font"] ?: @"") : @"";
}

- (void)syncTypedPanelsFromWindow:(UDGuiWindowNode *)window {
    BOOL isEdit = [window isKindOfClass:[UDEditDefWindowNode class]];
    self.attrEditCvarField.stringValue = isEdit ? ([window valueForKey:@"cvar"] ?: @"") : @"";
    self.attrEditMaxCharsField.stringValue = isEdit ? [NSString stringWithFormat:@"%ld", (long)[[window valueForKey:@"maxChars"] integerValue]] : @"";
    self.attrEditSourceField.stringValue = isEdit ? ([window valueForKey:@"source"] ?: @"") : @"";
    self.attrEditCvarGroupField.stringValue = isEdit ? ([window valueForKey:@"cvarGroup"] ?: @"") : @"";
    self.attrEditNumericButton.state = isEdit && [[window valueForKey:@"numeric"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditWrapButton.state = isEdit && [[window valueForKey:@"wrap"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditReadOnlyButton.state = isEdit && [[window valueForKey:@"readOnly"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditForceScrollButton.state = isEdit && [[window valueForKey:@"forceScroll"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditPasswordButton.state = isEdit && [[window valueForKey:@"password"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditLiveUpdateButton.state = !isEdit || [[window valueForKey:@"liveUpdate"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL isBind = [window isKindOfClass:[UDBindDefWindowNode class]];
    self.attrBindField.stringValue = isBind ? ([window valueForKey:@"bind"] ?: @"") : @"";

    BOOL isList = [window isKindOfClass:[UDListDefWindowNode class]];
    self.attrListHorizontalButton.state = isList && [[window valueForKey:@"horizontal"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrListNameField.stringValue = isList ? ([window valueForKey:@"listName"] ?: @"") : @"";
    self.attrListTabStopsField.stringValue = isList ? ([window valueForKey:@"tabStops"] ?: @"") : @"";
    self.attrListTabAlignsField.stringValue = isList ? ([window valueForKey:@"tabAligns"] ?: @"") : @"";
    self.attrListMultipleSelButton.state = isList && [[window valueForKey:@"multipleSelection"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    // TODO: Replace the flat choice/value text fields with a table view of
    // choice/value rows. Split the semicolon-delimited strings when loading the
    // inspector, then join the edited rows back into choices/values when saving.
    BOOL isChoice = [window isKindOfClass:[UDChoiceDefWindowNode class]];
    self.attrChoiceCvarField.stringValue = isChoice ? ([window valueForKey:@"cvar"] ?: @"") : @"";
    self.attrChoiceChoiceTypeField.stringValue = isChoice ? [NSString stringWithFormat:@"%ld", (long)[[window valueForKey:@"choiceType"] integerValue]] : @"";
    self.attrChoiceChoicesField.stringValue = isChoice ? ([window valueForKey:@"choices"] ?: @"") : @"";
    self.attrChoiceValuesField.stringValue = isChoice ? ([window valueForKey:@"values"] ?: @"") : @"";
    self.attrChoiceCurrentField.stringValue = isChoice ? [NSString stringWithFormat:@"%ld", (long)[[window valueForKey:@"currentChoice"] integerValue]] : @"";
    self.attrChoiceGuiField.stringValue = isChoice ? ([window valueForKey:@"gui"] ?: @"") : @"";
    self.attrChoiceCvarGroupField.stringValue = isChoice ? ([window valueForKey:@"cvarGroup"] ?: @"") : @"";
    self.attrChoiceLiveUpdateButton.state = !isChoice || [[window valueForKey:@"liveUpdate"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    BOOL isSlider = [window isKindOfClass:[UDSliderDefWindowNode class]];
    self.attrSliderCvarField.stringValue = isSlider ? ([window valueForKey:@"cvar"] ?: @"") : @"";
    self.attrSliderLowField.stringValue = isSlider ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"low"] doubleValue]] : @"";
    self.attrSliderHighField.stringValue = isSlider ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"high"] doubleValue]] : @"";
    self.attrSliderStepField.stringValue = isSlider ? [NSString stringWithFormat:@"%g", [[window valueForKey:@"stepSize"] doubleValue]] : @"";
    self.attrSliderVerticalButton.state = isSlider && [[window valueForKey:@"vertical"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderScrollBarButton.state = isSlider && [[window valueForKey:@"scrollBar"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderThumbShaderField.stringValue = isSlider ? ([window valueForKey:@"thumbShader"] ?: @"") : @"";
    self.attrSliderLiveUpdateButton.state = !isSlider || [[window valueForKey:@"liveUpdate"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderCvarGroupField.stringValue = isSlider ? ([window valueForKey:@"cvarGroup"] ?: @"") : @"";

    BOOL isRender = [window isKindOfClass:[UDRenderDefWindowNode class]];
    self.attrRenderModelField.stringValue = isRender ? ([window valueForKey:@"model"] ?: @"") : @"";
    self.attrRenderAnimField.stringValue = isRender ? ([window valueForKey:@"anim"] ?: @"") : @"";
    self.attrRenderAnimClassField.stringValue = isRender ? ([window valueForKey:@"animClass"] ?: @"") : @"";
    self.attrRenderLightOriginField.stringValue = isRender ? ([window valueForKey:@"lightOrigin"] ?: @"") : @"";
    self.attrRenderLightColorField.stringValue = isRender ? ([window valueForKey:@"lightColor"] ?: @"") : @"";
    self.attrRenderModelOriginField.stringValue = isRender ? ([window valueForKey:@"modelOrigin"] ?: @"") : @"";
    self.attrRenderModelRotateField.stringValue = isRender ? ([window valueForKey:@"modelRotate"] ?: @"") : @"";
    self.attrRenderViewOffsetField.stringValue = isRender ? ([window valueForKey:@"viewOffset"] ?: @"") : @"";
    self.attrRenderNeedsRenderButton.state = !isRender || [[window valueForKey:@"needsRender"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;

    self.sizeRectField.stringValue = [window stringPropertyForKey:@"rect"] ?: @"";
    self.sizeRotateField.stringValue = [window stringPropertyForKey:@"rotate"] ?: @"";
    self.sizeScaleField.stringValue = [window valueForKey:@"scale"] ?: @"";
    self.sizeTranslateField.stringValue = [window valueForKey:@"translate"] ?: @"";
    self.sizeTextScaleField.stringValue = [NSString stringWithFormat:@"%g", [[window valueForKey:@"textScale"] doubleValue]];
    [self reloadVariablesTableForWindow:window preserveSelection:YES selectRow:NSNotFound beginEditing:NO];

    self.eventsOnActionField.stringValue = [window stringPropertyForKey:@"onAction"] ?: @"";
    self.eventsOnTimeField.stringValue = [window stringPropertyForKey:@"onTime"] ?: @"";
}

- (NSArray<UDGuiVariableDefinition *> *)variableDefinitionsForWindow:(UDGuiWindowNode *)window {
    return window ? window.variableDefinitions : @[];
}

- (NSArray<UDGuiVariableDefinition *> *)selectedWindowVariableDefinitions {
    return [self variableDefinitionsForWindow:self.ownerDocument.viewModel.selectedWindow];
}

- (NSString *)defaultVariableNameForType:(UDGuiVariableDefinitionType)type inWindow:(UDGuiWindowNode *)window {
    NSString *prefix = type == UDGuiVariableDefinitionTypeVec4 ? @"vec4Var" : @"floatVar";
    NSSet<NSString *> *existingNames = [NSSet setWithArray:[[self variableDefinitionsForWindow:window] valueForKey:@"name"] ?: @[]];
    for (NSUInteger index = 1; index < 10000; index++) {
        NSString *candidate = [NSString stringWithFormat:@"%@%lu", prefix, (unsigned long)index];
        if (![existingNames containsObject:candidate]) {
            return candidate;
        }
    }
    return prefix;
}

- (void)syncVariableControlsFromSelection {
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    NSInteger row = self.variablesTableView.selectedRow;
    BOOL hasSelection = row >= 0 && row < (NSInteger)definitions.count;

    self.variablesTypeControl.enabled = hasSelection;
    if (!hasSelection) {
        self.variablesTypeControl.selectedSegment = 0;
        return;
    }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    self.variablesTypeControl.selectedSegment = definition.type == UDGuiVariableDefinitionTypeVec4 ? 1 : 0;
}

- (void)reloadVariablesTableForWindow:(UDGuiWindowNode *)window
                     preserveSelection:(BOOL)preserveSelection
                             selectRow:(NSInteger)forcedRow
                          beginEditing:(BOOL)beginEditing {
    if (!self.variablesTableView) {
        return;
    }

    NSInteger targetRow = forcedRow;
    if (targetRow == NSNotFound && preserveSelection) {
        targetRow = self.variablesTableView.selectedRow;
    }

    [self.variablesTableView reloadData];

    NSInteger count = (NSInteger)[self variableDefinitionsForWindow:window].count;
    if (count == 0) {
        [self.variablesTableView deselectAll:nil];
        [self syncVariableControlsFromSelection];
        return;
    }

    if (targetRow == NSNotFound) {
        targetRow = 0;
    }
    if (targetRow < 0) {
        targetRow = 0;
    }
    if (targetRow >= count) {
        targetRow = count - 1;
    }

    [self.variablesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)targetRow] byExtendingSelection:NO];
    [self.variablesTableView scrollRowToVisible:targetRow];
    [self syncVariableControlsFromSelection];

    if (beginEditing && [self.variablesTableView isKindOfClass:[UDInspectableTableView class]]) {
        [(UDInspectableTableView *)self.variablesTableView beginEditingSelectedCell];
    }
}

- (void)commitVariableDefinitionsForWindow:(UDGuiWindowNode *)window
                                 selectRow:(NSInteger)row
                              beginEditing:(BOOL)beginEditing {
    [self.ownerDocument notifyGUIModelDidChange];
    [self reloadVariablesTableForWindow:window preserveSelection:NO selectRow:row beginEditing:beginEditing];
}

- (void)replaceVariableDefinitionAtRow:(NSInteger)row
                                  type:(UDGuiVariableDefinitionType)type
                                  name:(NSString *)name
                                 value:(NSString *)value {
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (!window || row < 0 || row >= (NSInteger)definitions.count) {
        return;
    }

    UDGuiVariableDefinition *existing = [definitions objectAtIndex:(NSUInteger)row];
    NSString *nextName = [[name ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (nextName.length == 0) {
        nextName = existing.name;
    }

    [window replaceVariableDefinitionAtIndex:(NSUInteger)row
                              withDefinition:[[UDGuiVariableDefinition alloc] initWithType:type
                                                                                         name:nextName
                                                                                        value:(value ?: @"")]];
    [self commitVariableDefinitionsForWindow:window selectRow:row beginEditing:NO];
}

- (IBAction)changeVariablesActionButtons:(id)sender {
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    if (segment == 0) {
        UDGuiVariableDefinitionType type = self.variablesTypeControl.selectedSegment == 1 ? UDGuiVariableDefinitionTypeVec4 : UDGuiVariableDefinitionTypeFloat;
        NSString *defaultValue = type == UDGuiVariableDefinitionTypeVec4 ? @"0, 0, 0, 0" : @"0";
        NSString *defaultName = [self defaultVariableNameForType:type inWindow:window];
        [window addVariableDefinition:[[UDGuiVariableDefinition alloc] initWithType:type name:defaultName value:defaultValue]];
        [self commitVariableDefinitionsForWindow:window selectRow:(NSInteger)window.variableDefinitions.count - 1 beginEditing:YES];
        return;
    }

    if (segment == 1) {
        NSInteger row = self.variablesTableView.selectedRow;
        if (row < 0 || row >= (NSInteger)window.variableDefinitions.count) {
            return;
        }

        [window removeVariableDefinitionAtIndex:(NSUInteger)row];
        NSInteger nextRow = MIN(row, (NSInteger)window.variableDefinitions.count - 1);
        [self commitVariableDefinitionsForWindow:window selectRow:nextRow beginEditing:NO];
    }
}

- (IBAction)changeSelectedVariableType:(id)sender {
    (void)sender;
    NSInteger row = self.variablesTableView.selectedRow;
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (row < 0 || row >= (NSInteger)definitions.count) {
        return;
    }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    UDGuiVariableDefinitionType type = self.variablesTypeControl.selectedSegment == 1 ? UDGuiVariableDefinitionTypeVec4 : UDGuiVariableDefinitionTypeFloat;
    [self replaceVariableDefinitionAtRow:row type:type name:definition.name value:definition.value];
}

- (IBAction)commitTypedAttributesPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    if ([window isKindOfClass:[UDEditDefWindowNode class]]) {
        [window setValue:self.attrEditCvarField.stringValue forKey:@"cvar"];
        [window setValue:@(self.attrEditMaxCharsField.integerValue) forKey:@"maxChars"];
        [window setValue:self.attrEditSourceField.stringValue forKey:@"source"];
        [window setValue:self.attrEditCvarGroupField.stringValue forKey:@"cvarGroup"];
        [window setValue:@(self.attrEditNumericButton.state == NSControlStateValueOn) forKey:@"numeric"];
        [window setValue:@(self.attrEditWrapButton.state == NSControlStateValueOn) forKey:@"wrap"];
        [window setValue:@(self.attrEditReadOnlyButton.state == NSControlStateValueOn) forKey:@"readOnly"];
        [window setValue:@(self.attrEditForceScrollButton.state == NSControlStateValueOn) forKey:@"forceScroll"];
        [window setValue:@(self.attrEditPasswordButton.state == NSControlStateValueOn) forKey:@"password"];
        [window setValue:@(self.attrEditLiveUpdateButton.state == NSControlStateValueOn) forKey:@"liveUpdate"];
    }

    if ([window isKindOfClass:[UDChoiceDefWindowNode class]]) {
        [window setValue:self.attrChoiceCvarField.stringValue forKey:@"cvar"];
        [window setValue:@(self.attrChoiceChoiceTypeField.integerValue) forKey:@"choiceType"];
        [window setValue:self.attrChoiceChoicesField.stringValue forKey:@"choices"];
        [window setValue:self.attrChoiceValuesField.stringValue forKey:@"values"];
        [window setValue:@(self.attrChoiceCurrentField.integerValue) forKey:@"currentChoice"];
        [window setValue:self.attrChoiceGuiField.stringValue forKey:@"gui"];
        [window setValue:self.attrChoiceCvarGroupField.stringValue forKey:@"cvarGroup"];
        [window setValue:@(self.attrChoiceLiveUpdateButton.state == NSControlStateValueOn) forKey:@"liveUpdate"];
    }

    if ([window isKindOfClass:[UDBindDefWindowNode class]]) {
        [window setValue:self.attrBindField.stringValue forKey:@"bind"];
    }

    if ([window isKindOfClass:[UDListDefWindowNode class]]) {
        [window setValue:@(self.attrListHorizontalButton.state == NSControlStateValueOn) forKey:@"horizontal"];
        [window setValue:self.attrListNameField.stringValue forKey:@"listName"];
        [window setValue:self.attrListTabStopsField.stringValue forKey:@"tabStops"];
        [window setValue:self.attrListTabAlignsField.stringValue forKey:@"tabAligns"];
        [window setValue:@(self.attrListMultipleSelButton.state == NSControlStateValueOn) forKey:@"multipleSelection"];
    }

    if ([window isKindOfClass:[UDSliderDefWindowNode class]]) {
        [window setValue:self.attrSliderCvarField.stringValue forKey:@"cvar"];
        [window setValue:@(self.attrSliderLowField.doubleValue) forKey:@"low"];
        [window setValue:@(self.attrSliderHighField.doubleValue) forKey:@"high"];
        [window setValue:@(self.attrSliderStepField.doubleValue) forKey:@"stepSize"];
        [window setValue:@(self.attrSliderVerticalButton.state == NSControlStateValueOn) forKey:@"vertical"];
        [window setValue:@(self.attrSliderScrollBarButton.state == NSControlStateValueOn) forKey:@"scrollBar"];
        [window setValue:self.attrSliderThumbShaderField.stringValue forKey:@"thumbShader"];
        [window setValue:@(self.attrSliderLiveUpdateButton.state == NSControlStateValueOn) forKey:@"liveUpdate"];
        [window setValue:self.attrSliderCvarGroupField.stringValue forKey:@"cvarGroup"];
    }

    if ([window isKindOfClass:[UDRenderDefWindowNode class]]) {
        [window setValue:self.attrRenderModelField.stringValue forKey:@"model"];
        [window setValue:self.attrRenderAnimField.stringValue forKey:@"anim"];
        [window setValue:self.attrRenderAnimClassField.stringValue forKey:@"animClass"];
        [window setValue:self.attrRenderLightOriginField.stringValue forKey:@"lightOrigin"];
        [window setValue:self.attrRenderLightColorField.stringValue forKey:@"lightColor"];
        [window setValue:self.attrRenderModelOriginField.stringValue forKey:@"modelOrigin"];
        [window setValue:self.attrRenderModelRotateField.stringValue forKey:@"modelRotate"];
        [window setValue:self.attrRenderViewOffsetField.stringValue forKey:@"viewOffset"];
        [window setValue:@(self.attrRenderNeedsRenderButton.state == NSControlStateValueOn) forKey:@"needsRender"];
    }

    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (IBAction)commitWindowInfoPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    [window setValue:@(self.infoShowTimeButton.state == NSControlStateValueOn) forKey:@"showTime"];
    [window setValue:@(self.infoShowCoordsButton.state == NSControlStateValueOn) forKey:@"showCoords"];
    [window setValue:@(self.infoVisibleButton.state == NSControlStateValueOn) forKey:@"visible"];
    [window setValue:@(self.infoNoEventsButton.state == NSControlStateValueOn) forKey:@"noEvents"];
    [window setValue:@(self.infoForceAspectWidthField.doubleValue) forKey:@"forceAspectWidth"];
    [window setValue:@(self.infoForceAspectHeightField.doubleValue) forKey:@"forceAspectHeight"];
    [window setValue:@(self.infoMatScaleXField.doubleValue) forKey:@"matScaleX"];
    [window setValue:@(self.infoMatScaleYField.doubleValue) forKey:@"matScaleY"];
    [window setValue:@(self.infoBorderSizeField.doubleValue) forKey:@"borderSize"];
    [window setValue:self.infoForeColorField.stringValue forKey:@"foreColor"];
    [window setValue:self.infoHoverColorField.stringValue forKey:@"hoverColor"];
    [window setValue:self.infoBackColorField.stringValue forKey:@"backColor"];
    [window setValue:self.infoBorderColorField.stringValue forKey:@"borderColor"];
    [window setValue:self.infoMatColorField.stringValue forKey:@"matColor"];
    [window setValue:@(self.infoNoWrapButton.state == NSControlStateValueOn) forKey:@"noWrap"];
    [window setValue:@(self.infoShadowButton.state == NSControlStateValueOn) forKey:@"shadow"];
    [window setValue:@(self.infoTextAlignField.integerValue) forKey:@"textAlign"];
    [window setValue:@(self.infoTextAlignXField.doubleValue) forKey:@"textAlignX"];
    [window setValue:@(self.infoTextAlignYField.doubleValue) forKey:@"textAlignY"];
    [window setValue:self.infoShearField.stringValue forKey:@"shear"];
    [window setValue:@(self.infoWantEnterButton.state == NSControlStateValueOn) forKey:@"wantEnter"];
    [window setValue:@(self.infoNaturalMatScaleButton.state == NSControlStateValueOn) forKey:@"naturalMatScale"];
    [window setValue:@(self.infoNoClipButton.state == NSControlStateValueOn) forKey:@"noClip"];
    [window setValue:@(self.infoNoCursorButton.state == NSControlStateValueOn) forKey:@"noCursor"];
    [window setValue:@(self.infoMenuGUIButton.state == NSControlStateValueOn) forKey:@"menuGUI"];
    [window setValue:@(self.infoModalButton.state == NSControlStateValueOn) forKey:@"modal"];
    [window setValue:@(self.infoInvertRectButton.state == NSControlStateValueOn) forKey:@"invertRect"];
    [window setValue:self.infoNameOverrideField.stringValue forKey:@"nameOverride"];
    [window setValue:self.infoTextField.stringValue forKey:@"text"];
    [window setValue:self.infoBackgroundField.stringValue forKey:@"background"];
    [window setValue:self.infoVarBackgroundField.stringValue forKey:@"varBackground"];
    [window setValue:self.infoRunScriptField.stringValue forKey:@"runScript"];
    [window setValue:self.infoPlayField.stringValue forKey:@"play"];
    [window setValue:self.infoCommentField.stringValue forKey:@"comment"];
    [window setValue:self.infoFontField.stringValue forKey:@"font"];

    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (IBAction)commitTypedSizePanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    [window setValue:self.sizeRectField.stringValue forKey:@"rect"];
    [window setValue:self.sizeRotateField.stringValue forKey:@"rotate"];
    [window setValue:self.sizeScaleField.stringValue forKey:@"scale"];
    [window setValue:self.sizeTranslateField.stringValue forKey:@"translate"];
    [window setValue:@(self.sizeTextScaleField.doubleValue) forKey:@"textScale"];
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshTypedValidationHintsForWindow:self.ownerDocument.viewModel.selectedWindow];
    [self refreshFromDocument];
}

- (IBAction)commitTypedVariablesPanel:(id)sender {
    (void)sender;
}

- (IBAction)commitTypedEventsPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    [window setValue:self.eventsOnActionField.stringValue forKey:@"onAction"];
    [window setValue:self.eventsOnTimeField.stringValue forKey:@"onTime"];
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshTypedValidationHintsForWindow:self.ownerDocument.viewModel.selectedWindow];
    [self refreshFromDocument];
}


- (void)restoreOutlineSelection {
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        [self.outlineView deselectAll:nil];
        return;
    }

    NSInteger row = [self.outlineView rowForItem:selectedWindow];
    if (row >= 0) {
        [self.outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self.outlineView scrollRowToVisible:row];
    }
}

- (void)syncSelectionToViewModel:(UDGuiWindowNode *)selectedWindow {
    self.ownerDocument.viewModel.selectedWindow = selectedWindow;
}

- (UDGuiWindowNode *)windowNodeForOutlineItem:(id)item {
    return [item isKindOfClass:[UDGuiWindowNode class]] ? item : nil;
}

- (void)commitWindowIdentityEdit:(id)sender {
    (void)sender;
    if (self.activeInspectorSection != UDGuiInspectorSectionIdentity) {
        return;
    }
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        return;
    }

    if (self.classNameField.stringValue.length > 0) {
        [self.ownerDocument.editorService updateWindow:selectedWindow className:self.classNameField.stringValue];
    }
    if (self.windowNameField.stringValue.length > 0) {
        [self.ownerDocument.editorService updateWindow:selectedWindow name:self.windowNameField.stringValue];
    }

    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    id field = notification.object;
    if ([self isWindowInspectorField:field]) {
        [self commitWindowIdentityEdit:field];
        return;
    }
}

- (IBAction)addRootWindow:(id)sender {
    (void)sender;
    NSUInteger nextIndex = self.ownerDocument.viewModel.rootWindows.count + 1;
    UDGuiWindowNode *window = [UDGuiWindowNode windowNodeWithClassName:@"windowDef" name:[NSString stringWithFormat:@"Window%lu", (unsigned long)nextIndex]];
    [self.ownerDocument.editorService addWindow:window toParent:nil atIndex:self.ownerDocument.viewModel.rootWindows.count];
    self.ownerDocument.viewModel.selectedWindow = window;
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (IBAction)addChildWindow:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        return;
    }

    NSUInteger nextIndex = selectedWindow.children.count + 1;
    UDGuiWindowNode *window = [UDGuiWindowNode windowNodeWithClassName:@"windowDef" name:[NSString stringWithFormat:@"Child%lu", (unsigned long)nextIndex]];
    [self.ownerDocument.editorService addWindow:window toParent:selectedWindow atIndex:selectedWindow.children.count];
    self.ownerDocument.viewModel.selectedWindow = window;
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

- (IBAction)deleteSelectedWindow:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) {
        return;
    }

    [self.ownerDocument.editorService removeWindow:selectedWindow];
    self.ownerDocument.viewModel.selectedWindow = selectedWindow.parent;
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

#pragma mark - Outline view data source

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    (void)outlineView;
    NSArray<UDGuiWindowNode *> *children = [self.ownerDocument.viewModel childrenOfWindow:[self windowNodeForOutlineItem:item]];
    return (NSInteger)children.count;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    (void)outlineView;
    return [self outlineView:outlineView numberOfChildrenOfItem:item] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    (void)outlineView;
    NSArray<UDGuiWindowNode *> *children = [self.ownerDocument.viewModel childrenOfWindow:[self windowNodeForOutlineItem:item]];
    if (index < 0 || index >= (NSInteger)children.count) {
        return nil;
    }
    return [children objectAtIndex:(NSUInteger)index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
    (void)outlineView;
    UDGuiWindowNode *window = [self windowNodeForOutlineItem:item];
    if (!window) {
        return @"";
    }

    if ([tableColumn.identifier isEqualToString:@"node"]) {
        return [NSString stringWithFormat:@"%@ %@", window.className, window.name];
    }
    return @"";
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    NSInteger row = self.outlineView.selectedRow;
    UDGuiWindowNode *selectedWindow = row >= 0 ? [self.outlineView itemAtRow:row] : nil;
    [self syncSelectionToViewModel:selectedWindow];
    [self refreshFromDocument];
}

#pragma mark - Table view data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.variablesTableView) {
        return (NSInteger)[self selectedWindowVariableDefinitions].count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.variablesTableView) {
        return @"";
    }

    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (row < 0 || row >= (NSInteger)definitions.count) {
        return @"";
    }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    if ([tableColumn.identifier isEqualToString:@"name"]) {
        return definition.name;
    }
    if ([tableColumn.identifier isEqualToString:@"type"]) {
        return definition.type == UDGuiVariableDefinitionTypeVec4 ? @"vec4" : @"float";
    }
    if ([tableColumn.identifier isEqualToString:@"value"]) {
        return definition.value;
    }
    return @"";
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView != self.variablesTableView) {
        return;
    }

    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (row < 0 || row >= (NSInteger)definitions.count) {
        return;
    }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    NSString *stringValue = [object isKindOfClass:[NSString class]] ? (NSString *)object : [[object description] copy];

    if ([tableColumn.identifier isEqualToString:@"name"]) {
        [self replaceVariableDefinitionAtRow:row type:definition.type name:stringValue value:definition.value];
        return;
    }

    if ([tableColumn.identifier isEqualToString:@"value"]) {
        [self replaceVariableDefinitionAtRow:row type:definition.type name:definition.name value:stringValue];
    }
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.variablesTableView) {
        [self syncVariableControlsFromSelection];
    }
}

@end