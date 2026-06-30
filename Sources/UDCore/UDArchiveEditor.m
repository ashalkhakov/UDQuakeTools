/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDArchiveEditor.h"
#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDArchiveMutation.h"
#import "UDDirectoryNode.h"

static NSString *const UDArchiveEditorErrorDomain = @"com.udquake.error.archive-editor";
NSString *const UDArchiveEditorDidChangeNotification = @"UDArchiveEditorDidChangeNotification";

typedef NS_ENUM(NSInteger, UDArchiveEditorErrorCode) {
    UDArchiveEditorErrorCodePathAlreadyExists = 1,
    UDArchiveEditorErrorCodePathNotFound = 2,
    UDArchiveEditorErrorCodeTargetPathExists = 3,
};

static NSString *UDArchiveNormalizePath(NSString *path) {
    return [[path ?: @"" stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"/"]] copy];
}

@interface UDArchiveEditor ()
- (nullable UDArchiveEntry *)_entryAtPath:(NSString *)path inRoot:(UDDirectoryNode *)root;
- (NSArray<UDArchiveEntry *> *)_entriesUnderPath:(NSString *)path inRoot:(UDDirectoryNode *)root;
- (BOOL)_insertEntry:(UDArchiveEntry *)entry intoRoot:(UDDirectoryNode *)root error:(NSError **)error;
- (void)_removeEmptyAncestorDirectoriesStartingAtNode:(UDDirectoryNode *)node;
- (NSArray<UDArchiveEntry *> *)_copiedEntries:(NSArray<UDArchiveEntry *> *)entries;
- (void)_restoreEntriesForUndo:(NSArray<UDArchiveEntry *> *)entries;
- (void)_removeEntriesForUndo:(NSArray<UDArchiveEntry *> *)entries;
- (void)_invalidateCurrentDiff;
- (void)_notifyDidChange;
- (BOOL)_entriesMatchForDiff:(UDArchiveEntry *)lhs rhs:(UDArchiveEntry *)rhs;
@end

@implementation UDArchiveEditor

@synthesize archive = _archive;
@synthesize originalRoot = _originalRoot;
@synthesize currentRoot = _currentRoot;
@synthesize undoManager = _undoManager;

- (instancetype)initWithArchive:(UDArchive *)archive {
    NSParameterAssert(archive != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _archive = archive;
    _originalRoot = [archive.rootNode deepCopy];
    _currentRoot = [archive.rootNode deepCopy];
    _undoManager = [[NSUndoManager alloc] init];
    _diffDirty = YES;
    return self;
}

- (BOOL)isDirty {
    return (self.currentDiff.count > 0);
}

- (NSArray<UDArchiveMutation *> *)pendingMutations {
    return [self currentDiff];
}

- (NSArray<UDArchiveEntry *> *)currentEntries {
    return [self.currentRoot allEntries];
}

- (NSArray<UDArchiveMutation *> *)currentDiff {
    if (!_diffDirty && _cachedCurrentDiff) {
        return _cachedCurrentDiff;
    }

    NSMutableDictionary<NSString *, UDArchiveEntry *> *originalByPath = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSString *, UDArchiveEntry *> *currentByPath = [NSMutableDictionary dictionary];
    NSMutableArray<UDArchiveMutation *> *diff = [NSMutableArray array];
    NSMutableArray<UDArchiveEntry *> *unmatchedOriginal = [NSMutableArray array];
    NSMutableArray<UDArchiveEntry *> *unmatchedCurrent = [NSMutableArray array];

    for (UDArchiveEntry *entry in [self.originalRoot allEntries]) {
        [originalByPath setObject:entry forKey:entry.path];
    }
    for (UDArchiveEntry *entry in [self.currentRoot allEntries]) {
        [currentByPath setObject:entry forKey:entry.path];
    }

    for (NSString *path in originalByPath) {
        UDArchiveEntry *originalEntry = [originalByPath objectForKey:path];
        UDArchiveEntry *currentEntry = [currentByPath objectForKey:path];
        if (!currentEntry) {
            [unmatchedOriginal addObject:originalEntry];
            continue;
        }

        if (![self _entriesMatchForDiff:originalEntry rhs:currentEntry]) {
            NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:path forKey:@"path"];
            if (currentEntry.contentSource) {
                [payload setObject:currentEntry.contentSource forKey:@"source"];
            }
            [diff addObject:[[UDArchiveMutation alloc] initWithKind:@"replace"
                                                            payload:payload]];
        }
    }

    for (NSString *path in currentByPath) {
        if (![originalByPath objectForKey:path]) {
            [unmatchedCurrent addObject:[currentByPath objectForKey:path]];
        }
    }

    NSMutableIndexSet *matchedOriginalIndexes = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *matchedCurrentIndexes = [NSMutableIndexSet indexSet];
    for (NSUInteger currentIndex = 0; currentIndex < unmatchedCurrent.count; currentIndex++) {
        UDArchiveEntry *currentEntry = [unmatchedCurrent objectAtIndex:currentIndex];
        for (NSUInteger originalIndex = 0; originalIndex < unmatchedOriginal.count; originalIndex++) {
            if ([matchedOriginalIndexes containsIndex:originalIndex]) {
                continue;
            }

            UDArchiveEntry *originalEntry = [unmatchedOriginal objectAtIndex:originalIndex];
            if (originalEntry.contentSource != currentEntry.contentSource) {
                continue;
            }
            if (![originalEntry.contentType isEqualToString:currentEntry.contentType]) {
                continue;
            }

            [diff addObject:[[UDArchiveMutation alloc] initWithKind:@"move"
                                                            payload:@{ @"fromPath" : originalEntry.path,
                                                                       @"toPath" : currentEntry.path }]];
            [matchedOriginalIndexes addIndex:originalIndex];
            [matchedCurrentIndexes addIndex:currentIndex];
            break;
        }
    }

    for (NSUInteger index = 0; index < unmatchedCurrent.count; index++) {
        if ([matchedCurrentIndexes containsIndex:index]) {
            continue;
        }
        UDArchiveEntry *entry = [unmatchedCurrent objectAtIndex:index];
        NSMutableDictionary *payload = [NSMutableDictionary dictionaryWithObject:entry.path forKey:@"path"];
        if (entry.contentSource) {
            [payload setObject:entry.contentSource forKey:@"source"];
        }
        [diff addObject:[[UDArchiveMutation alloc] initWithKind:@"add"
                                                        payload:payload]];
    }

    for (NSUInteger index = 0; index < unmatchedOriginal.count; index++) {
        if ([matchedOriginalIndexes containsIndex:index]) {
            continue;
        }
        UDArchiveEntry *entry = [unmatchedOriginal objectAtIndex:index];
        [diff addObject:[[UDArchiveMutation alloc] initWithKind:@"remove"
                                                        payload:@{ @"path" : entry.path }]];
    }

    _cachedCurrentDiff = [diff copy];
    _diffDirty = NO;
    return _cachedCurrentDiff;
}

- (nullable UDArchiveEntry *)_entryAtPath:(NSString *)path inRoot:(UDDirectoryNode *)root {
    return [root entryAtRelativePath:UDArchiveNormalizePath(path)];
}

- (NSArray<UDArchiveEntry *> *)_entriesUnderPath:(NSString *)path inRoot:(UDDirectoryNode *)root {
    NSString *normalizedPath = UDArchiveNormalizePath(path);
    UDArchiveEntry *exactEntry = [self _entryAtPath:normalizedPath inRoot:root];
    if (exactEntry) {
        return @[ exactEntry ];
    }

    UDDirectoryNode *dir = [root directoryAtRelativePath:normalizedPath];
    return dir ? [dir allEntries] : @[];
}

- (BOOL)_insertEntry:(UDArchiveEntry *)entry intoRoot:(UDDirectoryNode *)root error:(NSError **)error {
    NSString *normalizedPath = UDArchiveNormalizePath(entry.path);
    if ([root entryAtRelativePath:normalizedPath] || [root directoryAtRelativePath:normalizedPath]) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathAlreadyExists
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Entry already exists at path: %@", normalizedPath] }];
        }
        return NO;
    }

    NSString *parentPath = [normalizedPath stringByDeletingLastPathComponent];
    if ([parentPath isEqualToString:@"."]) {
        parentPath = @"";
    }

    UDDirectoryNode *parent = [root ensureDirectoryAtRelativePath:parentPath];
    [parent addFileChild:entry];
    return YES;
}

- (void)_removeEmptyAncestorDirectoriesStartingAtNode:(UDDirectoryNode *)node {
    UDDirectoryNode *cursor = node;
    while (cursor && cursor.parent && cursor.directoryChildren.count == 0 && cursor.fileChildren.count == 0) {
        UDDirectoryNode *parent = cursor.parent;
        [parent removeDirectoryChild:cursor];
        cursor = parent;
    }
}

- (NSArray<UDArchiveEntry *> *)_copiedEntries:(NSArray<UDArchiveEntry *> *)entries {
    NSMutableArray<UDArchiveEntry *> *copies = [NSMutableArray arrayWithCapacity:entries.count];
    for (UDArchiveEntry *entry in entries) {
        [copies addObject:[entry entryByCopyingWithPath:entry.path contentSource:entry.contentSource modifiedAt:entry.modifiedAt]];
    }
    return copies;
}

- (void)_restoreEntriesForUndo:(NSArray<UDArchiveEntry *> *)entries {
    NSArray<UDArchiveEntry *> *restoredCopies = [self _copiedEntries:entries];
    for (UDArchiveEntry *entry in entries) {
        NSError *restoreError = nil;
        [self _insertEntry:[entry entryByCopyingWithPath:entry.path contentSource:entry.contentSource modifiedAt:entry.modifiedAt]
                 intoRoot:self.currentRoot
                   error:&restoreError];
        (void)restoreError;
    }

    if (restoredCopies.count > 0) {
        [[self.undoManager prepareWithInvocationTarget:self] _removeEntriesForUndo:restoredCopies];
        [self.undoManager setActionName:@"Delete"];
        [self _invalidateCurrentDiff];
        [self _notifyDidChange];
    }
}

- (void)_removeEntriesForUndo:(NSArray<UDArchiveEntry *> *)entries {
    NSArray<UDArchiveEntry *> *entryCopies = [self _copiedEntries:entries];
    NSArray<UDArchiveEntry *> *sortedEntries = [entryCopies sortedArrayUsingComparator:^NSComparisonResult(UDArchiveEntry *lhs, UDArchiveEntry *rhs) {
        if (lhs.path.length == rhs.path.length) {
            return [lhs.path compare:rhs.path];
        }
        return (lhs.path.length > rhs.path.length) ? NSOrderedAscending : NSOrderedDescending;
    }];

    for (UDArchiveEntry *entry in sortedEntries) {
        UDArchiveEntry *currentEntry = [self _entryAtPath:entry.path inRoot:self.currentRoot];
        if (!currentEntry) {
            continue;
        }
        UDDirectoryNode *parent = currentEntry.parent;
        [parent removeFileChild:currentEntry];
        [self _removeEmptyAncestorDirectoriesStartingAtNode:parent];
    }

    if (entryCopies.count > 0) {
        [[self.undoManager prepareWithInvocationTarget:self] _restoreEntriesForUndo:entryCopies];
        [self.undoManager setActionName:@"Restore Deleted Items"];
        [self _invalidateCurrentDiff];
        [self _notifyDidChange];
    }
}

- (void)_invalidateCurrentDiff {
    _cachedCurrentDiff = nil;
    _diffDirty = YES;
}

- (void)_notifyDidChange {
    [[NSNotificationCenter defaultCenter] postNotificationName:UDArchiveEditorDidChangeNotification object:self];
}

- (BOOL)_entriesMatchForDiff:(UDArchiveEntry *)lhs rhs:(UDArchiveEntry *)rhs {
    if (!lhs || !rhs) {
        return NO;
    }
    if (lhs.contentSource != rhs.contentSource) {
        return NO;
    }
    if (lhs.size != rhs.size) {
        return NO;
    }
    if (![lhs.contentType isEqualToString:rhs.contentType]) {
        return NO;
    }
    return YES;
}

- (BOOL)addSource:(id<UDContentSource>)source atPath:(NSString *)path error:(NSError **)error {
    NSParameterAssert(source != nil);
    NSParameterAssert(path.length > 0);

    NSString *normalizedPath = UDArchiveNormalizePath(path);
    if ([self _entryAtPath:normalizedPath inRoot:self.currentRoot] || [self.currentRoot directoryAtRelativePath:normalizedPath]) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathAlreadyExists
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Entry already exists at path: %@", normalizedPath] }];
        }
        return NO;
    }

    UDArchiveEntry *newEntry = [[UDArchiveEntry alloc] initWithPath:normalizedPath
                                                               size:source.length
                                                        contentType:@"application/octet-stream"
                                                         modifiedAt:[NSDate date]
                                                             source:source];

    if (![self _insertEntry:newEntry intoRoot:self.currentRoot error:error]) {
        return NO;
    }

    [[self.undoManager prepareWithInvocationTarget:self] removeNodeAtPath:normalizedPath error:NULL];
    [self.undoManager setActionName:@"Add File"];
    [self _invalidateCurrentDiff];
    [self _notifyDidChange];
    return YES;
}

- (BOOL)removeNodeAtPath:(NSString *)path error:(NSError **)error {
    NSParameterAssert(path.length > 0);

    NSString *normalizedPath = UDArchiveNormalizePath(path);
    UDArchiveEntry *exactEntry = [self _entryAtPath:normalizedPath inRoot:self.currentRoot];
    UDDirectoryNode *directory = exactEntry ? nil : [self.currentRoot directoryAtRelativePath:normalizedPath];
    NSArray<UDArchiveEntry *> *removedEntries = nil;

    if (exactEntry) {
        removedEntries = [self _copiedEntries:@[ exactEntry ]];
        UDDirectoryNode *parent = exactEntry.parent;
        [parent removeFileChild:exactEntry];
        [self _removeEmptyAncestorDirectoriesStartingAtNode:parent];
    } else if (directory && directory.parent) {
        removedEntries = [self _copiedEntries:[directory allEntries]];
        UDDirectoryNode *parent = directory.parent;
        [parent removeDirectoryChild:directory];
        [self _removeEmptyAncestorDirectoriesStartingAtNode:parent];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No entry found at path: %@", normalizedPath] }];
        }
        return NO;
    }

    [[self.undoManager prepareWithInvocationTarget:self] _restoreEntriesForUndo:removedEntries];
    [self.undoManager setActionName:@"Delete"];
    [self _invalidateCurrentDiff];
    [self _notifyDidChange];
    return YES;
}

- (BOOL)moveNodeFromPath:(NSString *)fromPath toPath:(NSString *)toPath error:(NSError **)error {
    NSParameterAssert(fromPath.length > 0);
    NSParameterAssert(toPath.length > 0);

    fromPath = UDArchiveNormalizePath(fromPath);
    toPath = UDArchiveNormalizePath(toPath);

    if ([fromPath isEqualToString:toPath]) {
        return YES;
    }

    if ([toPath hasPrefix:[fromPath stringByAppendingString:@"/"]]) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodeTargetPathExists
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Cannot move '%@' inside itself.", fromPath] }];
        }
        return NO;
    }

    NSArray<UDArchiveEntry *> *movingEntries = [self _entriesUnderPath:fromPath inRoot:self.currentRoot];
    if (movingEntries.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No entry found at path: %@", fromPath] }];
        }
        return NO;
    }

    NSMutableSet<NSString *> *movingPaths = [NSMutableSet setWithCapacity:movingEntries.count];
    NSMutableSet<NSString *> *targetPaths = [NSMutableSet setWithCapacity:movingEntries.count];
    for (UDArchiveEntry *movingEntry in movingEntries) {
        [movingPaths addObject:movingEntry.path];

        NSString *newPath = [movingEntry.path isEqualToString:fromPath]
            ? toPath
            : [toPath stringByAppendingString:[movingEntry.path substringFromIndex:fromPath.length]];

        if ([targetPaths containsObject:newPath]) {
            if (error) {
                *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                             code:UDArchiveEditorErrorCodeTargetPathExists
                                         userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Target path already exists: %@", newPath] }];
            }
            return NO;
        }
        [targetPaths addObject:newPath];

        for (UDArchiveEntry *entry in self.currentEntries) {
            if ([movingPaths containsObject:entry.path]) {
                continue;
            }
            if ([entry.path isEqualToString:newPath]) {
                if (error) {
                    *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                                 code:UDArchiveEditorErrorCodeTargetPathExists
                                             userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Target path already exists: %@", newPath] }];
                }
                return NO;
            }
        }

        UDDirectoryNode *dirAtTarget = [self.currentRoot directoryAtRelativePath:newPath];
        if (dirAtTarget && ![movingPaths containsObject:newPath]) {
            if (error) {
                *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                             code:UDArchiveEditorErrorCodeTargetPathExists
                                         userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"Target path already exists: %@", newPath] }];
            }
            return NO;
        }
    }

    NSArray<UDArchiveEntry *> *movingCopies = [self _copiedEntries:movingEntries];
    UDArchiveEntry *exactEntry = [self _entryAtPath:fromPath inRoot:self.currentRoot];
    if (exactEntry) {
        UDDirectoryNode *parent = exactEntry.parent;
        [parent removeFileChild:exactEntry];
        [self _removeEmptyAncestorDirectoriesStartingAtNode:parent];
    } else {
        UDDirectoryNode *directory = [self.currentRoot directoryAtRelativePath:fromPath];
        if (!directory || !directory.parent) {
            if (error) {
                *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                             code:UDArchiveEditorErrorCodePathNotFound
                                         userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No entry found at path: %@", fromPath] }];
            }
            return NO;
        }
        UDDirectoryNode *parent = directory.parent;
        [parent removeDirectoryChild:directory];
        [self _removeEmptyAncestorDirectoriesStartingAtNode:parent];
    }

    for (UDArchiveEntry *entry in movingCopies) {
        NSString *newPath = [entry.path isEqualToString:fromPath]
            ? toPath
            : [toPath stringByAppendingString:[entry.path substringFromIndex:fromPath.length]];
        UDArchiveEntry *moved = [entry entryByCopyingWithPath:newPath contentSource:entry.contentSource modifiedAt:[NSDate date]];
        if (![self _insertEntry:moved intoRoot:self.currentRoot error:error]) {
            return NO;
        }
    }

    [[self.undoManager prepareWithInvocationTarget:self] moveNodeFromPath:toPath toPath:fromPath error:NULL];
    [self.undoManager setActionName:@"Move"];
    [self _invalidateCurrentDiff];
    [self _notifyDidChange];
    return YES;
}

- (BOOL)replaceEntryAtPath:(NSString *)path withSource:(id<UDContentSource>)source error:(NSError **)error {
    NSParameterAssert(path.length > 0);
    NSParameterAssert(source != nil);

    NSString *normalizedPath = UDArchiveNormalizePath(path);
    UDArchiveEntry *entry = [self _entryAtPath:normalizedPath inRoot:self.currentRoot];
    if (!entry) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No entry found at path: %@", normalizedPath] }];
        }
        return NO;
    }

    id<UDContentSource> previousSource = entry.contentSource;
    UDDirectoryNode *parent = entry.parent;
    UDArchiveEntry *updated = [entry entryByCopyingWithPath:entry.path contentSource:source modifiedAt:[NSDate date]];
    [parent removeFileChild:entry];
    [parent addFileChild:updated];

    [[self.undoManager prepareWithInvocationTarget:self] replaceEntryAtPath:normalizedPath withSource:previousSource error:NULL];
    [self.undoManager setActionName:@"Replace File"];
    [self _invalidateCurrentDiff];
    [self _notifyDidChange];
    return YES;
}

- (NSData *)contentForEntryAtPath:(NSString *)path range:(NSRange)range error:(NSError **)error {
    NSParameterAssert(path.length > 0);

    UDArchiveEntry *entry = [self _entryAtPath:path inRoot:self.currentRoot];
    if (!entry) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No entry found at path: %@", path] }];
        }
        return nil;
    }

    id<UDContentSource> src = entry.contentSource;
    if (!src) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{ NSLocalizedDescriptionKey : [NSString stringWithFormat:@"No content source for entry: %@", path] }];
        }
        return nil;
    }

    return [src readRange:range error:error];
}

- (void)revertAll {
    _currentRoot = [self.originalRoot deepCopy];
    [self.undoManager removeAllActions];
    [self _invalidateCurrentDiff];
    [self _notifyDidChange];
}

@end
