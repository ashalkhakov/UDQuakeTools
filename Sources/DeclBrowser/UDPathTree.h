#import <Foundation/Foundation.h>
#import "UDProject.h"
#import "UDFileItem.h"
#import "UDDeclItem.h"

@interface UDPathTree : NSObject

@property (strong) UDProject *root;

- (void)deleteAllItems;
- (void)addFileToTree:(NSString *)path;
- (void)addDeclToTree:(NSString *)path type:(declType_t)type declName:(NSString *)declName;
- (NSArray<UDWorkspaceItem *> *)topLevelNodes;   // the children of root

@end

@interface UDDeclTreeWalker : NSObject

/**
 * Walks every node in the tree (depth-first).
 * fullPath is the path built from the root (using "/").
 * Set *stop = YES to abort early.
 */
+ (void)walkTree:(UDPathTree *)tree
      usingBlock:(void (^)(UDWorkspaceItem *node, BOOL *stop))block;

/**
 * Walks only the leaf nodes.
 */
+ (void)walkLeavesInTree:(UDPathTree *)tree
              usingBlock:(void (^)(UDWorkspaceItem *node, BOOL *stop))block;

/**
 * Builds a new filtered tree containing only the nodes that pass the test.
 * Returns the number of matching leaves.
 */
+ (NSInteger)filterTree:(UDPathTree *)sourceTree
               intoTree:(UDPathTree *)resultTree
              withBlock:(BOOL (^)(UDWorkspaceItem *node))test;

@end
