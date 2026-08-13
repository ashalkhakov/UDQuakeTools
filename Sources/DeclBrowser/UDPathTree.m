#import "UDPathTree.h"
#import "UDFolder.h"

@implementation UDPathTree

- (instancetype)init {
    self = [super init];
    if (self) {
        _root = [[UDProject alloc] initWithName:@"" path:nil];
    }
    return self;
}

- (void)deleteAllItems {
    [self.root removeAllChildren];
}

- (void)addFileToTree:(NSString *)path {
    NSArray *components = [path componentsSeparatedByString:@"/"];
    UDWorkspaceItem *current;
    NSInteger i, n;

    current = self.root;
    n = components.count;
    for (i = 0; i < n-1; i++) {
        NSString *comp = [components objectAtIndex:i];
        if (comp.length == 0) {
            continue;
        }

        UDWorkspaceItem *child = nil;
        for (UDWorkspaceItem *c in current.children) {
            if ([c.name isEqualToString:comp]) {
                child = c;
                break;
            }
        }
        if (!child) {
            child = [[UDFolder alloc] initWithName:comp path:path];
            [current addChild:child];
        }
        current = child;
    }
    
    // Leaf gets the resource
    UDFileItem *fileItem = [[UDFileItem alloc] initWithPath:path];
    [current addChild:fileItem];
}

- (void)addDeclToTree:(NSString *)path type:(declType_t)type declName:(NSString *)declName {
    NSArray *components = [path componentsSeparatedByString:@"/"];
    UDWorkspaceItem *current;
    NSInteger i, n;

    current = self.root;
    n = components.count;
    for (i = 0; i < n-1; i++) {
        NSString *comp = [components objectAtIndex:i];
        if (comp.length == 0) {
            continue;
        }

        UDWorkspaceItem *child = nil;
        for (UDWorkspaceItem *c in current.children) {
            if ([c.name isEqualToString:comp]) {
                child = c;
                break;
            }
        }
        if (!child) {
            child = [[UDFolder alloc] initWithName:comp path:path];
            [current addChild:child];
        }
        current = child;
    }
    
    // Leaf gets the resource
    UDDeclItem *declItem = [[UDDeclItem alloc] initWithType:type declName:declName path:path];
    [current addChild:declItem];
}

- (NSArray<UDWorkspaceItem *> *)topLevelNodes {
    return self.root.children;
}

@end

@implementation UDDeclTreeWalker

+ (void)walkTree:(UDPathTree *)tree
      usingBlock:(void (^)(UDWorkspaceItem *node, BOOL *stop))block
{
    if (!tree || !block) return;
    
    BOOL stop = NO;
    for (UDWorkspaceItem *top in tree.topLevelNodes) {
        [self walkNode:top block:block stop:&stop];
        if (stop) break;
    }
}

+ (void)walkLeavesInTree:(UDPathTree *)tree
              usingBlock:(void (^)(UDWorkspaceItem *node, BOOL *stop))block
{
    [self walkTree:tree usingBlock:^(UDWorkspaceItem *node, BOOL *stop) {
        if (node.kind == UDWorkspaceItemKindDecl || node.kind == UDWorkspaceItemKindFile) {
            block(node, stop);
        }
    }];
}

+ (NSInteger)filterTree:(UDPathTree *)sourceTree
               intoTree:(UDPathTree *)resultTree
              withBlock:(BOOL (^)(UDWorkspaceItem *node))test
{
    [resultTree deleteAllItems];
    __block NSInteger count = 0;
    
    [self walkLeavesInTree:sourceTree usingBlock:^(UDWorkspaceItem *node, BOOL *stop) {
        if (test(node)) {
            switch (node.kind) {
                case UDWorkspaceItemKindDecl: {
                    UDDeclItem *declItem = (UDDeclItem *)node;
                    [resultTree addDeclToTree:declItem.path type:declItem.type declName:declItem.declName];
                    count++;
                    break;
                }
                case UDWorkspaceItemKindFile:
                    [resultTree addFileToTree:((UDFileItem *)node).path];
                    count++;
                    break;
                default:
                    break; // should never happen
            }
        }
    }];
    
    return count;
}

#pragma mark - Private recursive method

+ (void)walkNode:(UDWorkspaceItem *)node
           block:(void (^)(UDWorkspaceItem *node, BOOL *stop))block
            stop:(BOOL *)stop
{
    if (*stop || !node) return;
    
    block(node, stop);
    if (*stop) return;
    
    for (UDWorkspaceItem *child in node.children) {
        [self walkNode:child block:block stop:stop];
        if (*stop) return;
    }
}

@end
