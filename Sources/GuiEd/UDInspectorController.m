/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDInspectorController.m — Inspector panel controller for the GUI editor.
 */

#import "UDInspectorController.h"
#import "UDEditDefInspectorController.h"
#import "UDChoiceDefInspectorController.h"
#import "UDBindDefInspectorController.h"
#import "UDListDefInspectorController.h"
#import "UDSliderDefInspectorController.h"
#import "UDRenderDefInspectorController.h"

#import "../UDCore/UDGuiModel.h"
#import "UDGuiEdDocument.h"
#import "UDGuiEditorService.h"
#import "UDGuiEditorViewModel.h"

static NSArray<NSString *> *GetAllowedClassNames(void) {
    static NSArray<NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @[@"windowDef", @"listDef", @"renderDef", @"sliderDef", @"bindDef", @"choiceDef", @"editDef"];
    });
    return names;
}

@interface UDInspectorController ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDGuiAttributeSubcontroller *> *subcontrollerCache;
@end

@implementation UDInspectorController

@synthesize view = _view;
@synthesize identityView = _identityView;
@synthesize sizeView = _sizeView;
@synthesize classNameField = _classNameField;
@synthesize windowNameField = _windowNameField;
@synthesize activeSubcontroller = _activeSubcontroller;

- (instancetype)init {
    self = [super init];
    if (self) {
       _subcontrollerCache = [[NSMutableDictionary alloc] init];
#ifdef GNUSTEP
       [NSBundle loadNibNamed:@"UDInspector" owner:self];
#else
       [[NSBundle mainBundle] loadNibNamed:@"UDInspector" owner:self topLevelObjects:nil];
#endif
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    if (self.classNameField) {
        [self.classNameField removeAllItems];
        [self.classNameField addItemsWithTitles:GetAllowedClassNames()];
    }
    [self scrollAttributesPanelToTop];
}

- (void)scrollAttributesPanelToTop {
    if (!self.attributesScrollView) { return; }
    NSView *docView = self.attributesScrollView.documentView;
    if (!docView) { return; }
    CGFloat maxY = NSMaxY(docView.bounds) - NSHeight(self.attributesScrollView.contentView.bounds);
    [self.attributesScrollView.contentView scrollToPoint:NSMakePoint(0.0, MAX(0.0, maxY))];
    [self.attributesScrollView reflectScrolledClipView:self.attributesScrollView.contentView];
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

// MARK: - Dynamic subcontrollers coordination

- (void)updateActiveSubcontrollerForWindow:(nullable UDGuiWindowNode *)window {
    NSString *subcontrollerKey = nil;
    Class subcontrollerClass = Nil;
    NSString *nibName = nil;
    
    if ([window isKindOfClass:[UDEditDefWindowNode class]]) {
       subcontrollerKey = @"editDef";
       subcontrollerClass = [UDEditDefInspectorController class];
       nibName = @"UDEditDefInspector";
    } else if ([window isKindOfClass:[UDChoiceDefWindowNode class]]) {
       subcontrollerKey = @"choiceDef";
       subcontrollerClass = [UDChoiceDefInspectorController class];
       nibName = @"UDChoiceDefInspector";
    } else if ([window isKindOfClass:[UDBindDefWindowNode class]]) {
       subcontrollerKey = @"bindDef";
       subcontrollerClass = [UDBindDefInspectorController class];
       nibName = @"UDBindDefInspector";
    } else if ([window isKindOfClass:[UDListDefWindowNode class]]) {
        subcontrollerKey = @"listDef";
        subcontrollerClass = [UDListDefInspectorController class];
        nibName = @"UDListDefInspector";
    } else if ([window isKindOfClass:[UDSliderDefWindowNode class]]) {
        subcontrollerKey = @"sliderDef";
        subcontrollerClass = [UDSliderDefInspectorController class];
        nibName = @"UDSliderDefInspector";
    } else if ([window isKindOfClass:[UDRenderDefWindowNode class]]) {
        subcontrollerKey = @"renderDef";
        subcontrollerClass = [UDRenderDefInspectorController class];
        nibName = @"UDRenderDefInspector";
    }
    
    UDGuiAttributeSubcontroller *targetSubcontroller = nil;
    if (subcontrollerKey) {
       targetSubcontroller = self.subcontrollerCache[subcontrollerKey];
       if (!targetSubcontroller && subcontrollerClass) {
           targetSubcontroller = [[subcontrollerClass alloc] initWithNibName:nibName];
           targetSubcontroller.context = self.context;
           self.subcontrollerCache[subcontrollerKey] = targetSubcontroller;
       }
    }
    
    if (_activeSubcontroller != targetSubcontroller) {
       if (_activeSubcontroller.view.superview) {
           [_activeSubcontroller.view removeFromSuperview];
       }
       _activeSubcontroller = targetSubcontroller;
       if (targetSubcontroller) {
           targetSubcontroller.view.frame = self.attributeTypeTabView.bounds;
           targetSubcontroller.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
           [self.attributeTypeTabView addSubview:targetSubcontroller.view];
       }
    }
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
    [self updateActiveSubcontrollerForWindow:window];
    self.attributeTypeTabView.hidden = (_activeSubcontroller == nil);
}

- (void)refreshValidationHintsForWindow:(nullable UDGuiWindowNode *)window {
    UDGuiWindowNode *preview = [self validationPreviewWindowFromWindow:window];
    BOOL rectValid    = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyRect]     ?: @"" forKey:UDGuiWindowPropertyRect];
    BOOL rotateValid  = [self previewWindow:preview validatesValue:[preview stringPropertyForKey:UDGuiWindowPropertyRotate]   ?: @"" forKey:UDGuiWindowPropertyRotate];

    [self setHintLabel:self.sizeRectHintLabel    valid:rectValid];
    [self setHintLabel:self.sizeRotateHintLabel  valid:rotateValid];
    
    if ([_activeSubcontroller respondsToSelector:@selector(refreshValidationHintsForWindow:)]) {
       [_activeSubcontroller refreshValidationHintsForWindow:window];
    }
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
    [self updateActiveSubcontrollerForWindow:window];
    [_activeSubcontroller syncFromWindow:window];
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
    [_activeSubcontroller applyToWindow:window];
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
    if ([_activeSubcontroller respondsToSelector:@selector(validatePropertiesForWindow:)]) {
       return [_activeSubcontroller validatePropertiesForWindow:window];
    }
    return YES;
}

// MARK: - Actions

- (IBAction)commitTypedAttributesPanel:(id)sender {
    [_activeSubcontroller commitTypedAttributesPanel:sender];
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

    NSString *newClassName = self.classNameField.selectedItem.title ?: @"";
    NSArray *allowedClasses = GetAllowedClassNames();
    if (newClassName.length > 0 && [allowedClasses containsObject:newClassName]) {
        [self.context.ownerDocument.editorService updateWindow:selectedWindow
                                                    className:newClassName];
    } else {
        [self.classNameField selectItemWithTitle:selectedWindow.className ?: @""];
    }

    if (self.windowNameField.stringValue.length > 0) {
       [self.context.ownerDocument.editorService updateWindow:selectedWindow
                                                        name:self.windowNameField.stringValue];
    }
    [self.context notifyModelChangedAndRefresh];
}

// MARK: - NSTextFieldDelegate

- (BOOL)isWindowIdentityField:(id)sender {
    return sender == self.windowNameField;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
    id field = notification.object;
    if ([self isWindowIdentityField:field]) {
       [self commitWindowIdentityEdit:field];
    }
}

@end
