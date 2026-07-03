/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+Events.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@property (nonatomic, strong) NSTableView *eventHandlersTableView;
@property (nonatomic, strong) NSTableView *eventCommandsTableView;
@property (nonatomic, strong) NSPopUpButton *eventCommandTypePopup;
@property (nonatomic, strong) NSTabView *eventCommandEditorTabView;
@property (nonatomic, strong) NSTextField *eventSetVariableField;
@property (nonatomic, strong) NSTextField *eventSetValueField;
@property (nonatomic, strong) NSTextField *eventSetFocusWindowField;
@property (nonatomic, strong) NSTextField *eventResetTimeWindowField;
@property (nonatomic, strong) NSTextField *eventResetTimeValueField;
@property (nonatomic, strong) NSTextField *eventTransitionVariableField;
@property (nonatomic, strong) NSTextField *eventTransitionFromField;
@property (nonatomic, strong) NSTextField *eventTransitionToField;
@property (nonatomic, strong) NSTextField *eventTransitionTimeField;
@property (nonatomic, strong) NSTextField *eventTransitionAccelField;
@property (nonatomic, strong) NSTextField *eventTransitionDecelField;
@property (nonatomic, strong) NSTextField *eventLocalSoundField;
@property (nonatomic, strong) NSTextField *eventRunScriptField;
@property (nonatomic, strong) NSTextField *eventShowCursorField;
@property (nonatomic, strong) NSTextField *eventFallbackArgumentsField;
@property (nonatomic, assign) BOOL suppressEventCommandEditorCommit;
@end

@implementation UDGuiEdDocumentWindowController (Events)

- (void)syncEventCommandsTableForSelectedHandler {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    [self.eventCommandsTableView reloadData];
    if (handler.commands.count > 0) {
        [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
    } else {
        [self.eventCommandsTableView deselectAll:nil];
    }
    [self syncEventCommandEditorFromSelection];
}

- (void)finishCommandListMutationForHandler:(UDGuiEventHandler *)handler selectedRow:(NSInteger)row {
    [self.ownerDocument notifyGUIModelDidChange];
    [self.eventCommandsTableView reloadData];
    if (row >= 0 && row < (NSInteger)handler.commands.count) {
        [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    } else {
        [self.eventCommandsTableView deselectAll:nil];
    }
    [self syncEventCommandEditorFromSelection];
}

- (NSArray<UDGuiEventHandler *> *)selectedWindowEventHandlers {
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    return window ? window.eventHandlers : @[];
}

- (nullable UDGuiEventHandler *)selectedEventHandler {
    NSArray<UDGuiEventHandler *> *handlers = [self selectedWindowEventHandlers];
    NSInteger row = self.eventHandlersTableView.selectedRow;
    if (row < 0 || row >= (NSInteger)handlers.count) {
        return nil;
    }
    return [handlers objectAtIndex:(NSUInteger)row];
}

- (nullable UDGuiScriptCommand *)selectedEventCommand {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    NSInteger row = self.eventCommandsTableView.selectedRow;
    if (!handler || row < 0 || row >= (NSInteger)handler.commands.count) {
        return nil;
    }
    return [handler.commands objectAtIndex:(NSUInteger)row];
}

- (void)selectEventCommandEditorTabIdentifier:(NSString *)identifier {
    if (!self.eventCommandEditorTabView) {
        return;
    }

    NSTabViewItem *item = nil;
    for (NSTabViewItem *candidate in self.eventCommandEditorTabView.tabViewItems) {
        if ([[candidate identifier] isKindOfClass:[NSString class]] && [[candidate identifier] isEqualToString:identifier]) {
            item = candidate;
            break;
        }
    }
    if (!item) {
        for (NSTabViewItem *candidate in self.eventCommandEditorTabView.tabViewItems) {
            if ([[candidate identifier] isKindOfClass:[NSString class]] && [[candidate identifier] isEqualToString:@"none"]) {
                item = candidate;
                break;
            }
        }
    }
    if (item) {
        [self.eventCommandEditorTabView selectTabViewItem:item];
    }
}

- (void)syncEventCommandEditorFromSelection {
    UDGuiScriptCommand *command = [self selectedEventCommand];
    BOOL hasSelection = command != nil;
    self.suppressEventCommandEditorCommit = YES;
    self.eventCommandTypePopup.enabled = hasSelection;

    if (!command) {
        [self.eventCommandTypePopup selectItemAtIndex:-1];
        [self selectEventCommandEditorTabIdentifier:@"none"];
        self.suppressEventCommandEditorCommit = NO;
        return;
    }

    NSString *keyword = command.keyword ?: @"";
    NSString *lower = keyword.lowercaseString;
    if (![self.eventCommandTypePopup itemWithTitle:keyword]) {
        [self.eventCommandTypePopup addItemWithTitle:keyword];
    }
    [self.eventCommandTypePopup selectItemWithTitle:keyword];

    [self populateEventEditorForCommand:command keyword:lower];
    self.suppressEventCommandEditorCommit = NO;
}

- (void)populateEventEditorForCommand:(UDGuiScriptCommand *)command keyword:(NSString *)lowerKeyword {
    if ([command isKindOfClass:[UDGuiSetCommand class]]) {
        [self populateEventEditorForSetCommand:(UDGuiSetCommand *)command];
        return;
    }
    if ([command isKindOfClass:[UDGuiSetFocusCommand class]]) {
        [self populateEventEditorForSetFocusCommand:(UDGuiSetFocusCommand *)command];
        return;
    }
    if ([command isKindOfClass:[UDGuiResetTimeCommand class]]) {
        [self populateEventEditorForResetTimeCommand:(UDGuiResetTimeCommand *)command];
        return;
    }
    if ([command isKindOfClass:[UDGuiTransitionCommand class]]) {
        [self populateEventEditorForTransitionCommand:(UDGuiTransitionCommand *)command];
        return;
    }
    if ([command isKindOfClass:[UDGuiSingleArgumentCommand class]]) {
        [self populateEventEditorForSingleArgumentCommand:(UDGuiSingleArgumentCommand *)command keyword:lowerKeyword];
        return;
    }
    if ([lowerKeyword isEqualToString:@"evalregs"] || [lowerKeyword isEqualToString:@"resetcinematics"] || [lowerKeyword isEqualToString:@"endgame"]) {
        [self selectEventCommandEditorTabIdentifier:lowerKeyword];
        return;
    }

    [self populateEventEditorForFallbackCommand:command];
}

- (void)populateEventEditorForSetCommand:(UDGuiSetCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"set"];
    self.eventSetVariableField.stringValue = command.variable ?: @"";
    self.eventSetValueField.stringValue = command.valueExpression ?: @"";
}

- (void)populateEventEditorForSetFocusCommand:(UDGuiSetFocusCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"setFocus"];
    self.eventSetFocusWindowField.stringValue = command.windowName ?: @"";
}

- (void)populateEventEditorForResetTimeCommand:(UDGuiResetTimeCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"resetTime"];
    self.eventResetTimeWindowField.stringValue = command.windowName ?: @"";
    self.eventResetTimeValueField.stringValue = command.timeExpression ?: @"";
}

- (void)populateEventEditorForTransitionCommand:(UDGuiTransitionCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"transition"];
    self.eventTransitionVariableField.stringValue = command.variable ?: @"";
    self.eventTransitionFromField.stringValue = command.fromValue ?: @"";
    self.eventTransitionToField.stringValue = command.toValue ?: @"";
    self.eventTransitionTimeField.stringValue = command.timeExpression ?: @"";
    self.eventTransitionAccelField.stringValue = command.accelExpression ?: @"";
    self.eventTransitionDecelField.stringValue = command.decelExpression ?: @"";
}

- (void)populateEventEditorForSingleArgumentCommand:(UDGuiSingleArgumentCommand *)command keyword:(NSString *)lowerKeyword {
    if ([lowerKeyword isEqualToString:@"localsound"]) {
        [self selectEventCommandEditorTabIdentifier:@"localSound"];
        self.eventLocalSoundField.stringValue = command.value ?: @"";
        return;
    }
    if ([lowerKeyword isEqualToString:@"runscript"]) {
        [self selectEventCommandEditorTabIdentifier:@"runScript"];
        self.eventRunScriptField.stringValue = command.value ?: @"";
        return;
    }
    if ([lowerKeyword isEqualToString:@"showcursor"]) {
        [self selectEventCommandEditorTabIdentifier:@"showCursor"];
        self.eventShowCursorField.stringValue = command.value ?: @"";
        return;
    }

    [self populateEventEditorForFallbackCommand:command];
}

- (void)populateEventEditorForFallbackCommand:(UDGuiScriptCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"fallback"];
    self.eventFallbackArgumentsField.stringValue = command.arguments ?: @"";
}

- (UDGuiScriptCommand *)eventCommandFromEditorState {
    NSString *keyword = self.eventCommandTypePopup.selectedItem.title ?: @"";
    return UDGuiScriptCommandFromEditorValues(keyword,
                                              self.eventSetVariableField.stringValue ?: @"",
                                              self.eventSetValueField.stringValue ?: @"",
                                              self.eventSetFocusWindowField.stringValue ?: @"",
                                              self.eventResetTimeWindowField.stringValue ?: @"",
                                              self.eventResetTimeValueField.stringValue ?: @"",
                                              self.eventTransitionVariableField.stringValue ?: @"",
                                              self.eventTransitionFromField.stringValue ?: @"",
                                              self.eventTransitionToField.stringValue ?: @"",
                                              self.eventTransitionTimeField.stringValue ?: @"",
                                              self.eventTransitionAccelField.stringValue ?: @"",
                                              self.eventTransitionDecelField.stringValue ?: @"",
                                              self.eventLocalSoundField.stringValue ?: @"",
                                              self.eventRunScriptField.stringValue ?: @"",
                                              self.eventShowCursorField.stringValue ?: @"",
                                              self.eventFallbackArgumentsField.stringValue ?: @"");
}

- (IBAction)eventCommandEditorChanged:(id)sender {
    (void)sender;
    if (self.suppressEventCommandEditorCommit) {
        return;
    }

    UDGuiEventHandler *handler = [self selectedEventHandler];
    NSInteger row = self.eventCommandsTableView.selectedRow;
    if (!handler || row < 0 || row >= (NSInteger)handler.commands.count) {
        return;
    }

    [handler replaceCommandAtIndex:(NSUInteger)row withCommand:[self eventCommandFromEditorState]];
    [self.ownerDocument notifyGUIModelDidChange];
    [self.eventCommandsTableView reloadData];
    [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self syncEventCommandEditorFromSelection];
}

- (UDGuiEventHandler *)eventHandlerForType:(UDGuiEventHandlerType)type qualifier:(NSString *)qualifier {
    if (type == UDGuiEventHandlerTypeOnTime) {
        return [[UDGuiTimedEventHandler alloc] initWithTimeExpression:(qualifier.length > 0 ? qualifier : @"0")];
    }
    if (type == UDGuiEventHandlerTypeOnNamedEvent) {
        return [[UDGuiNamedEventHandler alloc] initWithEventName:qualifier ?: @""];
    }
    return [[UDGuiSimpleEventHandler alloc] initWithType:type];
}

- (void)reloadEventsEditorForWindow:(UDGuiWindowNode *)window preserveSelection:(BOOL)preserveSelection {
    (void)window;
    NSInteger selectedHandler = preserveSelection ? self.eventHandlersTableView.selectedRow : NSNotFound;
    [self.eventHandlersTableView reloadData];

    NSInteger handlerCount = (NSInteger)[self selectedWindowEventHandlers].count;
    if (handlerCount > 0) {
        NSInteger row = selectedHandler;
        if (row == NSNotFound || row < 0) {
            row = 0;
        }
        if (row >= handlerCount) {
            row = handlerCount - 1;
        }
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    } else {
        [self.eventHandlersTableView deselectAll:nil];
    }

    [self syncEventCommandsTableForSelectedHandler];
}

- (IBAction)changeEventHandlersActionButtons:(id)sender {
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    NSInteger row = self.eventHandlersTableView.selectedRow;
    if (segment == 0) {
        UDGuiEventHandler *handler = [[UDGuiSimpleEventHandler alloc] initWithType:UDGuiEventHandlerTypeOnAction];
        [handler addCommand:[[UDGuiScriptCommand alloc] initWithKeyword:@"set" arguments:@"notime 0"]];
        [window addEventHandler:handler];
        [self.ownerDocument notifyGUIModelDidChange];
        [self reloadEventsEditorForWindow:window preserveSelection:NO];
        NSInteger newRow = (NSInteger)window.eventHandlers.count - 1;
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)newRow] byExtendingSelection:NO];
        return;
    }

    if (row < 0 || row >= (NSInteger)window.eventHandlers.count) {
        return;
    }

    if (segment == 1) {
        [window removeEventHandlerAtIndex:(NSUInteger)row];
    } else if (segment == 2 && row > 0) {
        UDGuiEventHandler *handler = [window.eventHandlers objectAtIndex:(NSUInteger)row];
        [window removeEventHandlerAtIndex:(NSUInteger)row];
        [window insertEventHandler:handler atIndex:(NSUInteger)(row - 1)];
    } else if (segment == 3 && row < (NSInteger)window.eventHandlers.count - 1) {
        UDGuiEventHandler *handler = [window.eventHandlers objectAtIndex:(NSUInteger)row];
        [window removeEventHandlerAtIndex:(NSUInteger)row];
        [window insertEventHandler:handler atIndex:(NSUInteger)(row + 1)];
    } else {
        return;
    }

    [self.ownerDocument notifyGUIModelDidChange];
    [self reloadEventsEditorForWindow:window preserveSelection:NO];
}

- (IBAction)changeEventCommandsActionButtons:(id)sender {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    if (!handler) {
        return;
    }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    NSInteger row = self.eventCommandsTableView.selectedRow;
    if (segment == 0) {
        [handler addCommand:[[UDGuiScriptCommand alloc] initWithKeyword:@"set" arguments:@"notime 0"]];
        row = (NSInteger)handler.commands.count - 1;
    } else if (segment == 1) {
        if (row < 0 || row >= (NSInteger)handler.commands.count) {
            return;
        }
        [handler removeCommandAtIndex:(NSUInteger)row];
        if (row >= (NSInteger)handler.commands.count) {
            row = (NSInteger)handler.commands.count - 1;
        }
    } else if (segment == 2) {
        if (row <= 0 || row >= (NSInteger)handler.commands.count) {
            return;
        }
        UDGuiScriptCommand *command = [handler.commands objectAtIndex:(NSUInteger)row];
        [handler removeCommandAtIndex:(NSUInteger)row];
        [handler insertCommand:command atIndex:(NSUInteger)(row - 1)];
        row -= 1;
    } else if (segment == 3) {
        if (row < 0 || row >= (NSInteger)handler.commands.count - 1) {
            return;
        }
        UDGuiScriptCommand *command = [handler.commands objectAtIndex:(NSUInteger)row];
        [handler removeCommandAtIndex:(NSUInteger)row];
        [handler insertCommand:command atIndex:(NSUInteger)(row + 1)];
        row += 1;
    } else {
        return;
    }

    [self finishCommandListMutationForHandler:handler selectedRow:row];
}

@end
