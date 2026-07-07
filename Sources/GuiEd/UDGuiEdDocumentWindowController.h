/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDGuiEdDocumentWindowController.h
 *
 * Thin orchestration layer for the GUI editor window.  All inspector, events,
 * variables, and outline-pane logic is delegated to focused collaborator
 * controllers (UDInspectorController, UDEventsController,
 * UDVariablesController, UDOutlinePaneController).
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"

NS_ASSUME_NONNULL_BEGIN

@class UDGuiEdDocument;

@interface UDGuiEdDocumentWindowController : NSWindowController <NSTextFieldDelegate, NSWindowDelegate, UDEditorControllerContext, NSSplitViewDelegate>

- (instancetype)initWithDocument:(UDGuiEdDocument *)document;

/// Reload all panes from the current document and selection state.
- (void)refreshFromDocument;

@end

NS_ASSUME_NONNULL_END
