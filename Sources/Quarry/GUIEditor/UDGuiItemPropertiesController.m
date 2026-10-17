/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGuiItemPropertiesController.m
 */

#import "UDGuiItemPropertiesController.h"
#import "rvGEWorkspace.h"
#import "rvGESelectionMgr.h"
#import "rvGEWindowWrapper.h"
#import "idFileSystem.h"
#import "idDict.h"
#import "idWindow.h"
#import "idStr.h"
#import "UDReferencePicker.h"

static NSControlStateValue UDState(BOOL on) {
    return on ? NSControlStateValueOn : NSControlStateValueOff;
}

static BOOL UDChecked(NSButton *button) {
    return button.state == NSControlStateValueOn;
}

/// ColorButton_SetColor and AlphaButton_SetColor: "r,g,b,a" in one well
/// (the engine had a button for the color and one for its alpha).
static void UDSetWellColor(NSColorWell *well, NSString *color) {
    float red = 0, green = 0, blue = 0, alpha = 0;
    sscanf(color.UTF8String, "%f,%f,%f,%f", &red, &green, &blue, &alpha);
    well.color = [NSColor colorWithCalibratedRed:red green:green blue:blue alpha:alpha];
}

/// The window's text for a number field: its value with no quotes.
static NSString *UDNumberText(NSTextField *field) {
    return field.stringValue;
}

/// atoi, as GetWindowText's text is read.
static int UDAtoi(NSTextField *field) {
    return atoi(UDNumberText(field).UTF8String);
}

@interface UDGuiItemPropertiesController ()
@property (nonatomic, strong, readwrite, nullable) UDReferencePicker *referencePicker;
@property (nonatomic, weak, nullable) NSTextField *pickedField;
@end

@implementation UDGuiItemPropertiesController {
    /// The dialog's dictionary: the window's state when it was shown.
    idDict *mDict;
    rvGEWindowType mType;
    BOOL _fontsListed;
}

- (BOOL)update {
    rvGEWorkspace *workspace = self.workspace;
    rvGESelectionMgr *selections = workspace.selections;
    if (workspace == nil || [selections num] != 1) {
        mDict = nil;
        return NO;
    }
    // GEItemPropsDlg_DoModal: the dictionary starts as the window's state
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:selections[0]];
    mDict = [wrapper.stateDict copy];
    mType = wrapper.windowType;
    [self _initTextPage];
    [self _setGeneralActive];
    [self _setImageActive];
    [self _setTextActive];
    return YES;
}

/// The page's dictionary applied (GEWorkspace's EditSelectedProperties),
/// if it changed anything.
- (void)_apply {
    if (mDict == nil) return;
    rvGEWorkspace *workspace = self.workspace;
    idDict *state = [rvGEWindowWrapper wrapperOf:workspace.selections[0]].stateDict;
    if ([self _dict:mDict equals:state]) return;
    [workspace applyItemProperties:[mDict copy]];
}

- (BOOL)_dict:(idDict *)a equals:(idDict *)b {
    if ([a numKeyVals] != [b numKeyVals]) return NO;
    for (int i = 0; i < [a numKeyVals]; i++) {
        NSString *value = [b getString:[a keyAtIndex:i] defaultString:nil];
        if (value == nil || ![value isEqualToString:[a valueAtIndex:i]]) return NO;
    }
    return YES;
}

/// The well's color as @a key's value (StringFromVec4); the value as it was
/// when the well still shows it (not the engine's: its 0-255 colors were
/// written back whatever they were).
- (void)_setColorKey:(NSString *)key fromWell:(NSColorWell *)well {
    NSColor *color = [well.color colorUsingColorSpaceName:NSCalibratedRGBColorSpace];
    NSString *old = [mDict getString:key defaultString:nil];
    if (old != nil) {
        float r = 0, g = 0, b = 0, a = 0;
        if (sscanf(old.UTF8String, "%f,%f,%f,%f", &r, &g, &b, &a) == 4
            && fabs(r - color.redComponent) < 1e-4 && fabs(g - color.greenComponent) < 1e-4
            && fabs(b - color.blueComponent) < 1e-4 && fabs(a - color.alphaComponent) < 1e-4) {
            return;
        }
    }
    [mDict set:key value:rvGE_StringFromVec4(idVec4_Make((float)color.redComponent, (float)color.greenComponent,
                                                         (float)color.blueComponent, (float)color.alphaComponent))];
}

static NSString *UDQuoted(NSString *s) {
    return [NSString stringWithFormat:@"\"%@\"", s];
}

#pragma mark - General (rvGEItemPropsGeneralPage)

/*
================
rvGEItemPropsGeneralPage::SetActive

Initializes the general properties page by copying data from the attached
window into the controls
================
*/
- (void)_setGeneralActive {
    BOOL enable;

    self.nameField.stringValue = rvGE_StripQuotes([mDict getString:@"name" defaultString:@"unnamed"]);

    enable = !rvGE_IsExpression([mDict getString:@"visible" defaultString:@"1"]);
    self.visibleButton.state = UDState(atol(rvGE_StripQuotes([mDict getString:@"visible" defaultString:@"1"]).UTF8String));
    self.visibleButton.enabled = enable;

    enable = !rvGE_IsExpression([mDict getString:@"notime" defaultString:@"0"]);
    self.noTimeButton.state = UDState(atol(rvGE_StripQuotes([mDict getString:@"notime" defaultString:@"0"]).UTF8String));
    self.noTimeButton.enabled = enable;

    enable = !rvGE_IsExpression([mDict getString:@"noevents" defaultString:@"0"]);
    self.noEventsButton.state = UDState(atol(rvGE_StripQuotes([mDict getString:@"noevents" defaultString:@"0"]).UTF8String));
    self.noEventsButton.enabled = enable;

    enable = !rvGE_IsExpression([mDict getString:@"noclip" defaultString:@"0"]);
    self.noClipButton.state = UDState(atol(rvGE_StripQuotes([mDict getString:@"noclip" defaultString:@"0"]).UTF8String));
    self.noClipButton.enabled = enable;

    enable = !rvGE_IsExpression([mDict getString:@"nocursor" defaultString:@"0"]);
    self.noCursorButton.enabled = enable;
    self.noCursorButton.state = UDState(atol(rvGE_StripQuotes([mDict getString:@"nocursor" defaultString:@"0"]).UTF8String));

    self.typeField.stringValue = [rvGEWindowWrapper stringFromWindowType:mType];
}

/// rvGEItemPropsGeneralPage::KillActive
- (void)_killGeneralActive {
    [mDict set:@"name" value:self.nameField.stringValue];

    if (self.visibleButton.isEnabled) {
        [mDict set:@"visible" value:UDChecked(self.visibleButton) ? @"1" : @"0"];
    }
    struct { __unsafe_unretained NSButton *button; __unsafe_unretained NSString *key; } flags[] = {
        { self.noTimeButton, @"notime" },
        { self.noEventsButton, @"noevents" },
        { self.noClipButton, @"noclip" },
        { self.noCursorButton, @"nocursor" },
    };
    for (size_t i = 0; i < sizeof(flags) / sizeof(flags[0]); i++) {
        if (!flags[i].button.isEnabled) continue;
        if (UDChecked(flags[i].button)) {
            [mDict set:flags[i].key value:@"1"];
        } else {
            [mDict deleteKey:flags[i].key];
        }
    }
}

- (IBAction)generalChanged:(id)sender {
    if (mDict == nil) return;
    [self _killGeneralActive];
    [self _apply];
}

#pragma mark - Image (rvGEItemPropsImagePage)

/*
================
rvGEItemPropsImagePage::UpdateCheckedStates

Updates the enabled state of all the controls that are linked to a checkbox
================
*/
- (void)_updateImageCheckedStates {
    BOOL state;
    BOOL rstate;
    BOOL enable;

    enable = !rvGE_IsExpression([mDict getString:@"backcolor" defaultString:@"1,1,1,1"]);
    self.useBackColorButton.enabled = enable;

    state = UDChecked(self.useBackColorButton) && self.useBackColorButton.isEnabled;
    self.backColorWell.enabled = state;

    state = UDChecked(self.useMaterialButton);
    self.backgroundField.enabled = state;
    self.variableBackgroundButton.enabled = state;
    self.matScaleXField.enabled = state;
    self.matScaleYField.enabled = state;
    self.xScaleLabel.enabled = state;
    self.yScaleLabel.enabled = state;

    NSString *temp = self.borderSizeField.stringValue;
    enable = !rvGE_IsExpression([mDict getString:@"bordersize" defaultString:@"0"]);
    self.borderSizeField.enabled = enable;

    state = atol(temp.UTF8String) ? YES : NO;
    rstate = UDChecked(self.useBorderColorButton);
    enable = !rvGE_IsExpression([mDict getString:@"bordercolor" defaultString:@"1,1,1,1"]);
    self.useBorderColorButton.enabled = state && enable;
    self.useBorderMaterialButton.enabled = state && enable;
    self.borderColorWell.enabled = rstate && state && enable;
    self.borderMaterialField.enabled = !rstate && state;

    state = (state && !rstate) || UDChecked(self.useMaterialButton);
    enable = !rvGE_IsExpression([mDict getString:@"matcolor" defaultString:@"1,1,1,1"]);
    self.matColorLabel.enabled = state && enable;
    self.matColorWell.enabled = state && enable;
}

/*
================
rvGEItemPropsImagePage::SetActive

Initializes the text properties page by copying data from the attached
window into the controls
================
*/
- (void)_setImageActive {
    UDSetWellColor(self.backColorWell, [mDict getString:@"backcolor" defaultString:@"1,1,1,1"]);
    UDSetWellColor(self.matColorWell, [mDict getString:@"matcolor" defaultString:@"1,1,1,1"]);
    UDSetWellColor(self.borderColorWell, [mDict getString:@"bordercolor" defaultString:@"0,0,0,1"]);

    self.backgroundField.stringValue = rvGE_StripQuotes([mDict getString:@"background" defaultString:@""]);
    self.borderMaterialField.stringValue = rvGE_StripQuotes([mDict getString:@"borderShader" defaultString:@""]);
    self.borderSizeField.stringValue = rvGE_StripQuotes([mDict getString:@"bordersize" defaultString:@"0"]);

    self.matScaleXField.stringValue = rvGE_StripQuotes([mDict getString:@"matscalex" defaultString:@"1"]);
    self.matScaleYField.stringValue = rvGE_StripQuotes([mDict getString:@"matscaley" defaultString:@"1"]);

    self.variableBackgroundButton.state = UDState([mDict getBool:@"variablebackground" defaultString:@"0"]);

    self.useMaterialButton.state = UDState(rvGE_StripQuotes([mDict getString:@"background" defaultString:@""]).length > 0);
    self.useBackColorButton.state = UDState(rvGE_StripQuotes([mDict getString:@"backcolor" defaultString:@""]).length > 0);

    BOOL material = [mDict getString:@"borderShader" defaultString:@""].length > 0;
    self.useBorderMaterialButton.state = UDState(material);
    self.useBorderColorButton.state = UDState(!material);

    [self _updateImageCheckedStates];
}

/*
================
rvGEItemPropsImagePage::KillActive

Applys the settings currently stored in the property page back into the attached window
================
*/
- (void)_killImageActive {
    BOOL matcolor = NO;

    if (UDChecked(self.useMaterialButton)) {
        float val;

        [mDict set:@"background" value:UDQuoted(self.backgroundField.stringValue)];
        matcolor = YES;

        val = (float)atof(UDNumberText(self.matScaleXField).UTF8String);
        if (val >= 0.999f && val <= 1.001f) {
            [mDict deleteKey:@"matscalex"];
        } else {
            [mDict set:@"matscalex" value:idStr_FloatArrayToString(&val, 1, 8)];
        }

        val = (float)atof(UDNumberText(self.matScaleYField).UTF8String);
        if (val >= 0.999f && val <= 1.001f) {
            [mDict deleteKey:@"matscaley"];
        } else {
            [mDict set:@"matscaley" value:idStr_FloatArrayToString(&val, 1, 8)];
        }

        if (UDChecked(self.variableBackgroundButton)) {
            [mDict set:@"variablebackground" value:@"1"];
        } else {
            [mDict deleteKey:@"variablebackground"];
        }
    } else {
        [mDict deleteKey:@"background"];
        [mDict deleteKey:@"variablebackground"];
        [mDict deleteKey:@"matscalex"];
        [mDict deleteKey:@"matscaley"];
    }

    if (UDChecked(self.useBackColorButton)) {
        if (self.backColorWell.isEnabled) {
            [self _setColorKey:@"backcolor" fromWell:self.backColorWell];
        }
    } else {
        [mDict deleteKey:@"backcolor"];
    }

    int bordersize = UDAtoi(self.borderSizeField);
    if (bordersize) {
        if (self.borderSizeField.isEnabled) {
            [mDict set:@"bordersize" value:[NSString stringWithFormat:@"%d", bordersize]];
        }

        if (UDChecked(self.useBorderColorButton)) {
            if (self.borderColorWell.isEnabled) {
                [self _setColorKey:@"bordercolor" fromWell:self.borderColorWell];
            }
            [mDict deleteKey:@"borderShader"];
        } else {
            [mDict set:@"borderShader" value:UDQuoted(self.borderMaterialField.stringValue)];
            [mDict deleteKey:@"bordercolor"];
            matcolor = YES;
        }
    } else {
        [mDict deleteKey:@"bordersize"];
        [mDict deleteKey:@"bordercolor"];
        [mDict deleteKey:@"borderShader"];
    }

    if (matcolor) {
        if (self.matColorWell.isEnabled) {
            [self _setColorKey:@"matcolor" fromWell:self.matColorWell];
        }
    } else {
        [mDict deleteKey:@"matcolor"];
    }
}

/// HandleMessage's WM_COMMAND: the checked states, then the page applied.
- (IBAction)imageChanged:(id)sender {
    if (mDict == nil) return;
    [self _updateImageCheckedStates];
    [self _killImageActive];
    [self _apply];
}

/// CheckRadioButton: one of the two (GNUstep does not group them).
- (IBAction)borderKindChanged:(id)sender {
    BOOL color = sender != self.useBorderMaterialButton;
    self.useBorderColorButton.state = UDState(color);
    self.useBorderMaterialButton.state = UDState(!color);
    [self imageChanged:sender];
}

#pragma mark - Text (rvGEItemPropsTextPage)

/*
================
rvGEItemPropsTextPage::Init

The alignments, and the fonts: <default>, then each folder in fonts/
================
*/
- (void)_initTextPage {
    NSPopUpButton *align = self.textAlignPopUp;
    if (align.numberOfItems != 3) {
        [align removeAllItems];
        [align addItemsWithTitles:@[@"Left", @"Center", @"Right"]];
    }

    // once, as the engine's page is made once
    NSPopUpButton *fonts = self.fontPopUp;
    if (_fontsListed) return;
    _fontsListed = YES;
    [fonts removeAllItems];
    [fonts addItemWithTitle:@"<default>"];
    idFileList *folders = [self.fileSystem listFiles:@"fonts" extension:@"/" error:NULL];
    for (int i = 0; i < [folders numFiles]; i++) {
        NSString *folder = [folders fileByIndex:i];
        if ([folder hasPrefix:@"."] || [fonts itemWithTitle:folder] != nil) {
            continue;
        }
        [fonts addItemWithTitle:folder];
    }
}

/*
================
rvGEItemPropsTextPage::UpdateCheckedStates

Updates the enabled state of all the controls that are linked to a checkbox
================
*/
- (void)_updateTextCheckedStates {
    BOOL state;
    BOOL enable;

    state = UDChecked(self.useTextButton);
    enable = !rvGE_IsExpression([mDict getString:@"forecolor" defaultString:@"1,1,1,1"]);

    self.foreColorWell.enabled = state && enable;

    self.textField.enabled = state;
    self.textScaleField.enabled = state;
    self.textAlignPopUp.enabled = state;
    self.textAlignXField.enabled = state;
    self.textAlignYField.enabled = state;
    self.fontPopUp.enabled = state;
    self.noWrapButton.enabled = state;

    self.alignmentLabel.enabled = state;
    self.alignXLabel.enabled = state;
    self.alignYLabel.enabled = state;
    self.scaleLabel.enabled = state;
    self.colorLabel.enabled = state;
    self.fontLabel.enabled = state;
}

/*
================
rvGEItemPropsTextPage::SetActive

Initializes the text properties page by copying data from the attached
window into the controls
================
*/
- (void)_setTextActive {
    UDSetWellColor(self.foreColorWell, [mDict getString:@"forecolor" defaultString:@"1,1,1,1"]);

    self.textField.stringValue = rvGE_StripQuotes([mDict getString:@"text" defaultString:@""]);
    self.textScaleField.stringValue = [mDict getString:@"textscale" defaultString:@"1.0"];
    self.textAlignXField.stringValue = [mDict getString:@"textalignx" defaultString:@"0"];
    self.textAlignYField.stringValue = [mDict getString:@"textaligny" defaultString:@"0"];

    int align = atoi([mDict getString:@"textalign" defaultString:@"0"].UTF8String);
    [self.textAlignPopUp selectItemAtIndex:align >= 0 && align < self.textAlignPopUp.numberOfItems ? align : -1];

    // Figure out which font to select
    NSString *font = [rvGE_StripQuotes([mDict getString:@"font" defaultString:@""]) lastPathComponent];
    NSInteger fontSel = font.length > 0 ? [self.fontPopUp indexOfItemWithTitle:font] : -1;
    [self.fontPopUp selectItemAtIndex:fontSel == -1 ? 0 : fontSel];

    self.useTextButton.state = UDState([mDict getString:@"text" defaultString:@""].length > 0);
    self.noWrapButton.state = UDState(atoi(rvGE_StripQuotes([mDict getString:@"nowrap" defaultString:@"0"]).UTF8String));

    [self _updateTextCheckedStates];
}

/*
================
rvGEItemPropsTextPage::KillActive

Applys the settings currently stored in the property page back into the attached window
================
*/
- (void)_killTextActive {
    int i;
    float f;

    if (UDChecked(self.useTextButton)) {
        if (self.foreColorWell.isEnabled) {
            [self _setColorKey:@"forecolor" fromWell:self.foreColorWell];
        }

        [mDict set:@"text" value:UDQuoted(self.textField.stringValue)];

        f = (float)atof(UDNumberText(self.textScaleField).UTF8String);
        [mDict set:@"textscale" value:idStr_FloatArrayToString(&f, 1, 8)];

        i = (int)self.textAlignPopUp.indexOfSelectedItem;
        if (i > 0) {
            [mDict set:@"textalign" value:[NSString stringWithFormat:@"%d", i]];
        } else {
            [mDict deleteKey:@"textalign"];
        }

        i = UDAtoi(self.textAlignXField);
        if (i) {
            [mDict set:@"textalignx" value:[NSString stringWithFormat:@"%d", i]];
        } else {
            [mDict deleteKey:@"textalignx"];
        }

        i = UDAtoi(self.textAlignYField);
        if (i) {
            [mDict set:@"textaligny" value:[NSString stringWithFormat:@"%d", i]];
        } else {
            [mDict deleteKey:@"textaligny"];
        }

        NSInteger fontSel = self.fontPopUp.indexOfSelectedItem;
        if (fontSel <= 0) {
            [mDict deleteKey:@"font"];
        } else {
            [mDict set:@"font" value:[NSString stringWithFormat:@"\"fonts/%@\"", self.fontPopUp.titleOfSelectedItem]];
        }

        if (UDChecked(self.noWrapButton)) {
            [mDict set:@"nowrap" value:@"1"];
        } else {
            [mDict deleteKey:@"nowrap"];
        }
    } else {
        [mDict deleteKey:@"text"];
        [mDict deleteKey:@"textscale"];
        [mDict deleteKey:@"textalign"];
        [mDict deleteKey:@"textalignx"];
        [mDict deleteKey:@"textaligny"];
        [mDict deleteKey:@"forecolor"];
        [mDict deleteKey:@"font"];
    }
}

- (IBAction)textChanged:(id)sender {
    if (mDict == nil) return;
    [self _updateTextCheckedStates];
    [self _killTextActive];
    [self _apply];
}

#pragma mark - Pickers

- (IBAction)pickReference:(id)sender {
    NSTextField *target = [sender tag] == 1 ? self.backgroundField : self.borderMaterialField;
    NSWindow *window = target.window;
    if (mDict == nil || self.resourceWorkspace == nil || window == nil || window.attachedSheet != nil || !target.isEnabled) {
        NSBeep();
        return;
    }
    UDReferenceField *field = [UDReferenceField fieldTitled:[sender tag] == 1 ? @"The window's background" : @"The border's material"
                                                        key:@"" controller:self kind:UDReferenceMaterials];
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    NSArray<NSString *> *names = [UDReferencePicker namesFor:field workspace:self.resourceWorkspace details:details];
    self.pickedField = target;
    self.referencePicker = [[UDReferencePicker alloc] initWithTitle:field.title names:names details:details current:target.stringValue];
    [self.referencePicker beginSheetForWindow:window target:self action:@selector(_referencePicked:)];
}

/// The name in the field, and the page applied (as typing it would).
- (void)_referencePicked:(UDReferencePicker *)picker {
    NSTextField *field = self.pickedField;
    if (field == nil || picker.chosenName == nil) return;
    field.stringValue = picker.chosenName;
    [self imageChanged:field];
}

@end
