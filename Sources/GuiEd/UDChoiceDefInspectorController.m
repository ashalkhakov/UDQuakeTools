/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDChoiceDefInspectorController.m — Controller for choiceDef attributes.
 */

#import "UDChoiceDefInspectorController.h"

@implementation UDChoiceDefInspectorController

@synthesize attrChoiceCvarField = _attrChoiceCvarField;
@synthesize attrChoiceChoiceTypeField = _attrChoiceChoiceTypeField;
@synthesize attrChoiceChoicesField = _attrChoiceChoicesField;
@synthesize attrChoiceValuesField = _attrChoiceValuesField;
@synthesize attrChoiceCurrentField = _attrChoiceCurrentField;
@synthesize attrChoiceGuiField = _attrChoiceGuiField;
@synthesize attrChoiceCvarGroupField = _attrChoiceCvarGroupField;
@synthesize attrChoiceLiveUpdateButton = _attrChoiceLiveUpdateButton;

- (void)syncFromWindow:(nullable UDGuiWindowNode *)node {
    UDChoiceDefWindowNode *window = (UDChoiceDefWindowNode *)node;
    self.attrChoiceCvarField.stringValue        = window.cvar ?: @"";
    self.attrChoiceChoiceTypeField.stringValue  = window ? [NSString stringWithFormat:@"%ld", (long)window.choiceType] : @"";
    self.attrChoiceChoicesField.stringValue     = window.choices ?: @"";
    self.attrChoiceValuesField.stringValue      = window.values ?: @"";
    self.attrChoiceCurrentField.stringValue     = window ? [NSString stringWithFormat:@"%ld", (long)window.currentChoice] : @"";
    self.attrChoiceGuiField.stringValue         = window.gui ?: @"";
    self.attrChoiceCvarGroupField.stringValue   = window.cvarGroup ?: @"";
    self.attrChoiceLiveUpdateButton.state = (!window || window.liveUpdate) ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyToWindow:(UDGuiWindowNode *)node {
    UDChoiceDefWindowNode *window = (UDChoiceDefWindowNode *)node;
    window.cvar          = self.attrChoiceCvarField.stringValue;
    window.choiceType    = self.attrChoiceChoiceTypeField.integerValue;
    window.choices       = self.attrChoiceChoicesField.stringValue;
    window.values        = self.attrChoiceValuesField.stringValue;
    window.currentChoice = self.attrChoiceCurrentField.integerValue;
    window.gui           = self.attrChoiceGuiField.stringValue;
    window.cvarGroup     = self.attrChoiceCvarGroupField.stringValue;
    window.liveUpdate    = self.attrChoiceLiveUpdateButton.state == NSControlStateValueOn;
}

@end
