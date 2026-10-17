/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGuiScriptsController.m
 */

#import "UDGuiScriptsController.h"
#import "rvGEWorkspace.h"
#import "rvGEWindowWrapper.h"
#import "rvGEScript.h"
#import "idDict.h"
#import "idWindow.h"
#import "idUserInterface.h"
#import "UDReferencePicker.h"
#import "idDeclManager.h"

/// A statement dragged in the outline: its path (indexes down the tree).
static NSPasteboardType const UDGuiStatementPathType = @"org.udquaketools.gui-statement-path";

@implementation UDGuiEventNode
@end

/// An if's else block, as its row under the if.
@interface UDGuiElseRow : NSObject
@property (nonatomic, weak) rvGEScriptStatement *owner;
@end

@implementation UDGuiElseRow
@end

@interface UDGuiScriptsController ()
@property (nonatomic, weak, readwrite, nullable) idWindow *window;
@property (nonatomic, copy, readwrite, nullable) NSString *eventKey;
/// The event's statements, and the text they were read from (or were last
/// written as): a script the same keeps them, and the outline's rows.
@property (nonatomic, strong, nullable) NSMutableArray<rvGEScriptStatement *> *statements;
@property (nonatomic, copy, nullable) NSString *statementsText;
/// The else rows, by their ifs.
@property (nonatomic, strong) NSMapTable<rvGEScriptStatement *, UDGuiElseRow *> *elseRows;
/// The window's events and variables as the tables show them.
@property (nonatomic, copy) NSArray<NSString *> *eventKeys;
@property (nonatomic, copy) NSArray<NSArray<NSString *> *> *variableRows;
@property (nonatomic) BOOL filling;
@property (nonatomic, strong, readwrite, nullable) UDReferencePicker *referencePicker;
@property (nonatomic) NSInteger pickedRow;
@property (nonatomic, strong, readwrite, nullable) UDExpressionEditor *expressionEditor;
/// What the expression editor edits: the condition (-1), or a variable's row.
@property (nonatomic) NSInteger expressionRow;
@end

@implementation UDGuiScriptsController {
    NSArray<NSTextField *> *_labels;
    NSArray<NSTextField *> *_fields;
    NSArray<NSButton *> *_picks;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _elseRows = [NSMapTable weakToStrongObjectsMapTable];
        _eventKeys = @[];
        _variableRows = @[];
    }
    return self;
}

- (void)awakeFromNib {
    [super awakeFromNib];
    [self.statementsOutline registerForDraggedTypes:@[UDGuiStatementPathType]];
    self.eventsTable.target = self;
    self.eventsTable.doubleAction = @selector(openEvent:);
    [self.eventPopUp removeAllItems];
    [self.eventPopUp addItemsWithTitles:[rvGEScript events]];
}

- (NSArray<NSTextField *> *)_labels {
    if (_labels == nil) {
        _labels = @[self.parameterLabel1, self.parameterLabel2, self.parameterLabel3,
                    self.parameterLabel4, self.parameterLabel5, self.parameterLabel6];
        _fields = @[self.parameterField1, self.parameterField2, self.parameterField3,
                    self.parameterField4, self.parameterField5, self.parameterField6];
        _picks = @[self.parameterPick1, self.parameterPick2, self.parameterPick3,
                   self.parameterPick4, self.parameterPick5, self.parameterPick6];
    }
    return _labels;
}

- (NSArray<NSTextField *> *)_fields {
    [self _labels];
    return _fields;
}

- (rvGEWindowWrapper *)_wrapper {
    return self.window ? [rvGEWindowWrapper wrapperOf:self.window] : nil;
}

#pragma mark - What is shown

- (void)showWindow:(idWindow *)window event:(NSString *)key {
    rvGEWindowWrapper *wrapper = window ? [rvGEWindowWrapper wrapperOf:window] : nil;
    if (key != nil && [wrapper.scriptDict getString:key defaultString:nil] == nil) {
        key = nil;      // gone (an undo)
    }
    BOOL same = window == self.window && ((key == nil && self.eventKey == nil) || [key isEqualToString:self.eventKey]);
    self.window = window;
    self.eventKey = key;
    if (!same) self.message.stringValue = @"";
    if (window == nil) {
        [self.pages selectTabViewItemWithIdentifier:@"none"];
        return;
    }
    if (key == nil) {
        [self.pages selectTabViewItemWithIdentifier:@"window"];
        [self _fillWindow];
        return;
    }
    [self.pages selectTabViewItemWithIdentifier:@"event"];
    [self _fillEvent:same];
}

#pragma mark - A window's events and variables

- (void)_fillWindow {
    rvGEWindowWrapper *wrapper = [self _wrapper];
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    for (int i = 0; i < [wrapper.scriptDict numKeyVals]; i++) {
        [keys addObject:[wrapper.scriptDict keyAtIndex:i]];
    }
    self.eventKeys = keys;
    NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
    for (int i = 0; i < [wrapper.variableDict numKeyVals]; i++) {
        // "definefloat\t\"name\"": its kind, its name
        NSString *key = [wrapper.variableDict keyAtIndex:i];
        NSRange tab = [key rangeOfCharacterFromSet:[NSCharacterSet whitespaceCharacterSet]];
        NSString *kind = tab.location == NSNotFound ? key : [key substringToIndex:tab.location];
        NSString *name = tab.location == NSNotFound ? @"" :
            [[key substringFromIndex:NSMaxRange(tab)] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\" \t"]];
        [rows addObject:@[kind, name, [wrapper.variableDict valueAtIndex:i]]];
    }
    self.variableRows = rows;
    [self.eventsTable reloadData];
    [self.variablesTable reloadData];

    // the events it may have: each it has not, and a time or a named event
    NSMenu *menu = self.addEventButton.menu;
    while (menu.numberOfItems > 1) [menu removeItemAtIndex:1];
    for (NSString *event in [rvGEScript events]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:event action:@selector(addEvent:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = event;
        item.toolTip = [rvGEScript helpOfEvent:event];
        [menu addItem:item];
    }
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(addEvent:)) {
        NSString *event = item.representedObject;
        if ([rvGEScript parameterOfKey:[rvGEScript keyOfEvent:event parameter:@"x"]] != nil) return YES;
        return [[self _wrapper].scriptDict getString:event defaultString:nil] == nil;
    }
    if (item.action == @selector(addStatement:)) {
        if ([item.representedObject isEqual:@"else"]) {
            id selected = self.selectedStatement;
            return [selected isKindOfClass:[rvGEScriptStatement class]] && [selected isIf] && [selected elseStatements] == nil;
        }
    }
    return YES;
}

/// The scripts' dict with @a key's script @a text (nil: taken off), in its
/// place; or, @a newKey given, renamed there.
- (idDict *)_scriptsWith:(NSString *)key text:(NSString *)text renamedTo:(NSString *)newKey {
    idDict *from = [self _wrapper].scriptDict;
    idDict *to = [[idDict alloc] init];
    BOOL found = NO;
    for (int i = 0; i < [from numKeyVals]; i++) {
        NSString *k = [from keyAtIndex:i];
        if ([k isEqualToString:key]) {
            found = YES;
            if (text != nil) [to set:newKey ?: k value:text];
        } else {
            [to set:k value:[from valueAtIndex:i]];
        }
    }
    if (!found && text != nil) [to set:newKey ?: key value:text];
    return to;
}

- (BOOL)_applyScripts:(idDict *)scripts variables:(idDict *)variables named:(NSString *)name {
    NSString *why = nil;
    if (![self.design setScripts:scripts variables:variables of:self.window named:name message:&why]) {
        self.message.stringValue = why ?: @"";
        NSBeep();
        return NO;
    }
    self.message.stringValue = @"";
    return YES;
}

/// The event's key not taken: a time 1 s after the last, a name not used.
- (NSString *)_newKeyFor:(NSString *)event {
    idDict *scripts = [self _wrapper].scriptDict;
    if ([event isEqualToString:@"onTime"]) {
        int last = -1000;
        for (int i = 0; i < [scripts numKeyVals]; i++) {
            NSString *key = [scripts keyAtIndex:i];
            if ([[rvGEScript eventOfKey:key] caseInsensitiveCompare:@"onTime"] == NSOrderedSame) {
                last = MAX(last, [rvGEScript parameterOfKey:key].intValue);
            }
        }
        return [rvGEScript keyOfEvent:event parameter:[NSString stringWithFormat:@"%d", last + 1000]];
    }
    if ([event isEqualToString:@"onNamedEvent"]) {
        for (int n = 1; ; n++) {
            NSString *key = [rvGEScript keyOfEvent:event parameter:[NSString stringWithFormat:@"event%d", n]];
            if ([scripts getString:key defaultString:nil] == nil) return key;
        }
    }
    return event;
}

- (IBAction)addEvent:(id)sender {
    NSString *event = [sender representedObject];
    if (event == nil || self.window == nil) return;
    NSString *key = [self _newKeyFor:event];
    if ([[self _wrapper].scriptDict getString:key defaultString:nil] != nil) {
        NSBeep();
        return;
    }
    idDict *scripts = [self _scriptsWith:key text:@"{\n}" renamedTo:nil];
    if ([self _applyScripts:scripts variables:[[self _wrapper].variableDict copy] named:@"Add Event"]) {
        [self _show:self.window event:key];
    }
}

- (IBAction)removeEvent:(id)sender {
    NSInteger row = self.eventsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.eventKeys.count) {
        NSBeep();
        return;
    }
    idDict *scripts = [self _scriptsWith:self.eventKeys[(NSUInteger)row] text:nil renamedTo:nil];
    [self _applyScripts:scripts variables:[[self _wrapper].variableDict copy] named:@"Delete Event"];
}

- (IBAction)openEvent:(id)sender {
    NSInteger row = self.eventsTable.clickedRow >= 0 ? self.eventsTable.clickedRow : self.eventsTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.eventKeys.count) return;
    [self _show:self.window event:self.eventKeys[(NSUInteger)row]];
}

/// The editor told to show @a key's event (its navigator's row).
- (void)_show:(idWindow *)window event:(NSString *)key {
    self.window = window;
    self.eventKey = key;
    id target = self.target;
    if (target != nil && self.action != NULL) {
        [NSApp sendAction:self.action to:target from:self];
    }
}

- (IBAction)addOrRemoveVariable:(id)sender {
    NSInteger segment = [sender respondsToSelector:@selector(selectedSegment)] ? [sender selectedSegment] : 0;
    idDict *variables = [[self _wrapper].variableDict copy];
    if (segment == 0) {
        for (int n = 1; ; n++) {
            NSString *key = [NSString stringWithFormat:@"definefloat\t\"variable%d\"", n];
            if ([variables getString:key defaultString:nil] == nil) {
                [variables set:key value:@"0"];
                break;
            }
        }
        [self _applyScripts:[[self _wrapper].scriptDict copy] variables:variables named:@"Add Variable"];
        return;
    }
    NSInteger row = self.variablesTable.selectedRow;
    if (row < 0 || row >= [variables numKeyVals]) {
        NSBeep();
        return;
    }
    idDict *kept = [[idDict alloc] init];
    for (int i = 0; i < [variables numKeyVals]; i++) {
        if (i != row) [kept set:[variables keyAtIndex:i] value:[variables valueAtIndex:i]];
    }
    [self _applyScripts:[[self _wrapper].scriptDict copy] variables:kept named:@"Delete Variable"];
}

#pragma mark - An event's

/// The event's script read (again, if it is not what was shown), and the
/// controls filled.
- (void)_fillEvent:(BOOL)same {
    NSString *text = [[self _wrapper].scriptDict getString:self.eventKey defaultString:@""];
    NSArray<NSNumber *> *path = same ? [self _pathOf:self.selectedStatement] : nil;
    if (self.statements == nil || !same || ![text isEqualToString:self.statementsText]) {
        NSString *why = nil;
        self.statements = [rvGEScript statementsFromText:text message:&why];
        self.statementsText = text;
        if (self.statements == nil) {
            self.message.stringValue = [NSString stringWithFormat:@"%@ does not read as statements: %@ (edit it in the source)", self.eventKey, why];
        }
    }
    self.filling = YES;
    NSString *event = [rvGEScript eventOfKey:self.eventKey];
    NSString *parameter = [rvGEScript parameterOfKey:self.eventKey];
    [self.eventPopUp selectItemWithTitle:event];
    BOOL timed = [event caseInsensitiveCompare:@"onTime"] == NSOrderedSame;
    BOOL named = [event caseInsensitiveCompare:@"onNamedEvent"] == NSOrderedSame;
    self.eventParameterLabel.stringValue = timed ? @"Time:" : named ? @"Name:" : @"";
    self.eventParameterField.stringValue = parameter ?: @"";
    self.eventParameterField.hidden = !(timed || named);
    self.eventParameterLabel.hidden = !(timed || named);
    self.eventHelp.stringValue = [rvGEScript helpOfEvent:event];

    NSMenu *menu = self.addStatementButton.menu;
    while (menu.numberOfItems > 1) [menu removeItemAtIndex:1];
    for (NSString *command in [[rvGEScript commands] arrayByAddingObject:@"else"]) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:command action:@selector(addStatement:) keyEquivalent:@""];
        item.target = self;
        item.representedObject = command;
        item.toolTip = [command isEqualToString:@"else"] ? @"An else block for the chosen if." : [rvGEScript helpOf:command];
        [menu addItem:item];
    }

    [self.statementsOutline reloadData];
    [self _expandAll];
    id selected = path != nil ? [self _itemAtPath:path] : nil;
    NSInteger row = selected != nil ? [self.statementsOutline rowForItem:selected] : -1;
    if (row >= 0) {
        [self.statementsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
    } else {
        [self.statementsOutline deselectAll:nil];
    }
    self.filling = NO;
    [self _fillStatement];
}

/// The statements written as the event's script, one edit named @a name.
- (BOOL)_applyStatements:(NSString *)name {
    NSString *text = [rvGEScript textFromStatements:self.statements];
    NSString *was = self.statementsText;
    self.statementsText = text;
    idDict *scripts = [self _scriptsWith:self.eventKey text:text renamedTo:nil];
    if (![self _applyScripts:scripts variables:[[self _wrapper].variableDict copy] named:name]) {
        // as it was
        self.statementsText = was;
        self.statements = [rvGEScript statementsFromText:was message:NULL];
        [self _fillEvent:NO];
        return NO;
    }
    return YES;
}

/// The event or its parameter changed: the script renamed, in its place.
- (IBAction)changeEvent:(id)sender {
    if (self.filling || self.eventKey == nil) return;
    NSString *event = self.eventPopUp.titleOfSelectedItem;
    BOOL timed = [event caseInsensitiveCompare:@"onTime"] == NSOrderedSame;
    BOOL named = [event caseInsensitiveCompare:@"onNamedEvent"] == NSOrderedSame;
    NSString *parameter = [self.eventParameterField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    if (timed && parameter.intValue <= 0 && ![parameter isEqualToString:@"0"]) parameter = @"0";
    if (named && parameter.length == 0) parameter = @"event1";
    NSString *key = [rvGEScript keyOfEvent:event parameter:(timed || named) ? parameter : nil];
    if ([key isEqualToString:self.eventKey]) return;
    if ([[self _wrapper].scriptDict getString:key defaultString:nil] != nil) {
        self.message.stringValue = [NSString stringWithFormat:@"The window has %@ already", key];
        NSBeep();
        [self _fillEvent:YES];
        return;
    }
    NSString *text = [[self _wrapper].scriptDict getString:self.eventKey defaultString:@"{\n}"];
    idDict *scripts = [self _scriptsWith:self.eventKey text:text renamedTo:key];
    if ([self _applyScripts:scripts variables:[[self _wrapper].variableDict copy] named:@"Event Change"]) {
        [self _show:self.window event:key];
    }
}

#pragma mark - The statements' rows (an outline)

- (NSMutableArray<rvGEScriptStatement *> *)_listOf:(id)item {
    if (item == nil) return self.statements;
    if ([item isKindOfClass:[UDGuiElseRow class]]) return [(UDGuiElseRow *)item owner].elseStatements;
    return [(rvGEScriptStatement *)item statements];
}

- (UDGuiElseRow *)_elseRowOf:(rvGEScriptStatement *)statement {
    UDGuiElseRow *row = [self.elseRows objectForKey:statement];
    if (row == nil) {
        row = [[UDGuiElseRow alloc] init];
        row.owner = statement;
        [self.elseRows setObject:row forKey:statement];
    }
    return row;
}

/// An if's rows: its statements, then its else.
- (NSArray *)_childrenOf:(id)item {
    if (item == nil) return self.statements ?: @[];
    if ([item isKindOfClass:[UDGuiElseRow class]]) return [(UDGuiElseRow *)item owner].elseStatements ?: @[];
    rvGEScriptStatement *statement = item;
    if (!statement.isIf) return @[];
    NSMutableArray *children = [statement.statements mutableCopy];
    if (statement.elseStatements != nil) [children addObject:[self _elseRowOf:statement]];
    return children;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    return (NSInteger)[self _childrenOf:item].count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    return [self _childrenOf:item][(NSUInteger)index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[UDGuiElseRow class]] || [(rvGEScriptStatement *)item isIf];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)column byItem:(id)item {
    if ([item isKindOfClass:[UDGuiElseRow class]]) return @"else";
    return [(rvGEScriptStatement *)item summary];
}

/// Every if and else open (GNUstep does not take nil for the root).
- (void)_expandAll {
    for (id item in [self _childrenOf:nil]) {
        [self.statementsOutline expandItem:item expandChildren:YES];
    }
}

/// The path of @a item (its index down each level), and back.
- (NSArray<NSNumber *> *)_pathOf:(id)item {
    if (item == nil) return nil;
    NSMutableArray<NSNumber *> *path = [NSMutableArray array];
    for (id at = item; at != nil; at = [self.statementsOutline parentForItem:at]) {
        id parent = [self.statementsOutline parentForItem:at];
        NSUInteger index = [[self _childrenOf:parent] indexOfObjectIdenticalTo:at];
        if (index == NSNotFound) return nil;
        [path insertObject:@(index) atIndex:0];
    }
    return path;
}

- (id)_itemAtPath:(NSArray<NSNumber *> *)path {
    id item = nil;
    for (NSNumber *index in path) {
        NSArray *children = [self _childrenOf:item];
        if (index.unsignedIntegerValue >= children.count) return nil;
        item = children[index.unsignedIntegerValue];
    }
    return item;
}

- (id)selectedStatement {
    NSInteger row = self.statementsOutline.selectedRow;
    return row >= 0 ? [self.statementsOutline itemAtRow:row] : nil;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    if (self.filling) return;
    [self _fillStatement];
}

/// Where a new statement goes: into the chosen if (or else) first, after
/// the chosen statement, or last.
- (void)_insertionFor:(NSMutableArray **)list index:(NSUInteger *)index parent:(id *)parent {
    id selected = self.selectedStatement;
    if (selected == nil) {
        *list = self.statements;
        *index = self.statements.count;
        *parent = nil;
    } else if ([selected isKindOfClass:[UDGuiElseRow class]] || [(rvGEScriptStatement *)selected isIf]) {
        *list = [self _listOf:selected];
        *index = 0;
        *parent = selected;
    } else {
        id up = [self.statementsOutline parentForItem:selected];
        *list = [self _listOf:up];
        *index = [*list indexOfObjectIdenticalTo:selected] + 1;
        *parent = up;
    }
}

- (IBAction)addStatement:(id)sender {
    NSString *command = [sender representedObject];
    if (command == nil || self.statements == nil) return;
    id added;
    if ([command isEqualToString:@"else"]) {
        rvGEScriptStatement *test = self.selectedStatement;
        if (![test isKindOfClass:[rvGEScriptStatement class]] || !test.isIf || test.elseStatements != nil) {
            NSBeep();
            return;
        }
        test.elseStatements = [NSMutableArray array];
        added = [self _elseRowOf:test];
    } else {
        NSMutableArray *list = nil;
        NSUInteger index = 0;
        id parent = nil;
        [self _insertionFor:&list index:&index parent:&parent];
        rvGEScriptStatement *statement = [rvGEScriptStatement statementWithCommand:command];
        [list insertObject:statement atIndex:index];
        added = statement;
    }
    if ([self _applyStatements:@"Add Statement"]) {
        [self _select:added];
    }
}

- (IBAction)removeStatement:(id)sender {
    id selected = self.selectedStatement;
    if (selected == nil) {
        NSBeep();
        return;
    }
    if ([selected isKindOfClass:[UDGuiElseRow class]]) {
        [(UDGuiElseRow *)selected owner].elseStatements = nil;
    } else {
        [[self _listOf:[self.statementsOutline parentForItem:selected]] removeObjectIdenticalTo:selected];
    }
    [self _applyStatements:@"Delete Statement"];
    [self.statementsOutline deselectAll:nil];
    [self _fillStatement];
}

/// The outline as the statements are, @a item chosen.
- (void)_select:(id)item {
    self.filling = YES;
    [self.statementsOutline reloadData];
    [self _expandAll];
    NSInteger row = [self.statementsOutline rowForItem:item];
    if (row >= 0) {
        [self.statementsOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row] byExtendingSelection:NO];
        [self.statementsOutline scrollRowToVisible:row];
    }
    self.filling = NO;
    [self _fillStatement];
}

#pragma mark - Dragging a statement to another place

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pasteboard {
    if (items.count != 1 || ![items[0] isKindOfClass:[rvGEScriptStatement class]]) return NO;
    NSArray<NSNumber *> *path = [self _pathOf:items[0]];
    [pasteboard declareTypes:@[UDGuiStatementPathType] owner:nil];
    [pasteboard setString:[[path valueForKey:@"stringValue"] componentsJoinedByString:@"."] forType:UDGuiStatementPathType];
    return YES;
}

- (id)_draggedItem:(id<NSDraggingInfo>)info {
    NSString *text = [[info draggingPasteboard] stringForType:UDGuiStatementPathType];
    if (text.length == 0) return nil;
    NSMutableArray<NSNumber *> *path = [NSMutableArray array];
    for (NSString *part in [text componentsSeparatedByString:@"."]) [path addObject:@(part.integerValue)];
    return [self _itemAtPath:path];
}

/// Whether @a item is @a statement or within it.
- (BOOL)_item:(id)item isIn:(id)statement {
    for (id at = item; at != nil; at = [self.statementsOutline parentForItem:at]) {
        if (at == statement) return YES;
        if ([at isKindOfClass:[UDGuiElseRow class]] && [(UDGuiElseRow *)at owner] == statement) return YES;
    }
    return NO;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id<NSDraggingInfo>)info proposedItem:(id)item
            proposedChildIndex:(NSInteger)index {
    id dragged = [self _draggedItem:info];
    if (dragged == nil || [info draggingSource] != outlineView) return NSDragOperationNone;
    if (item != nil && ![item isKindOfClass:[UDGuiElseRow class]] && ![(rvGEScriptStatement *)item isIf]) return NSDragOperationNone;
    if (item != nil && [self _item:item isIn:dragged]) return NSDragOperationNone;
    if (index == NSOutlineViewDropOnItemIndex) {
        [outlineView setDropItem:item dropChildIndex:0];
    }
    return NSDragOperationMove;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id<NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index {
    id dragged = [self _draggedItem:info];
    return dragged != nil && [self moveStatement:dragged toParent:item index:MAX(index, 0)];
}

- (BOOL)moveStatement:(id)statement toParent:(id)parent index:(NSInteger)index {
    if (![statement isKindOfClass:[rvGEScriptStatement class]] || (parent != nil && [self _item:parent isIn:statement])) return NO;
    NSMutableArray *from = [self _listOf:[self.statementsOutline parentForItem:statement]];
    NSMutableArray *to = [self _listOf:parent];
    if (from == nil || to == nil) return NO;
    NSUInteger at = [from indexOfObjectIdenticalTo:statement];
    if (at == NSNotFound) return NO;
    NSUInteger into = (NSUInteger)MIN(MAX(index, 0), (NSInteger)to.count);
    if (from == to && (into == at || into == at + 1)) return NO;
    [from removeObjectAtIndex:at];
    if (from == to && into > at) into--;
    [to insertObject:statement atIndex:into];
    if ([self _applyStatements:@"Move Statement"]) {
        [self _select:statement];
        return YES;
    }
    return NO;
}

#pragma mark - The chosen statement's parameters

- (void)_fillStatement {
    id selected = self.selectedStatement;
    NSArray<NSTextField *> *labels = [self _labels];
    NSArray<NSTextField *> *fields = [self _fields];
    rvGEScriptStatement *statement = [selected isKindOfClass:[rvGEScriptStatement class]] ? selected : nil;
    BOOL isIf = statement.isIf;
    self.statementHelp.stringValue = statement ? [rvGEScript helpOf:statement.command]
        : [selected isKindOfClass:[UDGuiElseRow class]] ? @"Run when the if's condition is 0." : @"Choose a statement to edit it.";
    self.conditionLabel.hidden = !isIf;
    self.conditionField.hidden = !isIf;
    self.conditionExpression.hidden = !isIf;
    self.conditionField.stringValue = isIf ? statement.condition : @"";
    self.conditionField.toolTip = @"An expression: of window variables (Window::name), the GUI's state (\"gui::name\"), time, numbers.";

    NSArray<NSString *> *names = statement && !isIf ? [rvGEScript parameterNamesOf:statement.command] : @[];
    NSArray<NSString *> *values = [self _shownArgumentsOf:statement names:names];
    NSUInteger shown = statement && !isIf ? MIN(MAX(names.count, values.count), labels.count) : 0;
    // set "cmd" takes more: one row more, for the next
    if (statement && [statement.command isEqualToString:@"set"] && [values.firstObject caseInsensitiveCompare:@"cmd"] == NSOrderedSame) {
        shown = MIN(values.count + 1, labels.count);
    }
    for (NSUInteger i = 0; i < labels.count; i++) {
        BOOL on = i < shown;
        labels[i].hidden = !on;
        fields[i].hidden = !on;
        _picks[i].hidden = YES;
        if (!on) continue;
        labels[i].stringValue = [NSString stringWithFormat:@"%@:", i < names.count ? names[i] : [NSString stringWithFormat:@"Value %lu", (unsigned long)i]];
        fields[i].stringValue = i < values.count ? values[i] : @"";
        _picks[i].hidden = [self _pickerKindOf:statement.command parameter:(NSInteger)i] == nil;
        NSString *help = [rvGEScript helpOf:statement.command parameter:(NSInteger)i];
        fields[i].toolTip = help;
        labels[i].toolTip = help;
    }
}

/// The parameters by the rows they show in: resetTime's one is its time
/// (the Time row, the Window one empty).
- (NSArray<NSString *> *)_shownArgumentsOf:(rvGEScriptStatement *)statement names:(NSArray<NSString *> *)names {
    if (statement == nil) return @[];
    if ([statement.command isEqualToString:@"resetTime"] && statement.arguments.count == 1) {
        return @[@"", statement.arguments[0]];
    }
    return statement.arguments;
}

/// A field or the condition edited: the statement as the rows have it.
- (IBAction)statementEdited:(id)sender {
    if (self.filling) return;
    rvGEScriptStatement *statement = [self.selectedStatement isKindOfClass:[rvGEScriptStatement class]] ? self.selectedStatement : nil;
    if (statement == nil) return;
    if (statement.isIf) {
        NSString *condition = [self.conditionField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if ([condition isEqualToString:statement.condition]) return;
        statement.condition = condition.length > 0 ? condition : @"1";
    } else {
        NSMutableArray<NSString *> *arguments = [NSMutableArray array];
        for (NSTextField *field in [self _fields]) {
            if (field.isHidden) break;
            [arguments addObject:field.stringValue];
        }
        // the empty ones it may go without, from the end
        NSInteger least = [rvGEScript minimumParametersOf:statement.command];
        while ((NSInteger)arguments.count > least && arguments.lastObject.length == 0) {
            [arguments removeLastObject];
        }
        if ([statement.command isEqualToString:@"resetTime"] && arguments.count == 2 && arguments[0].length == 0) {
            [arguments removeObjectAtIndex:0];
        }
        if ([arguments isEqualToArray:statement.arguments]) return;
        statement.arguments = arguments;
    }
    if ([self _applyStatements:@"Statement Change"]) {
        [self _select:statement];
    }
}

#pragma mark - The events' and variables' tables

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    if (tableView == self.eventsTable) return (NSInteger)self.eventKeys.count;
    if (tableView == self.variablesTable) return (NSInteger)self.variableRows.count;
    return 0;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView == self.eventsTable) {
        if (row < 0 || row >= (NSInteger)self.eventKeys.count) return nil;
        NSString *key = self.eventKeys[(NSUInteger)row];
        if ([column.identifier isEqualToString:@"event"]) return key;
        NSArray<rvGEScriptStatement *> *statements =
            [rvGEScript statementsFromText:[[self _wrapper].scriptDict getString:key defaultString:@""] message:NULL];
        return [[statements valueForKey:@"summary"] componentsJoinedByString:@" ; "];
    }
    if (row < 0 || row >= (NSInteger)self.variableRows.count) return nil;
    NSUInteger column3 = [column.identifier isEqualToString:@"kind"] ? 0 : [column.identifier isEqualToString:@"name"] ? 1 : 2;
    return self.variableRows[(NSUInteger)row][column3];
}

/// A variable edited: its kind (definefloat, definevec4, float), its name
/// or its value; the variables in their order.
- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
    if (tableView != self.variablesTable || row < 0 || row >= (NSInteger)self.variableRows.count) return;
    NSMutableArray<NSString *> *edited = [self.variableRows[(NSUInteger)row] mutableCopy];
    NSString *text = [[object description] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSUInteger at = [column.identifier isEqualToString:@"kind"] ? 0 : [column.identifier isEqualToString:@"name"] ? 1 : 2;
    if (at == 0 && ![@[@"definefloat", @"definevec4", @"float"] containsObject:text]) {
        self.message.stringValue = @"A variable is definefloat, definevec4 or float";
        NSBeep();
        return;
    }
    if (text.length == 0 || [text isEqualToString:edited[at]]) return;
    edited[at] = text;
    idDict *variables = [[idDict alloc] init];
    for (NSUInteger i = 0; i < self.variableRows.count; i++) {
        NSArray<NSString *> *v = i == (NSUInteger)row ? edited : self.variableRows[i];
        [variables set:[NSString stringWithFormat:@"%@\t\"%@\"", v[0], v[1]] value:v[2]];
    }
    [self _applyScripts:[[self _wrapper].scriptDict copy] variables:variables named:@"Variable Change"];
}

#pragma mark - Pickers

/// What a command's parameter names, for its picker: "window", "variable",
/// "sound", or nil (a value, a time).
- (NSString *)_pickerKindOf:(NSString *)command parameter:(NSInteger)index {
    if (index != 0) return nil;
    if ([command isEqualToString:@"setFocus"] || [command isEqualToString:@"resetTime"]) return @"window";
    if ([command isEqualToString:@"set"] || [command isEqualToString:@"transition"]) return @"variable";
    if ([command isEqualToString:@"localSound"]) return @"sound";
    return nil;
}

/// The GUI's windows, from the desktop down.
- (void)_windowsUnder:(idWindow *)window into:(NSMutableArray<idWindow *> *)windows {
    if (window == nil) return;
    [windows addObject:window];
    rvGEWindowWrapper *wrapper = [rvGEWindowWrapper wrapperOf:window];
    for (int i = 0; i < [wrapper childCount]; i++) {
        [self _windowsUnder:[wrapper childAtIndex:i] into:windows];
    }
}

- (IBAction)pickParameter:(id)sender {
    rvGEScriptStatement *statement = [self.selectedStatement isKindOfClass:[rvGEScriptStatement class]] ? self.selectedStatement : nil;
    NSInteger row = [sender tag] - 1;
    NSString *kind = statement ? [self _pickerKindOf:statement.command parameter:row] : nil;
    NSWindow *window = self.statementsOutline.window;
    if (kind == nil || window == nil || window.attachedSheet != nil) {
        NSBeep();
        return;
    }
    UDReferenceField *field = [UDReferenceField fieldTitled:@"" key:@"" controller:self kind:UDReferenceNames];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    NSMutableArray<idWindow *> *windows = [NSMutableArray array];
    [self _windowsUnder:[self.design.interface getDesktop] into:windows];
    if ([kind isEqualToString:@"sound"]) {
        field.title = @"A sound shader";
        field.kind = UDReferenceDecls;
        field.declType = DECL_SOUND;
    } else if ([kind isEqualToString:@"window"]) {
        field.title = @"A window";
        for (idWindow *w in windows) {
            [names addObject:[w getName]];
            [details addObject:[rvGEWindowWrapper stringFromWindowType:[rvGEWindowWrapper wrapperOf:w].windowType]];
        }
    } else {
        field.title = @"A window's variable";
        [self _variablesOf:windows transition:[statement.command isEqualToString:@"transition"] names:names details:details];
    }
    field.names = names;
    field.details = details;
    NSMutableArray<NSString *> *shownDetails = [NSMutableArray array];
    NSArray<NSString *> *offered = self.workspace != nil ? [UDReferencePicker namesFor:field workspace:self.workspace details:shownDetails] : names;
    self.pickedRow = row;
    self.referencePicker = [[UDReferencePicker alloc] initWithTitle:field.title names:offered
                                                            details:self.workspace != nil ? shownDetails : details
                                                            current:[self _fields][(NSUInteger)row].stringValue];
    [self.referencePicker beginSheetForWindow:window target:self action:@selector(_parameterPicked:)];
}

/// The name in the parameter's field, and the statement as the fields have it.
- (void)_parameterPicked:(UDReferencePicker *)picker {
    NSInteger row = self.pickedRow;
    if (picker.chosenName == nil || row < 0 || row >= (NSInteger)[self _fields].count) return;
    [self _fields][(NSUInteger)row].stringValue = picker.chosenName;
    [self statementEdited:[self _fields][(NSUInteger)row]];
}

/// The windows' variables, as Window::name: the ones every window has
/// that scripts set (or transitions move), and each window's own.
- (void)_variablesOf:(NSArray<idWindow *> *)windows transition:(BOOL)transition
               names:(NSMutableArray<NSString *> *)names details:(NSMutableArray<NSString *> *)details {
    NSArray<NSString *> *common = transition
        ? @[@"rect", @"backcolor", @"forecolor", @"matcolor", @"bordercolor"]
        : @[@"visible", @"text", @"rect", @"backcolor", @"forecolor", @"matcolor", @"bordercolor", @"background", @"textscale", @"noevents"];
    for (idWindow *w in windows) {
        for (NSString *var in common) {
            [names addObject:[NSString stringWithFormat:@"%@::%@", [w getName], var]];
            [details addObject:@"window"];
        }
        idDict *variables = [rvGEWindowWrapper wrapperOf:w].variableDict;
        for (int i = 0; i < [variables numKeyVals]; i++) {
            NSString *key = [variables keyAtIndex:i];
            NSRange quote = [key rangeOfString:@"\""];
            NSString *name = quote.location == NSNotFound ? key :
                [[key substringFromIndex:quote.location] stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]];
            [names addObject:[NSString stringWithFormat:@"%@::%@", [w getName], name]];
            [details addObject:@"variable"];
        }
    }
}

#pragma mark - Expressions

- (IBAction)editCondition:(id)sender {
    rvGEScriptStatement *statement = [self.selectedStatement isKindOfClass:[rvGEScriptStatement class]] ? self.selectedStatement : nil;
    if (statement == nil || !statement.isIf) {
        NSBeep();
        return;
    }
    [self _editExpression:statement.condition titled:@"The if's condition" row:-1];
}

- (IBAction)editVariable:(id)sender {
    NSInteger row = self.variablesTable.selectedRow;
    if (row < 0 || row >= (NSInteger)self.variableRows.count) {
        NSBeep();
        return;
    }
    NSArray<NSString *> *variable = self.variableRows[(NSUInteger)row];
    [self _editExpression:variable[2] titled:[NSString stringWithFormat:@"The value of %@", variable[1]] row:row];
}

/// What a GUI's expression may name: the windows' variables (quoted, as the
/// scripts name them), and the operators.
- (NSArray<UDExpressionCategory *> *)_expressionCategories {
    NSMutableArray<idWindow *> *windows = [NSMutableArray array];
    [self _windowsUnder:[self.design.interface getDesktop] into:windows];
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSMutableArray<NSString *> *details = [NSMutableArray array];
    [self _variablesOf:windows transition:NO names:names details:details];
    NSMutableArray<UDExpressionEntry *> *variables = [NSMutableArray array];
    for (NSUInteger i = 0; i < names.count; i++) {
        [variables addObject:[UDExpressionEntry entryNamed:names[i] insertion:[NSString stringWithFormat:@"\"%@\"", names[i]]
                                                   summary:[NSString stringWithFormat:@"A %@'s value, by its name.", details[i]]]];
    }
    [variables addObject:[UDExpressionEntry entryNamed:@"gui::" insertion:@"\"gui::\"" summary:@"The GUI's state, set by the game (gui::name)."]];
    NSMutableArray<UDExpressionEntry *> *operators = [NSMutableArray array];
    for (NSArray<NSString *> *op in @[@[@"+", @"Adds."], @[@"-", @"Subtracts."], @[@"*", @"Multiplies."], @[@"/", @"Divides."],
                                      @[@"%", @"The remainder."], @[@"==", @"1 when equal, else 0."], @[@"!=", @"1 when not equal."],
                                      @[@">", @"1 when greater."], @[@"<", @"1 when less."], @[@">=", @"1 when greater or equal."],
                                      @[@"<=", @"1 when less or equal."], @[@"&&", @"1 when both are not 0."], @[@"||", @"1 when either is not 0."],
                                      @[@"( )", @"Groups."]]) {
        [operators addObject:[UDExpressionEntry entryNamed:op[0] insertion:[op[0] isEqualToString:@"( )"] ? @"( " : [NSString stringWithFormat:@" %@ ", op[0]]
                                                   summary:op[1]]];
    }
    return @[[UDExpressionCategory categoryNamed:@"Variables" entries:variables],
             [UDExpressionCategory categoryNamed:@"Operators" entries:operators]];
}

- (void)_editExpression:(NSString *)text titled:(NSString *)title row:(NSInteger)row {
    NSWindow *window = self.pages.window;
    if (window == nil || window.attachedSheet != nil) {
        NSBeep();
        return;
    }
    self.expressionRow = row;
    self.expressionEditor = [[UDExpressionEditor alloc] initWithTitle:title text:text categories:[self _expressionCategories]];
    self.expressionEditor.checker = self;
    [self.expressionEditor beginSheetForWindow:window target:self action:@selector(_expressionEdited:)];
}

- (NSString *)expressionEditor:(UDExpressionEditor *)editor problemWith:(NSString *)text {
    return [self.design problemWithExpression:text in:self.window];
}

/// The condition, or the variable's value, as edited.
- (void)_expressionEdited:(UDExpressionEditor *)editor {
    NSString *text = [editor.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (self.expressionRow < 0) {
        self.conditionField.stringValue = text;
        [self statementEdited:self.conditionField];
    } else {
        [self tableView:self.variablesTable setObjectValue:text forTableColumn:[self.variablesTable tableColumnWithIdentifier:@"value"]
                    row:self.expressionRow];
    }
}

@end
