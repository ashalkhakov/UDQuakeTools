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

@interface UDVariablesController : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
    NSView *_view;
    __weak NSTableView *_variablesTableView;
    __weak NSSegmentedControl *_variablesTypeControl;
}

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — loaded programmatically from XIB

@property (nonatomic, strong, nullable) IBOutlet NSView *view;
@property (nonatomic, weak, nullable) IBOutlet NSTableView *variablesTableView;
@property (nonatomic, weak, nullable) IBOutlet NSSegmentedControl *variablesTypeControl;

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
