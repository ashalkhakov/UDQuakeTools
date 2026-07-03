/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDListDefInspectorController.m — Controller for listDef attributes.
 */

#import "UDListDefInspectorController.h"

@implementation UDListDefInspectorController

@synthesize attrListHorizontalButton = _attrListHorizontalButton;
@synthesize attrListNameField = _attrListNameField;
@synthesize attrListTabStopsField = _attrListTabStopsField;
@synthesize attrListTabAlignsField = _attrListTabAlignsField;
@synthesize attrListMultipleSelButton = _attrListMultipleSelButton;
@synthesize attrListTabStopsHintLabel = _attrListTabStopsHintLabel;
@synthesize attrListTabAlignsHintLabel = _attrListTabAlignsHintLabel;

- (void)setHintLabel:(NSTextField *)label valid:(BOOL)valid {
    if (!label) {
        return;
    }
    label.textColor = valid ? [NSColor secondaryLabelColor] : [NSColor systemRedColor];
}

- (void)syncFromWindow:(nullable UDGuiWindowNode *)node {
    UDListDefWindowNode *window = (UDListDefWindowNode *)node;
    self.attrListHorizontalButton.state   = window.horizontal        ? NSControlStateValueOn : NSControlStateValueOff;
    self.attrListNameField.stringValue    = window.listName  ?: @"";
    self.attrListTabStopsField.stringValue= window.tabStops  ?: @"";
    self.attrListTabAlignsField.stringValue= window.tabAligns?: @"";
    self.attrListMultipleSelButton.state  = window.multipleSelection ? NSControlStateValueOn : NSControlStateValueOff;
}

- (void)applyToWindow:(UDGuiWindowNode *)node {
    UDListDefWindowNode *window = (UDListDefWindowNode *)node;
    window.horizontal        = self.attrListHorizontalButton.state == NSControlStateValueOn;
    window.listName          = self.attrListNameField.stringValue;
    window.tabStops          = self.attrListTabStopsField.stringValue;
    window.tabAligns         = self.attrListTabAlignsField.stringValue;
    window.multipleSelection = self.attrListMultipleSelButton.state == NSControlStateValueOn;
}

- (BOOL)validatePropertiesForWindow:(UDGuiWindowNode *)window {
    id preview = [window deepCopy];
    [self applyToWindow:preview];
    
    // We validate on the current local strings
    BOOL tabStopsValid = [self validateEditorValue:self.attrListTabStopsField.stringValue ?: @"" forKey:UDGuiWindowPropertyTabStops onWindow:window];
    if (!tabStopsValid) { return NO; }
    
    BOOL tabAlignsValid = [self validateEditorValue:self.attrListTabAlignsField.stringValue ?: @"" forKey:UDGuiWindowPropertyTabAligns onWindow:window];
    return tabAlignsValid;
}

- (void)refreshValidationHintsForWindow:(nullable UDGuiWindowNode *)node {
    UDListDefWindowNode *window = (UDListDefWindowNode *)node;
    UDGuiWindowNode *preview = window ? [window deepCopy] : [UDGuiWindowNode windowNodeWithClassName:@"windowDef" name:@"Preview"];
    [self applyToWindow:preview];
    
    id tabStopsVal = [preview stringPropertyForKey:UDGuiWindowPropertyTabStops] ?: @"";
    id tabAlignsVal = [preview stringPropertyForKey:UDGuiWindowPropertyTabAligns] ?: @"";
    
    NSError *error = nil;
    BOOL tabStopsValid = [preview validateValue:&tabStopsVal forKey:UDGuiWindowPropertyTabStops error:&error];
    BOOL tabAlignsValid = [preview validateValue:&tabAlignsVal forKey:UDGuiWindowPropertyTabAligns error:&error];
    
    [self setHintLabel:self.attrListTabStopsHintLabel valid:tabStopsValid];
    [self setHintLabel:self.attrListTabAlignsHintLabel valid:tabAlignsValid];
}

@end
