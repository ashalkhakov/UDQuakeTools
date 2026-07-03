/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDRenderDefInspectorController.m — Controller for renderDef attributes.
 */

#import "UDRenderDefInspectorController.h"

@implementation UDRenderDefInspectorController

@synthesize attrRenderModelField = _attrRenderModelField;
@synthesize attrRenderAnimField = _attrRenderAnimField;
@synthesize attrRenderAnimClassField = _attrRenderAnimClassField;
@synthesize attrRenderLightOriginField = _attrRenderLightOriginField;
@synthesize attrRenderLightColorField = _attrRenderLightColorField;
@synthesize attrRenderModelOriginField = _attrRenderModelOriginField;
@synthesize attrRenderModelRotateField = _attrRenderModelRotateField;
@synthesize attrRenderViewOffsetField = _attrRenderViewOffsetField;
@synthesize attrRenderNeedsRenderButton = _attrRenderNeedsRenderButton;

- (void)syncFromWindow:(nullable UDGuiWindowNode *)node {
    UDRenderDefWindowNode *window = (UDRenderDefWindowNode *)node;
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

- (void)applyToWindow:(UDGuiWindowNode *)node {
    UDRenderDefWindowNode *window = (UDRenderDefWindowNode *)node;
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

@end
