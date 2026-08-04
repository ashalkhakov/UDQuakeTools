//
//  UDDeclBrowser.m
//  PakManager
//
//  Created by artyom on 8/2/26.
//

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

@property (strong, nonatomic) NSArray<UDDeclTreeNode *> *rootNodes; // = declTree.topLevelNodes
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

// Equivalent of DeclBrowser::AddDeclTypeToTree
- (void)addDeclTypeToTree:(declType_t)type
                     root:(NSString *)root
                     tree:(UDPathTree *)tree
{
    NSMutableArray<idDecl *> *decls = [NSMutableArray array];
    int num = [self.declManager numDecls:type];
    for (int i = 0; i < num; i++) {
        idDecl *decl = [self.declManager declByIndex:i type:type forceParse:NO error:nil];
        if (decl) [decls addObject:decl];
    }
    
    // same sort as original (idStr::IcmpPath)
    [decls sortUsingComparator:^NSComparisonResult(idDecl *a, idDecl *b) {
        return [[a name] caseInsensitiveCompare:[b name]];
    }];
    
    NSString *rootStr = [root stringByAppendingString:@"/"];
    
    for (idDecl *decl in decls) {
        NSString *declName = [rootStr stringByAppendingString:[decl name]];
        declName = [declName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        declName = [declName stringByTrimmingCharactersInSet:
                    [NSCharacterSet whitespaceCharacterSet]];
        
        NSInteger encodedId = GetIdFromTypeAndIndex(type, [decl index]);
        [tree addPathToTree:declName encodedId:encodedId];
    }
}

// Equivalent of DeclBrowser::AddScriptsToTree
- (void)addScriptsToTree:(UDPathTree *)tree {
    idFileList *files = [self.fileSystem listFilesTree:@"script" extension:@".script" sorted:YES inGameDir:nil error:nil];
    
    for (int i = 0; i < [files numFiles]; i++) {
        NSString *scriptName = [files fileByIndex:i];
        scriptName = [scriptName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        scriptName = [scriptName stringByDeletingPathExtension];
        
        NSInteger encodedId = GetIdFromTypeAndIndex(DECLTYPE_SCRIPT, i);
        [tree addPathToTree:scriptName encodedId:encodedId];
    }
    
    [self.fileSystem freeFileList:files];
}

// Equivalent of DeclBrowser::AddGUIsToTree
- (void)addGUIsToTree:(UDPathTree *)tree {
    idFileList *files = [self.fileSystem listFilesTree:@"guis" extension:@".gui" sorted:YES inGameDir:nil error:nil];
    
    for (int i = 0; i < [files numFiles]; i++) {
        NSString *guiName = [files fileByIndex:i];
        guiName = [guiName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        guiName = [guiName stringByDeletingPathExtension];
        
        NSInteger encodedId = GetIdFromTypeAndIndex(DECLTYPE_GUI, i);
        [tree addPathToTree:guiName encodedId:encodedId];
    }
    
    [self.fileSystem freeFileList:files];
}

// Equivalent of DeclBrowser::InitBaseDeclTree
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

- (BOOL)compareDeclName:(UDDeclTreeNode *)item name:(NSString *)name {
    // Name filter
    if (self.findNameString.length > 0) {
        if (![self filterString:self.findNameString matches:name]) {
            return NO;
        }
    }
        
    return YES;
}

-(BOOL)compareDeclText:(UDDeclTreeNode *)item name:(NSString *)name {
    // Text content filter
    if (self.findTextString.length > 0) {
        NSString *text = [self textOfNode:item];
        if ([text rangeOfString:self.findTextString options:NSCaseInsensitiveSearch].location == NSNotFound) {
            return NO;
        }
    }

    return YES;
}

- (NSString *)fileNameOfNode:(UDDeclTreeNode *)item {
    NSInteger encodedId = item.encodedId;
    declType_t type = GetTypeFromId(encodedId);
    int index = GetIndexFromId(encodedId);

    if (type == DECLTYPE_SCRIPT || type == DECLTYPE_GUI) {
        // Search inside the .script / .gui file
        NSString *ext = (type == DECLTYPE_SCRIPT) ? @".script" : @".gui";
        NSString *fileName = [item.fullPath stringByAppendingString:ext];
        return fileName;
    } else {
        const idDecl *decl = [_workspace.declManager declByIndex:index type:type forceParse:NO error:nil];
        if (!decl) return @"";
        return [decl fileName];
    }
}

- (NSString *)textOfNode:(UDDeclTreeNode *)item {
    NSInteger encodedId = item.encodedId;
    declType_t type = GetTypeFromId(encodedId);
    int index = GetIndexFromId(encodedId);

    if (type == DECLTYPE_SCRIPT || type == DECLTYPE_GUI) {
        // Search inside the .script / .gui file
        NSString *ext = (type == DECLTYPE_SCRIPT) ? @".script" : @".gui";
        NSString *fileName = [item.fullPath stringByAppendingString:ext];
        void *buffer = NULL;
        int bufferLen = [_workspace.fileSystem readFile:fileName buffer:&buffer timestamp:NULL error:nil];
        
        if (!bufferLen) {
            return @"";
        }
        
        NSString *text = [[NSString alloc] initWithBytes:buffer length:bufferLen encoding:NSUTF8StringEncoding];
        [_workspace.fileSystem freeFile:buffer error:nil];
        return text;
    } else {
        // Search inside the decl text
        const idDecl *decl = [_workspace.declManager declByIndex:index type:type forceParse:NO error:nil];
        if (!decl) return @"";

        NSMutableData *declText = [[NSMutableData alloc] init];
        [decl text:declText];

        NSString *text = [[NSString alloc] initWithData:declText encoding:NSUTF8StringEncoding];
        return text;
    }
}

- (void)findContaining:(NSString *)query {
    if (query.length == 0) {
        self.searchFileGroups = @[];
        [self.searchOutlineView reloadData];
        return;
    }
    
    self.findTextString = query;
    
    NSMutableDictionary<NSString *, UDDeclSearchFileGroup *> *groups = [NSMutableDictionary dictionary];
    
    [UDDeclTreeWalker walkLeavesInTree:self.baseDeclTree
                            usingBlock:^(UDDeclTreeNode *node, BOOL *stop) {
        NSString *text = [self textOfNode:node];
        if (!text) return;
        
        NSRange range = [text rangeOfString:query options:NSCaseInsensitiveSearch];
        if (range.location == NSNotFound) return;
        
        NSString *filename = [self fileNameOfNode:node];
        
        UDDeclSearchFileGroup *group = groups[filename];
        if (!group) {
            group = [[UDDeclSearchFileGroup alloc] init];
            group.filename = filename;
            group.matches = [NSMutableArray array];
            groups[filename] = group;
        }
        
        UDDeclSearchMatch *match = [[UDDeclSearchMatch alloc] init];
        match.node = node;
        match.matchRange = range;
        [group.matches addObject:match];
    }];
    
    // Sort groups by filename, matches by name
    NSArray *sorted = [[groups allValues] sortedArrayUsingComparator:^NSComparisonResult(UDDeclSearchFileGroup *a, UDDeclSearchFileGroup *b) {
        return [a.filename caseInsensitiveCompare:b.filename];
    }];
    
    for (UDDeclSearchFileGroup *g in sorted) {
        [g.matches sortUsingComparator:^NSComparisonResult(UDDeclSearchMatch *a, UDDeclSearchMatch *b) {
            return [a.node.title caseInsensitiveCompare:b.node.title];
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
                                                  withBlock:^BOOL(UDDeclTreeNode *node) {
            return [self compareDeclName:node name:node.fullPath];
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
                                                  withBlock:^BOOL(UDDeclTreeNode *node) {
            return [self compareDeclName:node name:node.fullPath];
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
    return ((UDDeclTreeNode *)item).children.count;
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
    return ((UDDeclTreeNode *)item).children[index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
    if (outlineView == self.searchOutlineView) {
        return [item isKindOfClass:[UDDeclSearchFileGroup class]];
    }

    return ((UDDeclTreeNode *)item).children.count > 0;
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
            cell.textField.stringValue = match.node.title;
        }
        return cell;
    }

    // outlineView == self.outlineView
    NSTableCellView *cell = [ov makeViewWithIdentifier:@"name" owner:nil];
    cell.textField.stringValue = ((UDDeclTreeNode *)item).title;
    return cell;
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification {
    NSOutlineView *ov = notification.object;
    
    if (ov == self.searchOutlineView) {
        id item = [ov itemAtRow:ov.selectedRow];
        if ([item isKindOfClass:[UDDeclSearchMatch class]]) {
            UDDeclSearchMatch *match = item;
            UDDeclTreeNode *node = match.node;
            
            const idDecl *decl = [self declFromTreeItem:node];
            if (decl) {
                if ([self.delegate respondsToSelector:@selector(declBrowser:didSelectDecl:)]) {
                    [self.delegate declBrowser:self didSelectDecl:decl];
                }
            } else {
                if ([self.delegate respondsToSelector:@selector(declBrowser:didSelectGuiOrScript:)]) {
                    [self.delegate declBrowser:self didSelectGuiOrScript:[self fileNameOfNode:node]];
                }
            }
            // later: also highlight match.matchRange in the text view
        }
        return;
    }
    
    if (ov == self.outlineView) {
        NSInteger row = self.outlineView.selectedRow;
        if (row < 0) {
            // nothing selected -> clear the text editor
            [self.delegate declBrowser:self didSelectDecl:nil];
            return;
        }
        
        UDDeclTreeNode *node = [self.outlineView itemAtRow:row];
        const idDecl *decl = [self declFromTreeItem:node];
        if (decl) {
            if ([self.delegate respondsToSelector:@selector(declBrowser:didSelectDecl:)]) {
                [self.delegate declBrowser:self didSelectDecl:decl];
            }
        } else {
            if ([self.delegate respondsToSelector:@selector(declBrowser:didSelectGuiOrScript:)]) {
                [self.delegate declBrowser:self didSelectGuiOrScript:node.fullPath];
            }
        }

        return;
    }
}

- (idDecl *)declFromTreeItem:(UDDeclTreeNode *)item {
    if (!item || item.children.count > 0) return nil;   // folder

    idDeclManager *declManager = _workspace.declManager;
    
    NSInteger id = item.encodedId;
    declType_t type = GetTypeFromId(id);
    int index = GetIndexFromId(id);
    
    if (type == DECLTYPE_GUI || type == DECLTYPE_SCRIPT) return nil;
    
    if (type < 0 || type >= [declManager numDeclTypes]) return nil;

    return [declManager declByIndex:index type:type forceParse:NO error:nil];
}

@end
