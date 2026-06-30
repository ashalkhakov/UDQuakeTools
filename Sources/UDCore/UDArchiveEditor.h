/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDArchiveEditor — mutable working copy of a UDArchive.
 */

#import <Foundation/Foundation.h>
#import "UDContentSource.h"

@class UDArchive;
@class UDArchiveEntry;
@class UDArchiveMutation;
@class UDDirectoryNode;

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString *const UDArchiveEditorDidChangeNotification;

@interface UDArchiveEditor : NSObject {
    UDArchive *_archive;
    UDDirectoryNode *_originalRoot;
    UDDirectoryNode *_currentRoot;
    NSUndoManager *_undoManager;
    NSArray<UDArchiveMutation *> *_cachedCurrentDiff;
    BOOL _diffDirty;
}

@property (nonatomic, readonly, strong) UDArchive *archive;
/** Compatibility alias for the net diff. */
@property (nonatomic, readonly, copy) NSArray<UDArchiveMutation *> *pendingMutations;
@property (nonatomic, readonly, strong) UDDirectoryNode *originalRoot;
@property (nonatomic, readonly, strong) UDDirectoryNode *currentRoot;
@property (nonatomic, readonly, strong) NSUndoManager *undoManager;
@property (nonatomic, readonly, getter=isDirty) BOOL dirty;
@property (nonatomic, readonly, copy) NSArray<UDArchiveEntry *> *currentEntries;

/**
 * Compute a best-effort diff from originalRoot to currentRoot.
 * The result collapses transient edits and represents the net archive delta.
 */
@property (nonatomic, readonly, copy) NSArray<UDArchiveMutation *> *currentDiff;

- (instancetype)initWithArchive:(UDArchive *)archive;

- (BOOL)addSource:(id<UDContentSource>)source
           atPath:(NSString *)path
            error:(NSError **)error;

- (BOOL)removeNodeAtPath:(NSString *)path
                   error:(NSError **)error;

- (BOOL)moveNodeFromPath:(NSString *)fromPath
                  toPath:(NSString *)toPath
                   error:(NSError **)error;

- (BOOL)replaceEntryAtPath:(NSString *)path
                withSource:(id<UDContentSource>)source
                     error:(NSError **)error;

- (nullable NSData *)contentForEntryAtPath:(NSString *)path
                                     range:(NSRange)range
                                     error:(NSError **)error;

- (NSArray<UDArchiveMutation *> *)currentDiff;

- (void)revertAll;

@end

NS_ASSUME_NONNULL_END
