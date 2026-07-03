/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDEditDefInspectorController.m — Controller for editDef attributes.
 */

#import "UDEditDefInspectorController.h"

@implementation UDEditDefInspectorController

@synthesize attrEditCvarField = _attrEditCvarField;
@synthesize attrEditSourceField = _attrEditSourceField;
@synthesize attrEditCvarGroupField = _attrEditCvarGroupField;
@synthesize attrEditMaxCharsField = _attrEditMaxCharsField;
@synthesize attrEditNumericButton = _attrEditNumericButton;
@synthesize attrEditWrapButton = _attrEditWrapButton;
@synthesize attrEditReadOnlyButton = _attrEditReadOnlyButton;
@synthesize attrEditForceScrollButton = _attrEditForceScrollButton;
@synthesize attrEditPasswordButton = _attrEditPasswordButton;
@synthesize attrEditLiveUpdateButton = _attrEditLiveUpdateButton;

- (void)syncFromWindow:(nullable UDGuiWindowNode *)node {
    UDEditDefWindowNode *window = (UDEditDefWindowNode *)node;
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

- (void)applyToWindow:(UDGuiWindowNode *)node {
    UDEditDefWindowNode *window = (UDEditDefWindowNode *)node;
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

@end
