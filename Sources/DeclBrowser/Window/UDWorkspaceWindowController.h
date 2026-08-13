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
@interface UDWorkspaceWindowController : NSWindowController <UDDeclBrowserDelegate>

@property (weak, nonatomic) IBOutlet NSOutlineView *outlineView;
@property (weak, nonatomic) IBOutlet NSSearchField *nameFilterField;
@property (weak, nonatomic) IBOutlet NSOutlineView *searchOutlineView;
@property (weak, nonatomic) IBOutlet NSSearchField *textFilterField;
@property (weak, nonatomic) IBOutlet NSTabView *tabView;         // right side of the split

@property (nonatomic, strong, nonnull) UDDeclBrowser *declBrowser;

- (IBAction)nameFilterChanged:(NSSearchField *)sender;
- (IBAction)textContainsFilterChanged:(NSSearchField *)sender;
@end
