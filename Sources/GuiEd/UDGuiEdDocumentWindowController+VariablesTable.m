/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController+VariablesTable.h"
#import "UDGuiEdDocumentWindowController+Conventions.h"
#import "UDGuiEdDocumentWindowController+Variables.h"
#import "UDGuiEdDocument.h"

#import "../UDCore/UDGuiEditorViewModel.h"
#import "../UDCore/UDGuiModel.h"

@interface UDGuiEdDocumentWindowController ()
@property (nonatomic, assign) UDGuiEdDocument *ownerDocument;
@end

@implementation UDGuiEdDocumentWindowController (VariablesTable)

- (UDGuiVariableDefinition *)selectedVariableDefinitionAtRow:(NSInteger)row {
    NSArray<UDGuiVariableDefinition *> *definitions = [self selectedWindowVariableDefinitions];
    if (row < 0 || row >= (NSInteger)definitions.count) {
        return nil;
    }
    return [definitions objectAtIndex:(NSUInteger)row];
}

- (id)tableViewObjectValueForVariablesTableView:(NSTableView *)tableView column:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    UDGuiVariableDefinition *definition = [self selectedVariableDefinitionAtRow:row];
    if (!definition) {
        return @"";
    }

    if ([tableColumn.identifier isEqualToString:@"name"]) {
        return definition.name;
    }
    if ([tableColumn.identifier isEqualToString:@"type"]) {
        return definition.type == UDGuiVariableDefinitionTypeVec4 ? @"vec4" : @"float";
    }
    if ([tableColumn.identifier isEqualToString:@"value"]) {
        return definition.value;
    }
    return @"";
}

- (void)tableViewSetObjectValueForVariablesTableView:(NSTableView *)tableView object:(id)object column:(NSTableColumn *)tableColumn row:(NSInteger)row {
    (void)tableView;
    UDGuiVariableDefinition *definition = [self selectedVariableDefinitionAtRow:row];
    if (!definition) {
        return;
    }

    NSString *stringValue = [self ud_stringValueFromObject:object];

    if ([tableColumn.identifier isEqualToString:@"name"]) {
        [self replaceVariableDefinitionAtRow:row type:definition.type name:stringValue value:definition.value];
        return;
    }

    if ([tableColumn.identifier isEqualToString:@"value"]) {
        [self replaceVariableDefinitionAtRow:row type:definition.type name:definition.name value:stringValue];
    }
}

@end
