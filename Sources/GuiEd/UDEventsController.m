/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDEventsController.m — Events panel controller for the GUI editor.
 */

#import "UDEventsController.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"
#import "../UDCore/UDGuiEventsProcessingService.h"

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
@synthesize eventIfConditionField = _eventIfConditionField;
@synthesize eventIfBranchesPopup = _eventIfBranchesPopup;
@synthesize modeSegmentedControl = _modeSegmentedControl;
@synthesize scriptScrollView = _scriptScrollView;
@synthesize scriptTextView = _scriptTextView;
@synthesize errorLabel = _errorLabel;

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
    self.errorLabel.textColor = [NSColor redColor];
    self.errorLabel.stringValue = @"";
    self.errorLabel.hidden = YES;

    self.scriptTextView.font = [NSFont userFixedPitchFontOfSize:11.0];
    self.scriptTextView.delegate = self;

    self.scriptScrollView.hidden = YES;
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

    UDGuiEventsProcessingService *service = [[UDGuiEventsProcessingService alloc] initWithCodec:self.context.ownerDocument.codec];
    NSString *text = [service serializeCommands:handler.commands];

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
    UDGuiEventsProcessingService *service = [[UDGuiEventsProcessingService alloc] initWithCodec:self.context.ownerDocument.codec];
    NSArray<UDGuiScriptCommand *> *commands = [service parseCommandsFromText:text error:&error];
    if (commands) {
        self.errorLabel.hidden = YES;
        self.errorLabel.stringValue = @"";

        BOOL changed = ![service areCommands:commands equalToCommands:handler.commands];

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
    UDGuiEventsProcessingService *service = [[UDGuiEventsProcessingService alloc] initWithCodec:self.context.ownerDocument.codec];
    NSArray<UDGuiScriptCommand *> *commands = [service parseCommandsFromText:text error:&error];
    if (commands) {
        self.errorLabel.hidden = YES;
        self.errorLabel.stringValue = @"";

        // Bulk replace to avoid O(n^2) removal operations.
        // We update the underlying model in real-time without registering global undo operations
        // to prevent keypress bloat on the document's undo stack. Local text changes are already
        // managed by the NSTextView's local undo manager, and a consolidated bulk commit with
        // global undo is performed on focus loss (textDidEndEditing:), row change, or mode toggle.
        // If a parsing/compilation error occurs, model updates are prevented and detailed visual error feedback
        // is displayed on the error label instead.
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

- (nullable id)selectedOutlineItem {
    NSInteger row = self.eventCommandsTableView.selectedRow;
    if (row < 0) {
       return nil;
    }
    return [self.eventCommandsTableView itemAtRow:row];
}

- (nullable UDGuiScriptCommand *)selectedEventCommand {
    id item = [self selectedOutlineItem];
    if ([item isKindOfClass:[UDGuiScriptCommand class]]) {
       return (UDGuiScriptCommand *)item;
    }
    return nil;
}

- (void)expandAllOutlineItems {
    UDGuiEventHandler *handler = [self selectedEventHandler];
    if (!handler) { return; }
    for (UDGuiScriptCommand *cmd in handler.commands) {
        [self.eventCommandsTableView expandItem:cmd expandChildren:YES];
    }
}

- (nullable id)parentForItem:(id)item {
    if (!item) {
       return nil;
    }
    UDGuiEventHandler *handler = [self selectedEventHandler];
    if (!handler) {
       return nil;
    }
    return [self findParentOfItem:item inCommands:handler.commands currentParent:nil];
}

- (nullable id)findParentOfItem:(id)item inCommands:(NSArray<UDGuiScriptCommand *> *)commands currentParent:(nullable id)currentParent {
    for (UDGuiScriptCommand *cmd in commands) {
       if (cmd == item) {
           return currentParent;
        }
       if ([cmd isKindOfClass:[UDGuiIfCommand class]]) {
           UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)cmd;
           for (UDGuiIfBranch *branch in ifCmd.branches) {
               if (branch == item) {
                   return ifCmd;
               }
               id found = [self findParentOfItem:item inCommands:branch.commands currentParent:branch];
               if (found) {
                   return found;
               }
           }
       }
    }
    return nil;
}

- (NSArray<UDGuiScriptCommand *> *)arrayByReplacingItem:(id)target withItem:(nullable id)replacement inCommands:(NSArray<UDGuiScriptCommand *> *)commands {
    NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray array];
    for (UDGuiScriptCommand *cmd in commands) {
       if (cmd == target) {
           if (replacement) {
               [newCommands addObject:replacement];
           }
       } else if ([cmd isKindOfClass:[UDGuiIfCommand class]]) {
           UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)cmd;
           NSMutableArray<UDGuiIfBranch *> *newBranches = [NSMutableArray array];
           for (UDGuiIfBranch *branch in ifCmd.branches) {
               if (branch == target) {
                   if (replacement) {
                       [newBranches addObject:replacement];
                   }
               } else {
                   NSArray<UDGuiScriptCommand *> *branchCommands = [self arrayByReplacingItem:target withItem:replacement inCommands:branch.commands];
                   [newBranches addObject:[[UDGuiIfBranch alloc] initWithCondition:branch.condition commands:branchCommands]];
               }
           }
           [newCommands addObject:[[UDGuiIfCommand alloc] initWithBranches:newBranches]];
       } else {
           [newCommands addObject:cmd];
       }
    }
    return newCommands;
}

- (NSArray<UDGuiScriptCommand *> *)arrayByInsertingItem:(UDGuiScriptCommand *)newItem afterItem:(id)target inCommands:(NSArray<UDGuiScriptCommand *> *)commands {
    NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray array];
    for (UDGuiScriptCommand *cmd in commands) {
        if ([cmd isKindOfClass:[UDGuiIfCommand class]]) {
            UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)cmd;
            NSMutableArray<UDGuiIfBranch *> *newBranches = [NSMutableArray array];
            for (UDGuiIfBranch *branch in ifCmd.branches) {
                if (branch == target) {
                    NSMutableArray<UDGuiScriptCommand *> *branchCommands = [NSMutableArray arrayWithArray:branch.commands];
                    [branchCommands insertObject:newItem atIndex:0];
                    [newBranches addObject:[[UDGuiIfBranch alloc] initWithCondition:branch.condition commands:branchCommands]];
                } else {
                    NSArray<UDGuiScriptCommand *> *branchCommands = [self arrayByInsertingItem:newItem afterItem:target inCommands:branch.commands];
                    [newBranches addObject:[[UDGuiIfBranch alloc] initWithCondition:branch.condition commands:branchCommands]];
                }
            }
            [newCommands addObject:[[UDGuiIfCommand alloc] initWithBranches:newBranches]];
        } else {
            [newCommands addObject:cmd];
        }
        if (cmd == target) {
            [newCommands addObject:newItem];
        }
    }
    return newCommands;
}

- (NSArray<UDGuiScriptCommand *> *)arrayByAddingItem:(UDGuiScriptCommand *)newItem toCommands:(NSArray<UDGuiScriptCommand *> *)commands {
    NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray arrayWithArray:commands];
    [newCommands addObject:newItem];
    return newCommands;
}

- (NSArray<UDGuiScriptCommand *> *)arrayByRemovingItem:(id)item inCommands:(NSArray<UDGuiScriptCommand *> *)commands {
    NSUInteger index = [commands indexOfObject:item];
    if (index != NSNotFound) {
       NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray arrayWithArray:commands];
       [newCommands removeObjectAtIndex:index];
       return newCommands;
    }
    
    NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray array];
    for (UDGuiScriptCommand *cmd in commands) {
       if ([cmd isKindOfClass:[UDGuiIfCommand class]]) {
           UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)cmd;
           NSMutableArray<UDGuiIfBranch *> *newBranches = [NSMutableArray array];
           for (UDGuiIfBranch *branch in ifCmd.branches) {
               NSArray<UDGuiScriptCommand *> *removedBranchCommands = [self arrayByRemovingItem:item inCommands:branch.commands];
               [newBranches addObject:[[UDGuiIfBranch alloc] initWithCondition:branch.condition commands:removedBranchCommands]];
           }
           [newCommands addObject:[[UDGuiIfCommand alloc] initWithBranches:newBranches]];
       } else {
           [newCommands addObject:cmd];
       }
    }
    return newCommands;
}

- (NSArray<UDGuiScriptCommand *> *)arrayByMovingItem:(id)item direction:(NSInteger)direction inCommands:(NSArray<UDGuiScriptCommand *> *)commands {
    NSUInteger index = [commands indexOfObject:item];
    if (index != NSNotFound) {
       NSInteger targetIndex = (NSInteger)index + direction;
       if (targetIndex >= 0 && targetIndex < (NSInteger)commands.count) {
           NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray arrayWithArray:commands];
           [newCommands removeObjectAtIndex:index];
           [newCommands insertObject:item atIndex:(NSUInteger)targetIndex];
           return newCommands;
       }
       return commands;
    }
    
    NSMutableArray<UDGuiScriptCommand *> *newCommands = [NSMutableArray array];
    for (UDGuiScriptCommand *cmd in commands) {
       if ([cmd isKindOfClass:[UDGuiIfCommand class]]) {
           UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)cmd;
           NSMutableArray<UDGuiIfBranch *> *newBranches = [NSMutableArray array];
           for (UDGuiIfBranch *branch in ifCmd.branches) {
               NSArray<UDGuiScriptCommand *> *movedBranchCommands = [self arrayByMovingItem:item direction:direction inCommands:branch.commands];
               [newBranches addObject:[[UDGuiIfBranch alloc] initWithCondition:branch.condition commands:movedBranchCommands]];
           }
           [newCommands addObject:[[UDGuiIfCommand alloc] initWithBranches:newBranches]];
       } else {
           [newCommands addObject:cmd];
       }
    }
    return newCommands;
}

- (nullable UDGuiExpression *)parseExpressionText:(NSString *)text {
    if (text.length == 0) {
       return nil;
    }
    NSString *wrapped = [NSString stringWithFormat:@"if ( %@ ) { }", text];
    NSArray<UDGuiScriptCommand *> *commands = [self.context.ownerDocument.codec scriptCommandsFromBlockValue:wrapped];
    if (commands.count > 0 && [commands[0] isKindOfClass:[UDGuiIfCommand class]]) {
       UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)commands[0];
       if (ifCmd.branches.count > 0) {
           return ifCmd.branches[0].condition;
       }
    }
    return nil;
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
       [self expandAllOutlineItems];
       UDGuiEventHandler *handler = [self selectedEventHandler];
       if (handler.commands.count > 0) {
           [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
       } else {
           [self.eventCommandsTableView deselectAll:nil];
       }
       [self syncEventCommandEditorFromSelection];
    }
}

- (void)finishCommandListMutationForHandler:(UDGuiEventHandler *)handler selectedItem:(nullable id)item {
    [self.context.ownerDocument notifyGUIModelDidChange];
    [self.eventCommandsTableView reloadData];
    [self expandAllOutlineItems];
    if (item) {
       NSInteger row = [self.eventCommandsTableView rowForItem:item];
       if (row >= 0) {
           [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
       } else {
           [self.eventCommandsTableView deselectAll:nil];
       }
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
    if ([command isKindOfClass:[UDGuiIfCommand class]]) {
       [self populateEditorForIfCommand:(UDGuiIfCommand *)command]; return;
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

- (void)populateEditorForIfCommand:(UDGuiIfCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"if"];
    
    [self.eventIfBranchesPopup removeAllItems];
    for (NSUInteger idx = 0; idx < command.branches.count; idx++) {
       UDGuiIfBranch *branch = [command.branches objectAtIndex:idx];
       NSString *title;
       if (idx == 0) {
           title = @"if";
       } else if (branch.condition) {
           title = [NSString stringWithFormat:@"else if ( %@ )", branch.condition];
       } else {
           title = @"else";
       }
       [self.eventIfBranchesPopup addItemWithTitle:title];
    }
    
    if (command.branches.count > 0) {
       [self.eventIfBranchesPopup selectItemAtIndex:0];
    }
    
    [self syncIfConditionFieldFromSelectedBranch];
}

- (void)syncIfConditionFieldFromSelectedBranch {
    id item = [self selectedOutlineItem];
    UDGuiIfCommand *ifCmd = nil;
    if ([item isKindOfClass:[UDGuiIfCommand class]]) {
       ifCmd = (UDGuiIfCommand *)item;
    } else if ([item isKindOfClass:[UDGuiIfBranch class]]) {
       id parent = [self parentForItem:item];
       if ([parent isKindOfClass:[UDGuiIfCommand class]]) {
           ifCmd = (UDGuiIfCommand *)parent;
       }
    }
    
    if (!ifCmd) {
       self.eventIfConditionField.stringValue = @"";
       return;
    }
    
    NSInteger selectedBranchIndex = self.eventIfBranchesPopup.indexOfSelectedItem;
    if (selectedBranchIndex >= 0 && selectedBranchIndex < (NSInteger)ifCmd.branches.count) {
       UDGuiIfBranch *branch = [ifCmd.branches objectAtIndex:(NSUInteger)selectedBranchIndex];
       if (branch.condition) {
           self.eventIfConditionField.stringValue = [self.context.ownerDocument.codec serializeExpression:branch.condition] ?: @"";
       } else {
           self.eventIfConditionField.stringValue = @"";
       }
    } else {
       self.eventIfConditionField.stringValue = @"";
    }
}

- (IBAction)eventIfBranchesPopupChanged:(id)sender {
    (void)sender;
    [self syncIfConditionFieldFromSelectedBranch];
}

- (void)populateEditorForFallbackCommand:(UDGuiScriptCommand *)command {
    [self selectEventCommandEditorTabIdentifier:@"fallback"];
    self.eventFallbackArgumentsField.stringValue = command.arguments ?: @"";
}

- (UDGuiScriptCommand *)eventCommandFromEditorState {
    NSString *keyword = self.eventCommandTypePopup.selectedItem.title ?: @"";
    if ([keyword isEqualToString:@"if"]) {
       UDGuiExpression *defaultCond = [self parseExpressionText:@"1"];
       if (!defaultCond) {
           defaultCond = [[UDGuiNumberLiteralExpression alloc] initWithValue:@"1"];
       }
       UDGuiIfBranch *thenBranch = [[UDGuiIfBranch alloc] initWithCondition:defaultCond commands:@[]];
       UDGuiIfBranch *elseBranch = [[UDGuiIfBranch alloc] initWithCondition:nil commands:@[]];
       return [[UDGuiIfCommand alloc] initWithBranches:@[thenBranch, elseBranch]];
    }
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
    id item = [self selectedOutlineItem];
    if (!handler || !item) { return; }

    UDGuiIfCommand *ifCmd = nil;
    if ([item isKindOfClass:[UDGuiIfCommand class]]) {
       ifCmd = (UDGuiIfCommand *)item;
    } else if ([item isKindOfClass:[UDGuiIfBranch class]]) {
       id parent = [self parentForItem:item];
       if ([parent isKindOfClass:[UDGuiIfCommand class]]) {
           ifCmd = (UDGuiIfCommand *)parent;
       }
    }

    BOOL isCommandTypePopup = (sender == self.eventCommandTypePopup);
    NSArray<UDGuiScriptCommand *> *newCommands = nil;
    id newItemToSelect = nil;

    if (ifCmd && !isCommandTypePopup) {
       NSInteger selectedBranchIndex = self.eventIfBranchesPopup.indexOfSelectedItem;
       if (selectedBranchIndex >= 0 && selectedBranchIndex < (NSInteger)ifCmd.branches.count) {
           UDGuiIfBranch *oldBranch = [ifCmd.branches objectAtIndex:(NSUInteger)selectedBranchIndex];
           NSString *conditionText = self.eventIfConditionField.stringValue ?: @"";
           UDGuiExpression *newCondition = [self parseExpressionText:conditionText];
           if (!newCondition && selectedBranchIndex < (NSInteger)ifCmd.branches.count - 1) {
               newCondition = [self parseExpressionText:@"1"];
               if (!newCondition) {
                   newCondition = [[UDGuiNumberLiteralExpression alloc] initWithValue:@"1"];
               }
           }
           UDGuiIfBranch *newBranch = [[UDGuiIfBranch alloc] initWithCondition:newCondition commands:oldBranch.commands];
            
           NSMutableArray<UDGuiIfBranch *> *newBranches = [NSMutableArray arrayWithArray:ifCmd.branches];
           [newBranches replaceObjectAtIndex:(NSUInteger)selectedBranchIndex withObject:newBranch];
           UDGuiIfCommand *newIfCmd = [[UDGuiIfCommand alloc] initWithBranches:newBranches];
            
           newCommands = [self arrayByReplacingItem:ifCmd withItem:newIfCmd inCommands:handler.commands];
           newItemToSelect = newIfCmd;
       }
    } else {
       NSInteger row = self.eventCommandsTableView.selectedRow;
       if (row >= 0) {
           UDGuiScriptCommand *oldCmd = [self.eventCommandsTableView itemAtRow:row];
           if ([oldCmd isKindOfClass:[UDGuiScriptCommand class]]) {
               UDGuiScriptCommand *newCmd = [self eventCommandFromEditorState];
               newCommands = [self arrayByReplacingItem:oldCmd withItem:newCmd inCommands:handler.commands];
               newItemToSelect = newCmd;
           }
       }
    }

    if (newCommands) {
        [handler replaceCommandsWithArray:newCommands];
        [self finishCommandListMutationForHandler:handler selectedItem:newItemToSelect];
    }
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

    id item = [self selectedOutlineItem];
    id targetItem = nil;

    if (segment == 0) {
       UDGuiScriptCommand *newCmd = [[UDGuiScriptCommand alloc] initWithKeyword:@"set" arguments:@"notime 0"];
       NSArray<UDGuiScriptCommand *> *newCommands;
       if (!item) {
           newCommands = [self arrayByAddingItem:newCmd toCommands:handler.commands];
       } else {
           newCommands = [self arrayByInsertingItem:newCmd afterItem:item inCommands:handler.commands];
       }
       [handler replaceCommandsWithArray:newCommands];
       targetItem = newCmd;
    } else if (segment == 1) {
       if (!item) { return; }
       NSArray<UDGuiScriptCommand *> *newCommands = [self arrayByRemovingItem:item inCommands:handler.commands];
       [handler replaceCommandsWithArray:newCommands];
       targetItem = nil;
    } else if (segment == 2) {
       if (!item) { return; }
       NSArray<UDGuiScriptCommand *> *newCommands = [self arrayByMovingItem:item direction:-1 inCommands:handler.commands];
       [handler replaceCommandsWithArray:newCommands];
       targetItem = item;
    } else if (segment == 3) {
       if (!item) { return; }
       NSArray<UDGuiScriptCommand *> *newCommands = [self arrayByMovingItem:item direction:1 inCommands:handler.commands];
       [handler replaceCommandsWithArray:newCommands];
       targetItem = item;
    } else {
       return;
    }

    [self finishCommandListMutationForHandler:handler selectedItem:targetItem];
}

// MARK: - NSTableViewDataSource (data)

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.eventHandlersTableView) {
       return (NSInteger)[self eventHandlersForSelectedWindow].count;
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
           [self expandAllOutlineItems];
           if ([self selectedEventHandler].commands.count > 0) {
               [self.eventCommandsTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
           } else {
               [self.eventCommandsTableView deselectAll:nil];
           }
           [self syncEventCommandEditorFromSelection];
       }
    }
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (notification.object == self.eventCommandsTableView) {
       [self syncEventCommandEditorFromSelection];
    }
}

// MARK: - NSTableViewDataSource (drag & drop)

- (BOOL)tableView:(NSTableView *)tableView
writeRowsWithIndexes:(NSIndexSet *)rowIndexes
     toPasteboard:(NSPasteboard *)pasteboard {
    if (tableView != self.eventHandlersTableView || rowIndexes.count == 0) {
       return NO;
    }
    NSInteger row = (NSInteger)rowIndexes.firstIndex;
    NSDictionary *payload = @{ @"kind": @"handlers", @"row": @(row) };
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
    if (tableView != self.eventHandlersTableView) {
       return NSDragOperationNone;
    }
    if (dropOperation != NSTableViewDropAbove) {
       [tableView setDropRow:row dropOperation:NSTableViewDropAbove];
    }
    NSDictionary *payload = [self dragPayloadFromDraggingInfo:info];
    if (!payload) { return NSDragOperationNone; }
    NSString *kind = payload[@"kind"];
    if (![kind isEqualToString:@"handlers"]) {
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

// MARK: - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(nullable id)item {
    if (!item) {
       UDGuiEventHandler *handler = [self selectedEventHandler];
       return (NSInteger)handler.commands.count;
    }
    
    if ([item isKindOfClass:[UDGuiIfCommand class]]) {
       return (NSInteger)((UDGuiIfCommand *)item).branches.count;
    }
    
    if ([item isKindOfClass:[UDGuiIfBranch class]]) {
       return (NSInteger)((UDGuiIfBranch *)item).commands.count;
    }
    
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(nullable id)item {
    if (!item) {
       UDGuiEventHandler *handler = [self selectedEventHandler];
       return [handler.commands objectAtIndex:(NSUInteger)index];
    }
    
    if ([item isKindOfClass:[UDGuiIfCommand class]]) {
       return [((UDGuiIfCommand *)item).branches objectAtIndex:(NSUInteger)index];
    }
    
    if ([item isKindOfClass:[UDGuiIfBranch class]]) {
       return [((UDGuiIfBranch *)item).commands objectAtIndex:(NSUInteger)index];
    }
    
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if ([item isKindOfClass:[UDGuiIfCommand class]]) {
       return ((UDGuiIfCommand *)item).branches.count > 0;
    }
    if ([item isKindOfClass:[UDGuiIfBranch class]]) {
       return ((UDGuiIfBranch *)item).commands.count > 0;
    }
    return NO;
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(nullable NSTableColumn *)tableColumn byItem:(nullable id)item {
    if ([item isKindOfClass:[UDGuiIfCommand class]]) {
       UDGuiIfCommand *ifCmd = (UDGuiIfCommand *)item;
       if (ifCmd.branches.count > 0) {
           UDGuiIfBranch *firstBranch = [ifCmd.branches objectAtIndex:0];
           NSString *condStr = firstBranch.condition ? [self.context.ownerDocument.codec serializeExpression:firstBranch.condition] : @"<invalid>";
           return [NSString stringWithFormat:@"if ( %@ )", condStr];
       }
       return @"if/else block";
    }
    
    if ([item isKindOfClass:[UDGuiIfBranch class]]) {
       UDGuiIfBranch *branch = (UDGuiIfBranch *)item;
       id parent = [self parentForItem:branch];
       if ([parent isKindOfClass:[UDGuiIfCommand class]]) {
           UDGuiIfCommand *parentIf = (UDGuiIfCommand *)parent;
           NSUInteger idx = [parentIf.branches indexOfObject:branch];
           if (idx == 0) {
               NSString *condStr = branch.condition ? [self.context.ownerDocument.codec serializeExpression:branch.condition] : @"<invalid>";
               return [NSString stringWithFormat:@"if ( %@ )", condStr];
           } else if (branch.condition) {
               NSString *condStr = [self.context.ownerDocument.codec serializeExpression:branch.condition];
               return [NSString stringWithFormat:@"else if ( %@ )", condStr];
           } else {
               return @"else";
           }
       }
       return @"branch";
    }
    
    if ([item isKindOfClass:[UDGuiScriptCommand class]]) {
       return [self.context.ownerDocument.codec serializeScriptCommand:(UDGuiScriptCommand *)item];
    }
    
    return @"";
}

@end
