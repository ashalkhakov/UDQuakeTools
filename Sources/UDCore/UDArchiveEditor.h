/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDArchiveEditor — mutable working copy of a UDArchive.
 *
 * The editor wraps an immutable UDArchive, maintains an ordered list of
 * pending mutations, and projects them onto a current set of entries
 * exposed as `currentEntries`.  The original archive is never modified;
 * `revertAll` discards all pending mutations and resets to the original
 * entry list.
 */

#import <Foundation/Foundation.h>
#import "UDContentSource.h"

@class UDArchive;
@class UDArchiveEntry;
@class UDArchiveMutation;

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveEditor : NSObject {
    UDArchive                          *_archive;
    NSMutableArray<UDArchiveMutation *> *_pendingMutations;
    NSMutableArray<UDArchiveEntry *>    *_currentEntries;
}

/** The original (immutable) archive this editor wraps. */
@property (nonatomic, readonly, strong) UDArchive *archive;

/** Ordered list of mutations applied since the last save/revert. */
@property (nonatomic, readonly, copy) NSArray<UDArchiveMutation *> *pendingMutations;

/** YES once at least one mutation has been applied. */
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;

/**
 * The current projected entry list — original entries with all pending
 * mutations applied in order.
 */
@property (nonatomic, readonly, copy) NSArray<UDArchiveEntry *> *currentEntries;

- (instancetype)initWithArchive:(UDArchive *)archive NS_DESIGNATED_INITIALIZER;

/**
 * Add a new entry backed by `source` at the given archive-relative path.
 * Fails if an entry at that exact path already exists.
 */
- (BOOL)addSource:(id<UDContentSource>)source
           atPath:(NSString *)path
            error:(NSError **)error;

/**
 * Remove the entry (or all entries beneath the directory) at `path`.
 * Fails if no matching entry or directory prefix is found.
 */
- (BOOL)removeNodeAtPath:(NSString *)path
                   error:(NSError **)error;

/**
 * Move a single entry from `fromPath` to `toPath`.
 * Fails if `fromPath` does not exist or `toPath` already exists.
 */
- (BOOL)moveNodeFromPath:(NSString *)fromPath
                  toPath:(NSString *)toPath
                   error:(NSError **)error;

/**
 * Replace the content source of an existing entry at `path`.
 * Fails if no entry exists at that path.
 */
- (BOOL)replaceEntryAtPath:(NSString *)path
                withSource:(id<UDContentSource>)source
                     error:(NSError **)error;

/**
 * Read `range` bytes from the entry at `path`, consulting the staged source
 * if one is present (i.e. the entry has been replaced but not yet saved).
 */
- (nullable NSData *)contentForEntryAtPath:(NSString *)path
                                     range:(NSRange)range
                                     error:(NSError **)error;

/** Discard all pending mutations and reset to the original archive entries. */
- (void)revertAll;

@end

NS_ASSUME_NONNULL_END
