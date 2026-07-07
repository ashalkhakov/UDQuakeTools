/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDBindDefInspectorController.m — Controller for bindDef attributes.
 */

#import "UDBindDefInspectorController.h"

@implementation UDBindDefInspectorController

@synthesize attrBindField = _attrBindField;

- (void)syncFromWindow:(nullable UDGuiWindowNode *)node {
    UDBindDefWindowNode *window = (UDBindDefWindowNode *)node;
    self.attrBindField.stringValue = window.bind ?: @"";
}

- (void)applyToWindow:(UDGuiWindowNode *)node {
    UDBindDefWindowNode *window = (UDBindDefWindowNode *)node;
    window.bind = self.attrBindField.stringValue;
}

@end
