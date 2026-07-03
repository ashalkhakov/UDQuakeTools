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

@interface UDEventsController : NSObject <NSTableViewDataSource, NSTableViewDelegate> {
    NSView *_view;
    NSTableView *_eventHandlersTableView;
    NSTableView *_eventCommandsTableView;
    NSPopUpButton *_eventCommandTypePopup;
    NSTabView *_eventCommandEditorTabView;
    NSTextField *_eventSetVariableField;
    NSTextField *_eventSetValueField;
    NSTextField *_eventSetFocusWindowField;
    NSTextField *_eventResetTimeWindowField;
    NSTextField *_eventResetTimeValueField;
    NSTextField *_eventTransitionVariableField;
    NSTextField *_eventTransitionFromField;
    NSTextField *_eventTransitionToField;
    NSTextField *_eventTransitionTimeField;
    NSTextField *_eventTransitionAccelField;
    NSTextField *_eventTransitionDecelField;
    NSTextField *_eventLocalSoundField;
    NSTextField *_eventRunScriptField;
    NSTextField *_eventShowCursorField;
    NSTextField *_eventFallbackArgumentsField;
}

/// Weak back-reference to the window controller acting as context.
@property (nonatomic, weak, nullable) id<UDEditorControllerContext> context;

// MARK: - Outlets — loaded programmatically from XIB

@property (nonatomic, strong, nullable) IBOutlet NSView *view;
@property (nonatomic, weak, nullable) IBOutlet NSTableView *eventHandlersTableView;
@property (nonatomic, weak, nullable) IBOutlet NSTableView *eventCommandsTableView;
@property (nonatomic, weak, nullable) IBOutlet NSPopUpButton *eventCommandTypePopup;
@property (nonatomic, weak, nullable) IBOutlet NSTabView *eventCommandEditorTabView;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventSetVariableField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventSetValueField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventSetFocusWindowField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventResetTimeWindowField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventResetTimeValueField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventTransitionVariableField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventTransitionFromField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventTransitionToField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventTransitionTimeField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventTransitionAccelField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventTransitionDecelField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventLocalSoundField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventRunScriptField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventShowCursorField;
@property (nonatomic, weak, nullable) IBOutlet NSTextField *eventFallbackArgumentsField;

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
