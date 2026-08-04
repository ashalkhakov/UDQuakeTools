#import "UDEditorTabViewController.h"
#import "UDEditorViewController.h"
#import "idDeclManager.h"

@implementation UDEditorTabViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tabStyle = NSTabViewControllerTabStyleToolbar;
}

- (void)openDeclInNewTab:(idDecl *)decl {
    // 1. Check if the decl is already open
    for (NSTabViewItem *item in self.tabViewItems) {
        UDEditorViewController *editor = (UDEditorViewController *)item.viewController;
        if (editor.decl == decl) {
            self.selectedTabViewItemIndex = [self.tabViewItems indexOfObject:item];
            return;
        }
    }
    
    // 2. Create new editor for this decl
    UDEditorViewController *newEditor = [[UDEditorViewController alloc] initWithDecl:decl];
    NSTabViewItem *newItem = [NSTabViewItem tabViewItemWithViewController:newEditor];
    
    newItem.label = decl.name;
    
    [self addTabViewItem:newItem];
    self.selectedTabViewItemIndex = self.tabViewItems.count - 1;
}

@end
