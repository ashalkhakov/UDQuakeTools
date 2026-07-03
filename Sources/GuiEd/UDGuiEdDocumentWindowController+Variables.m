/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+Variables.h"
#import "UDGuiEdDocument.h"
#import "UDInspectableTableView.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@end

@implementation UDGuiEdDocumentWindowController (Variables)

- (NSInteger)normalizedRow:(NSInteger)row forCount:(NSInteger)count {
    if (count <= 0) {
        return NSNotFound;
    }
    if (row == NSNotFound || row < 0) {
        return 0;
    }
    return MIN(row, count - 1);
}

- (NSArray<UDGuiVariableDefinition *> *)variableDefinitionsForWindow:(UDGuiWindowNode *)window {
    return window ? window.variableDefinitions : @[];
}

- (NSArray<UDGuiVariableDefinition *> *)selectedWindowVariableDefinitions {
    return [self variableDefinitionsForWindow:self.ownerDocument.viewModel.selectedWindow];
}

- (NSString *)defaultVariableNameForType:(UDGuiVariableDefinitionType)type inWindow:(UDGuiWindowNode *)window {
    NSString *prefix = type == UDGuiVariableDefinitionTypeVec4 ? @"vec4Var" : @"floatVar";
    NSSet<NSString *> *existingNames = [NSSet setWithArray:[[self variableDefinitionsForWindow:window] valueForKey:@"name"] ?: @[]];
    for (NSUInteger index = 1; index < 10000; index++) {
        NSString *candidate = [NSString stringWithFormat:@"%@%lu", prefix, (unsigned long)index];
        if (![existingNames containsObject:candidate]) {
            return candidate;
        }
    }
    return prefix;
}

- (void)syncVariableControlsFromSelection {
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
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

- (void)reloadVariablesTableForWindow:(UDGuiWindowNode *)window
                     preserveSelection:(BOOL)preserveSelection
                             selectRow:(NSInteger)forcedRow
                          beginEditing:(BOOL)beginEditing {
    if (!self.variablesTableView) {
        return;
    }

    NSInteger targetRow = forcedRow;
    if (targetRow == NSNotFound && preserveSelection) {
        targetRow = self.variablesTableView.selectedRow;
    }

    [self.variablesTableView reloadData];

    NSInteger count = (NSInteger)[self variableDefinitionsForWindow:window].count;
    if (count == 0) {
        [self.variablesTableView deselectAll:nil];
        [self syncVariableControlsFromSelection];
        return;
    }

    targetRow = [self normalizedRow:targetRow forCount:count];

    [self.variablesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)targetRow] byExtendingSelection:NO];
    [self.variablesTableView scrollRowToVisible:targetRow];
    [self syncVariableControlsFromSelection];

    if (beginEditing && [self.variablesTableView isKindOfClass:[UDInspectableTableView class]]) {
        [(UDInspectableTableView *)self.variablesTableView beginEditingSelectedCell];
    }
}

- (void)commitVariableDefinitionsForWindow:(UDGuiWindowNode *)window
                                 selectRow:(NSInteger)row
                              beginEditing:(BOOL)beginEditing {
    [self.ownerDocument notifyGUIModelDidChange];
    [self reloadVariablesTableForWindow:window preserveSelection:NO selectRow:row beginEditing:beginEditing];
}

- (void)replaceVariableDefinitionAtRow:(NSInteger)row
                                  type:(UDGuiVariableDefinitionType)type
                                  name:(NSString *)name
                                 value:(NSString *)value {
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (!window || row < 0 || row >= (NSInteger)definitions.count) {
        return;
    }

    UDGuiVariableDefinition *existing = [definitions objectAtIndex:(NSUInteger)row];
    NSString *nextName = [[name ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] copy];
    if (nextName.length == 0) {
        nextName = existing.name;
    }

    [window replaceVariableDefinitionAtIndex:(NSUInteger)row
                              withDefinition:[[UDGuiVariableDefinition alloc] initWithType:type
                                                                                         name:nextName
                                                                                        value:(value ?: @"")]];
    [self commitVariableDefinitionsForWindow:window selectRow:row beginEditing:NO];
}

- (IBAction)changeVariablesActionButtons:(id)sender {
    UDGuiWindowNode *window = self.ownerDocument.viewModel.selectedWindow;
    if (!window) {
        return;
    }

    NSSegmentedControl *control = (NSSegmentedControl *)sender;
    NSInteger segment = control.selectedSegment;
    control.selectedSegment = -1;

    if (segment == 0) {
        UDGuiVariableDefinitionType type = self.variablesTypeControl.selectedSegment == 1 ? UDGuiVariableDefinitionTypeVec4 : UDGuiVariableDefinitionTypeFloat;
        NSString *defaultValue = type == UDGuiVariableDefinitionTypeVec4 ? @"0, 0, 0, 0" : @"0";
        NSString *defaultName = [self defaultVariableNameForType:type inWindow:window];
        [window addVariableDefinition:[[UDGuiVariableDefinition alloc] initWithType:type name:defaultName value:defaultValue]];
        [self commitVariableDefinitionsForWindow:window selectRow:(NSInteger)window.variableDefinitions.count - 1 beginEditing:YES];
        return;
    }

    if (segment == 1) {
        NSInteger row = self.variablesTableView.selectedRow;
        if (row < 0 || row >= (NSInteger)window.variableDefinitions.count) {
            return;
        }

        [window removeVariableDefinitionAtIndex:(NSUInteger)row];
        NSInteger nextRow = MIN(row, (NSInteger)window.variableDefinitions.count - 1);
        [self commitVariableDefinitionsForWindow:window selectRow:nextRow beginEditing:NO];
    }
}

- (IBAction)changeSelectedVariableType:(id)sender {
    (void)sender;
    NSInteger row = self.variablesTableView.selectedRow;
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (row < 0 || row >= (NSInteger)definitions.count) {
        return;
    }

    UDGuiVariableDefinition *definition = [definitions objectAtIndex:(NSUInteger)row];
    UDGuiVariableDefinitionType type = self.variablesTypeControl.selectedSegment == 1 ? UDGuiVariableDefinitionTypeVec4 : UDGuiVariableDefinitionTypeFloat;
    [self replaceVariableDefinitionAtRow:row type:type name:definition.name value:definition.value];
}

@end
