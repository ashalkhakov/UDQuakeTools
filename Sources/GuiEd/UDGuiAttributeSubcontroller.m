/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiAttributeSubcontroller.m — Base class implementation for typed inspector sub-controllers.
 */

#import "UDGuiAttributeSubcontroller.h"

@implementation UDGuiAttributeSubcontroller

@synthesize view = _view;
@synthesize context = _context;

- (instancetype)initWithNibName:(NSString *)nibName {
    self = [super init];
    if (self) {
#ifdef GNUSTEP
        [NSBundle loadNibNamed:nibName owner:self];
#else
        [[NSBundle mainBundle] loadNibNamed:nibName owner:self topLevelObjects:nil];
#endif
    }
    return self;
}

- (void)syncFromWindow:(nullable UDGuiWindowNode *)window {
    // Subclasses override
}

- (void)applyToWindow:(UDGuiWindowNode *)window {
    // Subclasses override
}

- (BOOL)validatePropertiesForWindow:(UDGuiWindowNode *)window {
    return YES;
}

- (void)refreshValidationHintsForWindow:(nullable UDGuiWindowNode *)window {
    // Subclasses override
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

- (void)syncBoolButton:(NSButton *)button key:(NSString *)key window:(nullable UDGuiWindowNode *)window defaultOnWhenNil:(BOOL)defaultOnWhenNil {
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

- (IBAction)commitTypedAttributesPanel:(id)sender {
    (void)sender;
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }
    if (![self validatePropertiesForWindow:window]) {
        [self refreshValidationHintsForWindow:window];
        return;
    }
    [self applyToWindow:window];
    [self.context notifyModelChangedAndRefresh];
}

@end
