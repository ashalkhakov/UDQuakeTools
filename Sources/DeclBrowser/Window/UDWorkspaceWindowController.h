#import <AppKit/AppKit.h>
#import "UDDeclBrowser.h"

/**
 * NSWindowController subclass that manages the single IDE workspace window.
 *
 * Layout (built programmatically / from WorkspaceWindow.xib):
 *   NSSplitView
 *     Left  → NSScrollView > NSOutlineView   (workspace file tree)
 *     Right → NSTabView                      (editor tabs)
 */
@class UDTabBarView;

@interface UDWorkspaceWindowController : NSWindowController <UDDeclBrowserDelegate, NSWindowDelegate>

@property (weak, nonatomic) IBOutlet NSOutlineView *outlineView;
@property (weak, nonatomic) IBOutlet NSSearchField *nameFilterField;
@property (weak, nonatomic) IBOutlet NSOutlineView *searchOutlineView;
@property (weak, nonatomic) IBOutlet NSSearchField *textFilterField;
@property (weak, nonatomic) IBOutlet NSTabView *tabView;         // right side of the split (tabless; content only)
@property (weak, nonatomic) IBOutlet UDTabBarView *tabBarView;   // the Xcode-like tab strip above it

@property (nonatomic, strong, nonnull) UDDeclBrowser *declBrowser;

- (IBAction)nameFilterChanged:(NSSearchField *)sender;
- (IBAction)textContainsFilterChanged:(NSSearchField *)sender;

// File menu save plumbing (VSCode-style; the window controller intercepts
// these ahead of the workspace document in the responder chain):
- (IBAction)saveDocument:(id)sender;     // Save the current tab's document
- (IBAction)saveAllDocuments:(id)sender; // Save every dirty open tab
- (IBAction)saveDocumentAs:(id)sender;   // Save the current decl as a new decl

// File > Workspace Settings…: edit all workspace settings; applying them
// restarts the workspace in place (closes tabs, reloads decls).
- (IBAction)showWorkspaceSettings:(id)sender;
@end
