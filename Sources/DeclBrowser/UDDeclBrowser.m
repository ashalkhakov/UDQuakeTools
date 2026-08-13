#import <AppKit/AppKit.h>

#import "idDeclManager.h"
#import "idFileSystem.h"
#import "idStr.h"
#import "UDDeclBrowser.h"
#import "UDWorkspace.h"

@implementation UDDeclSearchMatch
@end
@implementation UDDeclSearchFileGroup
@end

@interface UDDeclBrowser ()
@property (strong, nonatomic, readwrite) UDWorkspace *workspace;
@property (strong, nonatomic) UDPathTree *baseDeclTree; // full unfiltered tree
@property (strong, nonatomic) UDPathTree *declTree; // currently filtered tree (filter by name)

@property (strong) NSArray<UDDeclSearchFileGroup *> *searchFileGroups;  // the data for the Search outline
@property (weak)   NSOutlineView *searchOutlineView;                    // the second outline

@property (strong, nonatomic) NSArray<UDWorkspaceItem *> *rootNodes; // = declTree.topLevelNodes
@property (assign, nonatomic) int numListedDecls;
@property (strong, nonatomic) NSString *findNameString;
@property (strong, nonatomic) NSString *findTextString;
@property (weak) NSOutlineView *outlineView; // the main decl outline view
@end

@implementation UDDeclBrowser

-(instancetype)initWithWorkspace:(UDWorkspace *)workspace {
    self = [super init];
    if (self) {
        _workspace = workspace;
        _baseDeclTree = [[UDPathTree alloc] init];
        _declTree = [[UDPathTree alloc] init];
        _rootNodes = [[NSArray alloc] init];
        _numListedDecls = 0;
        _findNameString = @"";
        _findTextString = @"";
        [self reset];
    }
    return self;
}

-(idDeclManager *)declManager {
    return _workspace.declManager;
}
-(idFileSystem *)fileSystem {
    return _workspace.fileSystem;
}

- (void)addDeclTypeToTree:(declType_t)type
                     root:(NSString *)root
                     tree:(UDPathTree *)tree
{
    NSMutableArray<idDecl *> *decls = [NSMutableArray array];
    
    for (idDecl *decl in [self.declManager declsOfType:type forceParse:NO]) {
        [decls addObject:decl];
    }
    
    // same sort as original (idStr::IcmpPath)
    [decls sortUsingComparator:^NSComparisonResult(idDecl *a, idDecl *b) {
        return [[a name] caseInsensitiveCompare:[b name]];
    }];
    
    NSString *rootStr = [root stringByAppendingString:@"/"];
    
    for (idDecl *decl in decls) {
        NSString *declPath = [rootStr stringByAppendingString:[decl name]];
        declPath = [declPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        declPath = [declPath stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
        
        [tree addDeclToTree:declPath type:type declName:decl.name];
    }
}

- (void)addScriptsToTree:(UDPathTree *)tree {
    idFileList *files = [self.fileSystem listFilesTree:@"script" extension:@".script" sorted:YES inGameDir:nil error:nil];
    
    for (int i = 0; i < [files numFiles]; i++) {
        NSString *scriptName = [files fileByIndex:i];
        scriptName = [scriptName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        scriptName = [scriptName stringByDeletingPathExtension];
        NSString *fileName = [scriptName stringByAppendingString:@".script"];
        
        [tree addFileToTree:scriptName];
    }
    
    [self.fileSystem freeFileList:files];
}

- (void)addGUIsToTree:(UDPathTree *)tree {
    idFileList *files = [self.fileSystem listFilesTree:@"guis" extension:@".gui" sorted:YES inGameDir:nil error:nil];
    
    for (int i = 0; i < [files numFiles]; i++) {
        NSString *guiName = [files fileByIndex:i];
        guiName = [guiName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        guiName = [guiName stringByDeletingPathExtension];
        NSString *fileName = [guiName stringByAppendingString:@".gui"];
        
        [tree addFileToTree:fileName];
    }
    
    [self.fileSystem freeFileList:files];
}

- (void)initBaseDeclTree {
    self.numListedDecls = 0;
    [self.baseDeclTree deleteAllItems];
    
    idDeclManager *declManager = _workspace.declManager;
    
    for (int i = 0; i < [declManager numDeclTypes]; i++) {
        NSString *typeName = [declManager declNameFromType:(declType_t)i];
        [self addDeclTypeToTree:(declType_t)i root:typeName tree:self.baseDeclTree];
    }
    
    [self addScriptsToTree:self.baseDeclTree];
    [self addGUIsToTree:self.baseDeclTree];
}

- (BOOL)filterString:(NSString *)pattern matches:(NSString *)string {
    return idStr_Filter(pattern.UTF8String, string.UTF8String, NO);
}

- (BOOL)compareDeclName:(UDWorkspaceItem *)item name:(NSString *)name {
    // Name filter
    if (self.findNameString.length > 0) {
        if (![self filterString:self.findNameString matches:name]) {
            return NO;
        }
    }
    
    return YES;
}

- (void)findContaining:(NSString *)query {
    if (query.length == 0) {
        self.searchFileGroups = @[];
        [self.searchOutlineView reloadData];
        return;
    }
    
    self.findTextString = query;
    
    NSMutableDictionary<NSString *, UDDeclSearchFileGroup *> *groups = [NSMutableDictionary dictionary];
    UDWorkspace *workspace = self.workspace;
    
    [UDDeclTreeWalker walkLeavesInTree:self.baseDeclTree
                            usingBlock:^(UDWorkspaceItem *node, BOOL *stop) {
        if (![node matchesTextSearch:query inWorkspace:workspace]) {
            return;
        }
        
        NSString *filename = node.path;
        
        UDDeclSearchFileGroup *group = groups[filename];
        if (!group) {
            group = [[UDDeclSearchFileGroup alloc] init];
            group.filename = filename;
            group.matches = [NSMutableArray array];
            groups[filename] = group;
        }
        
        UDDeclSearchMatch *match = [[UDDeclSearchMatch alloc] init];
        match.node = node;
        //match.matchRange = range; // FIXME: reimplement
        [group.matches addObject:match];
    }];
    
    // Sort groups by filename, matches by name
    NSArray *sorted = [[groups allValues] sortedArrayUsingComparator:^NSComparisonResult(UDDeclSearchFileGroup *a, UDDeclSearchFileGroup *b) {
        return [a.filename caseInsensitiveCompare:b.filename];
    }];
    
    for (UDDeclSearchFileGroup *g in sorted) {
        [g.matches sortUsingComparator:^NSComparisonResult(UDDeclSearchMatch *a, UDDeclSearchMatch *b) {
            return [a.node.name caseInsensitiveCompare:b.node.name];
        }];
    }
    
    self.searchFileGroups = sorted;
    [self.searchOutlineView reloadData];
}

- (void)reset {
    [self initBaseDeclTree];
    
    self.findNameString = @"*";
    //self.findNameEdit.stringValue = self.findNameString;   // if you have a text field
    
    self.findTextString = @"";
    //self.findTextEdit.stringValue = @"";
    
    self.numListedDecls = (int)[UDDeclTreeWalker filterTree:self.baseDeclTree
                                                   intoTree:self.declTree
                                                  withBlock:^BOOL(UDWorkspaceItem *node) {
        return [self compareDeclName:node name:node.path];
    }];
    
    self.rootNodes = self.declTree.topLevelNodes;
    [self.outlineView reloadData];
    
    self.searchFileGroups = @[];
    
    // status
    // self.statusLabel.stringValue = [NSString stringWithFormat:@"%ld decls listed", (long)self.numListedDecls];
}

- (void)findByName:(NSString *)name {
    self.findNameString = name;
    self.numListedDecls = (int)[UDDeclTreeWalker filterTree:self.baseDeclTree
                                                   intoTree:self.declTree
                                                  withBlock:^BOOL(UDWorkspaceItem *node) {
        return [self compareDeclName:node name:node.path];
    }];
    
    self.rootNodes = self.declTree.topLevelNodes;
    [self.outlineView reloadData];
}

- (void)attachToOutlineViews:(NSOutlineView *)outlineView searchOutline:(NSOutlineView *)searchOutlineView {
    self.outlineView = outlineView;
    outlineView.dataSource = self;
    outlineView.delegate = self;
    
    // Optional but nice
    outlineView.allowsMultipleSelection = NO;
    outlineView.allowsEmptySelection = YES;
    
    self.searchOutlineView = searchOutlineView;
    searchOutlineView.dataSource = self;
    searchOutlineView.delegate = self;
    
    searchOutlineView.allowsMultipleSelection = NO;
    searchOutlineView.allowsEmptySelection = YES;
}

#pragma mark - NSOutlineViewDataSource

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
    if (outlineView == self.searchOutlineView) {
        if (item == nil) return self.searchFileGroups.count;
        if ([item isKindOfClass:[UDDeclSearchFileGroup class]]) {
            return ((UDDeclSearchFileGroup *)item).matches.count;
        }
        return 0;
    }
    
    // outlineView == self.outlineView
    if (item == nil) {
        return self.rootNodes.count;
    }
    return ((UDWorkspaceItem *)item).children.count;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
    if (outlineView == self.searchOutlineView) {
        if (item == nil) return self.searchFileGroups[index];
        return ((UDDeclSearchFileGroup *)item).matches[index];
    }
    
    // outlineView == self.outlineView
    if (item == nil) {
        return self.rootNodes[index];
    }
    return ((UDWorkspaceItem *)item).children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (outlineView == self.searchOutlineView) {
        return [item isKindOfClass:[UDDeclSearchFileGroup class]];
    }

    UDWorkspaceItem *node = (UDWorkspaceItem *)item;
    return node.kind == UDWorkspaceItemKindGroup;
}

#pragma mark - NSOutlineViewDelegate

- (NSView *)outlineView:(NSOutlineView *)ov
     viewForTableColumn:(NSTableColumn *)tableColumn
                   item:(id)item {
    if (ov == self.searchOutlineView) {
        NSTableCellView *cell = [ov makeViewWithIdentifier:@"name" owner:nil];
        
        if ([item isKindOfClass:[UDDeclSearchFileGroup class]]) {
            cell.textField.stringValue = ((UDDeclSearchFileGroup *)item).filename;
            // optional: make it bold
        } else {
            UDDeclSearchMatch *match = item;
            cell.textField.stringValue = match.node.name;
        }
        return cell;
    }
    
    // outlineView == self.outlineView
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"name" owner:nil];
    cell.textField.stringValue = ((UDWorkspaceItem *)item).name;
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSOutlineView *ov = notification.object;
    
    if (ov == self.searchOutlineView) {
        NSInteger row = self.searchOutlineView.selectedRow;
        /*
         if (row < 0) {
         // nothing selected -> clear the text editor
         if ([self.delegate respondsToSelector:@selector(declBrowserDidClearSelection:)]) {
         [self.delegate declBrowserDidClearSelection:self];
         }
         return;
         }*/
        
        id item = [ov itemAtRow:ov.selectedRow];
        if ([item isKindOfClass:[UDDeclSearchMatch class]]) {
            UDDeclSearchMatch *match = item;
            UDWorkspaceItem *node = match.node;

            if ([self.delegate respondsToSelector:@selector(declBrowser:didSelectResource:)]) {
                [self.delegate declBrowser:self didSelectResource:node];
            }
        }
        return;
    }
    
    if (ov == self.outlineView) {
        NSInteger row = self.outlineView.selectedRow;
        if (row < 0) {
            // nothing selected -> clear the text editor
            if ([self.delegate respondsToSelector:@selector(declBrowserDidClearSelection:)]) {
                [self.delegate declBrowserDidClearSelection:self];
            }
            return;
        }
        
        UDWorkspaceItem *node = [self.outlineView itemAtRow:row];
        if ([self.delegate respondsToSelector:@selector(declBrowser:didSelectResource:)]) {
            [self.delegate declBrowser:self didSelectResource:node];
        }
        
        return;
    }
}

@end
