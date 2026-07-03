/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDInspectorController.m — Inspector panel controller for the GUI editor.
 */

#import "UDInspectorController.h"

#import "../UDCore/UDGuiModel.h"
#import "UDGuiEdDocument.h"
#import "UDGuiEditorService.h"
#import "UDGuiEditorViewModel.h"

@implementation UDInspectorController

@synthesize view = _view;
@synthesize identityView = _identityView;
@synthesize sizeView = _sizeView;
@synthesize classNameField = _classNameField;
@synthesize windowNameField = _windowNameField;

- (instancetype)init {
    self = [super init];
    if (self) {
#ifdef GNUSTEP
        [NSBundle loadNibNamed:@"UDInspector" owner:self];
#else
        [[NSBundle mainBundle] loadNibNamed:@"UDInspector" owner:self topLevelObjects:nil];
#endif
    }
    return self;
}

// MARK: - Private helpers

- (void)setHintLabel:(NSTextField *)label valid:(BOOL)valid {
    if (!label) {
        return;
    }
    label.textColor = valid ? [NSColor secondaryLabelColor] : [NSColor systemRedColor];
}

- (void)syncBoolButton:(NSButton *)button
                   key:(NSString *)key
                window:(nullable UDGuiWindowNode *)window
      defaultOnWhenNil:(BOOL)defaultOnWhenNil {
    BOOL value = window ? [[window valueForKey:key] boolValue] : defaultOnWhenNil;
    button.state = value ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)syncDoubleField:(NSTextField *)field key:(NSString *)key window:(nullable UDGuiWindowNode *)window {
    field.stringValue = window ? [NSString stringWithFormat:@"%g", [[window valueForKey:key] doubleValue]] : @"";
}

- (void)syncIntegerField:(NSTextField *)field key:(NSString *)key window:(nullable UDGuiWindowNode *)window {
    field.stringValue = window ? [NSString stringWithFormat:@"%ld", (long)[[window valueForKey:key] integerValue]] : @"";
}

- (void)syncStringField:(NSTextField *)field key:(NSString *)key window:(nullable UDGuiWindowNode *)window {
    field.stringValue = window ? ([window valueForKey:key] ?: @"") : @"";
}

- (void)applyBoolButton:(NSButton *)button key:(NSString *)key window:(UDGuiWindowNode *)window {
    [window setValue:@(button.state == NSControlStateValueOn) forKey:key];
}

- (void)applyDoubleField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window {
    [window setValue:@(field.doubleValue) forKey:key];
}

- (void)applyIntegerField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window {
    [window setValue:@(field.integerValue) forKey:key];
}

- (void)applyStringField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window {
    [window setValue:field.stringValue forKey:key];
}

// MARK: - Typed-panel dispatch

- (id)typedWindow:(UDGuiWindowNode *)window class:(Class)windowClass {
    return [window isKindOfClass:windowClass] ? window : nil;
}

- (void)dispatchTypedPanelsForWindow:(nullable UDGuiWindowNode *)window sync:(BOOL)sync {
    Class windowClasses[] = {
        [UDEditDefWindowNode class],
        [UDChoiceDefWindowNode class],
        [UDBindDefWindowNode class],
        [UDListDefWindowNode class],
        [UDSliderDefWindowNode class],
        [UDRenderDefWindowNode class],
    };

    SEL selectors[] = {
        sync ? @selector(syncEditPanelFromWindow:)   : @selector(applyEditPanelToWindow:),
        sync ? @selector(syncChoicePanelFromWindow:) : @selector(applyChoicePanelToWindow:),
        sync ? @selector(syncBindPanelFromWindow:)   : @selector(applyBindPanelToWindow:),
        sync ? @selector(syncListPanelFromWindow:)   : @selector(applyListPanelToWindow:),
        sync ? @selector(syncSliderPanelFromWindow:) : @selector(applySliderPanelToWindow:),
        sync ? @selector(syncRenderPanelFromWindow:) : @selector(applyRenderPanelToWindow:),
    };

    for (NSInteger typeIndex = 0; typeIndex < (NSInteger)(sizeof(windowClasses) / sizeof(windowClasses[0])); typeIndex++) {
        id typedWindow = [self typedWindow:window class:windowClasses[typeIndex]];
        if (!sync && !typedWindow) {
            continue;
        }
        SEL selector = selectors[typeIndex];
        typedef void (*TypedPanelDispatch)(id, SEL, id);
        TypedPanelDispatch dispatch = (TypedPanelDispatch)[self methodForSelector:selector];
        dispatch(self, selector, typedWindow);
    }
}

// MARK: - Per-type sync

- (void)syncEditPanelFromWindow:(nullable UDEditDefWindowNode *)window {
    self.attrEditCvarField.stringValue       = window.cvar ?: @"";
    self.attrEditMaxCharsField.stringValue   = window ? [NSString stringWithFormat:@"%ld", (long)window.maxChars] : @"";
    self.attrEditSourceField.stringValue     = window.source ?: @"";
    self.attrEditCvarGroupField.stringValue  = window.cvarGroup ?: @"";
    self.attrEditNumericButton.state    = window.numeric    ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditWrapButton.state       = window.wrap       ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditReadOnlyButton.state   = window.readOnly   ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditForceScrollButton.state= window.forceScroll? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditPasswordButton.state   = window.password   ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditLiveUpdateButton.state = (!window || window.liveUpdate) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyEditPanelToWindow:(UDEditDefWindowNode *)window {
    window.cvar       = self.attrEditCvarField.stringValue;
    window.maxChars   = self.attrEditMaxCharsField.integerValue;
    window.source     = self.attrEditSourceField.stringValue;
    window.cvarGroup  = self.attrEditCvarGroupField.stringValue;
    window.numeric    = self.attrEditNumericButton.state    == NSControlStateValueOn;
    window.wrap       = self.attrEditWrapButton.state       == NSControlStateValueOn;
    window.readOnly   = self.attrEditReadOnlyButton.state   == NSControlStateValueOn;
    window.forceScroll= self.attrEditForceScrollButton.state== NSControlStateValueOn;
    window.password   = self.attrEditPasswordButton.state   == NSControlStateValueOn;
    window.liveUpdate = self.attrEditLiveUpdateButton.state == NSControlStateValueOn;
}

- (void)syncChoicePanelFromWindow:(nullable UDChoiceDefWindowNode *)window {
    self.attrChoiceCvarField.stringValue        = window.cvar ?: @"";
    self.attrChoiceChoiceTypeField.stringValue  = window ? [NSString stringWithFormat:@"%ld", (long)window.choiceType] : @"";
    self.attrChoiceChoicesField.stringValue     = window.choices ?: @"";
    self.attrChoiceValuesField.stringValue      = window.values ?: @"";
    self.attrChoiceCurrentField.stringValue     = window ? [NSString stringWithFormat:@"%ld", (long)window.currentChoice] : @"";
    self.attrChoiceGuiField.stringValue         = window.gui ?: @"";
    self.attrChoiceCvarGroupField.stringValue   = window.cvarGroup ?: @"";
    self.attrChoiceLiveUpdateButton.state = (!window || window.liveUpdate) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyChoicePanelToWindow:(UDChoiceDefWindowNode *)window {
    window.cvar          = self.attrChoiceCvarField.stringValue;
    window.choiceType    = self.attrChoiceChoiceTypeField.integerValue;
    window.choices       = self.attrChoiceChoicesField.stringValue;
    window.values        = self.attrChoiceValuesField.stringValue;
    window.currentChoice = self.attrChoiceCurrentField.integerValue;
    window.gui           = self.attrChoiceGuiField.stringValue;
    window.cvarGroup     = self.attrChoiceCvarGroupField.stringValue;
    window.liveUpdate    = self.attrChoiceLiveUpdateButton.state == NSControlStateValueOn;
}

- (void)syncBindPanelFromWindow:(nullable UDBindDefWindowNode *)window {
    self.attrBindField.stringValue = window.bind ?: @"";
}

- (void)applyBindPanelToWindow:(UDBindDefWindowNode *)window {
    window.bind = self.attrBindField.stringValue;
}

- (void)syncListPanelFromWindow:(nullable UDListDefWindowNode *)window {
    self.attrListHorizontalButton.state   = window.horizontal        ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrListNameField.stringValue    = window.listName  ?: @"";
    self.attrListTabStopsField.stringValue= window.tabStops  ?: @"";
    self.attrListTabAlignsField.stringValue= window.tabAligns?: @"";
    self.attrListMultipleSelButton.state  = window.multipleSelection ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyListPanelToWindow:(UDListDefWindowNode *)window {
    window.horizontal        = self.attrListHorizontalButton.state == NSControlStateValueOn;
    window.listName          = self.attrListNameField.stringValue;
    window.tabStops          = self.attrListTabStopsField.stringValue;
    window.tabAligns         = self.attrListTabAlignsField.stringValue;
    window.multipleSelection = self.attrListMultipleSelButton.state == NSControlStateValueOn;
}

- (void)syncSliderPanelFromWindow:(nullable UDSliderDefWindowNode *)window {
    self.attrSliderCvarField.stringValue        = window.cvar ?: @"";
    self.attrSliderLowField.stringValue         = window ? [NSString stringWithFormat:@"%g", window.low]      : @"";
    self.attrSliderHighField.stringValue        = window ? [NSString stringWithFormat:@"%g", window.high]     : @"";
    self.attrSliderStepField.stringValue        = window ? [NSString stringWithFormat:@"%g", window.stepSize] : @"";
    self.attrSliderVerticalButton.state   = window.vertical  ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderScrollBarButton.state  = window.scrollBar ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderThumbShaderField.stringValue = window.thumbShader ?: @"";
    self.attrSliderLiveUpdateButton.state = (!window || window.liveUpdate) ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderCvarGroupField.stringValue   = window.cvarGroup ?: @"";
}

- (void)applySliderPanelToWindow:(UDSliderDefWindowNode *)window {
    window.cvar        = self.attrSliderCvarField.stringValue;
    window.low         = self.attrSliderLowField.doubleValue;
    window.high        = self.attrSliderHighField.doubleValue;
    window.stepSize    = self.attrSliderStepField.doubleValue;
    window.vertical    = self.attrSliderVerticalButton.state   == NSControlStateValueOn;
    window.scrollBar   = self.attrSliderScrollBarButton.state  == NSControlStateValueOn;
    window.thumbShader = self.attrSliderThumbShaderField.stringValue;
    window.liveUpdate  = self.attrSliderLiveUpdateButton.state == NSControlStateValueOn;
    window.cvarGroup   = self.attrSliderCvarGroupField.stringValue;
}

- (void)syncRenderPanelFromWindow:(nullable UDRenderDefWindowNode *)window {
    self.attrRenderModelField.stringValue      = window.model ?: @"";
    self.attrRenderAnimField.stringValue       = window.anim  ?: @"";
    self.attrRenderAnimClassField.stringValue  = window.animClass ?: @"";
    self.attrRenderLightOriginField.stringValue= window.lightOrigin ?: @"";
    self.attrRenderLightColorField.stringValue = window.lightColor  ?: @"";
    self.attrRenderModelOriginField.stringValue= window.modelOrigin ?: @"";
    self.attrRenderModelRotateField.stringValue= window.modelRotate ?: @"";
    self.attrRenderViewOffsetField.stringValue = window.viewOffset  ?: @"";
    self.attrRenderNeedsRenderButton.state = (!window || window.needsRender) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyRenderPanelToWindow:(UDRenderDefWindowNode *)window {
    window.model       = self.attrRenderModelField.stringValue;
    window.anim        = self.attrRenderAnimField.stringValue;
    window.animClass   = self.attrRenderAnimClassField.stringValue;
    window.lightOrigin = self.attrRenderLightOriginField.stringValue;
    window.lightColor  = self.attrRenderLightColorField.stringValue;
    window.modelOrigin = self.attrRenderModelOriginField.stringValue;
    window.modelRotate = self.attrRenderModelRotateField.stringValue;
    window.viewOffset  = self.attrRenderViewOffsetField.stringValue;
    window.needsRender = self.attrRenderNeedsRenderButton.state == NSControlStateValueOn;
}

// MARK: - Validation helpers

- (BOOL)previewWindow:(UDGuiWindowNode *)window validatesValue:(id)value forKey:(NSString *)key {
    id candidateValue = value ?: @"";
    NSError *error = nil;
    return [window validateValue:&candidateValue forKey:key error:&error];
}

- (UDGuiWindowNode *)validationPreviewWindowFromWindow:(nullable UDGuiWindowNode *)window {
    UDGuiWindowNode *preview = window ? [window deepCopy] : [UDGuiWindowNode windowNodeWithClassName:@"windowDef" name:@"Preview"];
    [self applySizePanelToWindow:preview];
    [self applyTypedPanelsToWindow:preview];
    return preview;
}

- (BOOL)validateEditorValue:(id)value forKey:(NSString *)key onWindow:(UDGuiWindowNode *)window {
    id candidateValue = value ?: @"";
    NSError *error = nil;
    BOOL valid = [window validateValue:&candidateValue forKey:key error:&error];
    if (!valid && error) {
        [self.context presentError:error];
    }
    return valid;
}

- (BOOL)validateStringKeys:(NSArray<NSString *> *)keys
               fieldValues:(NSDictionary<NSString *, NSString *> *)fieldValues
                  onWindow:(UDGuiWindowNode *)window {
    for (NSString *key in keys) {
        NSString *value = fieldValues[key] ?: @"";
        if (![self validateEditorValue:value forKey:key onWindow:window]) {
            return NO;
        }
    }
    return YES;
}

// MARK: - UDInspectorController public interface

- (void)updateAttributeGroupVisibilityForWindow:(nullable UDGuiWindowNode *)window {
    NSInteger selectedType = [self attributeTypeTabForWindow:window];
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

- (void)refreshValidationHintsForWindow:(nullable UDGuiWindowNode *)window {
    UDGuiWindowNode *preview = [self validationPreviewWindowFromWindow:window];
    BOOL rectValid    = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyRect]     ?: @"" forKey:UDGuiWindowPropertyRect];
    BOOL rotateValid  = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyRotate]   ?: @"" forKey:UDGuiWindowPropertyRotate];
    BOOL tabStopsValid= [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyTabStops] ?: @"" forKey:UDGuiWindowPropertyTabStops];
    BOOL tabAlignsValid=[self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyTabAligns]?: @"" forKey:UDGuiWindowPropertyTabAligns];

    [self setHintLabel:self.sizeRectHintLabel    valid:rectValid];
    [self setHintLabel:self.sizeRotateHintLabel  valid:rotateValid];
    [self setHintLabel:self.attrListTabStopsHintLabel  valid:tabStopsValid];
    [self setHintLabel:self.attrListTabAlignsHintLabel valid:tabAlignsValid];
}

- (void)syncSizePanelFromWindow:(nullable UDGuiWindowNode *)window {
    BOOL hasWindow = window != nil;
    self.sizeRectField.stringValue      = hasWindow ? [window stringPropertyForKey:UDGuiWindowPropertyRect]    ?: @"" : @"";
    self.sizeRotateField.stringValue    = hasWindow ? [window stringPropertyForKey:UDGuiWindowPropertyRotate]  ?: @"" : @"";
    self.sizeScaleField.stringValue     = hasWindow ? [window valueForKey:UDGuiWindowPropertyScale]             ?: @"" : @"";
    self.sizeTranslateField.stringValue = hasWindow ? [window valueForKey:UDGuiWindowPropertyTranslate]         ?: @"" : @"";
    self.sizeTextScaleField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:UDGuiWindowPropertyTextScale] doubleValue]] : @"";
}

- (void)syncInfoPanelFromWindow:(nullable UDGuiWindowNode *)window {
    // Boolean buttons
    struct { NSButton *__weak btn; NSString *key; BOOL defaultOn; } boolBindings[] = {
        { self.infoShowTimeButton,       UDGuiWindowPropertyShowTime,       NO },
        { self.infoShowCoordsButton,     UDGuiWindowPropertyShowCoords,     NO },
        { self.infoVisibleButton,        UDGuiWindowPropertyVisible,        YES },
        { self.infoNoEventsButton,       UDGuiWindowPropertyNoEvents,       NO },
        { self.infoNoWrapButton,         UDGuiWindowPropertyNoWrap,         NO },
        { self.infoShadowButton,         UDGuiWindowPropertyShadow,         NO },
        { self.infoWantEnterButton,      UDGuiWindowPropertyWantEnter,      NO },
        { self.infoNaturalMatScaleButton,UDGuiWindowPropertyNaturalMatScale,NO },
        { self.infoNoClipButton,         UDGuiWindowPropertyNoClip,         NO },
        { self.infoNoCursorButton,       UDGuiWindowPropertyNoCursor,       NO },
        { self.infoMenuGUIButton,        UDGuiWindowPropertyMenuGUI,        NO },
        { self.infoModalButton,          UDGuiWindowPropertyModal,          NO },
        { self.infoInvertRectButton,     UDGuiWindowPropertyInvertRect,     NO },
    };
    for (size_t bindingIndex = 0; bindingIndex < sizeof(boolBindings)/sizeof(boolBindings[0]); bindingIndex++) {
        if (boolBindings[bindingIndex].btn) {
            [self syncBoolButton:boolBindings[bindingIndex].btn key:boolBindings[bindingIndex].key
                          window:window defaultOnWhenNil:boolBindings[bindingIndex].defaultOn];
        }
    }

    // Double fields
    NSTextField *__weak doubleFields[]  = { self.infoForceAspectWidthField, self.infoForceAspectHeightField, self.infoMatScaleXField, self.infoMatScaleYField, self.infoBorderSizeField, self.infoTextAlignXField, self.infoTextAlignYField };
    NSString    *doubleKeys[]           = { UDGuiWindowPropertyForceAspectWidth, UDGuiWindowPropertyForceAspectHeight, UDGuiWindowPropertyMatScaleX, UDGuiWindowPropertyMatScaleY, UDGuiWindowPropertyBorderSize, UDGuiWindowPropertyTextAlignX, UDGuiWindowPropertyTextAlignY };
    for (size_t fieldIndex = 0; fieldIndex < sizeof(doubleFields)/sizeof(doubleFields[0]); fieldIndex++) {
        if (doubleFields[fieldIndex]) { [self syncDoubleField:doubleFields[fieldIndex] key:doubleKeys[fieldIndex] window:window]; }
    }

    // Integer fields
    if (self.infoTextAlignField) { [self syncIntegerField:self.infoTextAlignField key:UDGuiWindowPropertyTextAlign window:window]; }

    // String fields
    NSTextField *__weak stringFields[] = { self.infoForeColorField, self.infoHoverColorField, self.infoBackColorField, self.infoBorderColorField, self.infoMatColorField, self.infoShearField, self.infoNameOverrideField, self.infoTextField, self.infoBackgroundField, self.infoVarBackgroundField, self.infoRunScriptField, self.infoPlayField, self.infoCommentField, self.infoFontField };
    NSString    *stringKeys[]          = { UDGuiWindowPropertyForeColor, UDGuiWindowPropertyHoverColor, UDGuiWindowPropertyBackColor, UDGuiWindowPropertyBorderColor, UDGuiWindowPropertyMatColor, UDGuiWindowPropertyShear, UDGuiWindowPropertyNameOverride, UDGuiWindowPropertyText, UDGuiWindowPropertyBackground, UDGuiWindowPropertyVarBackground, UDGuiWindowPropertyRunScript, UDGuiWindowPropertyPlay, UDGuiWindowPropertyComment, UDGuiWindowPropertyFont };
    for (size_t fieldIndex = 0; fieldIndex < sizeof(stringFields)/sizeof(stringFields[0]); fieldIndex++) {
        if (stringFields[fieldIndex]) { [self syncStringField:stringFields[fieldIndex] key:stringKeys[fieldIndex] window:window]; }
    }
}

- (void)syncFromWindow:(nullable UDGuiWindowNode *)window {
    [self syncInfoPanelFromWindow:window];
    [self syncSizePanelFromWindow:window];
    [self dispatchTypedPanelsForWindow:window sync:YES];
    [self updateAttributeGroupVisibilityForWindow:window];
    [self refreshValidationHintsForWindow:window];
}

- (void)applyInfoPanelToWindow:(UDGuiWindowNode *)window {
    // Boolean buttons
    struct { NSButton *__weak btn; NSString *key; } boolBindings[] = {
        { self.infoShowTimeButton,        UDGuiWindowPropertyShowTime },
        { self.infoShowCoordsButton,      UDGuiWindowPropertyShowCoords },
        { self.infoVisibleButton,         UDGuiWindowPropertyVisible },
        { self.infoNoEventsButton,        UDGuiWindowPropertyNoEvents },
        { self.infoNoWrapButton,          UDGuiWindowPropertyNoWrap },
        { self.infoShadowButton,          UDGuiWindowPropertyShadow },
        { self.infoWantEnterButton,       UDGuiWindowPropertyWantEnter },
        { self.infoNaturalMatScaleButton, UDGuiWindowPropertyNaturalMatScale },
        { self.infoNoClipButton,          UDGuiWindowPropertyNoClip },
        { self.infoNoCursorButton,        UDGuiWindowPropertyNoCursor },
        { self.infoMenuGUIButton,         UDGuiWindowPropertyMenuGUI },
        { self.infoModalButton,           UDGuiWindowPropertyModal },
        { self.infoInvertRectButton,      UDGuiWindowPropertyInvertRect },
    };
    for (size_t bindingIndex = 0; bindingIndex < sizeof(boolBindings)/sizeof(boolBindings[0]); bindingIndex++) {
        if (boolBindings[bindingIndex].btn) {
            [self applyBoolButton:boolBindings[bindingIndex].btn key:boolBindings[bindingIndex].key window:window];
        }
    }

    // Double fields
    NSTextField *__weak doubleFields[] = { self.infoForceAspectWidthField, self.infoForceAspectHeightField, self.infoMatScaleXField, self.infoMatScaleYField, self.infoBorderSizeField, self.infoTextAlignXField, self.infoTextAlignYField };
    NSString    *doubleKeys[]          = { UDGuiWindowPropertyForceAspectWidth, UDGuiWindowPropertyForceAspectHeight, UDGuiWindowPropertyMatScaleX, UDGuiWindowPropertyMatScaleY, UDGuiWindowPropertyBorderSize, UDGuiWindowPropertyTextAlignX, UDGuiWindowPropertyTextAlignY };
    for (size_t fieldIndex = 0; fieldIndex < sizeof(doubleFields)/sizeof(doubleFields[0]); fieldIndex++) {
        if (doubleFields[fieldIndex]) { [self applyDoubleField:doubleFields[fieldIndex] key:doubleKeys[fieldIndex] window:window]; }
    }

    // Integer fields
    if (self.infoTextAlignField) { [self applyIntegerField:self.infoTextAlignField key:UDGuiWindowPropertyTextAlign window:window]; }

    // String fields
    NSTextField *__weak stringFields[] = { self.infoForeColorField, self.infoHoverColorField, self.infoBackColorField, self.infoBorderColorField, self.infoMatColorField, self.infoShearField, self.infoNameOverrideField, self.infoTextField, self.infoBackgroundField, self.infoVarBackgroundField, self.infoRunScriptField, self.infoPlayField, self.infoCommentField, self.infoFontField };
    NSString    *stringKeys[]          = { UDGuiWindowPropertyForeColor, UDGuiWindowPropertyHoverColor, UDGuiWindowPropertyBackColor, UDGuiWindowPropertyBorderColor, UDGuiWindowPropertyMatColor, UDGuiWindowPropertyShear, UDGuiWindowPropertyNameOverride, UDGuiWindowPropertyText, UDGuiWindowPropertyBackground, UDGuiWindowPropertyVarBackground, UDGuiWindowPropertyRunScript, UDGuiWindowPropertyPlay, UDGuiWindowPropertyComment, UDGuiWindowPropertyFont };
    for (size_t fieldIndex = 0; fieldIndex < sizeof(stringFields)/sizeof(stringFields[0]); fieldIndex++) {
        if (stringFields[fieldIndex]) { [self applyStringField:stringFields[fieldIndex] key:stringKeys[fieldIndex] window:window]; }
    }
}

- (void)applySizePanelToWindow:(UDGuiWindowNode *)window {
    [window setValue:self.sizeRectField.stringValue      forKey:UDGuiWindowPropertyRect];
    [window setValue:self.sizeRotateField.stringValue    forKey:UDGuiWindowPropertyRotate];
    [window setValue:self.sizeScaleField.stringValue     forKey:UDGuiWindowPropertyScale];
    [window setValue:self.sizeTranslateField.stringValue forKey:UDGuiWindowPropertyTranslate];
    [window setValue:@(self.sizeTextScaleField.doubleValue) forKey:UDGuiWindowPropertyTextScale];
}

- (void)applyTypedPanelsToWindow:(UDGuiWindowNode *)window {
    [self dispatchTypedPanelsForWindow:window sync:NO];
}

- (BOOL)validateSizePanelForWindow:(UDGuiWindowNode *)window {
    return [self validateStringKeys:@[UDGuiWindowPropertyRect, UDGuiWindowPropertyRotate]
                        fieldValues:@{
                            UDGuiWindowPropertyRect:   self.sizeRectField.stringValue   ?: @"",
                            UDGuiWindowPropertyRotate: self.sizeRotateField.stringValue ?: @"",
                        }
                           onWindow:window];
}

- (BOOL)validateTypedPanelsForWindow:(UDGuiWindowNode *)window {
    if (![window isKindOfClass:[UDListDefWindowNode class]]) {
        return YES;
    }
    return [self validateStringKeys:@[UDGuiWindowPropertyTabStops, UDGuiWindowPropertyTabAligns]
                        fieldValues:@{
                            UDGuiWindowPropertyTabStops:  self.attrListTabStopsField.stringValue  ?: @"",
                            UDGuiWindowPropertyTabAligns: self.attrListTabAlignsField.stringValue ?: @"",
                        }
                           onWindow:window];
}

- (UDGuiAttributeTypeTab)attributeTypeTabForWindow:(nullable UDGuiWindowNode *)window {
    Class windowClasses[] = {
        [UDEditDefWindowNode class],
        [UDChoiceDefWindowNode class],
        [UDBindDefWindowNode class],
        [UDListDefWindowNode class],
        [UDSliderDefWindowNode class],
        [UDRenderDefWindowNode class],
    };
    for (NSInteger classIndex = 0; classIndex < (NSInteger)(sizeof(windowClasses) / sizeof(windowClasses[0])); classIndex++) {
        if ([window isKindOfClass:windowClasses[classIndex]]) {
            return (UDGuiAttributeTypeTab)classIndex;
        }
    }
    return (UDGuiAttributeTypeTab)-1;
}

// MARK: - Actions

- (IBAction)commitTypedAttributesPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    if (![self validateTypedPanelsForWindow:window]) {
        [self refreshValidationHintsForWindow:window];
        return;
    }
    [self applyTypedPanelsToWindow:window];
    [self.context notifyModelChangedAndRefresh];
}

- (IBAction)commitWindowInfoPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    [self applyInfoPanelToWindow:window];
    [self.context notifyModelChangedAndRefresh];
}

- (IBAction)commitTypedSizePanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    if (![self validateSizePanelForWindow:window]) {
        [self refreshValidationHintsForWindow:window];
        return;
    }
    [self applySizePanelToWindow:window];
    [self.context notifyModelChangedAndRefresh];
}

- (IBAction)commitWindowIdentityEdit:(id)sender {
    (void)sender;
    UDGuiWindowNode *selectedWindow = self.context.ownerDocument.viewModel.selectedWindow;
    if (!selectedWindow) { return; }

    if (self.classNameField.stringValue.length > 0) {
        [self.context.ownerDocument.editorService updateWindow:selectedWindow
                                                     className:self.classNameField.stringValue];
    }
    if (self.windowNameField.stringValue.length > 0) {
        [self.context.ownerDocument.editorService updateWindow:selectedWindow
                                                          name:self.windowNameField.stringValue];
    }
    [self.context notifyModelChangedAndRefresh];
}

// MARK: - NSTextFieldDelegate

- (BOOL)isWindowIdentityField:(id)sender {
    return sender == self.classNameField || sender == self.windowNameField;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    id field = notification.object;
    if ([self isWindowIdentityField:field]) {
        [self commitWindowIdentityEdit:field];
    }
}

@end
