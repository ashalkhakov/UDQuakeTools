/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEdDocumentWindowController (Conventions)

- (NSString *)ud_stringValueFromObject:(id)object;
- (void)ud_setTextField:(NSTextField *)field fromString:(NSString *)stringValue;
- (void)ud_notifyModelDidChangeAndRefresh;

@end

NS_ASSUME_NONNULL_END
