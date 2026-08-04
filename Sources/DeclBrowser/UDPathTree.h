//
//  UDPathTree.h
//  PakManager
//
//  Created by artyom on 8/2/26.
//

#import <Foundation/Foundation.h>

#define DECLTYPE_SHIFT     24
#define DECLINDEX_MASK     (1 << DECLTYPE_SHIFT) - 1
#define DECLTYPE_SCRIPT    126
#define DECLTYPE_GUI       127

#define GetIdFromTypeAndIndex(type, index)  (((int)(type) << DECLTYPE_SHIFT) | (index))
#define GetTypeFromId(id)                   ((declType_t)((int)(id) >> DECLTYPE_SHIFT))
#define GetIndexFromId(id)                  ((int)(id) & DECLINDEX_MASK)

@interface UDDeclTreeNode : NSObject
@property (copy)   NSString *title;
@property (strong) NSString *fullPath;
@property (assign) NSInteger encodedId;
@property (strong) NSMutableArray<UDDeclTreeNode *> *children;
@property (weak)   UDDeclTreeNode *parent;
@end

@interface UDPathTree : NSObject
@property (strong) UDDeclTreeNode *root;
- (void)deleteAllItems;
- (void)addPathToTree:(NSString *)path encodedId:(NSInteger)encodedId;
- (NSArray<UDDeclTreeNode *> *)topLevelNodes;   // the children of root
@end

@interface UDDeclTreeWalker : NSObject

/**
 * Walks every node in the tree (depth-first).
 * fullPath is the path built from the root (using "/").
 * Set *stop = YES to abort early.
 */
+ (void)walkTree:(UDPathTree *)tree
      usingBlock:(void (^)(UDDeclTreeNode *node, BOOL *stop))block;

/**
 * Walks only the leaf nodes.
 */
+ (void)walkLeavesInTree:(UDPathTree *)tree
              usingBlock:(void (^)(UDDeclTreeNode *node, BOOL *stop))block;

/**
 * Builds a new filtered tree containing only the nodes that pass the test.
 * Returns the number of matching leaves.
 */
+ (NSInteger)filterTree:(UDPathTree *)sourceTree
               intoTree:(UDPathTree *)resultTree
              withBlock:(BOOL (^)(UDDeclTreeNode *node))test;

@end
