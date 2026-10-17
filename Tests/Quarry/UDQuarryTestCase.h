#import <XCTest/XCTest.h>
#import <AppKit/AppKit.h>

#import "UDWorkspaceWindowController.h"
#import "UDBaseEditorViewController.h"

@class UDEditorTabManager, UDWorkspaceDocument;

NS_ASSUME_NONNULL_BEGIN

/// The Doom 3 install the real-data cases browse: $UD_DOOM3_PATH, or
/// /Volumes/ExtraSSD/games/DOOM 3 when that is unset. Returns nil when the
/// directory has no base/pak000.pk4, so those cases can step aside.
NSString * _Nullable UDDoom3InstallPath(void);

/**
 * Base class for the Quarry cases. They drive the app the way a user
 * does — a workspace document opens its window, the outline is expanded and
 * a row selected, text is typed into the editors' fields through the field
 * editor, File > Save is sent — and then check both the UI and what landed
 * on disk.
 *
 * Every case gets a fresh scratch directory (removed afterwards) to use as
 * fs_savepath, so saving never writes anywhere else.
 */
@interface UDQuarryTestCase : XCTestCase

/// Per-case scratch directory; removed in -tearDown.
@property (nonatomic, copy, readonly) NSString *scratchDirectory;

/// Workspace settings in the shape a .qworkspace file holds.
- (NSDictionary *)workspaceSettingsWithBasePath:(NSString *)basePath
                                       savePath:(NSString *)savePath;

/// Opens a workspace document the way File > Open does for a .qworkspace
/// file (read the settings, make and show the workspace window). The
/// document is closed in -tearDown. Returns nil (after an XCTFail) when the
/// workspace does not start or the window does not load.
- (nullable UDWorkspaceWindowController *)openWorkspaceWithSettings:(NSDictionary *)settings;

/// A workspace document's window controller, once it has started (nil before).
- (nullable UDWorkspaceWindowController *)workspaceWindowControllerOf:(UDWorkspaceDocument *)document;

/// Closes a workspace opened with -openWorkspaceWithSettings: early (to
/// reopen it fresh and see what was saved).
- (void)closeWorkspace:(UDWorkspaceWindowController *)controller;

- (UDEditorTabManager *)tabManagerOf:(UDWorkspaceWindowController *)controller;

/// Expands the outline down to the slash-separated path ("pda/admin_moses")
/// and returns the row of its last component, or -1 (after an XCTFail).
- (NSInteger)revealOutlinePath:(NSString *)path inController:(UDWorkspaceWindowController *)controller;

/// Selects the outline row for path — which is what opens an editor tab —
/// and returns the editor of the tab that is then selected.
- (nullable __kindof UDBaseEditorViewController *)openOutlinePath:(NSString *)path
                                                     inController:(UDWorkspaceWindowController *)controller;

/// Every item of the main outline, fully expanded, as slash-separated paths
/// of display names.
- (NSArray<NSString *> *)expandedOutlinePathsInController:(UDWorkspaceWindowController *)controller;

/// Runs the run loop until condition holds or timeout passes.
- (BOOL)spinUntil:(BOOL (^)(void))condition timeout:(NSTimeInterval)timeout;

/// The text field whose value is bound to selection.<key> of the editor's
/// object controller (fullName, ident, subject, ...). Found through the
/// binding rather than the placeholder: on macOS a bound field's placeholder
/// is replaced by the binding's own ("No Selection" and so on).
- (nullable NSTextField *)textFieldBoundTo:(NSString *)key inView:(NSView *)view;

/// Finds views by what a user sees: a button's title, or the first subview
/// of a class.
/// The control under @a view bound to selection.<key> (its value, selected
/// value or index): found by what it edits, its tooltip being help.
- (nullable __kindof NSView *)viewBoundTo:(NSString *)key inView:(NSView *)view;
/// The same, a control of @a cls (a slider beside its field, say).
- (nullable __kindof NSView *)viewBoundTo:(NSString *)key ofClass:(Class)cls inView:(NSView *)view;
- (nullable NSButton *)buttonTitled:(NSString *)title inView:(NSView *)view;
- (nullable __kindof NSView *)firstSubviewOfClass:(Class)cls inView:(NSView *)view;
- (nullable NSSegmentedControl *)segmentedControlWithAction:(SEL)action inView:(NSView *)view;
/// Every view under @a view, breadth first, while @a visit says YES.
- (void)forEachViewUnder:(NSView *)view do:(BOOL (^)(NSView *view))visit;
/// A control by its tool tip (the settings' and New Declaration's name what
/// they set).
- (nullable __kindof NSView *)viewWithToolTip:(NSString *)toolTip inView:(NSView *)view;

/// Clicks the tab labelled label of the first tab view under view that has
/// one (only the selected tab's view is in the view hierarchy).
- (void)selectTabLabeled:(NSString *)label inView:(NSView *)view;

/// Lets the run loop turn once in its current mode, as it does between
/// user events: managed object contexts process pending changes (and so
/// post their change notifications and register undo) at that point.
- (void)finishEvent;

/// Types into a field like a user: focus it, select all, insert the text
/// through the field editor, and end editing (Tab away) so its binding
/// pushes the value into the model.
- (void)typeText:(NSString *)text intoField:(NSTextField *)field;

/// Makes the text view first responder and replaces its text by inserting,
/// like typing; the binding commits when editing ends (e.g. on OK).
- (void)typeText:(NSString *)text intoTextView:(NSTextView *)textView;

/// Schedules block to run once a modal window is up (the run loop is in
/// NSModalPanelRunLoopMode from then on, so a timer is the only way in).
/// If the modal is still up 20s later it is aborted and the case fails,
/// rather than hanging the run.
- (void)whenModalWindowAppears:(void (^)(NSWindow *window))block;

@end

NS_ASSUME_NONNULL_END
