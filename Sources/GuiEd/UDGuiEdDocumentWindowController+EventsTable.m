/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+EventsTable.h"
#import "UDGuiEdDocumentWindowController+Events.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

static NSPasteboardType const UDGuiEventsReorderPasteboardType = @"com.udquake.guied.reorder-row";

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@property (nonatomic, strong) NSTableView *eventHandlersTableView;
@property (nonatomic, strong) NSTableView *eventCommandsTableView;
@end

@implementation UDGuiEdDocumentWindowController (EventsTable)

- (NSDictionary *)eventsDragPayloadFromDraggingInfo:(id<NSDraggingInfo>)info {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    NSData *data = [pasteboard dataForType:UDGuiEventsReorderPasteboardType];
    if (!data) {
        return nil;
    }

    NSDictionary *payload = [NSKeyedUnarchiver unarchiveObjectWithData:data];
    return [payload isKindOfClass:[NSDictionary class]] ? payload : nil;
}

- (NSInteger)normalizedDestinationRow:(NSInteger)row count:(NSInteger)count sourceRow:(NSInteger)sourceRow {
    NSInteger destinationRow = MIN(MAX(row, 0), count);
    if (destinationRow == sourceRow || destinationRow == sourceRow + 1) {
        return NSNotFound;
    }
    return (destinationRow > sourceRow) ? destinationRow - 1 : destinationRow;
}

- (void)copyCommandsFromHandler:(UDGuiEventHandler *)source toHandler:(UDGuiEventHandler *)target {
    for (UDGuiScriptCommand *command in source.commands) {
        [target addCommand:[command deepCopy]];
    }
}

- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pasteboard {
    if ((tableView != self.eventHandlersTableView && tableView != self.eventCommandsTableView) || rowIndexes.count == 0) {
        return NO;
    }

    NSInteger row = (NSInteger)rowIndexes.firstIndex;
    NSString *kind = (tableView == self.eventHandlersTableView) ? @"handlers" : @"commands";
    NSDictionary *payload = @{ @"kind": kind, @"row": @(row) };
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:payload];
    if (!data) {
        return NO;
    }

    [pasteboard declareTypes:@[UDGuiEventsReorderPasteboardType] owner:nil];
    [pasteboard setData:data forType:UDGuiEventsReorderPasteboardType];
    return YES;
}

- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id<NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)dropOperation {
    if (tableView != self.eventHandlersTableView && tableView != self.eventCommandsTableView) {
        return NSDragOperationNone;
    }

    if (dropOperation != NSTableViewDropAbove) {
        [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    }

    NSDictionary *payload = [self eventsDragPayloadFromDraggingInfo:info];
    if (!payload) {
        return NSDragOperationNone;
    }

    NSString *kind = payload[@"kind"];
    if ((tableView == self.eventHandlersTableView && ![kind isEqualToString:@"handlers"]) ||
        (tableView == self.eventCommandsTableView && ![kind isEqualToString:@"commands"])) {
        return NSDragOperationNone;
    }

    return NSDragOperationMove;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id<NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)dropOperation {
    (void)dropOperation;
    NSDictionary *payload = [self eventsDragPayloadFromDraggingInfo:info];
    if (!payload) {
        return NO;
    }

    NSInteger sourceRow = [payload[@"row"] integerValue];
    if (tableView == self.eventHandlersTableView) {
        UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
        NSInteger count = (NSInteger)window.eventHandlers.count;
        if (!window || sourceRow < 0 || sourceRow >= count) {
            return NO;
        }

        NSInteger destinationRow = [self normalizedDestinationRow:row count:count sourceRow:sourceRow];
        if (destinationRow == NSNotFound) {
            return NO;
        }

        UDGuiEventHandler *item = [window.eventHandlers objectAtIndex:(NSUInteger)sourceRow];
        [window removeEventHandlerAtIndex:(NSUInteger)sourceRow];
        [window insertEventHandler:item atIndex:(NSUInteger)destinationRow];
        [self.ownerDocument notifyGUIModelDidChange];
        [self reloadEventsEditorForWindow:window preserveSelection:NO];
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)destinationRow] byExtendingSelection:NO];
        return YES;
    }

    if (tableView == self.eventCommandsTableView) {
        UDGuiEventHandler *handler = [self selectedEventHandler];
        NSInteger count = (NSInteger)handler.commands.count;
        if (!handler || sourceRow < 0 || sourceRow >= count) {
            return NO;
        }

        NSInteger destinationRow = [self normalizedDestinationRow:row count:count sourceRow:sourceRow];
        if (destinationRow == NSNotFound) {
            return NO;
        }

        UDGuiScriptCommand *item = [handler.commands objectAtIndex:(NSUInteger)sourceRow];
        [handler removeCommandAtIndex:(NSUInteger)sourceRow];
        [handler insertCommand:item atIndex:(NSUInteger)destinationRow];
        [self.ownerDocument notifyGUIModelDidChange];
        [self.eventCommandsTableView reloadData];
        [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)destinationRow] byExtendingSelection:NO];
        [self syncEventCommandEditorFromSelection];
        return YES;
    }

    return NO;
}

- (id)tableViewObjectValueForEventsTableView:(NSTableView *)tableView column:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.eventHandlersTableView) {
        NSArray<UDGuiEventHandler *> *handlers = [self selectedWindowEventHandlers];
        if (row < 0 || row >= (NSInteger)handlers.count) {
            return @"";
        }

        UDGuiEventHandler *handler = [handlers objectAtIndex:(NSUInteger)row];
        if ([tableColumn.identifier isEqualToString:@"event"]) {
            return UDGuiEventKeywordForType(handler.type);
        }
        if ([tableColumn.identifier isEqualToString:@"qualifier"]) {
            return [handler eventQualifier] ?: @"";
        }
        return @"";
    }

    if (tableView == self.eventCommandsTableView) {
        UDGuiEventHandler *handler = [self selectedEventHandler];
        if (!handler || row < 0 || row >= (NSInteger)handler.commands.count) {
            return @"";
        }
        UDGuiScriptCommand *command = [handler.commands objectAtIndex:(NSUInteger)row];
        return [command serializedStatement];
    }

    return @"";
}

- (void)tableViewSetObjectValueForEventsTableView:(NSTableView *)tableView object:(id)object column:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.eventHandlersTableView) {
        UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
        NSArray<UDGuiEventHandler *> *handlers = [self selectedWindowEventHandlers];
        if (!window || row < 0 || row >= (NSInteger)handlers.count) {
            return;
        }

        UDGuiEventHandler *existing = [handlers objectAtIndex:(NSUInteger)row];
        NSString *stringValue = [object isKindOfClass:[NSString class]] ? (NSString *)object : [[object description] copy];

        if ([tableColumn.identifier isEqualToString:@"event"]) {
            UDGuiEventHandlerType type = existing.type;
            if (!UDGuiEventTypeFromKeyword(stringValue ?: @"", &type)) {
                return;
            }
            UDGuiEventHandler *replacement = [self eventHandlerForType:type qualifier:[existing eventQualifier] ?: @""];
            [self copyCommandsFromHandler:existing toHandler:replacement];
            [window replaceEventHandlerAtIndex:(NSUInteger)row withEventHandler:replacement];
        } else if ([tableColumn.identifier isEqualToString:@"qualifier"]) {
            UDGuiEventHandler *replacement = [self eventHandlerForType:existing.type qualifier:stringValue ?: @""];
            [self copyCommandsFromHandler:existing toHandler:replacement];
            [window replaceEventHandlerAtIndex:(NSUInteger)row withEventHandler:replacement];
        } else {
            return;
        }

        [self.ownerDocument notifyGUIModelDidChange];
        [self reloadEventsEditorForWindow:window preserveSelection:NO];
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        return;
    }

    if (tableView == self.eventCommandsTableView) {
        // Commands are edited through the typed command editor controls.
        return;
    }
}

@end
