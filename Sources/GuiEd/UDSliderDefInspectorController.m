/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDSliderDefInspectorController.m — Controller for sliderDef attributes.
 */

#import "UDSliderDefInspectorController.h"

@implementation UDSliderDefInspectorController

@synthesize attrSliderCvarField = _attrSliderCvarField;
@synthesize attrSliderLowField = _attrSliderLowField;
@synthesize attrSliderHighField = _attrSliderHighField;
@synthesize attrSliderStepField = _attrSliderStepField;
@synthesize attrSliderVerticalButton = _attrSliderVerticalButton;
@synthesize attrSliderScrollBarButton = _attrSliderScrollBarButton;
@synthesize attrSliderThumbShaderField = _attrSliderThumbShaderField;
@synthesize attrSliderLiveUpdateButton = _attrSliderLiveUpdateButton;
@synthesize attrSliderCvarGroupField = _attrSliderCvarGroupField;

- (void)syncFromWindow:(nullable UDGuiWindowNode *)node {
    UDSliderDefWindowNode *window = (UDSliderDefWindowNode *)node;
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

- (void)applyToWindow:(UDGuiWindowNode *)node {
    UDSliderDefWindowNode *window = (UDSliderDefWindowNode *)node;
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

@end
