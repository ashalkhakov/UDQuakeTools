#import "UDEditorTabManager.h"
//#import "UDResource.h"
#import "UDFileItem.h"
#import "UDBaseEditorViewController.h"

@interface UDEditorTabManager ()
/** path (NSString) → BaseEditorViewController */
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDBaseEditorViewController *> *openEditors;
@property (nonatomic, strong) UDWorkspace *workspace;
@end

@implementation UDEditorTabManager

- (instancetype)initWithTabView:(NSTabView *)tabView workspace:(UDWorkspace *)workspace {
    self = [super init];
    if (self) {
        _tabView = tabView;
        _openEditors = [NSMutableDictionary dictionary];
        _workspace = workspace;
    }
    return self;
}

- (UDBaseEditorViewController *)openEditorForWorkspaceItem:(UDWorkspaceItem *)item {
    if (!item.path.length) {
        return nil;
    }
    NSString *path = item.path;

    // Reuse existing tab.
    UDBaseEditorViewController *existing = self.openEditors[path];
    if (existing) {
        NSTabViewItem *tabItem = [self tabViewItemForPath:path];
        if (tabItem) {
            [self.tabView selectTabViewItem:tabItem];
        }
        return existing;
    }

    // Create a new editor VC for this file.
    UDBaseEditorViewController *vc = [UDBaseEditorViewController editorViewControllerForWorkspaceItem:item inWorkspace:_workspace];

    vc.view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    vc.view.frame = self.tabView.contentRect; // set initial frame explicitly

    // Wrap it in a tab view item.
    NSTabViewItem *tabItem = [[NSTabViewItem alloc] initWithIdentifier:path];
    tabItem.label = item.name;
    tabItem.view  = vc.view;
    
    [self.tabView addTabViewItem:tabItem];
    [self.tabView selectTabViewItem:tabItem];

    // Force layout and redisplay
    [self.tabView setNeedsLayout:YES];
    [self.tabView layoutSubtreeIfNeeded];
    [self.tabView setNeedsDisplay:YES];

    self.openEditors[path] = vc;
    return vc;
}

- (void)closeTabForPath:(NSString *)path {
    NSTabViewItem *tabItem = [self tabViewItemForPath:path];
    if (tabItem) {
        [self.tabView removeTabViewItem:tabItem];
    }
    [self.openEditors removeObjectForKey:path];
}

- (void)closeAllTabs {
    for (NSString *path in [self.openEditors allKeys]) {
        [self closeTabForPath:path];
    }
}

#pragma mark - Private

- (nullable NSTabViewItem *)tabViewItemForPath:(NSString *)path {
    for (NSTabViewItem *item in self.tabView.tabViewItems) {
        if ([item.identifier isEqual:path]) {
            return item;
        }
    }
    return nil;
}

@end
