/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDDirectoryNode.h"
#import "UDArchiveEntry.h"

@interface UDDirectoryNode ()
- (instancetype)_initWithName:(NSString *)name parent:(nullable UDDirectoryNode *)parent;
@end

@implementation UDDirectoryNode

@synthesize name = _name;
@synthesize parent = _parent;
@synthesize directoryChildren = _directoryChildren;
@synthesize fileChildren = _fileChildren;

static NSComparisonResult UDSortDirectoriesByName(UDDirectoryNode *a, UDDirectoryNode *b, void *context) {
    (void)context;
    return [a.name caseInsensitiveCompare:b.name];
}

static NSComparisonResult UDSortEntriesByName(UDArchiveEntry *a, UDArchiveEntry *b, void *context) {
    (void)context;
    return [a.name caseInsensitiveCompare:b.name];
}

static NSString *UDNormalizeRelativeArchivePath(NSString *path) {
    return [[path ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] copy];
}

- (instancetype)initRootNode {
    return [self _initWithName:@"" parent:nil];
}

- (instancetype)initWithName:(NSString *)name parent:(UDDirectoryNode *)parent {
    return [self _initWithName:name parent:parent];
}

- (instancetype)_initWithName:(NSString *)name parent:(UDDirectoryNode *)parent {
    self = [super init];
    if (!self) {
        return nil;
    }

    _name = [name copy] ?: @"";
    _parent = parent;
    _directoryChildren = [NSMutableArray array];
    _fileChildren = [NSMutableArray array];
    return self;
}

+ (instancetype)rootNode {
    return [[self alloc] initRootNode];
}

- (NSString *)path {
    if (!self.parent) {
        return @"";
    }

    NSString *parentPath = self.parent.path;
    if (parentPath.length == 0) {
        return self.name;
    }
    return [parentPath stringByAppendingFormat:@"/%@", self.name];
}

- (NSArray<UDDirectoryNode *> *)directoryChildren {
    return [_directoryChildren sortedArrayUsingFunction:UDSortDirectoriesByName context:NULL];
}

- (NSArray<UDArchiveEntry *> *)fileChildren {
    return [_fileChildren sortedArrayUsingFunction:UDSortEntriesByName context:NULL];
}

- (NSArray *)children {
    NSMutableArray *combined = [NSMutableArray arrayWithArray:self.directoryChildren];
    [combined addObjectsFromArray:self.fileChildren];
    return combined;
}

+ (instancetype)rootNodeFromEntries:(NSArray<UDArchiveEntry *> *)entries {
    UDDirectoryNode *root = [self rootNode];
    for (UDArchiveEntry *entry in entries) {
        NSString *normalizedPath = UDNormalizeRelativeArchivePath(entry.path);
        if (normalizedPath.length == 0) {
            continue;
        }

        NSString *parentPath = [normalizedPath stringByDeletingLastPathComponent];
        if ([parentPath isEqualToString:@"."]) {
            parentPath = @"";
        }

        UDDirectoryNode *parent = [root ensureDirectoryAtRelativePath:parentPath];
        [parent addFileChild:entry];
    }
    return root;
}

- (nullable UDDirectoryNode *)_directoryNamed:(NSString *)name {
    for (UDDirectoryNode *child in _directoryChildren) {
        if ([child.name isEqualToString:name]) {
            return child;
        }
    }
    return nil;
}

- (nullable UDArchiveEntry *)_fileNamed:(NSString *)name {
    for (UDArchiveEntry *entry in _fileChildren) {
        if ([entry.name isEqualToString:name]) {
            return entry;
        }
    }
    return nil;
}

- (nullable UDDirectoryNode *)directoryAtRelativePath:(NSString *)path {
    NSString *normalized = UDNormalizeRelativeArchivePath(path);
    if (normalized.length == 0) {
        return self;
    }

    UDDirectoryNode *node = self;
    for (NSString *component in [normalized pathComponents]) {
        node = [node _directoryNamed:component];
        if (!node) {
            return nil;
        }
    }
    return node;
}

- (UDDirectoryNode *)ensureDirectoryAtRelativePath:(NSString *)path {
    NSString *normalized = UDNormalizeRelativeArchivePath(path);
    if (normalized.length == 0) {
        return self;
    }

    UDDirectoryNode *node = self;
    for (NSString *component in [normalized pathComponents]) {
        UDDirectoryNode *child = [node _directoryNamed:component];
        if (!child) {
            child = [[UDDirectoryNode alloc] initWithName:component parent:node];
            [node addDirectoryChild:child];
        }
        node = child;
    }
    return node;
}

- (nullable UDArchiveEntry *)entryAtRelativePath:(NSString *)path {
    NSString *normalized = UDNormalizeRelativeArchivePath(path);
    if (normalized.length == 0) {
        return nil;
    }

    NSString *parentPath = [normalized stringByDeletingLastPathComponent];
    if ([parentPath isEqualToString:@"."]) {
        parentPath = @"";
    }

    UDDirectoryNode *parent = [self directoryAtRelativePath:parentPath];
    if (!parent) {
        return nil;
    }
    return [parent _fileNamed:normalized.lastPathComponent];
}

- (void)addDirectoryChild:(UDDirectoryNode *)directoryNode {
    if (!directoryNode || [_directoryChildren containsObject:directoryNode]) {
        return;
    }

    directoryNode->_parent = self;
    [_directoryChildren addObject:directoryNode];
}

- (void)addFileChild:(UDArchiveEntry *)entry {
    if (!entry || [_fileChildren containsObject:entry]) {
        return;
    }

    entry.parent = self;
    [_fileChildren addObject:entry];
}

- (void)removeDirectoryChild:(UDDirectoryNode *)directoryNode {
    if (!directoryNode) {
        return;
    }

    [_directoryChildren removeObject:directoryNode];
    directoryNode->_parent = nil;
}

- (void)removeFileChild:(UDArchiveEntry *)entry {
    if (!entry) {
        return;
    }

    [_fileChildren removeObject:entry];
    entry.parent = nil;
}

- (NSArray<UDArchiveEntry *> *)allEntries {
    NSMutableArray<UDArchiveEntry *> *entries = [NSMutableArray array];
    for (UDDirectoryNode *directory in self.directoryChildren) {
        [entries addObjectsFromArray:[directory allEntries]];
    }
    [entries addObjectsFromArray:self.fileChildren];
    return entries;
}

- (UDDirectoryNode *)deepCopy {
    UDDirectoryNode *copy = [UDDirectoryNode rootNode];
    for (UDArchiveEntry *entry in [self allEntries]) {
        UDArchiveEntry *entryCopy = [entry entryByCopyingWithPath:entry.path
                                                    contentSource:entry.contentSource
                                                       modifiedAt:entry.modifiedAt];
        NSString *parentPath = [entry.path stringByDeletingLastPathComponent];
        if ([parentPath isEqualToString:@"."]) {
            parentPath = @"";
        }

        UDDirectoryNode *parent = [copy ensureDirectoryAtRelativePath:parentPath];
        [parent addFileChild:entryCopy];
    }
    return copy;
}

@end
