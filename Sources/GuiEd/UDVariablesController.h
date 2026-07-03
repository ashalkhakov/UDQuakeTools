/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDVariablesController.h — Variables panel controller for the GUI editor.
 *
 * Acts as NSTableViewDataSource and NSTableViewDelegate for the variables
 * table, and drives the variable-type segmented control.
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"
#import "../UDCore/UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDVariablesController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — assigned by window controller after XIB load

@property (nonatomic, weak, nullable) NSTableView *variablesTableView;
@property (nonatomic, weak, nullable) NSSegmentedControl *variablesTypeControl;

// MARK: - Interface

/// Reload the variables table for the given window.
/// Pass NSNotFound for forcedRow to preserve the current selection or start at 0.
- (void)reloadForWindow:(nullable UDGuiWindowNode *)window
       preserveSelection:(BOOL)preserveSelection
               selectRow:(NSInteger)forcedRow
            beginEditing:(BOOL)beginEditing;

/// Sync the type-control state from the current table selection.
- (void)syncControlsFromSelection;

/// Replace the variable definition at the given row with new type/name/value.
- (void)replaceVariableDefinitionAtRow:(NSInteger)row
                                  type:(UDGuiVariableDefinitionType)type
                                  name:(NSString *)name
                                 value:(NSString *)value;

// MARK: - Actions forwarded from window controller

- (IBAction)changeVariablesActionButtons:(id)sender;
- (IBAction)changeSelectedVariableType:(id)sender;

@end

NS_ASSUME_NONNULL_END
