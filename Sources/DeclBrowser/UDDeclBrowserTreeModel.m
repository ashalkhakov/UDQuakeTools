/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * Decl Browser tree model.
 */

#import "UDDeclBrowserTreeModel.h"

#import "../UDCore/UDDeclModel.h"

@interface UDDeclBrowserTreeNode ()
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *fullPath;
@property (nonatomic, assign, getter=isLeaf) BOOL leaf;
@property (nullable, nonatomic, strong) UDDeclDefinition *definition;
@property (nonatomic, strong) NSMutableArray<UDDeclBrowserTreeNode *> *mutableChildren;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *mutableChildNameToFirstIndex;
@end

@implementation UDDeclBrowserTreeNode

- (instancetype)initWithName:(NSString *)name
                    fullPath:(NSString *)fullPath
                        leaf:(BOOL)leaf
                  definition:(nullable UDDeclDefinition *)definition {
    self = [super init];
    if (self) {
        _name = [name copy];
        _fullPath = [fullPath copy];
        _leaf = leaf;
        _definition = definition;
        _mutableChildren = [NSMutableArray array];
        _mutableChildNameToFirstIndex = [NSMutableDictionary dictionary];
    }
    return self;
}

- (instancetype)init {
    self = [self initWithName:@"empty" fullPath:@"empty" leaf:NO definition:nil];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

- (NSArray<UDDeclBrowserTreeNode *> *)children {
    return [self.mutableChildren copy];
}

- (void)addChild:(UDDeclBrowserTreeNode *)child {
    NSNumber *existingIndex = [self.mutableChildNameToFirstIndex objectForKey:child.name ?: @""];
    if (!existingIndex) {
        [self.mutableChildNameToFirstIndex setObject:@(self.mutableChildren.count) forKey:child.name ?: @""];
    }
    [self.mutableChildren addObject:child];
}

- (nullable NSNumber *)firstChildIndexForName:(NSString *)name {
    return [self.mutableChildNameToFirstIndex objectForKey:name ?: @""];
}

- (void)rebuildChildNameIndex {
    [self.mutableChildNameToFirstIndex removeAllObjects];
    for (NSUInteger idx = 0; idx < self.mutableChildren.count; idx++) {
        UDDeclBrowserTreeNode *child = [self.mutableChildren objectAtIndex:idx];
        NSString *childName = child.name ?: @"";
        if (![self.mutableChildNameToFirstIndex objectForKey:childName]) {
            [self.mutableChildNameToFirstIndex setObject:@((NSInteger)idx) forKey:childName];
        }
    }
}

- (NSUInteger)childCount {
    return self.mutableChildren.count;
}

- (nullable UDDeclBrowserTreeNode *)childAtIndex:(NSUInteger)index {
    if (index >= self.mutableChildren.count) {
        return nil;
    }
    return [self.mutableChildren objectAtIndex:index];
}

@end

@interface UDDeclBrowserTreeModel ()
@property (nonatomic, strong) UDDeclBrowserTreeNode *rootNode;
@property (nonatomic, strong) NSMutableDictionary<NSString *, UDDeclBrowserTreeNode *> *nodeForPrefixRowsCache;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSArray<NSNumber *> *> *selectionPathByDefinitionKey;
@end

@implementation UDDeclBrowserTreeModel

- (instancetype)init {
    self = [super init];
    if (self) {
        _rootNode = [[UDDeclBrowserTreeNode alloc] initWithName:@"" fullPath:@"" leaf:NO definition:nil];
        _nodeForPrefixRowsCache = [NSMutableDictionary dictionary];
        _selectionPathByDefinitionKey = [NSMutableDictionary dictionary];
        [_nodeForPrefixRowsCache setObject:_rootNode forKey:@"0"];
    }
    return self;
}

- (void)rebuildWithDefinitions:(NSArray<UDDeclDefinition *> *)definitions {
    self.rootNode = [[UDDeclBrowserTreeNode alloc] initWithName:@"" fullPath:@"" leaf:NO definition:nil];

    for (UDDeclDefinition *definition in definitions) {
        NSString *declType = definition.declType.length > 0 ? definition.declType : @"<unknown type>";
        UDDeclBrowserTreeNode *typeNode = [self _findOrCreateFolderWithName:declType
                                                                    fullPath:declType
                                                                      parent:self.rootNode];

        NSString *declName = definition.declName.length > 0 ? definition.declName : @"<unnamed decl>";
        NSString *trimmedDeclName = [declName stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]];
        NSArray<NSString *> *components = trimmedDeclName.length > 0 ? [trimmedDeclName componentsSeparatedByString:@"/"] : @[ @"<unnamed decl>" ];

        UDDeclBrowserTreeNode *folder = typeNode;
        NSMutableString *pathBuilder = [NSMutableString string];
        for (NSUInteger componentIndex = 0; componentIndex < components.count; componentIndex++) {
            NSString *component = [components objectAtIndex:componentIndex];
            if (component.length == 0) {
                continue;
            }

            BOOL isLeafComponent = (componentIndex == components.count - 1);
            if (isLeafComponent) {
                NSString *leafPath = trimmedDeclName.length > 0 ? trimmedDeclName : declName;
                UDDeclBrowserTreeNode *leaf = [[UDDeclBrowserTreeNode alloc] initWithName:component
                                                                                  fullPath:leafPath
                                                                                      leaf:YES
                                                                                definition:definition];
                [folder addChild:leaf];
                break;
            }

            if (pathBuilder.length > 0) {
                [pathBuilder appendString:@"/"];
            }
            [pathBuilder appendString:component];

            folder = [self _findOrCreateFolderWithName:component
                                              fullPath:[pathBuilder copy]
                                                parent:folder];
        }
    }

    [self _sortNodeRecursively:self.rootNode];
    [self _rebuildSelectionIndexes];
}

- (NSInteger)numberOfRowsInColumn:(NSInteger)column selectedRows:(NSArray<NSNumber *> *)selectedRows {
    UDDeclBrowserTreeNode *node = [self _nodeForColumn:column selectedRows:selectedRows];
    if (!node) {
        return 0;
    }
    return (NSInteger)[node childCount];
}

- (nullable UDDeclBrowserTreeNode *)nodeForRow:(NSInteger)row
                                      inColumn:(NSInteger)column
                                   selectedRows:(NSArray<NSNumber *> *)selectedRows {
    UDDeclBrowserTreeNode *parent = [self _nodeForColumn:column selectedRows:selectedRows];
    if (!parent || row < 0) {
        return nil;
    }
    return [parent childAtIndex:(NSUInteger)row];
}

- (nullable NSArray<NSNumber *> *)firstLeafSelectionPath {
    NSMutableArray<NSNumber *> *path = [NSMutableArray array];
    if ([self _appendFirstLeafPathFromNode:self.rootNode intoPath:path]) {
        return [path copy];
    }
    return nil;
}

- (nullable NSArray<NSNumber *> *)selectionPathForNodeNameChain:(NSArray<NSString *> *)nameChain {
    if (nameChain.count == 0) {
        return nil;
    }

    NSMutableArray<NSNumber *> *path = [NSMutableArray arrayWithCapacity:nameChain.count];
    UDDeclBrowserTreeNode *node = self.rootNode;

    for (NSUInteger idx = 0; idx < nameChain.count; idx++) {
        NSString *expectedName = [nameChain objectAtIndex:idx];
        NSNumber *foundIndexNumber = [node firstChildIndexForName:expectedName];
        if (!foundIndexNumber) {
            return nil;
        }

        NSUInteger foundIndex = (NSUInteger)[foundIndexNumber integerValue];
        UDDeclBrowserTreeNode *nextNode = [node childAtIndex:foundIndex];
        if (!nextNode) {
            return nil;
        }

        [path addObject:@((NSInteger)foundIndex)];
        node = nextNode;
    }

    return [path copy];
}

- (nullable NSArray<NSNumber *> *)selectionPathForDefinitionWithType:(NSString *)declType
                                                                 name:(NSString *)declName
                                                           sourcePath:(NSString *)sourcePath {
    NSString *definitionKey = [self _definitionKeyForType:declType name:declName sourcePath:sourcePath];
    NSArray<NSNumber *> *path = [self.selectionPathByDefinitionKey objectForKey:definitionKey];
    return [path copy];
}

- (UDDeclBrowserTreeNode *)_findOrCreateFolderWithName:(NSString *)name
                                               fullPath:(NSString *)fullPath
                                                 parent:(UDDeclBrowserTreeNode *)parent {
    for (UDDeclBrowserTreeNode *child in parent.children) {
        if (!child.isLeaf && [child.name isEqualToString:name]) {
            return child;
        }
    }

    UDDeclBrowserTreeNode *folder = [[UDDeclBrowserTreeNode alloc] initWithName:name
                                                                        fullPath:fullPath
                                                                            leaf:NO
                                                                      definition:nil];
    [parent addChild:folder];
    return folder;
}

- (void)_sortNodeRecursively:(UDDeclBrowserTreeNode *)node {
    [node.mutableChildren sortUsingComparator:^NSComparisonResult(UDDeclBrowserTreeNode *a, UDDeclBrowserTreeNode *b) {
        if (a.isLeaf != b.isLeaf) {
            return a.isLeaf ? NSOrderedDescending : NSOrderedAscending;
        }
        return [a.name localizedCaseInsensitiveCompare:b.name];
    }];
    [node rebuildChildNameIndex];

    for (UDDeclBrowserTreeNode *child in node.children) {
        if (!child.isLeaf) {
            [self _sortNodeRecursively:child];
        }
    }
}

- (nullable UDDeclBrowserTreeNode *)_nodeForColumn:(NSInteger)column selectedRows:(NSArray<NSNumber *> *)selectedRows {
    if (column < 0) {
        return nil;
    }

    NSString *targetKey = [self _prefixCacheKeyForSelectedRows:selectedRows levelCount:column];
    UDDeclBrowserTreeNode *cachedNode = [self.nodeForPrefixRowsCache objectForKey:targetKey];
    if (cachedNode) {
        return cachedNode;
    }

    UDDeclBrowserTreeNode *node = self.rootNode;
    NSMutableArray<NSNumber *> *prefixRows = [NSMutableArray arrayWithCapacity:(NSUInteger)column];
    for (NSInteger level = 0; level < column; level++) {
        if (level >= (NSInteger)selectedRows.count) {
            return nil;
        }

        NSInteger selectedRow = [[selectedRows objectAtIndex:(NSUInteger)level] integerValue];
        if (selectedRow < 0) {
            return nil;
        }

        UDDeclBrowserTreeNode *nextNode = [node childAtIndex:(NSUInteger)selectedRow];
        if (!nextNode || nextNode.isLeaf) {
            return nil;
        }

        node = nextNode;
        [prefixRows addObject:@(selectedRow)];
        NSString *prefixKey = [self _prefixCacheKeyForSelectedRows:prefixRows levelCount:prefixRows.count];
        [self.nodeForPrefixRowsCache setObject:node forKey:prefixKey];
    }

    [self.nodeForPrefixRowsCache setObject:node forKey:targetKey];
    return node;
}

- (BOOL)_appendFirstLeafPathFromNode:(UDDeclBrowserTreeNode *)node intoPath:(NSMutableArray<NSNumber *> *)path {
    NSArray<UDDeclBrowserTreeNode *> *children = node.children;
    for (NSUInteger idx = 0; idx < children.count; idx++) {
        UDDeclBrowserTreeNode *child = [children objectAtIndex:idx];
        [path addObject:@((NSInteger)idx)];
        if (child.isLeaf) {
            return YES;
        }
        if ([self _appendFirstLeafPathFromNode:child intoPath:path]) {
            return YES;
        }
        [path removeLastObject];
    }
    return NO;
}

- (NSString *)_definitionKeyForType:(NSString *)declType
                               name:(NSString *)declName
                         sourcePath:(NSString *)sourcePath {
    NSString *safeType = declType ?: @"";
    NSString *safeName = declName ?: @"";
    NSString *safePath = sourcePath ?: @"";
    return [NSString stringWithFormat:@"%@\n%@\n%@", safeType, safeName, safePath];
}

- (NSString *)_prefixCacheKeyForSelectedRows:(NSArray<NSNumber *> *)selectedRows levelCount:(NSInteger)levelCount {
    if (levelCount <= 0) {
        return @"0";
    }

    NSMutableString *key = [NSMutableString stringWithCapacity:(NSUInteger)(levelCount * 4)];
    [key appendString:@"0"];
    NSInteger safeCount = MIN(levelCount, (NSInteger)selectedRows.count);
    for (NSInteger idx = 0; idx < safeCount; idx++) {
        NSInteger row = [[selectedRows objectAtIndex:(NSUInteger)idx] integerValue];
        [key appendFormat:@"/%ld", (long)row];
    }
    return [key copy];
}

- (void)_rebuildSelectionIndexes {
    [self.nodeForPrefixRowsCache removeAllObjects];
    [self.nodeForPrefixRowsCache setObject:self.rootNode forKey:@"0"];

    [self.selectionPathByDefinitionKey removeAllObjects];
    NSMutableArray<NSNumber *> *path = [NSMutableArray array];
    [self _indexDefinitionsFromNode:self.rootNode path:path];
}

- (void)_indexDefinitionsFromNode:(UDDeclBrowserTreeNode *)node path:(NSMutableArray<NSNumber *> *)path {
    NSArray<UDDeclBrowserTreeNode *> *children = node.children;
    for (NSUInteger idx = 0; idx < children.count; idx++) {
        UDDeclBrowserTreeNode *child = [children objectAtIndex:idx];
        [path addObject:@((NSInteger)idx)];

        if (child.isLeaf && child.definition) {
            NSString *key = [self _definitionKeyForType:child.definition.declType
                                                   name:child.definition.declName
                                             sourcePath:child.definition.sourceVirtualPath];
            if (![self.selectionPathByDefinitionKey objectForKey:key]) {
                [self.selectionPathByDefinitionKey setObject:[path copy] forKey:key];
            }
        } else {
            [self _indexDefinitionsFromNode:child path:path];
        }

        [path removeLastObject];
    }
}

@end
