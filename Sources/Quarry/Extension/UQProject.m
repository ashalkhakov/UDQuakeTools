/*---------------------------------------------------------------------------------------------
 *  UQProject.m
 *--------------------------------------------------------------------------------------------*/

#import "UQProject.h"
#import "UDWorkspace.h"
#import "UDWorkspaceManager.h"
#import "UDPathTree.h"
#import "UDDeclItem.h"
#import "UDFileItem.h"
#import "idDeclManager.h"
#import "idFileSystem.h"
#import "idStr.h"

NSNotificationName const UQProjectDidStartNotification = @"UQProjectDidStartNotification";

static NSString *const UQScheme = @"quarry";
static NSString *const UQFileRoot = @"file";

static NSError *UQError(NSString *message) {
    return [NSError errorWithDomain:@"UQProjectErrorDomain" code:1 userInfo:@{ NSLocalizedDescriptionKey: message }];
}

/// A game starting reads its paks on a thread of its own; two at once share
/// its parsers' tables, so they start one after the other.
static NSMutableArray<UQProject *> *UQStarting;

@implementation UQProject {
    NSMutableArray<void (^)(UDWorkspace *)> *_waiting;
    BOOL _started;
    UDWorkspace *_starting;
    UDPathTree *_tree;          // every decl, script and GUI
    UDPathTree *_shown;         // what the filter leaves of it; nil: all of it
    NSString *_filter;
}

- (instancetype)initWithFolder:(NSURL *)folder workbench:(id<UDWorkbench>)workbench {
    if (!(self = [super init])) return nil;
    _folder = [folder copy];
    _workbench = workbench;
    _waiting = [NSMutableArray array];
    _tree = [[UDPathTree alloc] init];
    _filter = @"";
    NSArray *names = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:folder.path error:NULL]
                         sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *name in names) {
        if ([name.pathExtension isEqualToString:@"qworkspace"]) {
            _workspaceFileURL = [folder URLByAppendingPathComponent:name];
            break;
        }
    }
    [self _start];
    return self;
}

// ---------------------------------------------------------------------------
// MARK: - Its game
// ---------------------------------------------------------------------------

- (void)_start {
    NSError *error = nil;
    NSData *data = _workspaceFileURL ? [NSData dataWithContentsOfURL:_workspaceFileURL options:0 error:&error] : nil;
    NSDictionary *settings = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:&error] : nil;
    if (![settings isKindOfClass:[NSDictionary class]]) {
        [self _didFail:error ?: UQError(_workspaceFileURL ? @"Its .qworkspace isn't a Quarry workspace's settings."
                                                          : @"The folder has no .qworkspace.")];
        return;
    }
    _starting = [[UDWorkspace alloc] initWithDictionary:settings rootDirectory:settings[@"fs_basepath"]];
    if (!UQStarting) UQStarting = [NSMutableArray array];
    [UQStarting addObject:self];
    if (UQStarting.count == 1) [_starting startupInBackgroundWithTarget:self action:@selector(_didStart:)];
}

- (void)_didStart:(UDWorkspace *)workspace {
    [UQStarting removeObject:self];
    UQProject *next = UQStarting.firstObject;
    if (next) [next->_starting startupInBackgroundWithTarget:next action:@selector(_didStart:)];
    if (workspace.startupError) {
        [self _didFail:workspace.startupError];
        return;
    }
    _workspace = workspace;
    _starting = nil;
    [[UDWorkspaceManager sharedManager] registerWorkspace:workspace];
    [self _readTree];
    _started = YES;
    [_treeView refresh];
    [[NSNotificationCenter defaultCenter] postNotificationName:UQProjectDidStartNotification object:self];
    NSArray *waiting = [_waiting copy];
    [_waiting removeAllObjects];
    for (void (^block)(UDWorkspace *) in waiting) block(workspace);
}

- (void)_didFail:(NSError *)error {
    _startupError = error;
    _starting = nil;
    _started = YES;
    NSLog(@"Quarry: %@ not started: %@", _workspaceFileURL.lastPathComponent ?: _folder.lastPathComponent, error.localizedDescription);
    [_treeView refresh];
    [[NSNotificationCenter defaultCenter] postNotificationName:UQProjectDidStartNotification object:self];
    NSArray *waiting = [_waiting copy];
    [_waiting removeAllObjects];
    for (void (^block)(UDWorkspace *) in waiting) block(nil);
}

- (BOOL)applySettings:(NSDictionary *)settings error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:settings options:NSJSONWritingPrettyPrinted error:error];
    if (!data || !_workspaceFileURL || ![data writeToURL:_workspaceFileURL options:NSDataWritingAtomic error:error]) {
        if (error && !*error) *error = UQError(@"The folder has no .qworkspace to write.");
        return NO;
    }
    // still starting: once it has, again
    if (!_started) {
        __weak UQProject *weakSelf = self;
        [self whenStarted:^(UDWorkspace *workspace) { [weakSelf applySettings:settings error:NULL]; }];
        return YES;
    }
    if (_workspace) [[UDWorkspaceManager sharedManager] closeWorkspace:_workspace];
    _workspace = nil;
    _startupError = nil;
    _started = NO;
    [_tree deleteAllItems];
    _shown = nil;
    [_treeView refresh];
    [self _start];
    return YES;
}

- (void)whenStarted:(void (^)(UDWorkspace *))block {
    if (_started) block(_workspace);
    else [_waiting addObject:[block copy]];
}

- (void)dealloc {
    if (_workspace) {
        [[UDWorkspaceManager sharedManager] closeWorkspace:_workspace];
    }
}

// ---------------------------------------------------------------------------
// MARK: - URLs
// ---------------------------------------------------------------------------

/// quarry:<path>, its path's characters escaped as a URL's path's.
static NSURL *UQURLOfPath(NSString *path) {
    NSString *escaped = [path stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]];
    return [NSURL URLWithString:[NSString stringWithFormat:@"%@:%@", UQScheme, escaped]];
}

+ (NSURL *)URLOfDeclType:(NSString *)typeName name:(NSString *)name {
    return UQURLOfPath([NSString stringWithFormat:@"/%@/%@", typeName, name]);
}

+ (NSURL *)URLOfGamePath:(NSString *)path {
    return UQURLOfPath([NSString stringWithFormat:@"/%@/%@", UQFileRoot, path]);
}

+ (BOOL)parseURL:(NSURL *)url typeName:(NSString **)typeName name:(NSString **)name path:(NSString **)path {
    if (typeName) *typeName = nil;
    if (name) *name = nil;
    if (path) *path = nil;
    if (![url.scheme.lowercaseString isEqualToString:UQScheme]) return NO;
    NSString *full = url.path;
    if (![full hasPrefix:@"/"]) return NO;
    NSRange slash = [full rangeOfString:@"/" options:0 range:NSMakeRange(1, full.length - 1)];
    if (slash.location == NSNotFound || NSMaxRange(slash) >= full.length) return NO;
    NSString *root = [full substringWithRange:NSMakeRange(1, slash.location - 1)];
    NSString *rest = [full substringFromIndex:NSMaxRange(slash)];
    if ([root isEqualToString:UQFileRoot]) {
        if (path) *path = rest;
    } else {
        if (typeName) *typeName = root;
        if (name) *name = rest;
    }
    return YES;
}

// ---------------------------------------------------------------------------
// MARK: - Reading and writing (UDFileSystemProvider)
// ---------------------------------------------------------------------------

/// A file's text as an editor has it, its line ends \n.
static NSString *UQEditorText(NSString *text) {
    NSString *lf = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    return [lf stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
}

- (nullable idDeclBase *)_declOfType:(NSString *)typeName name:(NSString *)name error:(NSError **)error {
    idDeclManager *decls = _workspace.declManager;
    declType_t type = [decls declTypeFromName:typeName];
    idDeclBase *decl = (int)type >= 0 && (int)type < [decls numDeclTypes] ? [decls declByName:name type:type forceParse:YES error:error] : nil;
    if (!decl && error && !*error) *error = UQError([NSString stringWithFormat:@"There is no %@ %@.", typeName, name]);
    return decl;
}

- (NSData *)contentsOfURL:(NSURL *)url error:(NSError **)error {
    NSString *typeName, *name, *path;
    if (![UQProject parseURL:url typeName:&typeName name:&name path:&path]) {
        if (error) *error = UQError([NSString stringWithFormat:@"%@ is no Quarry URL.", url.absoluteString]);
        return nil;
    }
    if (!_workspace) {
        if (error) *error = _startupError ?: UQError(@"The game hasn't started yet.");
        return nil;
    }
    if (path) {
        void *buffer = NULL;
        NSError *failure = nil;
        int length = [_workspace.fileSystem readFile:path buffer:&buffer timestamp:NULL error:&failure];
        if (length < 0 || failure) {
            if (error) *error = failure ?: UQError([NSString stringWithFormat:@"There is no %@ in the game.", path]);
            return nil;
        }
        NSString *text = length ? [[NSString alloc] initWithBytes:buffer length:(NSUInteger)length encoding:NSUTF8StringEncoding] : @"";
        if (buffer) [_workspace.fileSystem freeFile:buffer error:nil];
        return [UQEditorText(text ?: @"") dataUsingEncoding:NSUTF8StringEncoding];
    }
    idDeclBase *decl = [self _declOfType:typeName name:name error:error];
    if (!decl) return nil;
    NSMutableData *text = [NSMutableData data];
    [decl text:text];
    NSString *string = [[NSString alloc] initWithData:text encoding:NSUTF8StringEncoding] ?: @"";
    return [UQEditorText(string) dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)writeContents:(NSData *)data toURL:(NSURL *)url error:(NSError **)error {
    NSString *typeName, *name, *path;
    if (![UQProject parseURL:url typeName:&typeName name:&name path:&path] || !_workspace) {
        if (error) *error = _startupError ?: UQError([NSString stringWithFormat:@"%@ can't be saved.", url.absoluteString]);
        return NO;
    }
    if (path) {
        // into the savepath, the mod's folder (the paks are never written)
        if ([_workspace.fileSystem writeFile:path buffer:data.bytes size:(int)data.length basePath:nil error:error] < 0) return NO;
        return YES;
    }
    idDeclBase *decl = [self _declOfType:typeName name:name error:error];
    if (!decl) return NO;
    [decl setText:[data mutableCopy]];
    if (![decl replaceSourceFileText:error]) return NO;
    [decl invalidate];
    return YES;
}

- (NSString *)languageModeOfURL:(NSURL *)url {
    NSString *path;
    [UQProject parseURL:url typeName:NULL name:NULL path:&path];
    NSString *extension = path.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"script"]) return @"idscript";
    if (path) return [[UDLanguageModeRegistry sharedRegistry] modeForFileURL:[NSURL fileURLWithPath:path]].identifier;
    return @"iddecl";
}

- (NSString *)displayNameOfURL:(NSURL *)url {
    NSString *typeName, *name, *path;
    [UQProject parseURL:url typeName:&typeName name:&name path:&path];
    return path ? path.lastPathComponent : name.lastPathComponent ?: url.lastPathComponent;
}

// ---------------------------------------------------------------------------
// MARK: - The tree (UDTreeDataProvider)
// ---------------------------------------------------------------------------

- (void)_readTree {
    [_tree deleteAllItems];
    idDeclManager *decls = _workspace.declManager;
    for (int i = 0; i < [decls numDeclTypes]; i++) {
        declType_t type = (declType_t)i;
        NSString *typeName = [decls declNameFromType:type];
        NSMutableArray<idDeclBase *> *found = [NSMutableArray array];
        for (idDeclBase *decl in [decls declsOfType:type forceParse:NO]) [found addObject:decl];
        [found sortUsingComparator:^NSComparisonResult(idDeclBase *a, idDeclBase *b) {
            return [[a name] caseInsensitiveCompare:[b name]];
        }];
        for (idDeclBase *decl in found) {
            NSString *path = [[typeName stringByAppendingString:@"/"] stringByAppendingString:decl.name];
            path = [[path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]
                       stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            [_tree addDeclToTree:path type:type declName:decl.name];
        }
    }
    for (NSArray *kind in @[ @[ @"script", @".script" ], @[ @"guis", @".gui" ] ]) {
        idFileList *files = [_workspace.fileSystem listFilesTree:kind[0] extension:kind[1] sorted:YES inGameDir:nil error:nil];
        for (int i = 0; i < [files numFiles]; i++) {
            [_tree addFileToTree:[[files fileByIndex:i] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]];
        }
        [_workspace.fileSystem freeFileList:files];
    }
    [self _applyFilter];
}

- (NSArray<UDWorkspaceItem *> *)itemsContainingText:(NSString *)query {
    NSMutableArray *found = [NSMutableArray array];
    if (!_workspace || !query.length) return found;
    UDWorkspace *workspace = _workspace;
    [UDDeclTreeWalker walkLeavesInTree:_tree usingBlock:^(UDWorkspaceItem *node, BOOL *stop) {
        if ([node matchesTextSearch:query inWorkspace:workspace]) [found addObject:node];
    }];
    return found;
}

- (NSURL *)URLOfItem:(UDWorkspaceItem *)node {
    if (node.kind == UDWorkspaceItemKindDecl) {
        UDDeclItem *decl = (UDDeclItem *)node;
        return [UQProject URLOfDeclType:[_workspace.declManager declNameFromType:decl.type] name:decl.declName];
    }
    return node.kind == UDWorkspaceItemKindFile ? [UQProject URLOfGamePath:node.path] : nil;
}

- (void)reloadTree {
    if (!_workspace) return;
    [self _readTree];
    [_treeView refresh];
}

/// What matches the filter (Quarry's: idStr_Filter's wildcards over a name).
- (void)_applyFilter {
    if (!_filter.length) {
        _shown = nil;
        return;
    }
    NSString *pattern = [_filter containsString:@"*"] || [_filter containsString:@"?"] ? _filter
                                                                                         : [NSString stringWithFormat:@"*%@*", _filter];
    _shown = [[UDPathTree alloc] init];
    [UDDeclTreeWalker filterTree:_tree intoTree:_shown withBlock:^BOOL(UDWorkspaceItem *node) {
        return idStr_Filter(pattern.UTF8String, node.name.UTF8String, NO);
    }];
}

- (NSArray *)treeView:(UDTreeViewController *)treeView childrenOfElement:(id)element {
    if (!element) {
        if (_startupError) return @[ _startupError ];
        if (!_workspace) return @[ @"Opening…" ];
        return [(_shown ?: _tree) topLevelNodes];
    }
    return [element isKindOfClass:[UDWorkspaceItem class]] ? [(UDWorkspaceItem *)element children] : @[];
}

- (UDTreeItem *)treeView:(UDTreeViewController *)treeView itemForElement:(id)element {
    if ([element isKindOfClass:[NSError class]]) {
        UDTreeItem *item = [UDTreeItem itemWithLabel:@"Not started"];
        item.toolTip = [(NSError *)element localizedDescription];
        item.detail = [(NSError *)element localizedDescription];
        return item;
    }
    if (![element isKindOfClass:[UDWorkspaceItem class]]) return [UDTreeItem itemWithLabel:[element description]];
    UDWorkspaceItem *node = element;
    UDTreeItem *item = [UDTreeItem itemWithLabel:node.name];
    if (node.kind == UDWorkspaceItemKindGroup) {
        item.collapsibleState = _shown ? UDTreeItemCollapsibleStateExpanded : UDTreeItemCollapsibleStateCollapsed;
        return item;
    }
    item.resourceURL = [self URLOfItem:node];
    item.toolTip = item.resourceURL.absoluteString;
    item.action = @selector(openResource:);
    return item;
}

- (id)treeView:(UDTreeViewController *)treeView parentOfElement:(id)element {
    UDWorkspaceItem *parent = [element isKindOfClass:[UDWorkspaceItem class]] ? [(UDWorkspaceItem *)element parent] : nil;
    return parent == (_shown ?: _tree).root ? nil : parent;
}

- (void)treeView:(UDTreeViewController *)treeView filterDidChange:(NSString *)filter {
    _filter = [filter copy] ?: @"";
    [self _applyFilter];
    [treeView refresh];
}

@end
