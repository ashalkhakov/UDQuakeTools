/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDGuiEdDocumentWindowController (EventsTable)

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard;
- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation;
- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation;
- (id)tableViewObjectValueForEventsTableView:(NSTableView *)tableView column:(NSTableColumn *)tableColumn row:(NSInteger)row;
- (void)tableViewSetObjectValueForEventsTableView:(NSTableView *)tableView object:(id)object column:(NSTableColumn *)tableColumn row:(NSInteger)row;

@end

NS_ASSUME_NONNULL_END
