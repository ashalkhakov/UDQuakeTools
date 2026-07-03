/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDVariablesController.m — Variables panel controller for the GUI editor.
 */

#import "UDVariablesController.h"
#import "UDInspectableTableView.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@implementation UDVariablesController

// MARK: - Private helpers

- (NSArray<UDGuiVariableDefinition *> *)variableDefinitionsForWindow:(nullable UDGuiWindowNode *)window {
    return window ? window.variableDefinitions : @[];
}

- (NSArray<UDGuiVariableDefinition *> *)variableDefinitionsForSelectedWindow {
    return [self variableDefinitionsForWindow:self.context.ownerDocument.viewModel.selectedWindow];
}

- (NSString *)defaultVariableNameForType:(UDGuiVariableDefinitionType)type
                                inWindow:(UDGuiWindowNode *)window {
    NSString *prefix = type == UDGuiVariableDefinitionTypeVec4 ? @"vec4Var" : @"floatVar";
    NSSet<NSString *> *existingNames = [NSSet setWithArray:[[self variableDefinitionsForWindow:window] valueForKey:@"name"] ?: @[]];
    for (NSUInteger candidateNumber = 1; candidateNumber < 10000; candidateNumber++) {
        NSString *candidate = [NSString stringWithFormat:@"%@%lu", prefix, (unsigned long)candidateNumber];
        if (![existingNames containsObject:candidate]) {
            return candidate;
        }
    }
    return prefix;
}

- (NSInteger)normalizedRow:(NSInteger)row forCount:(NSInteger)count {
    if (count <= 0) { return NSNotFound; }
    if (row == NSNotFound || row < 0) { return 0; }
    return MIN(row, count - 1);
}

- (nullable UDGuiVariableDefinition *)variableDefinitionAtRow:(NSInteger)row {
    NSArray<UDGuiVariableDefinition *> *defs = [self variableDefinitionsForSelectedWindow];
    if (row < 0 || row >= (NSInteger)defs.count) { return nil; }
    return [defs objectAtIndex:(NSUInteger)row];
}

// MARK: - UDVariablesController public interface

- (void)syncControlsFromSelection {
    NSArray<UDGuiVariableDefinition *> *definitions = [self variableDefinitionsForSelectedWindow];
    NSInteger row = self.variablesTableView.selectedRow;
    BOOL hasSelection = row >= 0 && row < (NSInteger)definitions.count;

    self.variablesTypeControl.enabled = hasSelection;
    if (!hasSelection) {
        self.variablesTypeControl.selectedSegment = 0;
        return;
    }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    self.variablesTypeControl.selectedSegment = definition.type == UDGuiVariableDefinitionTypeVec4 ? 1 : 0;
}

- (void)reloadForWindow:(nullable UDGuiWindowNode *)window
       preserveSelection:(BOOL)preserveSelection
               selectRow:(NSInteger)forcedRow
            beginEditing:(BOOL)beginEditing {
    if (!self.variablesTableView) { return; }

    NSInteger targetRow = forcedRow;
    if (targetRow == NSNotFound && preserveSelection) {
        targetRow = self.variablesTableView.selectedRow;
    }

    [self.variablesTableView reloadData];

    NSInteger count = (NSInteger)[self variableDefinitionsForWindow:window].count;
    if (count == 0) {
        [self.variablesTableView deselectAll:nil];
        [self syncControlsFromSelection];
        return;
    }

    targetRow = [self normalizedRow:targetRow forCount:count];
    [self.variablesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)targetRow] byExtendingSelection:NO];
    [self.variablesTableView scrollRowToVisible:targetRow];
    [self syncControlsFromSelection];

    if (beginEditing && [self.variablesTableView isKindOfClass:[UDInspectableTableView class]]) {
        [(UDInspectableTableView *)self.variablesTableView beginEditingSelectedCell];
    }
}

- (void)commitVariableDefinitionsForWindow:(UDGuiWindowNode *)window
                                 selectRow:(NSInteger)row
                              beginEditing:(BOOL)beginEditing {
    [self.context.ownerDocument notifyGUIModelDidChange];
    [self reloadForWindow:window preserveSelection:NO selectRow:row beginEditing:beginEditing];
}

- (void)replaceVariableDefinitionAtRow:(NSInteger)row
                                  type:(UDGuiVariableDefinitionType)type
                                  name:(NSString *)name
                                 value:(NSString *)value {
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    NSArray<UDGuiVariableDefinition *> *definitions = [self variableDefinitionsForSelectedWindow];
    if (!window || row < 0 || row >= (NSInteger)definitions.count) { return; }

    UDGuiVariableDefinition *existing = [definitions objectAtIndex:(NSUInteger)row];
    NSString *nextName = [[name ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (nextName.length == 0) { nextName = existing.name; }

    [window replaceVariableDefinitionAtIndex:(NSUInteger)row
                              withDefinition:[[UDGuiVariableDefinition alloc] initWithType:type
                                                                                      name:nextName
                                                                                     value:(value ?: @"")]];
    [self commitVariableDefinitionsForWindow:window selectRow:row beginEditing:NO];
}

// MARK: - Actions

- (IBAction)changeVariablesActionButtons:(id)sender {
    UDGuiWindowNode *window = self.context.ownerDocument.viewModel.selectedWindow;
    if (!window) { return; }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    if (segment == 0) {
        UDGuiVariableDefinitionType type = self.variablesTypeControl.selectedSegment == 1
            ? UDGuiVariableDefinitionTypeVec4 : UDGuiVariableDefinitionTypeFloat;
        NSString *defaultValue = type == UDGuiVariableDefinitionTypeVec4 ? @"0, 0, 0, 0" : @"0";
        NSString *defaultName  = [self defaultVariableNameForType:type inWindow:window];
        [window addVariableDefinition:[[UDGuiVariableDefinition alloc] initWithType:type
                                                                               name:defaultName
                                                                              value:defaultValue]];
        [self commitVariableDefinitionsForWindow:window
                                       selectRow:(NSInteger)window.variableDefinitions.count - 1
                                    beginEditing:YES];
        return;
    }

    if (segment == 1) {
        NSInteger row = self.variablesTableView.selectedRow;
        if (row < 0 || row >= (NSInteger)window.variableDefinitions.count) { return; }
        [window removeVariableDefinitionAtIndex:(NSUInteger)row];
        NSInteger nextRow = MIN(row, (NSInteger)window.variableDefinitions.count - 1);
        [self commitVariableDefinitionsForWindow:window selectRow:nextRow beginEditing:NO];
    }
}

- (IBAction)changeSelectedVariableType:(id)sender {
    (void)sender;
    NSInteger row = self.variablesTableView.selectedRow;
    NSArray<UDGuiVariableDefinition *> *definitions = [self variableDefinitionsForSelectedWindow];
    if (row < 0 || row >= (NSInteger)definitions.count) { return; }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    UDGuiVariableDefinitionType type = self.variablesTypeControl.selectedSegment == 1
        ? UDGuiVariableDefinitionTypeVec4 : UDGuiVariableDefinitionTypeFloat;
    [self replaceVariableDefinitionAtRow:row type:type name:definition.name value:definition.value];
}

// MARK: - NSTableViewDataSource

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
    (void)tableView;
    return (NSInteger)[self variableDefinitionsForSelectedWindow].count;
}

- (nullable id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(nullable NSTableColumn *)tableColumn
                          row:(NSInteger)row {
    (void)tableView;
    UDGuiVariableDefinition *definition = [self variableDefinitionAtRow:row];
    if (!definition) { return @""; }

    if ([tableColumn.identifier isEqualToString:@"name"]) { return definition.name; }
    if ([tableColumn.identifier isEqualToString:@"type"]) {
        return definition.type == UDGuiVariableDefinitionTypeVec4 ? @"vec4" : @"float";
    }
    if ([tableColumn.identifier isEqualToString:@"value"]) { return definition.value; }
    return @"";
}

- (void)tableView:(NSTableView *)tableView
   setObjectValue:(nullable id)object
   forTableColumn:(nullable NSTableColumn *)tableColumn
              row:(NSInteger)row {
    (void)tableView;
    UDGuiVariableDefinition *definition = [self variableDefinitionAtRow:row];
    if (!definition) { return; }

    NSString *stringValue = [object isKindOfClass:[NSString class]]
        ? (NSString *)object : [[object description] copy];

    if ([tableColumn.identifier isEqualToString:@"name"]) {
        [self replaceVariableDefinitionAtRow:row type:definition.type name:stringValue value:definition.value];
    } else if ([tableColumn.identifier isEqualToString:@"value"]) {
        [self replaceVariableDefinitionAtRow:row type:definition.type name:definition.name value:stringValue];
    }
}

// MARK: - NSTableViewDelegate (selection)

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
    (void)notification;
    [self syncControlsFromSelection];
}

@end
