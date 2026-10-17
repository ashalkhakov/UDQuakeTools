/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * UDGuiScriptsController.h — the inspector's Scripts, structured (not the
 * engine's: its GEItemScriptsDlg edited a window's scripts as text). For a
 * window: its events (each script it has, added from a menu of the events
 * it may have, taken off, opened) and its variables. For an event (its row
 * in the navigator): the event and its parameter, its statements as rows
 * (an if's within it, its else after), added from a menu of the commands,
 * taken off, dragged into another order; and the chosen statement's every
 * parameter, named, with what it is. Each edit is one Undo. Laid out in
 * UDGuiViewerView.xib.
 */

#import <Cocoa/Cocoa.h>

@class rvGEWorkspace, idWindow;

NS_ASSUME_NONNULL_BEGIN

/// A window's event in the navigator: its row, under the window.
@interface UDGuiEventNode : NSObject
@property (nonatomic, weak, nullable) idWindow *window;
@property (nonatomic, copy) NSString *key;
@end

@interface UDGuiScriptsController : NSObject <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate>

/// The design the scripts are of.
@property (nonatomic, weak, nullable) rvGEWorkspace *workspace;
/// Told to show an event in the navigator (one added, one opened from the
/// events, one renamed): the sender is the controller, its window and its
/// eventKey what to show (eventKey nil: the window).
@property (nonatomic, weak, nullable) id target;
@property (nonatomic, nullable) SEL action;

/// What the pane shows: @a window's events and variables, or (an event's
/// key) that event's script; nothing, for no window.
- (void)showWindow:(nullable idWindow *)window event:(nullable NSString *)key;
@property (nonatomic, weak, readonly, nullable) idWindow *window;
@property (nonatomic, copy, readonly, nullable) NSString *eventKey;

// The pages: "none", "window", "event"
@property (weak) IBOutlet NSTabView *pages;
@property (weak) IBOutlet NSTextField *message;

// A window's: its events and its variables
@property (weak) IBOutlet NSTableView *eventsTable;
@property (weak) IBOutlet NSPopUpButton *addEventButton;
@property (weak) IBOutlet NSTableView *variablesTable;
- (IBAction)addEvent:(nullable id)sender;
- (IBAction)removeEvent:(nullable id)sender;
- (IBAction)openEvent:(nullable id)sender;
- (IBAction)addOrRemoveVariable:(nullable id)sender;

// An event's: the event, its statements, the chosen statement
@property (weak) IBOutlet NSPopUpButton *eventPopUp;
@property (weak) IBOutlet NSTextField *eventParameterLabel;
@property (weak) IBOutlet NSTextField *eventParameterField;
@property (weak) IBOutlet NSTextField *eventHelp;
@property (weak) IBOutlet NSOutlineView *statementsOutline;
@property (weak) IBOutlet NSPopUpButton *addStatementButton;
@property (weak) IBOutlet NSTextField *statementHelp;
@property (weak) IBOutlet NSTextField *conditionLabel;
@property (weak) IBOutlet NSTextField *conditionField;
@property (weak) IBOutlet NSTextField *parameterLabel1;
@property (weak) IBOutlet NSTextField *parameterField1;
@property (weak) IBOutlet NSTextField *parameterLabel2;
@property (weak) IBOutlet NSTextField *parameterField2;
@property (weak) IBOutlet NSTextField *parameterLabel3;
@property (weak) IBOutlet NSTextField *parameterField3;
@property (weak) IBOutlet NSTextField *parameterLabel4;
@property (weak) IBOutlet NSTextField *parameterField4;
@property (weak) IBOutlet NSTextField *parameterLabel5;
@property (weak) IBOutlet NSTextField *parameterField5;
@property (weak) IBOutlet NSTextField *parameterLabel6;
@property (weak) IBOutlet NSTextField *parameterField6;
- (IBAction)changeEvent:(nullable id)sender;
- (IBAction)addStatement:(nullable id)sender;
- (IBAction)removeStatement:(nullable id)sender;
- (IBAction)statementEdited:(nullable id)sender;

/// The statement shown in the fields (the outline's chosen one), and the
/// rows a drag moves (for the tests: what a drop does).
@property (nonatomic, readonly, nullable) id selectedStatement;
- (BOOL)moveStatement:(id)statement toParent:(nullable id)parent index:(NSInteger)index;

@end

NS_ASSUME_NONNULL_END
