/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+TableSelection.h"
#import "UDGuiEdDocumentWindowController+Events.h"
#import "UDGuiEdDocumentWindowController+Variables.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, strong) NSTableView *eventHandlersTableView;
@property (nonatomic, strong) NSTableView *eventCommandsTableView;
@end

@implementation UDGuiEdDocumentWindowController (TableSelection)

- (void)syncCommandsTableSelectionFromSelectedHandler {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    if (handler.commands.count > 0) {
        [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    } else {
        [self.eventCommandsTableView deselectAll:nil];
    }
}

- (void)handleTableViewSelectionDidChangeNotification:(NSNotification *)notification {
    if (notification.object == self.variablesTableView) {
        [self syncVariableControlsFromSelection];
        return;
    }

    if (notification.object == self.eventHandlersTableView) {
        [self.eventCommandsTableView reloadData];
        [self syncCommandsTableSelectionFromSelectedHandler];
        [self syncEventCommandEditorFromSelection];
        return;
    }

    if (notification.object == self.eventCommandsTableView) {
        [self syncEventCommandEditorFromSelection];
    }
}

@end
