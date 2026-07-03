/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDOutlinePaneController.h — Outline pane controller for the GUI editor.
 *
 * Acts as NSOutlineViewDataSource and NSOutlineViewDelegate for the window
 * hierarchy outline view, and handles window add/remove actions.
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDOutlinePaneController : NSObject <NSOutlineViewDataSource, NSOutlineViewDelegate>

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — assigned by window controller after XIB load

@property (nonatomic, weak, nullable) NSOutlineView *outlineView;

// MARK: - Interface

/// Reload outline data and restore the current selection.
- (void)refreshOutlinePane;

// MARK: - Actions forwarded from window controller

- (IBAction)addRootWindow:(id)sender;
- (IBAction)addChildWindow:(id)sender;
- (IBAction)deleteSelectedWindow:(id)sender;

@end

NS_ASSUME_NONNULL_END
