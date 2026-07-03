/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDGuiEdDocumentWindowController.h"
#import "../UDCore/UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@class UDGuiWindowNode;

@interface UDGuiEdDocumentWindowController (Events)

- (NSArray<UDGuiEventHandler *> *)selectedWindowEventHandlers;
- (nullable UDGuiEventHandler *)selectedEventHandler;
- (nullable UDGuiScriptCommand *)selectedEventCommand;
- (UDGuiEventHandler *)eventHandlerForType:(UDGuiEventHandlerType)type qualifier:(NSString *)qualifier;
- (void)syncEventCommandEditorFromSelection;
- (void)reloadEventsEditorForWindow:(nullable UDGuiWindowNode *)window preserveSelection:(BOOL)preserveSelection;

- (IBAction)eventCommandEditorChanged:(id)sender;
- (IBAction)changeEventHandlersActionButtons:(id)sender;
- (IBAction)changeEventCommandsActionButtons:(id)sender;

@end

NS_ASSUME_NONNULL_END
