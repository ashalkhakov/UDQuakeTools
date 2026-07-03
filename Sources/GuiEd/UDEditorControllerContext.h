/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDEditorControllerContext.h — Shared context protocol for GUI editor collaborator controllers.
 */

#import <Foundation/Foundation.h>

@class UDGuiEdDocument;

NS_ASSUME_NONNULL_BEGIN

/**
 * Context protocol adopted by UDGuiEdDocumentWindowController and provided to
 * each collaborator. Gives collaborators access to the document and a way to
 * trigger a model-change + UI refresh cycle.
 */
@protocol UDEditorControllerContext <NSObject>

@property (nonatomic, readonly) UDGuiEdDocument *ownerDocument;

/// Commits a model mutation: marks the document dirty, serializes, and
/// refreshes all panes.  Call when the document model has actually changed.
- (void)notifyModelChangedAndRefresh;

/// Refreshes all panes from the current document/selection state without
/// marking the document dirty.  Call for pure UI-state changes (e.g. selection).
- (void)refreshFromDocument;

/// Present an error to the user via the responder chain.
- (void)presentError:(NSError *)error;

@end

NS_ASSUME_NONNULL_END
