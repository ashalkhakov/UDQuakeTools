#import <AppKit/AppKit.h>
#import "UDDeclBrowser.h"

/**
 * NSWindowController subclass that manages the single IDE workspace window.
 *
 * Layout (UDWorkspaceWindow.xib), Xcode's and RDLKit's designer's three
 * panes in an NSSplitView:
 *     Left   → the navigator: a DMTabBar over a tabless NSTabView (the
 *              decls and files, Find, Issues)
 *     Centre → the editor tabs: UDTabBarView over a tabless NSTabView,
 *              Editor | Source beside them
 *     Right  → the inspector: a DMTabBar over a host the selected editor's
 *              panes go in (UDInspecting), "No Inspector" when it has none
 * The sides keep their width as the window grows; the centre takes it.
 */
@class UDTabBarView, DMTabBar, UDScriptDebugger;

@protocol UDErrorsViewControllerDelegate;

@interface UDWorkspaceWindowController : NSWindowController <UDDeclBrowserDelegate, NSWindowDelegate, UDErrorsViewControllerDelegate, NSSplitViewDelegate>

@property (weak, nonatomic) IBOutlet NSOutlineView *outlineView;
@property (weak, nonatomic) IBOutlet NSSearchField *nameFilterField;
@property (weak, nonatomic) IBOutlet NSOutlineView *searchOutlineView;
@property (weak, nonatomic) IBOutlet NSSearchField *textFilterField;
@property (weak, nonatomic) IBOutlet NSTabView *tabView;         // right side of the split (tabless; content only)
@property (weak, nonatomic) IBOutlet UDTabBarView *tabBarView;   // the Xcode-like tab strip above it
@property (weak, nonatomic) IBOutlet NSSegmentedControl *representationControl; // Editor | Source, beside it
@property (weak, nonatomic) IBOutlet NSSplitView *split;                 // navigator | editors | inspector
@property (weak, nonatomic) IBOutlet DMTabBar *navigatorTabBar;
@property (weak, nonatomic) IBOutlet NSTabView *navigatorTabView;
@property (weak, nonatomic) IBOutlet DMTabBar *inspectorTabBar;
@property (weak, nonatomic) IBOutlet NSView *inspectorHost;
@property (weak, nonatomic) IBOutlet NSTextField *inspectorPlaceholder;
// The debugger's: its navigator tab's host; under the editors (editorSplit's
// second pane), the debug bar over the debug area.
@property (weak, nonatomic) IBOutlet NSView *debugNavigatorHost;
@property (weak, nonatomic) IBOutlet NSView *breakpointNavigatorHost;
@property (weak, nonatomic) IBOutlet NSSplitView *editorSplit;
@property (weak, nonatomic) IBOutlet NSView *debugPane;
@property (weak, nonatomic) IBOutlet NSView *debugBarHost;
@property (weak, nonatomic) IBOutlet NSView *debugAreaHost;

@property (nonatomic, strong, nonnull) UDDeclBrowser *declBrowser;

- (IBAction)nameFilterChanged:(NSSearchField *)sender;

// The side panes' tab bars: the tab each has chosen shown (the sender is
// the bar).
- (IBAction)navigatorTabChanged:(id)sender;
- (IBAction)inspectorTabChanged:(id)sender;
/// The selected editor's navigator tab @a title shown; its inspector's.
- (void)showNavigatorPaneTitled:(NSString *)title;
- (void)showInspectorPaneTitled:(NSString *)title;
- (IBAction)textContainsFilterChanged:(NSSearchField *)sender;

// File menu save plumbing (VSCode-style; the window controller intercepts
// these ahead of the workspace document in the responder chain):
- (IBAction)saveDocument:(id)sender;     // Save the current tab's document
- (IBAction)saveAllDocuments:(id)sender; // Save every dirty open tab
- (IBAction)saveDocumentAs:(id)sender;   // Save the current decl as a new decl

// File > Workspace Settings…: edit all workspace settings in a plain window;
// applying them restarts the workspace in place (closes tabs, reloads decls).
- (IBAction)showWorkspaceSettings:(id)sender;
- (IBAction)newPDA:(id)sender;
- (IBAction)newSkin:(id)sender;

// Edit > Jump to Definition: the current tab's, when it is a script's.
- (IBAction)jumpToDefinition:(id)sender;

// Opens the file at @a path (in the workspace's file system) in its tab,
// selecting @a length characters from @a line's @a character (0-based).
- (void)openFileAtPath:(NSString *)path line:(NSInteger)line character:(NSInteger)character length:(NSInteger)length;
/// The scripts' debugger (UDScriptDebugger): Debug > Run starts the
/// workspace's game for debugging, Attach a game started so; the session's
/// actions, the debug area shown or hidden.
@property (nonatomic, strong, readonly) UDScriptDebugger *scriptDebugger;
- (IBAction)startDebugging:(nullable id)sender;
- (IBAction)attachDebugger:(nullable id)sender;
- (IBAction)stopDebugging:(nullable id)sender;
- (IBAction)debugContinueOrPause:(nullable id)sender;
- (IBAction)debugStepOver:(nullable id)sender;
- (IBAction)debugStepInto:(nullable id)sender;
- (IBAction)debugStepOut:(nullable id)sender;
- (IBAction)toggleDebugArea:(nullable id)sender;
/// Debug > Run to Cursor, from the window: the selected script's tab's.
- (IBAction)runToCursor:(nullable id)sender;
- (IBAction)jumpToCursor:(nullable id)sender;
@property (nonatomic, readonly, getter=isDebugAreaShown) BOOL debugAreaShown;

@end
