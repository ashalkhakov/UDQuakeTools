/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEdDocumentWindowController (VariablesTable)

- (id)tableViewObjectValueForVariablesTableView:(NSTableView *)tableView column:(NSTableColumn *)tableColumn row:(NSInteger)row;
- (void)tableViewSetObjectValueForVariablesTableView:(NSTableView *)tableView object:(id)object column:(NSTableColumn *)tableColumn row:(NSInteger)row;

@end

NS_ASSUME_NONNULL_END
