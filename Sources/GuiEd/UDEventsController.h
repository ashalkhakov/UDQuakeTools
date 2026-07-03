/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDEventsController.h — Events panel controller for the GUI editor.
 *
 * Acts as NSTableViewDataSource and NSTableViewDelegate for the event-handlers
 * and event-commands table views, and drives the event-command inline editor.
 */

#import <AppKit/AppKit.h>
#import "UDEditorControllerContext.h"
#import "../UDCore/UDGuiModel.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDEventsController : NSObject <NSTableViewDataSource, NSTableViewDelegate>

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — assigned by window controller after XIB load

@property (nonatomic, weak, nullable) NSTableView *eventHandlersTableView;
@property (nonatomic, weak, nullable) NSTableView *eventCommandsTableView;
@property (nonatomic, weak, nullable) NSPopUpButton *eventCommandTypePopup;
@property (nonatomic, weak, nullable) NSTabView *eventCommandEditorTabView;
@property (nonatomic, weak, nullable) NSTextField *eventSetVariableField;
@property (nonatomic, weak, nullable) NSTextField *eventSetValueField;
@property (nonatomic, weak, nullable) NSTextField *eventSetFocusWindowField;
@property (nonatomic, weak, nullable) NSTextField *eventResetTimeWindowField;
@property (nonatomic, weak, nullable) NSTextField *eventResetTimeValueField;
@property (nonatomic, weak, nullable) NSTextField *eventTransitionVariableField;
@property (nonatomic, weak, nullable) NSTextField *eventTransitionFromField;
@property (nonatomic, weak, nullable) NSTextField *eventTransitionToField;
@property (nonatomic, weak, nullable) NSTextField *eventTransitionTimeField;
@property (nonatomic, weak, nullable) NSTextField *eventTransitionAccelField;
@property (nonatomic, weak, nullable) NSTextField *eventTransitionDecelField;
@property (nonatomic, weak, nullable) NSTextField *eventLocalSoundField;
@property (nonatomic, weak, nullable) NSTextField *eventRunScriptField;
@property (nonatomic, weak, nullable) NSTextField *eventShowCursorField;
@property (nonatomic, weak, nullable) NSTextField *eventFallbackArgumentsField;

// MARK: - Interface

/// Register drag-and-drop types on the managed table views; call from windowDidLoad.
- (void)registerDragTypes;

/// Reload the events editor for the given window, optionally preserving the
/// current handler-row selection.
- (void)reloadForWindow:(nullable UDGuiWindowNode *)window preserveSelection:(BOOL)preserveSelection;

- (void)syncEventCommandEditorFromSelection;

// MARK: - Selection accessors

- (NSArray<UDGuiEventHandler *> *)eventHandlersForSelectedWindow;
- (nullable UDGuiEventHandler *)selectedEventHandler;
- (nullable UDGuiScriptCommand *)selectedEventCommand;

// MARK: - Actions forwarded from window controller

- (IBAction)eventCommandEditorChanged:(id)sender;
- (IBAction)changeEventHandlersActionButtons:(id)sender;
- (IBAction)changeEventCommandsActionButtons:(id)sender;

@end

NS_ASSUME_NONNULL_END
