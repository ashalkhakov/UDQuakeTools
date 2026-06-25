/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDDirectoryNode — virtual directory tree built from a flat entry list.
 *
 * Each node represents one directory level.  Leaf entries (files) are
 * represented by UDArchiveEntry objects stored directly in `children`.
 * Sub-directory entries are represented by nested UDDirectoryNode objects.
 *
 * Children are sorted: directories first (alphabetical), then files
 * (alphabetical).  This ordering is stable across reload calls.
 */

#import <Foundation/Foundation.h>

@class UDArchiveEntry;

NS_ASSUME_NONNULL_BEGIN

@interface UDDirectoryNode : NSObject {
    NSString *_path;
    NSString *_name;
    NSArray  *_children;
}

/** Full path from the archive root (e.g. @"maps/dm").  Empty for the root node. */
@property (nonatomic, readonly, copy) NSString *path;

/** The single path component represented by this node (e.g. @"dm").  Empty for root. */
@property (nonatomic, readonly, copy) NSString *name;

/**
 * Ordered children of this directory.
 * Each element is either a UDDirectoryNode (sub-directory) or a
 * UDArchiveEntry (file leaf).  Directories sort before files; within each
 * group the order is case-insensitive alphabetical.
 */
@property (nonatomic, readonly, copy) NSArray *children;

/**
 * Build a root UDDirectoryNode from a flat array of UDArchiveEntry objects.
 * The returned node has path="" and name="" and contains the full tree.
 */
+ (instancetype)rootNodeFromEntries:(NSArray<UDArchiveEntry *> *)entries;

@end

NS_ASSUME_NONNULL_END
