//
//  UDPathTree.m
//  PakManager
//
//  Created by artyom on 8/2/26.
//

#import "UDPathTree.h"

@implementation UDDeclTreeNode
- (instancetype)init {
    self = [super init];
    if (self) {
        _children = [NSMutableArray array];
        _encodedId = -1;
    }
    return self;
}
@end

@implementation UDPathTree

- (instancetype)init {
    self = [super init];
    if (self) {
        _root = [[UDDeclTreeNode alloc] init];
        _root.title = @"";
    }
    return self;
}

- (void)deleteAllItems {
    [self.root.children removeAllObjects];
}

- (void)addPathToTree:(NSString *)path encodedId:(NSInteger)encodedId {
    // Direct equivalent of PathTreeCtrl::AddPathToTree
    NSArray *components = [path componentsSeparatedByString:@"/"];
    UDDeclTreeNode *current = self.root;
    
    for (NSString *comp in components) {
        if (comp.length == 0) continue;
        
        UDDeclTreeNode *child = nil;
        for (UDDeclTreeNode *c in current.children) {
            if ([c.title isEqualToString:comp]) {
                child = c;
                break;
            }
        }
        
        if (!child) {
            child = [[UDDeclTreeNode alloc] init];
            child.fullPath = path;
            child.title = comp;
            child.parent = current;
            [current.children addObject:child];
        }
        current = child;
    }
    
    current.encodedId = encodedId;   // leaf stores the id
}

- (NSArray<UDDeclTreeNode *> *)topLevelNodes {
    return self.root.children;
}

@end

@implementation UDDeclTreeWalker

+ (void)walkTree:(UDPathTree *)tree
      usingBlock:(void (^)(UDDeclTreeNode *node, BOOL *stop))block
{
    if (!tree || !block) return;
    
    BOOL stop = NO;
    for (UDDeclTreeNode *top in tree.topLevelNodes) {
        [self walkNode:top block:block stop:&stop];
        if (stop) break;
    }
}

+ (void)walkLeavesInTree:(UDPathTree *)tree
              usingBlock:(void (^)(UDDeclTreeNode *node, BOOL *stop))block
{
    [self walkTree:tree usingBlock:^(UDDeclTreeNode *node, BOOL *stop) {
        if (node.children.count == 0) {
            block(node, stop);
        }
    }];
}

+ (NSInteger)filterTree:(UDPathTree *)sourceTree
               intoTree:(UDPathTree *)resultTree
              withBlock:(BOOL (^)(UDDeclTreeNode *node))test
{
    [resultTree deleteAllItems];
    __block NSInteger count = 0;
    
    [self walkLeavesInTree:sourceTree usingBlock:^(UDDeclTreeNode *node, BOOL *stop) {
        if (test(node)) {
            [resultTree addPathToTree:node.fullPath encodedId:node.encodedId];
            count++;
        }
    }];
    
    return count;
}

#pragma mark - Private recursive method

+ (void)walkNode:(UDDeclTreeNode *)node
           block:(void (^)(UDDeclTreeNode *node, BOOL *stop))block
            stop:(BOOL *)stop
{
    if (*stop || !node) return;
    
    block(node, stop);
    if (*stop) return;
    
    for (UDDeclTreeNode *child in node.children) {
        [self walkNode:child block:block stop:stop];
        if (*stop) return;
    }
}

@end
