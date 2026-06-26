/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDDirectoryNode.h"
#import "UDArchiveEntry.h"

@interface UDDirectoryNode ()
- (instancetype)initWithPath:(NSString *)path
                        name:(NSString *)name
                    children:(NSArray *)children NS_DESIGNATED_INITIALIZER;
@end

@implementation UDDirectoryNode

@synthesize path     = _path;
@synthesize name     = _name;
@synthesize children = _children;

- (instancetype)initWithPath:(NSString *)path
                        name:(NSString *)name
                    children:(NSArray *)children {
    self = [super init];
    if (!self) {
        return nil;
    }
    _path     = [path copy];
    _name     = [name copy];
    _children = [children copy];
    return self;
}

/* ------------------------------------------------------------------ */
#pragma mark - Public factory

+ (instancetype)rootNodeFromEntries:(NSArray<UDArchiveEntry *> *)entries {
    return [self _buildNodeAtPath:@"" name:@"" fromEntries:entries];
}

/* ------------------------------------------------------------------ */
#pragma mark - Private recursive builder

+ (instancetype)_buildNodeAtPath:(NSString *)nodePath
                            name:(NSString *)nodeName
                     fromEntries:(NSArray<UDArchiveEntry *> *)allEntries {
    NSMutableArray *fileChildren = [NSMutableArray array];
    /* Map of first-level sub-directory name → entries that live beneath it. */
    NSMutableDictionary<NSString *, NSMutableArray<UDArchiveEntry *> *> *dirMap =
        [NSMutableDictionary dictionary];

    NSString *prefix = (nodePath.length > 0) ? [nodePath stringByAppendingString:@"/"] : @"";

    for (UDArchiveEntry *entry in allEntries) {
        NSString *relative = entry.path;

        /* Strip the node's own path prefix. */
        if (prefix.length > 0) {
            if (![relative hasPrefix:prefix]) {
                continue;
            }
            relative = [relative substringFromIndex:prefix.length];
        }

        /* Locate the next '/' separator. */
        NSRange slashRange = [relative rangeOfString:@"/"];
        if (slashRange.location == NSNotFound) {
            /* Direct file child of this node. */
            [fileChildren addObject:entry];
        } else {
            /* Entry lives in a sub-directory of this node. */
            NSString *dirName = [relative substringToIndex:slashRange.location];
            NSMutableArray *dirArray = [dirMap objectForKey:dirName];
            if (!dirArray) {
                dirArray = [NSMutableArray array];
                [dirMap setObject:dirArray forKey:dirName];
            }
            [dirArray addObject:entry];
        }
    }

    /* Recursively build sub-directory nodes, sorted alphabetically. */
    NSArray<NSString *> *sortedDirNames =
        [[dirMap allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];

    NSMutableArray *children = [NSMutableArray array];
    for (NSString *dirName in sortedDirNames) {
        NSString *childPath = (nodePath.length > 0)
            ? [nodePath stringByAppendingFormat:@"/%@", dirName]
            : dirName;
        UDDirectoryNode *child = [self _buildNodeAtPath:childPath
                                                   name:dirName
                                            fromEntries:allEntries];
        [children addObject:child];
    }

    /* Append file leaves, sorted by name. */
    NSArray *sortedFiles = [fileChildren sortedArrayUsingComparator:
        ^NSComparisonResult(UDArchiveEntry *a, UDArchiveEntry *b) {
            return [a.name caseInsensitiveCompare:b.name];
        }];
    [children addObjectsFromArray:sortedFiles];

    return [[UDDirectoryNode alloc] initWithPath:nodePath name:nodeName children:children];
}

@end
