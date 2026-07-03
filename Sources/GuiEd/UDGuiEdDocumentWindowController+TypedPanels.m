/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+TypedPanels.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
- (void)reloadVariablesTableForWindow:(UDGuiWindowNode *)window
                     preserveSelection:(BOOL)preserveSelection
                             selectRow:(NSInteger)forcedRow
                          beginEditing:(BOOL)beginEditing;
- (void)reloadEventsEditorForWindow:(UDGuiWindowNode *)window preserveSelection:(BOOL)preserveSelection;
@end

@implementation UDGuiEdDocumentWindowController (TypedPanels)

- (void)setHintLabel:(NSTextField *)label valid:(BOOL)valid {
    if (!label) {
        return;
    }
    label.textColor = valid ? [NSColor secondaryLabelColor] : [NSColor systemRedColor];
}

- (void)updateAttributeGroupVisibilityForWindow:(UDGuiWindowNode *)window {
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

- (void)refreshTypedValidationHintsForWindow:(UDGuiWindowNode *)window {
    UDGuiWindowNode *preview = [self validationPreviewWindowFromWindow:window];
    BOOL rectValid = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyRect] ?: @"" forKey:UDGuiWindowPropertyRect];
    BOOL rotateValid = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyRotate] ?: @"" forKey:UDGuiWindowPropertyRotate];
    BOOL tabStopsValid = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyTabStops] ?: @"" forKey:UDGuiWindowPropertyTabStops];
    BOOL tabAlignsValid = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyTabAligns] ?: @"" forKey:UDGuiWindowPropertyTabAligns];

    [self setHintLabel:self.sizeRectHintLabel valid:rectValid];
    [self setHintLabel:self.sizeRotateHintLabel valid:rotateValid];

    [self setHintLabel:self.attrListTabStopsHintLabel valid:tabStopsValid];
    [self setHintLabel:self.attrListTabAlignsHintLabel valid:tabAlignsValid];
}

- (UDGuiWindowNode *)validationPreviewWindowFromWindow:(UDGuiWindowNode *)window {
    UDGuiWindowNode *preview = window ? [window deepCopy] : [UDGuiWindowNode windowNodeWithClassName:@"windowDef" name:@"Preview"];

    [self applySizePanelToWindow:preview];
    [self applyTypedPanelsToWindow:preview];

    return preview;
}

- (BOOL)previewWindow:(UDGuiWindowNode *)window validatesValue:(id)value forKey:(NSString *)key {
    id candidateValue = value ?: @"";
    NSError *error = nil;
    return [window validateValue:&candidateValue forKey:key error:&error];
}

- (void)syncBoolButton:(NSButton *)button key:(NSString *)key window:(UDGuiWindowNode *)window defaultOnWhenNil:(BOOL)defaultOnWhenNil {
    BOOL value = window ? [[window valueForKey:key] boolValue] : defaultOnWhenNil;
    button.state = value ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)syncDoubleField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window {
    field.stringValue = window ? [NSString stringWithFormat:@"%g", [[window valueForKey:key] doubleValue]] : @"";
}

- (void)syncIntegerField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window {
    field.stringValue = window ? [NSString stringWithFormat:@"%ld", (long)[[window valueForKey:key] integerValue]] : @"";
}

- (void)syncStringField:(NSTextField *)field key:(NSString *)key window:(UDGuiWindowNode *)window {
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

- (id)typedWindow:(UDGuiWindowNode *)window class:(Class)windowClass {
    return [window isKindOfClass:windowClass] ? window : nil;
}

- (UDGuiAttributeTypeTab)attributeTypeTabForWindow:(UDGuiWindowNode *)window {
    Class windowClasses[] = {
        [UDEditDefWindowNode class],
        [UDChoiceDefWindowNode class],
        [UDBindDefWindowNode class],
        [UDListDefWindowNode class],
        [UDSliderDefWindowNode class],
        [UDRenderDefWindowNode class],
    };

    for (NSInteger index = 0; index < (NSInteger)(sizeof(windowClasses) / sizeof(windowClasses[0])); index++) {
        if ([window isKindOfClass:windowClasses[index]]) {
            return (UDGuiAttributeTypeTab)index;
        }
    }

    return (UDGuiAttributeTypeTab)-1;
}

- (void)dispatchTypedPanelsForWindow:(UDGuiWindowNode *)window sync:(BOOL)sync {
    Class windowClasses[] = {
        [UDEditDefWindowNode class],
        [UDChoiceDefWindowNode class],
        [UDBindDefWindowNode class],
        [UDListDefWindowNode class],
        [UDSliderDefWindowNode class],
        [UDRenderDefWindowNode class],
    };

    SEL selectors[] = {
        sync ? @selector(syncEditPanelFromWindow:) : @selector(applyEditPanelToWindow:),
        sync ? @selector(syncChoicePanelFromWindow:) : @selector(applyChoicePanelToWindow:),
        sync ? @selector(syncBindPanelFromWindow:) : @selector(applyBindPanelToWindow:),
        sync ? @selector(syncListPanelFromWindow:) : @selector(applyListPanelToWindow:),
        sync ? @selector(syncSliderPanelFromWindow:) : @selector(applySliderPanelToWindow:),
        sync ? @selector(syncRenderPanelFromWindow:) : @selector(applyRenderPanelToWindow:),
    };

    for (NSInteger index = 0; index < (NSInteger)(sizeof(windowClasses) / sizeof(windowClasses[0])); index++) {
        id typedWindow = [self typedWindow:window class:windowClasses[index]];
        if (!sync && !typedWindow) {
            continue;
        }

        SEL selector = selectors[index];
        typedef void (*TypedPanelDispatch)(id, SEL, id);
        TypedPanelDispatch dispatch = (TypedPanelDispatch)[self methodForSelector:selector];
        dispatch(self, selector, typedWindow);
    }
}

- (void)syncBoolBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self syncBoolButton:binding[0]
                         key:binding[1]
                      window:window
             defaultOnWhenNil:[binding[2] boolValue]];
    }
}

- (void)syncDoubleBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self syncDoubleField:binding[0] key:binding[1] window:window];
    }
}

- (void)syncIntegerBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self syncIntegerField:binding[0] key:binding[1] window:window];
    }
}

- (void)syncStringBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self syncStringField:binding[0] key:binding[1] window:window];
    }
}

- (void)applyBoolBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self applyBoolButton:binding[0] key:binding[1] window:window];
    }
}

- (void)applyDoubleBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self applyDoubleField:binding[0] key:binding[1] window:window];
    }
}

- (void)applyIntegerBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self applyIntegerField:binding[0] key:binding[1] window:window];
    }
}

- (void)applyStringBindings:(NSArray<NSArray *> *)bindings window:(UDGuiWindowNode *)window {
    for (NSArray *binding in bindings) {
        [self applyStringField:binding[0] key:binding[1] window:window];
    }
}

- (BOOL)validateEditorValue:(id)value forKey:(NSString *)key onWindow:(UDGuiWindowNode *)window {
    id candidateValue = value ?: @"";
    NSError *error = nil;
    BOOL valid = [window validateValue:&candidateValue forKey:key error:&error];
    if (!valid && error) {
        [self presentError:error];
    }
    return valid;
}

- (BOOL)validateStringKeys:(NSArray<NSString *> *)keys fieldValues:(NSDictionary<NSString *, NSString *> *)fieldValues onWindow:(UDGuiWindowNode *)window {
    for (NSString *key in keys) {
        NSString *value = fieldValues[key] ?: @"";
        if (![self validateEditorValue:value forKey:key onWindow:window]) {
            return NO;
        }
    }
    return YES;
}

- (BOOL)validateSizePanelForWindow:(UDGuiWindowNode *)window {
    return [self validateStringKeys:@[UDGuiWindowPropertyRect, UDGuiWindowPropertyRotate]
                        fieldValues:@{
                            UDGuiWindowPropertyRect: self.sizeRectField.stringValue ?: @"",
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
                            UDGuiWindowPropertyTabStops: self.attrListTabStopsField.stringValue ?: @"",
                            UDGuiWindowPropertyTabAligns: self.attrListTabAlignsField.stringValue ?: @"",
                        }
                           onWindow:window];
}

- (void)syncCommonInfoPanelFromWindow:(UDGuiWindowNode *)window {
    [self syncBoolBindings:@[
        @[self.infoShowTimeButton, UDGuiWindowPropertyShowTime, @NO],
        @[self.infoShowCoordsButton, UDGuiWindowPropertyShowCoords, @NO],
        @[self.infoVisibleButton, UDGuiWindowPropertyVisible, @YES],
        @[self.infoNoEventsButton, UDGuiWindowPropertyNoEvents, @NO],
        @[self.infoNoWrapButton, UDGuiWindowPropertyNoWrap, @NO],
        @[self.infoShadowButton, UDGuiWindowPropertyShadow, @NO],
        @[self.infoWantEnterButton, UDGuiWindowPropertyWantEnter, @NO],
        @[self.infoNaturalMatScaleButton, UDGuiWindowPropertyNaturalMatScale, @NO],
        @[self.infoNoClipButton, UDGuiWindowPropertyNoClip, @NO],
        @[self.infoNoCursorButton, UDGuiWindowPropertyNoCursor, @NO],
        @[self.infoMenuGUIButton, UDGuiWindowPropertyMenuGUI, @NO],
        @[self.infoModalButton, UDGuiWindowPropertyModal, @NO],
        @[self.infoInvertRectButton, UDGuiWindowPropertyInvertRect, @NO],
    ] window:window];

    [self syncDoubleBindings:@[
        @[self.infoForceAspectWidthField, UDGuiWindowPropertyForceAspectWidth],
        @[self.infoForceAspectHeightField, UDGuiWindowPropertyForceAspectHeight],
        @[self.infoMatScaleXField, UDGuiWindowPropertyMatScaleX],
        @[self.infoMatScaleYField, UDGuiWindowPropertyMatScaleY],
        @[self.infoBorderSizeField, UDGuiWindowPropertyBorderSize],
        @[self.infoTextAlignXField, UDGuiWindowPropertyTextAlignX],
        @[self.infoTextAlignYField, UDGuiWindowPropertyTextAlignY],
    ] window:window];

    [self syncIntegerBindings:@[
        @[self.infoTextAlignField, UDGuiWindowPropertyTextAlign],
    ] window:window];

    [self syncStringBindings:@[
        @[self.infoForeColorField, UDGuiWindowPropertyForeColor],
        @[self.infoHoverColorField, UDGuiWindowPropertyHoverColor],
        @[self.infoBackColorField, UDGuiWindowPropertyBackColor],
        @[self.infoBorderColorField, UDGuiWindowPropertyBorderColor],
        @[self.infoMatColorField, UDGuiWindowPropertyMatColor],
        @[self.infoShearField, UDGuiWindowPropertyShear],
        @[self.infoNameOverrideField, UDGuiWindowPropertyNameOverride],
        @[self.infoTextField, UDGuiWindowPropertyText],
        @[self.infoBackgroundField, UDGuiWindowPropertyBackground],
        @[self.infoVarBackgroundField, UDGuiWindowPropertyVarBackground],
        @[self.infoRunScriptField, UDGuiWindowPropertyRunScript],
        @[self.infoPlayField, UDGuiWindowPropertyPlay],
        @[self.infoCommentField, UDGuiWindowPropertyComment],
        @[self.infoFontField, UDGuiWindowPropertyFont],
    ] window:window];
}

- (void)syncTypedPanelsFromWindow:(UDGuiWindowNode *)window {
    [self dispatchTypedPanelsForWindow:window sync:YES];

    [self syncSizePanelFromWindow:window];
    [self reloadVariablesTableForWindow:window preserveSelection:YES selectRow:NSNotFound beginEditing:NO];

    [self reloadEventsEditorForWindow:window preserveSelection:YES];
}

- (void)syncSizePanelFromWindow:(UDGuiWindowNode *)window {
    BOOL hasWindow = window != nil;
    self.sizeRectField.stringValue = hasWindow ? [window stringPropertyForKey:UDGuiWindowPropertyRect] ?: @"" : @"";
    self.sizeRotateField.stringValue = hasWindow ? [window stringPropertyForKey:UDGuiWindowPropertyRotate] ?: @"" : @"";
    self.sizeScaleField.stringValue = hasWindow ? [window valueForKey:UDGuiWindowPropertyScale] ?: @"" : @"";
    self.sizeTranslateField.stringValue = hasWindow ? [window valueForKey:UDGuiWindowPropertyTranslate] ?: @"" : @"";
    self.sizeTextScaleField.stringValue = hasWindow ? [NSString stringWithFormat:@"%g", [[window valueForKey:UDGuiWindowPropertyTextScale] doubleValue]] : @"";
}

- (void)applySizePanelToWindow:(UDGuiWindowNode *)window {
    [window setValue:self.sizeRectField.stringValue forKey:UDGuiWindowPropertyRect];
    [window setValue:self.sizeRotateField.stringValue forKey:UDGuiWindowPropertyRotate];
    [window setValue:self.sizeScaleField.stringValue forKey:UDGuiWindowPropertyScale];
    [window setValue:self.sizeTranslateField.stringValue forKey:UDGuiWindowPropertyTranslate];
    [window setValue:@(self.sizeTextScaleField.doubleValue) forKey:UDGuiWindowPropertyTextScale];
}

- (void)applyTypedPanelsToWindow:(UDGuiWindowNode *)window {
    [self dispatchTypedPanelsForWindow:window sync:NO];
}

- (void)applyCommonInfoPanelToWindow:(UDGuiWindowNode *)window {
    [self applyBoolBindings:@[
        @[self.infoShowTimeButton, UDGuiWindowPropertyShowTime],
        @[self.infoShowCoordsButton, UDGuiWindowPropertyShowCoords],
        @[self.infoVisibleButton, UDGuiWindowPropertyVisible],
        @[self.infoNoEventsButton, UDGuiWindowPropertyNoEvents],
        @[self.infoNoWrapButton, UDGuiWindowPropertyNoWrap],
        @[self.infoShadowButton, UDGuiWindowPropertyShadow],
        @[self.infoWantEnterButton, UDGuiWindowPropertyWantEnter],
        @[self.infoNaturalMatScaleButton, UDGuiWindowPropertyNaturalMatScale],
        @[self.infoNoClipButton, UDGuiWindowPropertyNoClip],
        @[self.infoNoCursorButton, UDGuiWindowPropertyNoCursor],
        @[self.infoMenuGUIButton, UDGuiWindowPropertyMenuGUI],
        @[self.infoModalButton, UDGuiWindowPropertyModal],
        @[self.infoInvertRectButton, UDGuiWindowPropertyInvertRect],
    ] window:window];

    [self applyDoubleBindings:@[
        @[self.infoForceAspectWidthField, UDGuiWindowPropertyForceAspectWidth],
        @[self.infoForceAspectHeightField, UDGuiWindowPropertyForceAspectHeight],
        @[self.infoMatScaleXField, UDGuiWindowPropertyMatScaleX],
        @[self.infoMatScaleYField, UDGuiWindowPropertyMatScaleY],
        @[self.infoBorderSizeField, UDGuiWindowPropertyBorderSize],
        @[self.infoTextAlignXField, UDGuiWindowPropertyTextAlignX],
        @[self.infoTextAlignYField, UDGuiWindowPropertyTextAlignY],
    ] window:window];

    [self applyIntegerBindings:@[
        @[self.infoTextAlignField, UDGuiWindowPropertyTextAlign],
    ] window:window];

    [self applyStringBindings:@[
        @[self.infoForeColorField, UDGuiWindowPropertyForeColor],
        @[self.infoHoverColorField, UDGuiWindowPropertyHoverColor],
        @[self.infoBackColorField, UDGuiWindowPropertyBackColor],
        @[self.infoBorderColorField, UDGuiWindowPropertyBorderColor],
        @[self.infoMatColorField, UDGuiWindowPropertyMatColor],
        @[self.infoShearField, UDGuiWindowPropertyShear],
        @[self.infoNameOverrideField, UDGuiWindowPropertyNameOverride],
        @[self.infoTextField, UDGuiWindowPropertyText],
        @[self.infoBackgroundField, UDGuiWindowPropertyBackground],
        @[self.infoVarBackgroundField, UDGuiWindowPropertyVarBackground],
        @[self.infoRunScriptField, UDGuiWindowPropertyRunScript],
        @[self.infoPlayField, UDGuiWindowPropertyPlay],
        @[self.infoCommentField, UDGuiWindowPropertyComment],
        @[self.infoFontField, UDGuiWindowPropertyFont],
    ] window:window];
}

- (void)syncEditPanelFromWindow:(UDEditDefWindowNode *)window {
    self.attrEditCvarField.stringValue = window.cvar ?: @"";
    self.attrEditMaxCharsField.stringValue = window ? [NSString stringWithFormat:@"%ld", (long)window.maxChars] : @"";
    self.attrEditSourceField.stringValue = window.source ?: @"";
    self.attrEditCvarGroupField.stringValue = window.cvarGroup ?: @"";
    self.attrEditNumericButton.state = window.numeric ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditWrapButton.state = window.wrap ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditReadOnlyButton.state = window.readOnly ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditForceScrollButton.state = window.forceScroll ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditPasswordButton.state = window.password ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrEditLiveUpdateButton.state = !window || window.liveUpdate ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyEditPanelToWindow:(UDEditDefWindowNode *)window {
    window.cvar = self.attrEditCvarField.stringValue;
    window.maxChars = self.attrEditMaxCharsField.integerValue;
    window.source = self.attrEditSourceField.stringValue;
    window.cvarGroup = self.attrEditCvarGroupField.stringValue;
    window.numeric = self.attrEditNumericButton.state == NSControlStateValueOn;
    window.wrap = self.attrEditWrapButton.state == NSControlStateValueOn;
    window.readOnly = self.attrEditReadOnlyButton.state == NSControlStateValueOn;
    window.forceScroll = self.attrEditForceScrollButton.state == NSControlStateValueOn;
    window.password = self.attrEditPasswordButton.state == NSControlStateValueOn;
    window.liveUpdate = self.attrEditLiveUpdateButton.state == NSControlStateValueOn;
}

- (void)syncChoicePanelFromWindow:(UDChoiceDefWindowNode *)window {
    self.attrChoiceCvarField.stringValue = window.cvar ?: @"";
    self.attrChoiceChoiceTypeField.stringValue = window ? [NSString stringWithFormat:@"%ld", (long)window.choiceType] : @"";
    self.attrChoiceChoicesField.stringValue = window.choices ?: @"";
    self.attrChoiceValuesField.stringValue = window.values ?: @"";
    self.attrChoiceCurrentField.stringValue = window ? [NSString stringWithFormat:@"%ld", (long)window.currentChoice] : @"";
    self.attrChoiceGuiField.stringValue = window.gui ?: @"";
    self.attrChoiceCvarGroupField.stringValue = window.cvarGroup ?: @"";
    self.attrChoiceLiveUpdateButton.state = !window || window.liveUpdate ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyChoicePanelToWindow:(UDChoiceDefWindowNode *)window {
    window.cvar = self.attrChoiceCvarField.stringValue;
    window.choiceType = self.attrChoiceChoiceTypeField.integerValue;
    window.choices = self.attrChoiceChoicesField.stringValue;
    window.values = self.attrChoiceValuesField.stringValue;
    window.currentChoice = self.attrChoiceCurrentField.integerValue;
    window.gui = self.attrChoiceGuiField.stringValue;
    window.cvarGroup = self.attrChoiceCvarGroupField.stringValue;
    window.liveUpdate = self.attrChoiceLiveUpdateButton.state == NSControlStateValueOn;
}

- (void)syncBindPanelFromWindow:(UDBindDefWindowNode *)window {
    self.attrBindField.stringValue = window.bind ?: @"";
}

- (void)applyBindPanelToWindow:(UDBindDefWindowNode *)window {
    window.bind = self.attrBindField.stringValue;
}

- (void)syncListPanelFromWindow:(UDListDefWindowNode *)window {
    self.attrListHorizontalButton.state = window.horizontal ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrListNameField.stringValue = window.listName ?: @"";
    self.attrListTabStopsField.stringValue = window.tabStops ?: @"";
    self.attrListTabAlignsField.stringValue = window.tabAligns ?: @"";
    self.attrListMultipleSelButton.state = window.multipleSelection ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyListPanelToWindow:(UDListDefWindowNode *)window {
    window.horizontal = self.attrListHorizontalButton.state == NSControlStateValueOn;
    window.listName = self.attrListNameField.stringValue;
    window.tabStops = self.attrListTabStopsField.stringValue;
    window.tabAligns = self.attrListTabAlignsField.stringValue;
    window.multipleSelection = self.attrListMultipleSelButton.state == NSControlStateValueOn;
}

- (void)syncSliderPanelFromWindow:(UDSliderDefWindowNode *)window {
    self.attrSliderCvarField.stringValue = window.cvar ?: @"";
    self.attrSliderLowField.stringValue = window ? [NSString stringWithFormat:@"%g", window.low] : @"";
    self.attrSliderHighField.stringValue = window ? [NSString stringWithFormat:@"%g", window.high] : @"";
    self.attrSliderStepField.stringValue = window ? [NSString stringWithFormat:@"%g", window.stepSize] : @"";
    self.attrSliderVerticalButton.state = window.vertical ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderScrollBarButton.state = window.scrollBar ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderThumbShaderField.stringValue = window.thumbShader ?: @"";
    self.attrSliderLiveUpdateButton.state = !window || window.liveUpdate ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrSliderCvarGroupField.stringValue = window.cvarGroup ?: @"";
}

- (void)applySliderPanelToWindow:(UDSliderDefWindowNode *)window {
    window.cvar = self.attrSliderCvarField.stringValue;
    window.low = self.attrSliderLowField.doubleValue;
    window.high = self.attrSliderHighField.doubleValue;
    window.stepSize = self.attrSliderStepField.doubleValue;
    window.vertical = self.attrSliderVerticalButton.state == NSControlStateValueOn;
    window.scrollBar = self.attrSliderScrollBarButton.state == NSControlStateValueOn;
    window.thumbShader = self.attrSliderThumbShaderField.stringValue;
    window.liveUpdate = self.attrSliderLiveUpdateButton.state == NSControlStateValueOn;
    window.cvarGroup = self.attrSliderCvarGroupField.stringValue;
}

- (void)syncRenderPanelFromWindow:(UDRenderDefWindowNode *)window {
    self.attrRenderModelField.stringValue = window.model ?: @"";
    self.attrRenderAnimField.stringValue = window.anim ?: @"";
    self.attrRenderAnimClassField.stringValue = window.animClass ?: @"";
    self.attrRenderLightOriginField.stringValue = window.lightOrigin ?: @"";
    self.attrRenderLightColorField.stringValue = window.lightColor ?: @"";
    self.attrRenderModelOriginField.stringValue = window.modelOrigin ?: @"";
    self.attrRenderModelRotateField.stringValue = window.modelRotate ?: @"";
    self.attrRenderViewOffsetField.stringValue = window.viewOffset ?: @"";
    self.attrRenderNeedsRenderButton.state = !window || window.needsRender ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyRenderPanelToWindow:(UDRenderDefWindowNode *)window {
    window.model = self.attrRenderModelField.stringValue;
    window.anim = self.attrRenderAnimField.stringValue;
    window.animClass = self.attrRenderAnimClassField.stringValue;
    window.lightOrigin = self.attrRenderLightOriginField.stringValue;
    window.lightColor = self.attrRenderLightColorField.stringValue;
    window.modelOrigin = self.attrRenderModelOriginField.stringValue;
    window.modelRotate = self.attrRenderModelRotateField.stringValue;
    window.viewOffset = self.attrRenderViewOffsetField.stringValue;
    window.needsRender = self.attrRenderNeedsRenderButton.state == NSControlStateValueOn;
}

@end
