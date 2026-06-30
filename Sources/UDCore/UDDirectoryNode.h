/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDirectoryNode — runtime archive tree node.
 */

#import <Foundation/Foundation.h>

@class UDArchiveEntry;

NS_ASSUME_NONNULL_BEGIN

@interface UDDirectoryNode : NSObject {
    NSString *_name;
    __unsafe_unretained UDDirectoryNode *_parent;
    NSMutableArray<UDDirectoryNode *> *_directoryChildren;
    NSMutableArray<UDArchiveEntry *> *_fileChildren;
}

/** Full path from the archive root (e.g. @"maps/dm").  Empty for the root node. */
@property (nonatomic, readonly, copy) NSString *path;

/** The single path component represented by this node (e.g. @"dm"). Empty for root. */
@property (nonatomic, readonly, copy) NSString *name;

/** Weak backlink to the owning parent directory. Nil for the root node. */
@property (nonatomic, readonly, assign, nullable) UDDirectoryNode *parent;

/** Sorted child directories. */
@property (nonatomic, readonly, copy) NSArray<UDDirectoryNode *> *directoryChildren;

/** Sorted child file entries. */
@property (nonatomic, readonly, copy) NSArray<UDArchiveEntry *> *fileChildren;

/**
 * Ordered children of this directory.
 * Each element is either a UDDirectoryNode (sub-directory) or a
 * UDArchiveEntry (file leaf).  Directories sort before files; within each
 * group the order is case-insensitive alphabetical.
 */
@property (nonatomic, readonly, copy) NSArray *children;

/** Create an empty root node. */
+ (instancetype)rootNode;

/** Build a root UDDirectoryNode from a flat array of UDArchiveEntry objects. */
+ (instancetype)rootNodeFromEntries:(NSArray<UDArchiveEntry *> *)entries;

- (instancetype)initRootNode;
- (instancetype)initWithName:(NSString *)name parent:(nullable UDDirectoryNode *)parent;

- (nullable UDDirectoryNode *)directoryAtRelativePath:(NSString *)path;
- (UDDirectoryNode *)ensureDirectoryAtRelativePath:(NSString *)path;
- (nullable UDArchiveEntry *)entryAtRelativePath:(NSString *)path;

- (void)addDirectoryChild:(UDDirectoryNode *)directoryNode;
- (void)addFileChild:(UDArchiveEntry *)entry;
- (void)removeDirectoryChild:(UDDirectoryNode *)directoryNode;
- (void)removeFileChild:(UDArchiveEntry *)entry;

- (NSArray<UDArchiveEntry *> *)allEntries;
- (UDDirectoryNode *)deepCopy;

@end

NS_ASSUME_NONNULL_END
