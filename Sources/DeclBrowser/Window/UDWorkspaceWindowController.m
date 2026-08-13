#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDDeclBrowser.h"
#import "UDEditorTabManager.h"

@interface UDWorkspaceWindowController ()
@property (nonatomic, strong) UDEditorTabManager *tabManager;
@end

@implementation UDWorkspaceWindowController

- (instancetype)init {
    self = [super initWithWindowNibName:@"UDWorkspaceWindow"];
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    
    self.declBrowser = [[UDDeclBrowser alloc] initWithWorkspace:self.workspace];
    self.declBrowser.delegate = self;

    [self.declBrowser attachToOutlineViews:self.outlineView searchOutline:self.searchOutlineView];
    [self.declBrowser reset];          // builds the full tree

    self.tabManager = [[UDEditorTabManager alloc] initWithTabView:self.tabView workspace:self.workspace];
}

-(UDWorkspace *)workspace {
    return ((UDWorkspaceDocument *)self.document).workspace;
}

//
// text editing
//

- (void)textDidChange:(NSNotification *)notification {
#if 0
    id selected = /* currently selected decl */;
    if (selected) {
        [self.document setText:self.textView.string forDecl:selected];
        [self.document updateChangeCount:NSChangeDone];
    }
#endif
}

- (IBAction)nameFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findByName:(name.length ? name : @"*")];
}

- (IBAction)textContainsFilterChanged:(NSSearchField *)sender {
    NSString *name = sender.stringValue;
    
    [self.declBrowser findContaining:name ?: @""];
}

#pragma mark - UDDeclBrowserDelegate

- (void)declBrowser:(UDDeclBrowser *)browser didSelectResource:(UDWorkspaceItem *)resource {
    if (resource.kind == UDWorkspaceItemKindGroup) {
        return;
    }

    [self.tabManager openEditorForWorkspaceItem:resource];
}

- (void)declBrowserDidClearSelection:(UDDeclBrowser *)browser {
    // TODO: do something about it?
}

@end
