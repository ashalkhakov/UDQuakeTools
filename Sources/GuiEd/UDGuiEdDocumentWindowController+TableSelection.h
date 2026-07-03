/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEdDocumentWindowController (TableSelection)

- (void)handleTableViewSelectionDidChangeNotification:(NSNotification *)notification;

@end

NS_ASSUME_NONNULL_END
