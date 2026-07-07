/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDEventsController.m — Events panel controller for the GUI editor.
 */

#import "UDEventsController.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

static NSPasteboardType const UDGuiEventsReorderPasteboardType = @"com.udquake.guied.reorder-row";

// Layout constants for the script editor workspace UI
static const CGFloat kUDEventsErrorLabelHeight = 24.0;
static const CGFloat kUDEventsModeControlWidth = 160.0;
static const CGFloat kUDEventsModeControlHeight = 24.0;
static const CGFloat kUDEventsTopBarHeight = 28.0;
static const CGFloat kUDEventsScrollBorderOffset = 2.0;

@interface UDEventsController () <NSTextViewDelegate>
@property (nonatomic, assign) BOOL suppressEventCommandEditorCommit;
@property (nonatomic, strong) NSSegmentedControl *modeSegmentedControl;
@property (nonatomic, strong) NSScrollView *scriptScrollView;
@property (nonatomic, strong) NSTextView *scriptTextView;
@property (nonatomic, strong) NSTextField *errorLabel;
@property (nonatomic, assign) BOOL isScriptMode;
@property (nonatomic, strong, nullable) UDGuiEventHandler *activeEventHandler;
@end

@implementation UDEventsController

@synthesize view = _view;
@synthesize eventHandlersTableView = _eventHandlersTableView;
@synthesize eventCommandsTableView = _eventCommandsTableView;
@synthesize eventCommandTypePopup = _eventCommandTypePopup;
@synthesize eventCommandEditorTabView = _eventCommandEditorTabView;
@synthesize eventSetVariableField = _eventSetVariableField;
@synthesize eventSetValueField = _eventSetValueField;
@synthesize eventSetFocusWindowField = _eventSetFocusWindowField;
@synthesize eventResetTimeWindowField = _eventResetTimeWindowField;
@synthesize eventResetTimeValueField = _eventResetTimeValueField;
@synthesize eventTransitionVariableField = _eventTransitionVariableField;
@synthesize eventTransitionFromField = _eventTransitionFromField;
@synthesize eventTransitionToField = _eventTransitionToField;
@synthesize eventTransitionTimeField = _eventTransitionTimeField;
@synthesize eventTransitionAccelField = _eventTransitionAccelField;
@synthesize eventTransitionDecelField = _eventTransitionDecelField;
@synthesize eventLocalSoundField = _eventLocalSoundField;
@synthesize eventRunScriptField = _eventRunScriptField;
@synthesize eventShowCursorField = _eventShowCursorField;
@synthesize eventFallbackArgumentsField = _eventFallbackArgumentsField;

- (instancetype)init {
    self = [super init];
    if (self) {
#ifdef GNUSTEP
        [NSBundle loadNibNamed:@"UDEvents" owner:self];
#else
        [[NSBundle mainBundle] loadNibNamed:@"UDEvents" owner:self topLevelObjects:nil];
#endif
    }
    return self;
}

// MARK: - Setup

- (void)registerDragTypes {
    if (self.eventHandlersTableView) {
        [self.eventHandlersTableView registerForDraggedTypes:@[UDGuiEventsReorderPasteboardType]];
        [self.eventHandlersTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    }
    if (self.eventCommandsTableView) {
        [self.eventCommandsTableView registerForDraggedTypes:@[UDGuiEventsReorderPasteboardType]];
        [self.eventCommandsTableView setDraggingSourceOperationMask:NSDragOperationMove forLocal:YES];
    }
}

- (NSView *)commandsContainer {
    NSView *container = self.eventCommandsTableView.superview;
    while (container && container != self.view) {
        if (container.superview == self.view) {
            return container;
        }
        container = container.superview;
    }
    return container;
}

- (void)awakeFromNib {
    NSView *container = [self commandsContainer];
    if (!container) { return; }

    // 1. Mode segmented control
    NSSegmentedControl *modeControl = [[NSSegmentedControl alloc] initWithFrame:NSMakeRect(container.bounds.size.width - kUDEventsModeControlWidth, container.bounds.size.height - kUDEventsTopBarHeight, kUDEventsModeControlWidth, kUDEventsModeControlHeight)];
    modeControl.segmentCount = 2;
    [modeControl setLabel:@"Structured" forSegment:0];
    [modeControl setLabel:@"Script" forSegment:1];
    modeControl.selectedSegment = 0;
    modeControl.target = self;
    modeControl.action = @selector(toggleEditorMode:);
    modeControl.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    [container addSubview:modeControl];
    self.modeSegmentedControl = modeControl;

    // 2. Error Label
    NSTextField *errLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, container.bounds.size.width, kUDEventsErrorLabelHeight)];
    errLabel.editable = NO;
    errLabel.selectable = YES;
    errLabel.bordered = NO;
    errLabel.drawsBackground = NO;
    errLabel.textColor = [NSColor redColor];
    errLabel.font = [NSFont systemFontOfSize:11.0];
    errLabel.stringValue = @"";
    errLabel.hidden = YES;
    errLabel.autoresizingMask = NSViewWidthSizable | NSViewMaxYMargin;
    [container addSubview:errLabel];
    self.errorLabel = errLabel;

    // 3. Script ScrollView & TextView
    CGFloat scrollY = kUDEventsErrorLabelHeight;
    CGFloat scrollHeight = container.bounds.size.height - kUDEventsErrorLabelHeight - kUDEventsTopBarHeight - 4.0;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, scrollY, container.bounds.size.width, scrollHeight)];
    scroll.hasVerticalScroller = YES;
    scroll.hasHorizontalScroller = YES;
    scroll.autohidesScrollers = YES;
    scroll.borderType = NSBezelBorder;
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTextView *text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, container.bounds.size.width - kUDEventsScrollBorderOffset, scrollHeight - kUDEventsScrollBorderOffset)];
    text.minSize = NSMakeSize(0.0, scrollHeight - kUDEventsScrollBorderOffset);
    text.maxSize = NSMakeSize(1e7, 1e7);
    text.verticallyResizable = YES;
    text.horizontallyResizable = YES;
    text.autoresizingMask = NSViewWidthSizable;
    [text.textContainer setContainerSize:NSMakeSize(1e7, 1e7)];
    [text.textContainer setWidthTracksTextView:NO];
    text.font = [NSFont userFixedPitchFontOfSize:11.0];
    text.delegate = self;

    scroll.documentView = text;
    scroll.hidden = YES;
    [container addSubview:scroll];

    self.scriptScrollView = scroll;
    self.scriptTextView = text;
}

- (void)toggleEditorMode:(id)sender {
    NSInteger selectedSegment = self.modeSegmentedControl.selectedSegment;
    BOOL newScriptMode = (selectedSegment == 1);
    if (self.isScriptMode == newScriptMode) {
        return;
    }

    if (self.isScriptMode) {
        [self commitTextEdits];
    }

    self.isScriptMode = newScriptMode;
    [self updateViewVisibilityForCurrentMode];

    if (self.isScriptMode) {
        [self loadScriptForSelectedHandler];
    } else {
        [self syncCommandsTableForSelectedHandler];
    }
}

- (void)updateViewVisibilityForCurrentMode {
    BOOL isScript = self.isScriptMode;
    NSView *container = [self commandsContainer];
    for (NSView *subview in container.subviews) {
        if (subview == self.modeSegmentedControl) {
            continue;
        }
        if (subview == self.scriptScrollView || subview == self.errorLabel) {
            subview.hidden = !isScript;
        } else {
            subview.hidden = isScript;
        }
    }
}

- (void)loadScriptForSelectedHandler {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    self.activeEventHandler = handler;

    if (!handler) {
        self.scriptTextView.string = @"";
        self.scriptTextView.editable = NO;
        self.errorLabel.hidden = YES;
        self.errorLabel.stringValue = @"";
        return;
    }

    self.scriptTextView.editable = YES;

    NSMutableString *text = [NSMutableString string];
    for (UDGuiScriptCommand *command in handler.commands) {
        if ([command.keyword isEqualToString:@"__ud_raw_script_body__"]) {
            NSString *rawBody = command.arguments ?: @"";
            [text appendString:rawBody];
        } else {
            if ([command isKindOfClass:[UDGuiIfCommand class]]) {
                [text appendFormat:@"%@\n", [command serializedStatement]];
            } else {
                [text appendFormat:@"%@ ;\n", [command serializedStatement]];
            }
        }
    }

    self.scriptTextView.string = text;
    self.errorLabel.hidden = YES;
    self.errorLabel.stringValue = @"";
}

- (void)commitTextEdits {
    if (!self.isScriptMode) { return; }
    UDGuiEventHandler *handler = self.activeEventHandler;
    if (!handler) { return; }

    NSString *text = self.scriptTextView.string ?: @"";
    NSError *error = nil;
    NSArray<UDGuiScriptCommand *> *commands = [self.context.ownerDocument.codec scriptCommandsFromBlockValue:text error:&error];
    if (commands) {
        self.errorLabel.hidden = YES;
        self.errorLabel.stringValue = @"";

        BOOL changed = NO;
        if (commands.count != handler.commands.count) {
            changed = YES;
        } else {
            for (NSUInteger i = 0; i < commands.count; i++) {
                NSString *newCmdStr = [[commands objectAtIndex:i] serializedStatement];
                NSString *oldCmdStr = [[handler.commands objectAtIndex:i] serializedStatement];
                if (![newCmdStr isEqualToString:oldCmdStr]) {
                    changed = YES;
                    break;
                }
            }
        }

        if (changed) {
            UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
            NSUInteger handlerIndex = [window.eventHandlers indexOfObject:handler];
            if (handlerIndex != NSNotFound) {
                [self.context.ownerDocument.editorService updateCommandsForEventHandlerAtIndex:handlerIndex
                                                                                       onWindow:window
                                                                                    newCommands:commands];
                [self.context.ownerDocument notifyGUIModelDidChange];
            }
        }
    } else {
        if (error) {
            self.errorLabel.stringValue = error.localizedDescription;
            self.errorLabel.hidden = NO;
        }
    }
}

// MARK: - NSTextViewDelegate

- (void)textDidChange:(NSNotification *)notification {
    if (notification.object != self.scriptTextView) { return; }

    UDGuiEventHandler *handler = self.activeEventHandler;
    if (!handler) { return; }

    NSString *text = self.scriptTextView.string ?: @"";
    NSError *error = nil;
    NSArray<UDGuiScriptCommand *> *commands = [self.context.ownerDocument.codec scriptCommandsFromBlockValue:text error:&error];
    if (commands) {
        self.errorLabel.hidden = YES;
        self.errorLabel.stringValue = @"";

        // Bulk replace to avoid O(n^2) removal operations.
        // We update the underlying model in real-time without registering global undo operations
        // to prevent keypress bloat on the document's undo stack. Local text changes are already
        // managed by the NSTextView's local undo manager, and a consolidated bulk commit with
        // global undo is performed on focus loss (textDidEndEditing:), row change, or mode toggle.
        [handler replaceCommandsWithArray:commands];

        [self.context.ownerDocument notifyGUIModelDidChange];
    } else {
        if (error) {
            self.errorLabel.stringValue = error.localizedDescription;
            self.errorLabel.hidden = NO;
        }
    }
}

- (void)textDidEndEditing:(NSNotification *)notification {
    if (notification.object == self.scriptTextView) {
        [self commitTextEdits];
    }
}

// MARK: - Selection accessors

- (NSArray<UDGuiEventHandler *> *)eventHandlersForSelectedWindow {
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    return window ? window.eventHandlers : @[];
}

- (nullable UDGuiEventHandler *)selectedEventHandler {
    NSArray<UDGuiEventHandler *> *handlers = [self eventHandlersForSelectedWindow];
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

// MARK: - Reload

- (void)reloadForWindow:(nullable UDGuiWindowNode *)window preserveSelection:(BOOL)preserveSelection {
    (void)window;
    NSInteger selectedHandler = preserveSelection ? self.eventHandlersTableView.selectedRow : NSNotFound;
    [self.eventHandlersTableView reloadData];

    NSInteger handlerCount = (NSInteger)[self eventHandlersForSelectedWindow].count;
    if (handlerCount > 0) {
        NSInteger row = selectedHandler;
        if (row == NSNotFound || row < 0) { row = 0; }
        if (row >= handlerCount) { row = handlerCount - 1; }
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    } else {
        [self.eventHandlersTableView deselectAll:nil];
    }
    [self syncCommandsTableForSelectedHandler];
}

// MARK: - Commands table sync

- (void)syncCommandsTableForSelectedHandler {
    if (self.isScriptMode) {
        [self loadScriptForSelectedHandler];
    } else {
        [self.eventCommandsTableView reloadData];
        UDGuiEventHandler *handler = [self selectedEventHandler];
        if (handler.commands.count > 0) {
            [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
        } else {
            [self.eventCommandsTableView deselectAll:nil];
        }
        [self syncEventCommandEditorFromSelection];
    }
}

- (void)finishCommandListMutationForHandler:(UDGuiEventHandler *)handler selectedRow:(NSInteger)row {
    [self.context.ownerDocument notifyGUIModelDidChange];
    [self.eventCommandsTableView reloadData];
    if (row >= 0 && row < (NSInteger)handler.commands.count) {
        [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    } else {
        [self.eventCommandsTableView deselectAll:nil];
    }
    [self syncEventCommandEditorFromSelection];
}

// MARK: - Event command editor

- (void)selectEventCommandEditorTabIdentifier:(NSString *)identifier {
    if (!self.eventCommandEditorTabView) { return; }

    NSTabViewItem *item = nil;
    for (NSTabViewItem *candidate in self.eventCommandEditorTabView.tabViewItems) {
        if ([[candidate identifier] isKindOfClass:[NSString class]] &&
            [[candidate identifier] isEqualToString:identifier]) {
            item = candidate;
            break;
        }
    }
    if (!item) {
        for (NSTabViewItem *candidate in self.eventCommandEditorTabView.tabViewItems) {
            if ([[candidate identifier] isKindOfClass:[NSString class]] &&
                [[candidate identifier] isEqualToString:@"none"]) {
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
    NSString *lower   = keyword.lowercaseString;
    if (![self.eventCommandTypePopup itemWithTitle:keyword]) {
        [self.eventCommandTypePopup addItemWithTitle:keyword];
    }
    [self.eventCommandTypePopup selectItemWithTitle:keyword];

    [self populateEventEditorForCommand:command keyword:lower];
    self.suppressEventCommandEditorCommit = NO;
}

- (void)populateEventEditorForCommand:(UDGuiScriptCommand *)command keyword:(NSString *)lowerKeyword {
    if ([command isKindOfClass:[UDGuiSetCommand class]]) {
        [self populateEditorForSetCommand:(UDGuiSetCommand *)command]; return;
    }
    if ([command isKindOfClass:[UDGuiSetFocusCommand class]]) {
        [self populateEditorForSetFocusCommand:(UDGuiSetFocusCommand *)command]; return;
    }
    if ([command isKindOfClass:[UDGuiResetTimeCommand class]]) {
        [self populateEditorForResetTimeCommand:(UDGuiResetTimeCommand *)command]; return;
    }
    if ([command isKindOfClass:[UDGuiTransitionCommand class]]) {
        [self populateEditorForTransitionCommand:(UDGuiTransitionCommand *)command]; return;
    }
    if ([command isKindOfClass:[UDGuiSingleArgumentCommand class]]) {
        [self populateEditorForSingleArgumentCommand:(UDGuiSingleArgumentCommand *)command keyword:lowerKeyword]; return;
    }
    if ([lowerKeyword isEqualToString:@"evalregs"] ||
        [lowerKeyword isEqualToString:@"resetcinematics"] ||
        [lowerKeyword isEqualToString:@"endgame"]) {
        [self selectEventCommandEditorTabIdentifier:lowerKeyword]; return;
    }
    [self populateEditorForFallbackCommand:command];
}

- (void)populateEditorForSetCommand:(UDGuiSetCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"set"];
    self.eventSetVariableField.stringValue = command.variable ?: @"";
    self.eventSetValueField.stringValue    = command.valueExpression ?: @"";
}

- (void)populateEditorForSetFocusCommand:(UDGuiSetFocusCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"setFocus"];
    self.eventSetFocusWindowField.stringValue = command.windowName ?: @"";
}

- (void)populateEditorForResetTimeCommand:(UDGuiResetTimeCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"resetTime"];
    self.eventResetTimeWindowField.stringValue = command.windowName ?: @"";
    self.eventResetTimeValueField.stringValue  = command.timeExpression ?: @"";
}

- (void)populateEditorForTransitionCommand:(UDGuiTransitionCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"transition"];
    self.eventTransitionVariableField.stringValue = command.variable ?: @"";
    self.eventTransitionFromField.stringValue     = command.fromValue ?: @"";
    self.eventTransitionToField.stringValue       = command.toValue ?: @"";
    self.eventTransitionTimeField.stringValue     = command.timeExpression ?: @"";
    self.eventTransitionAccelField.stringValue    = command.accelExpression ?: @"";
    self.eventTransitionDecelField.stringValue    = command.decelExpression ?: @"";
}

- (void)populateEditorForSingleArgumentCommand:(UDGuiSingleArgumentCommand *)command keyword:(NSString *)lowerKeyword {
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
    [self populateEditorForFallbackCommand:command];
}

- (void)populateEditorForFallbackCommand:(UDGuiScriptCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"fallback"];
    self.eventFallbackArgumentsField.stringValue = command.arguments ?: @"";
}

- (UDGuiScriptCommand *)eventCommandFromEditorState {
    NSString *keyword = self.eventCommandTypePopup.selectedItem.title ?: @"";
    return UDGuiScriptCommandFromEditorValues(keyword,
        self.eventSetVariableField.stringValue       ?: @"",
        self.eventSetValueField.stringValue          ?: @"",
        self.eventSetFocusWindowField.stringValue    ?: @"",
        self.eventResetTimeWindowField.stringValue   ?: @"",
        self.eventResetTimeValueField.stringValue    ?: @"",
        self.eventTransitionVariableField.stringValue?: @"",
        self.eventTransitionFromField.stringValue    ?: @"",
        self.eventTransitionToField.stringValue      ?: @"",
        self.eventTransitionTimeField.stringValue    ?: @"",
        self.eventTransitionAccelField.stringValue   ?: @"",
        self.eventTransitionDecelField.stringValue   ?: @"",
        self.eventLocalSoundField.stringValue        ?: @"",
        self.eventRunScriptField.stringValue         ?: @"",
        self.eventShowCursorField.stringValue        ?: @"",
        self.eventFallbackArgumentsField.stringValue ?: @"");
}

// MARK: - Actions

- (IBAction)eventCommandEditorChanged:(id)sender {
    (void)sender;
    if (self.suppressEventCommandEditorCommit) { return; }

    UDGuiEventHandler *handler = [self selectedEventHandler];
    NSInteger row = self.eventCommandsTableView.selectedRow;
    if (!handler || row < 0 || row >= (NSInteger)handler.commands.count) { return; }

    [handler replaceCommandAtIndex:(NSUInteger)row withCommand:[self eventCommandFromEditorState]];
    [self.context.ownerDocument notifyGUIModelDidChange];
    [self.eventCommandsTableView reloadData];
    [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    [self syncEventCommandEditorFromSelection];
}

- (UDGuiEventHandler *)newEventHandlerForType:(UDGuiEventHandlerType)type qualifier:(NSString *)qualifier {
    if (type == UDGuiEventHandlerTypeOnTime) {
        return [[UDGuiTimedEventHandler alloc] initWithTimeExpression:(qualifier.length > 0 ? qualifier : @"0")];
    }
    if (type == UDGuiEventHandlerTypeOnNamedEvent) {
        return [[UDGuiNamedEventHandler alloc] initWithEventName:qualifier ?: @""];
    }
    return [[UDGuiSimpleEventHandler alloc] initWithType:type];
}

- (IBAction)changeEventHandlersActionButtons:(id)sender {
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }

    if (self.isScriptMode) {
        [self commitTextEdits];
    }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    NSInteger row = self.eventHandlersTableView.selectedRow;
    if (segment == 0) {
        UDGuiEventHandler *handler = [[UDGuiSimpleEventHandler alloc] initWithType:UDGuiEventHandlerTypeOnAction];
        [handler addCommand:[[UDGuiScriptCommand alloc] initWithKeyword:@"set" arguments:@"notime 0"]];
        [window addEventHandler:handler];
        [self.context.ownerDocument notifyGUIModelDidChange];
        [self reloadForWindow:window preserveSelection:NO];
        NSInteger newRow = (NSInteger)window.eventHandlers.count - 1;
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)newRow] byExtendingSelection:NO];
        return;
    }

    if (row < 0 || row >= (NSInteger)window.eventHandlers.count) { return; }

    if (segment == 1) {
        [window removeEventHandlerAtIndex:(NSUInteger)row];
    } else if (segment == 2 && row > 0) {
        UDGuiEventHandler *h = [window.eventHandlers objectAtIndex:(NSUInteger)row];
        [window removeEventHandlerAtIndex:(NSUInteger)row];
        [window insertEventHandler:h atIndex:(NSUInteger)(row - 1)];
    } else if (segment == 3 && row < (NSInteger)window.eventHandlers.count - 1) {
        UDGuiEventHandler *h = [window.eventHandlers objectAtIndex:(NSUInteger)row];
        [window removeEventHandlerAtIndex:(NSUInteger)row];
        [window insertEventHandler:h atIndex:(NSUInteger)(row + 1)];
    } else {
        return;
    }

    [self.context.ownerDocument notifyGUIModelDidChange];
    [self reloadForWindow:window preserveSelection:NO];
}

- (IBAction)changeEventCommandsActionButtons:(id)sender {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    if (!handler) { return; }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    NSInteger row = self.eventCommandsTableView.selectedRow;
    if (segment == 0) {
        [handler addCommand:[[UDGuiScriptCommand alloc] initWithKeyword:@"set" arguments:@"notime 0"]];
        row = (NSInteger)handler.commands.count - 1;
    } else if (segment == 1) {
        if (row < 0 || row >= (NSInteger)handler.commands.count) { return; }
        [handler removeCommandAtIndex:(NSUInteger)row];
        if (row >= (NSInteger)handler.commands.count) { row = (NSInteger)handler.commands.count - 1; }
    } else if (segment == 2) {
        if (row <= 0 || row >= (NSInteger)handler.commands.count) { return; }
        UDGuiScriptCommand *cmd = [handler.commands objectAtIndex:(NSUInteger)row];
        [handler removeCommandAtIndex:(NSUInteger)row];
        [handler insertCommand:cmd atIndex:(NSUInteger)(row - 1)];
        row -= 1;
    } else if (segment == 3) {
        if (row < 0 || row >= (NSInteger)handler.commands.count - 1) { return; }
        UDGuiScriptCommand *cmd = [handler.commands objectAtIndex:(NSUInteger)row];
        [handler removeCommandAtIndex:(NSUInteger)row];
        [handler insertCommand:cmd atIndex:(NSUInteger)(row + 1)];
        row += 1;
    } else {
        return;
    }

    [self finishCommandListMutationForHandler:handler selectedRow:row];
}

// MARK: - NSTableViewDataSource (data)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.eventHandlersTableView) {
        return (NSInteger)[self eventHandlersForSelectedWindow].count;
    }
    if (tableView == self.eventCommandsTableView) {
        return (NSInteger)[self selectedEventHandler].commands.count;
    }
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    if (tableView == self.eventHandlersTableView) {
        NSArray<UDGuiEventHandler *> *handlers = [self eventHandlersForSelectedWindow];
        if (row < 0 || row >= (NSInteger)handlers.count) { return @""; }
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
        if (!handler || row < 0 || row >= (NSInteger)handler.commands.count) { return @""; }
        return [[handler.commands objectAtIndex:(NSUInteger)row] serializedStatement];
    }

    return @"";
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(nullable id)object
   forTableColumn:(nullable NSTableColumn *)tableColumn
              row:(NSInteger)row {
    if (tableView == self.eventHandlersTableView) {
        UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
        NSArray<UDGuiEventHandler *> *handlers = [self eventHandlersForSelectedWindow];
        if (!window || row < 0 || row >= (NSInteger)handlers.count) { return; }

        UDGuiEventHandler *existing = [handlers objectAtIndex:(NSUInteger)row];
        NSString *stringValue = [object isKindOfClass:[NSString class]] ? (NSString *)object : [[object description] copy];

        if ([tableColumn.identifier isEqualToString:@"event"]) {
            UDGuiEventHandlerType type = existing.type;
            if (!UDGuiEventTypeFromKeyword(stringValue ?: @"", &type)) { return; }
            UDGuiEventHandler *replacement = [self newEventHandlerForType:type qualifier:[existing eventQualifier] ?: @""];
            [self copyCommandsFromHandler:existing toHandler:replacement];
            [window replaceEventHandlerAtIndex:(NSUInteger)row withEventHandler:replacement];
        } else if ([tableColumn.identifier isEqualToString:@"qualifier"]) {
            UDGuiEventHandler *replacement = [self newEventHandlerForType:existing.type qualifier:stringValue ?: @""];
            [self copyCommandsFromHandler:existing toHandler:replacement];
            [window replaceEventHandlerAtIndex:(NSUInteger)row withEventHandler:replacement];
        } else {
            return;
        }

        [self.context.ownerDocument notifyGUIModelDidChange];
        [self reloadForWindow:window preserveSelection:NO];
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        return;
    }
    // event-commands table is edited through the command editor controls only
}

- (void)copyCommandsFromHandler:(UDGuiEventHandler *)source toHandler:(UDGuiEventHandler *)target {
    for (UDGuiScriptCommand *cmd in source.commands) {
        [target addCommand:[cmd deepCopy]];
    }
}

// MARK: - NSTableViewDelegate (selection)

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.eventHandlersTableView) {
        if (self.isScriptMode) {
            [self commitTextEdits];
            [self loadScriptForSelectedHandler];
        } else {
            [self.eventCommandsTableView reloadData];
            if ([self selectedEventHandler].commands.count > 0) {
                [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
            } else {
                [self.eventCommandsTableView deselectAll:nil];
            }
            [self syncEventCommandEditorFromSelection];
        }
        return;
    }
    if (notification.object == self.eventCommandsTableView) {
        [self syncEventCommandEditorFromSelection];
    }
}

// MARK: - NSTableViewDataSource (drag & drop)

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pasteboard {
    if ((tableView != self.eventHandlersTableView && tableView != self.eventCommandsTableView) ||
        rowIndexes.count == 0) {
        return NO;
    }
    NSInteger row = (NSInteger)rowIndexes.firstIndex;
    NSString *kind = (tableView == self.eventHandlersTableView) ? @"handlers" : @"commands";
    NSDictionary *payload = @{ @"kind": kind, @"row": @(row) };
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:payload];
    if (!data) { return NO; }
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
    NSDictionary *payload = [self dragPayloadFromDraggingInfo:info];
    if (!payload) { return NSDragOperationNone; }
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
    NSDictionary *payload = [self dragPayloadFromDraggingInfo:info];
    if (!payload) { return NO; }
    NSInteger sourceRow = [payload[@"row"] integerValue];

    if (tableView == self.eventHandlersTableView) {
        if (self.isScriptMode) {
            [self commitTextEdits];
        }
        UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
        NSInteger count = (NSInteger)window.eventHandlers.count;
        if (!window || sourceRow < 0 || sourceRow >= count) { return NO; }
        NSInteger destRow = [self normalizedDestinationRow:row count:count sourceRow:sourceRow];
        if (destRow == NSNotFound) { return NO; }
        UDGuiEventHandler *item = [window.eventHandlers objectAtIndex:(NSUInteger)sourceRow];
        [window removeEventHandlerAtIndex:(NSUInteger)sourceRow];
        [window insertEventHandler:item atIndex:(NSUInteger)destRow];
        [self.context.ownerDocument notifyGUIModelDidChange];
        [self reloadForWindow:window preserveSelection:NO];
        [self.eventHandlersTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)destRow] byExtendingSelection:NO];
        return YES;
    }

    if (tableView == self.eventCommandsTableView) {
        UDGuiEventHandler *handler = [self selectedEventHandler];
        NSInteger count = (NSInteger)handler.commands.count;
        if (!handler || sourceRow < 0 || sourceRow >= count) { return NO; }
        NSInteger destRow = [self normalizedDestinationRow:row count:count sourceRow:sourceRow];
        if (destRow == NSNotFound) { return NO; }
        UDGuiScriptCommand *item = [handler.commands objectAtIndex:(NSUInteger)sourceRow];
        [handler removeCommandAtIndex:(NSUInteger)sourceRow];
        [handler insertCommand:item atIndex:(NSUInteger)destRow];
        [self.context.ownerDocument notifyGUIModelDidChange];
        [self.eventCommandsTableView reloadData];
        [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)destRow] byExtendingSelection:NO];
        [self syncEventCommandEditorFromSelection];
        return YES;
    }

    return NO;
}

// MARK: - Drag helpers

- (nullable NSDictionary *)dragPayloadFromDraggingInfo:(id<NSDraggingInfo>)info {
    NSPasteboard *pasteboard = [info draggingPasteboard];
    NSData *data = [pasteboard dataForType:UDGuiEventsReorderPasteboardType];
    if (!data) { return nil; }
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

@end
