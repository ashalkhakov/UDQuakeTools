#import "UDEditorTabManager.h"
//#import "UDResource.h"
#import "UDFileItem.h"
#import "UDBaseEditorViewController.h"
#import "UDBaseDocument.h"

@interface UDEditorTabManager ()
/** path (NSString) → BaseEditorViewController */
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDBaseEditorViewController *> *openEditors;
@property (nonatomic, strong) UDWorkspace *workspace;
@property (nonatomic, strong, readwrite) UDTabBarView *tabBar;
@end

@implementation UDEditorTabManager

- (instancetype)initWithTabView:(NSTabView *)tabView tabBar:(UDTabBarView *)tabBar workspace:(UDWorkspace *)workspace {
    self = [super init];
    if (self) {
        _tabView = tabView;
        _tabBar = tabBar;
        _openEditors = [NSMutableDictionary dictionary];
        _workspace = workspace;

        tabBar.delegate = self;

        // Per-tab dirty indicator: documents announce change-count updates.
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(_documentEditedStateChanged:)
                                                     name:UDBaseDocumentEditedStateDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
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
        self.tabBar.selectedItem = [self.tabBar itemWithRepresentedObject:path];
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

    // The visible tab in the bar.
    UDTabBarItem *barItem = [UDTabBarItem itemWithTitle:item.name representedObject:path];
    barItem.toolTip = path;
    [self.tabBar addItem:barItem];
    self.tabBar.selectedItem = barItem;

    return vc;
}

- (void)closeTabForPath:(NSString *)path {
    NSTabViewItem *tabItem = [self tabViewItemForPath:path];
    if (tabItem) {
        [self.tabView removeTabViewItem:tabItem];
    }
    [self.openEditors removeObjectForKey:path];

    UDTabBarItem *barItem = [self.tabBar itemWithRepresentedObject:path];
    if (barItem) {
        [self.tabBar removeItem:barItem];
    }

    // NSTabView auto-selects a neighbor after a removal; mirror that in the bar.
    NSString *selectedPath = [self _selectedTabViewPath];
    self.tabBar.selectedItem = selectedPath != nil ? [self.tabBar itemWithRepresentedObject:selectedPath] : nil;
}

- (void)closeAllTabs {
    for (NSString *path in [self.openEditors allKeys]) {
        [self closeTabForPath:path];
    }
}

- (UDBaseEditorViewController *)selectedEditor {
    NSString *path = [self _selectedTabViewPath];
    return path != nil ? self.openEditors[path] : nil;
}

- (NSArray<UDBaseEditorViewController *> *)allEditors {
    return self.openEditors.allValues;
}

#pragma mark - UDTabBarViewDelegate

- (void)tabBarView:(UDTabBarView *)tabBarView didSelectItem:(UDTabBarItem *)item {
    NSTabViewItem *tabItem = [self tabViewItemForPath:item.representedObject];
    if (tabItem) {
        [self.tabView selectTabViewItem:tabItem];
    }
}

// Close button clicked: confirm when the tab's document has unsaved changes.
- (void)tabBarView:(UDTabBarView *)tabBarView requestsCloseForItem:(UDTabBarItem *)item {
    NSString *path = item.representedObject;
    if (path == nil) {
        return;
    }

    UDBaseDocument *document = self.openEditors[path].editorDocument;
    if (document.isDocumentEdited) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = [NSString stringWithFormat:@"“%@” has unsaved changes.", path.lastPathComponent];
        alert.informativeText = @"Do you want to save them before closing the tab?";
        [alert addButtonWithTitle:@"Save and Close"];
        [alert addButtonWithTitle:@"Discard Changes"];
        [alert addButtonWithTitle:@"Cancel"];

        NSModalResponse response = [alert runModal];
        if (response == NSAlertFirstButtonReturn) {
            NSError *error = nil;
            if (![document ud_save:&error]) {
                [NSApp presentError:error];
                return; // keep the tab open; nothing was lost
            }
        } else if (response == NSAlertThirdButtonReturn) {
            return;
        }
    }

    [self closeTabForPath:path];
}

#pragma mark - Dirty tracking

- (void)_documentEditedStateChanged:(NSNotification *)notification {
    for (NSString *path in self.openEditors) {
        UDBaseEditorViewController *editor = self.openEditors[path];
        if (editor.editorDocument == notification.object) {
            [self.tabBar itemWithRepresentedObject:path].dirty = editor.editorDocument.isDocumentEdited;
            break;
        }
    }
}

#pragma mark - Private

- (nullable NSString *)_selectedTabViewPath {
    id identifier = self.tabView.selectedTabViewItem.identifier;
    return [identifier isKindOfClass:[NSString class]] ? identifier : nil;
}

- (nullable NSTabViewItem *)tabViewItemForPath:(NSString *)path {
    for (NSTabViewItem *item in self.tabView.tabViewItems) {
        if ([item.identifier isEqual:path]) {
            return item;
        }
    }
    return nil;
}

@end
