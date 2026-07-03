/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"
#import "../UDCore/UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@class UDGuiWindowNode;

@interface UDGuiEdDocumentWindowController (Variables)

- (NSArray<UDGuiVariableDefinition *> *)selectedWindowVariableDefinitions;
- (void)replaceVariableDefinitionAtRow:(NSInteger)row
                                  type:(UDGuiVariableDefinitionType)type
                                  name:(NSString *)name
                                 value:(NSString *)value;
- (void)syncVariableControlsFromSelection;
- (void)reloadVariablesTableForWindow:(nullable UDGuiWindowNode *)window
                     preserveSelection:(BOOL)preserveSelection
                             selectRow:(NSInteger)forcedRow
                          beginEditing:(BOOL)beginEditing;

- (IBAction)changeVariablesActionButtons:(id)sender;
- (IBAction)changeSelectedVariableType:(id)sender;

@end

NS_ASSUME_NONNULL_END
