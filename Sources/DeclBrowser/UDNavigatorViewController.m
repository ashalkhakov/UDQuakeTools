#import "UDSplitViewController.h"
#import "UDNavigatorViewController.h"
#import "UDWorkspaceWindowController.h"
#import "UDWorkspaceDocument.h"
#import "UDWorkspace.h"
#import "idDeclManager.h"

@implementation UDNavigatorViewController

// Helper to grab the workspace from the responder chain
- (UDWorkspace *)currentWorkspace {
    UDWorkspaceWindowController *wc = (UDWorkspaceWindowController *)self.view.window.windowController;
    return wc.workspaceDocument.workspace;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.outlineView.dataSource = self;
    self.outlineView.delegate = self;
    
    // Wire up the double-click action
    self.outlineView.target = self;
    self.outlineView.doubleAction = @selector(outlineViewDoubleClicked:);
}

- (void)outlineViewDoubleClicked:(id)sender {
    NSInteger clickedRow = [self.outlineView clickedRow];
    if (clickedRow < 0) return; // Clicked outside any row
    
    id item = [self.outlineView itemAtRow:clickedRow];
    
    // Check if they double-clicked a folder ("Materials", "Skins") or an actual decl
    if (![item isKindOfClass:[NSString class]]) {
        idDecl *decl = (idDecl *)item;

        // Traverse up to the Split View Controller to find the Tab Controller sibling
        if ([self.parentViewController isKindOfClass:[UDSplitViewController class]]) {
            UDSplitViewController *splitVC = (UDSplitViewController *)self.parentViewController;
            [splitVC.tabVC openDeclInNewTab:decl];
        }
    } else {
        // If they double-click a folder, toggle its expansion state
        if ([self.outlineView isItemExpanded:item]) {
            [self.outlineView collapseItem:item];
        } else {
            [self.outlineView expandItem:item];
        }
    }
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    UDWorkspace *workspace = [self currentWorkspace];
    if (!workspace) return 0;
    
    if (item == nil) {
        // Root level: Return number of declaration types
        return [workspace.declManager numDeclTypes];
    } else if ([item isKindOfClass:[NSString class]]) {
        // Child level: Return number of decls in this specific type
        int typeIndex = [workspace.declManager declTypeFromName:(NSString *)item];
        return [workspace.declManager numDecls:(declType_t)typeIndex];
    }
    
    return 0;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    UDWorkspace *workspace = [self currentWorkspace];
    
    if (item == nil) {
        // Root items are just NSStrings representing the type (e.g., "Materials")
        return [workspace.declManager declTypeName:(declType_t)index];
    } else if ([item isKindOfClass:[NSString class]]) {
        // Child items are the actual idDecl objects
        int typeIndex = [workspace.declManager declTypeFromName:(NSString *)item];
        return [workspace.declManager declByIndex:(int)index type:(declType_t)typeIndex forceParse:NO error:nil];
    }
    
    return nil;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    return [item isKindOfClass:[NSString class]];
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {

    NSTableCellView *cell = [outlineView makeViewWithIdentifier:@"DataCell" owner:self];
    
    if ([item isKindOfClass:[NSString class]]) {
        cell.textField.stringValue = (NSString *)item;
    } else {
        idDeclBase *decl = (idDeclBase *)item;
        cell.textField.stringValue = decl.name;
    }
    
    return cell;
}

@end
