/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser window controller.
 */

#import "UDDeclBrowserWindowController.h"
#import "UDDeclBrowserTreeModel.h"
#import "UDDeclBrowserViewModel.h"
#import "../UDCore/UDDeclModel.h"

@interface UDDeclBrowserWindowController ()
- (void)_rebuildResults;
- (void)_reloadStatus;
- (NSArray<NSNumber *> *)_selectedRowsBeforeColumn:(NSInteger)column;
- (NSArray<NSString *> *)_selectedNodeNameChain;
- (nullable UDDeclBrowserTreeNode *)_selectedLeafNode;
- (NSString *)_formattedSourceForDefinition:(UDDeclDefinition *)definition;
- (NSString *)_displayTitleForNode:(UDDeclBrowserTreeNode *)node;
- (void)_autoSelectFirstLeafIfAvailable;
- (void)_applySelectionPath:(NSArray<NSNumber *> *)selectionPath;
- (void)_selectNode:(nullable UDDeclBrowserTreeNode *)node;
@end

@implementation UDDeclBrowserWindowController

@synthesize searchField = _searchField;
@synthesize gamePopUpButton = _gamePopUpButton;
@synthesize browser = _browser;
@synthesize statusLabel = _statusLabel;
@synthesize pathLabel = _pathLabel;
@synthesize bodyView = _bodyView;

- (instancetype)init {
    self = [super initWithWindowNibName:@"UDDeclBrowserWindow"];
    if (self) {
        _viewModel = [[UDDeclBrowserViewModel alloc] init];
    }
    return self;
}

- (void)windowDidLoad {
    [super windowDidLoad];
    [self.browser setTarget:self];
    [self.browser setAction:@selector(browserSingleClick:)];
    [self.browser setAllowsEmptySelection:YES];
    [self.browser setAllowsMultipleSelection:NO];
    [self.browser setTitled:YES];
    [self.browser setSeparatesColumns:YES];
    [self.browser setMaxVisibleColumns:4];
    [self.browser setMinColumnWidth:160.0];
    [self.gamePopUpButton selectItemWithTitle:self->_viewModel.selectedGameDisplayName];
    [self _reloadStatus];
    [self _rebuildResults];
}

- (void)reloadFromDirectoryURL:(nullable NSURL *)directoryURL {
    [self->_viewModel loadFromDirectoryURL:directoryURL statusText:NULL];
    [self.browser loadColumnZero];
    [self _autoSelectFirstLeafIfAvailable];
    [self _setStatus:self->_viewModel.statusText];
}

- (void)_rebuildResults {
    [self.browser loadColumnZero];
    [self _autoSelectFirstLeafIfAvailable];
    [self _reloadStatus];
}

- (NSArray<NSNumber *> *)_selectedRowsBeforeColumn:(NSInteger)column {
    if (column <= 0) {
        return @[];
    }

    NSMutableArray<NSNumber *> *selectedRows = [NSMutableArray arrayWithCapacity:(NSUInteger)column];
    for (NSInteger currentColumn = 0; currentColumn < column; currentColumn++) {
        NSInteger selectedRow = [self.browser selectedRowInColumn:currentColumn];
        [selectedRows addObject:@(selectedRow)];
    }
    return [selectedRows copy];
}

- (NSArray<NSString *> *)_selectedNodeNameChain {
    NSMutableArray<NSString *> *nameChain = [NSMutableArray array];
    NSInteger selectedColumn = [self.browser selectedColumn];
    if (selectedColumn < 0) {
        return @[];
    }

    for (NSInteger column = 0; column <= selectedColumn; column++) {
        NSInteger row = [self.browser selectedRowInColumn:column];
        if (row < 0) {
            break;
        }

        UDDeclBrowserTreeNode *node = [self->_viewModel nodeForRow:row
                                                           inColumn:column
                                                        selectedRows:[self _selectedRowsBeforeColumn:column]];
        if (!node) {
            break;
        }
        [nameChain addObject:node.name ?: @""];
    }

    return [nameChain copy];
}

- (nullable UDDeclBrowserTreeNode *)_selectedLeafNode {
    NSInteger column = [self.browser selectedColumn];
    NSInteger row = column >= 0 ? [self.browser selectedRowInColumn:column] : -1;
    if (column < 0 || row < 0) {
        return nil;
    }

    UDDeclBrowserTreeNode *node = [self->_viewModel nodeForRow:row
                                                       inColumn:column
                                                    selectedRows:[self _selectedRowsBeforeColumn:column]];
    if (!node || !node.isLeaf) {
        return nil;
    }
    return node;
}

- (void)_reloadStatus {
    [self _setStatus:self->_viewModel.statusText];
}

- (void)_autoSelectFirstLeafIfAvailable {
    NSArray<NSNumber *> *selectionPath = [self->_viewModel firstLeafSelectionPath];
    if (!selectionPath || selectionPath.count == 0) {
        [self.pathLabel setStringValue:@"No selection"];
        [self.bodyView setString:@""];
        return;
    }

    [self _applySelectionPath:selectionPath];
}

- (void)_applySelectionPath:(NSArray<NSNumber *> *)selectionPath {
    for (NSInteger column = 0; column < (NSInteger)selectionPath.count; column++) {
        NSInteger row = [[selectionPath objectAtIndex:(NSUInteger)column] integerValue];
        if (row < 0) {
            return;
        }
        [self.browser selectRow:row inColumn:column];
    }

    NSInteger leafColumn = (NSInteger)selectionPath.count - 1;
    NSInteger leafRow = [[selectionPath lastObject] integerValue];
    UDDeclBrowserTreeNode *selectedNode = [self->_viewModel nodeForRow:leafRow
                                                               inColumn:leafColumn
                                                            selectedRows:[self _selectedRowsBeforeColumn:leafColumn]];
    [self _selectNode:selectedNode];
}

- (void)_setStatus:(NSString *)status {
    [self.statusLabel setStringValue:status];
}

- (void)_selectNode:(nullable UDDeclBrowserTreeNode *)node {
    if (!node) {
        [self.pathLabel setStringValue:@"No selection"];
        [self.bodyView setString:@""];
        return;
    }

    [self.pathLabel setStringValue:[self _displayTitleForNode:node]];

    if (node.isLeaf && node.definition) {
        [self.bodyView setString:[self _formattedSourceForDefinition:node.definition]];
    } else {
        [self.bodyView setString:@""];
    }
}

- (NSString *)_formattedSourceForDefinition:(UDDeclDefinition *)definition {
    return definition.body ?: @"";
}

- (NSString *)_displayTitleForNode:(UDDeclBrowserTreeNode *)node {
    if (!node) {
        return @"No selection";
    }

    if (node.isLeaf && node.definition) {
        NSString *declName = node.name.length > 0 ? node.name : (node.definition.declName ?: @"<unnamed decl>");
        NSString *sourcePath = node.definition.sourceVirtualPath.length > 0 ? node.definition.sourceVirtualPath : @"<unknown source>";
        return [NSString stringWithFormat:@"%@ [%@]", declName, sourcePath];
    }

    return node.fullPath.length > 0 ? node.fullPath : (node.name ?: @"");
}

- (NSInteger)browser:(NSBrowser *)sender numberOfRowsInColumn:(NSInteger)column {
    (void)sender;
    return [self->_viewModel numberOfRowsInColumn:column selectedRows:[self _selectedRowsBeforeColumn:column]];
}

- (void)browser:(NSBrowser *)sender willDisplayCell:(id)cell atRow:(NSInteger)row column:(NSInteger)column {
    (void)sender;
    UDDeclBrowserTreeNode *node = [self->_viewModel nodeForRow:row
                                                       inColumn:column
                                                    selectedRows:[self _selectedRowsBeforeColumn:column]];
    if (!node) {
        return;
    }
    [cell setLeaf:node.isLeaf];
    [cell setLoaded:YES];
    [cell setEnabled:YES];
    [cell setTitle:[self _displayTitleForNode:node]];
    [cell setRepresentedObject:node];
}

- (void)browserSingleClick:(id)sender {
    (void)sender;
    NSInteger column = [self.browser selectedColumn];
    NSInteger row = column >= 0 ? [self.browser selectedRowInColumn:column] : -1;
    UDDeclBrowserTreeNode *node = [self->_viewModel nodeForRow:row
                                                       inColumn:column
                                                    selectedRows:[self _selectedRowsBeforeColumn:column]];
    [self _selectNode:node];
}

- (IBAction)searchChanged:(id)sender {
    UDDeclBrowserTreeNode *previousLeaf = [self _selectedLeafNode];
    NSArray<NSString *> *previousNameChain = [self _selectedNodeNameChain];

    [self->_viewModel setSearchText:[self.searchField stringValue] ?: @""];

    [self.browser loadColumnZero];

    NSArray<NSNumber *> *restoredPath = nil;
    if (previousLeaf && previousLeaf.definition) {
        restoredPath = [self->_viewModel selectionPathForDefinitionWithType:previousLeaf.definition.declType
                                                                        name:previousLeaf.definition.declName
                                                                  sourcePath:previousLeaf.definition.sourceVirtualPath];
    }
    if (!restoredPath && previousNameChain.count > 0) {
        restoredPath = [self->_viewModel selectionPathForNodeNameChain:previousNameChain];
    }

    if (restoredPath && restoredPath.count > 0) {
        [self _applySelectionPath:restoredPath];
    } else {
        [self _autoSelectFirstLeafIfAvailable];
    }

    [self _reloadStatus];
}

- (IBAction)gameChanged:(id)sender {
    (void)sender;
    [self->_viewModel setSelectedGameDisplayName:self.gamePopUpButton.selectedItem.title];
}

- (IBAction)openFolder:(id)sender {
    (void)sender;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];

    NSInteger result = [panel runModal];
#ifdef GNUSTEP
    BOOL accepted = (result == NSFileHandlingPanelOKButton);
#else
    BOOL accepted = (result == NSModalResponseOK);
#endif
    if (!accepted) {
        return;
    }

    NSURL *selectedURL = panel.URL;
    if (selectedURL) {
        [self reloadFromDirectoryURL:selectedURL];
    }
}

@end
