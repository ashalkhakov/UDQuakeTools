/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+Conventions.h"
#import "UDGuiEdDocument.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@end

@implementation UDGuiEdDocumentWindowController (Conventions)

- (NSString *)ud_stringValueFromObject:(id)object {
    return [object isKindOfClass:[NSString class]] ? (NSString *)object : [[object description] copy];
}

- (void)ud_setTextField:(NSTextField *)field fromString:(NSString *)stringValue {
    if (!field) {
        return;
    }
    field.stringValue = stringValue ?: @"";
}

- (void)ud_notifyModelDidChangeAndRefresh {
    [self.ownerDocument notifyGUIModelDidChange];
    [self refreshFromDocument];
}

@end
