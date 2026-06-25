/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDArchiveEditor.h"
#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDArchiveMutation.h"

static NSString *const UDArchiveEditorErrorDomain = @"com.udquake.error.archive-editor";

typedef NS_ENUM(NSInteger, UDArchiveEditorErrorCode) {
    UDArchiveEditorErrorCodePathAlreadyExists = 1,
    UDArchiveEditorErrorCodePathNotFound      = 2,
    UDArchiveEditorErrorCodeTargetPathExists  = 3,
};

@implementation UDArchiveEditor

@synthesize archive          = _archive;
@synthesize pendingMutations = _pendingMutations;

- (instancetype)initWithArchive:(UDArchive *)archive {
    NSParameterAssert(archive != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _archive          = archive;
    _pendingMutations = [NSMutableArray array];
    _currentEntries   = [NSMutableArray arrayWithArray:archive.entries];
    return self;
}

/* ------------------------------------------------------------------ */
#pragma mark - Synthesised accessors

- (BOOL)isDirty {
    return (_pendingMutations.count > 0);
}

- (NSArray<UDArchiveEntry *> *)currentEntries {
    return [_currentEntries copy];
}

/* ------------------------------------------------------------------ */
#pragma mark - Lookup helpers

/** Return the first entry whose path exactly matches `path`, or nil. */
- (nullable UDArchiveEntry *)_entryAtPath:(NSString *)path {
    for (UDArchiveEntry *entry in _currentEntries) {
        if ([entry.path isEqualToString:path]) {
            return entry;
        }
    }
    return nil;
}

/* ------------------------------------------------------------------ */
#pragma mark - Mutations

- (BOOL)addSource:(id<UDContentSource>)source
           atPath:(NSString *)path
            error:(NSError **)error {
    NSParameterAssert(source != nil);
    NSParameterAssert(path.length > 0);

    if ([self _entryAtPath:path]) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathAlreadyExists
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Entry already exists at path: %@", path]}];
        }
        return NO;
    }

    UDArchiveEntry *newEntry = [[UDArchiveEntry alloc]
        initWithPath:path
                size:source.length
         contentType:@"application/octet-stream"
          modifiedAt:[NSDate date]
              source:source];

    [_currentEntries addObject:newEntry];

    UDArchiveMutation *mutation = [[UDArchiveMutation alloc]
        initWithKind:@"add"
             payload:@{@"path": path, @"source": source}];
    [_pendingMutations addObject:mutation];

    return YES;
}

- (BOOL)removeNodeAtPath:(NSString *)path error:(NSError **)error {
    NSParameterAssert(path.length > 0);

    NSString *dirPrefix = [path stringByAppendingString:@"/"];
    NSMutableArray<UDArchiveEntry *> *toRemove = [NSMutableArray array];

    for (UDArchiveEntry *entry in _currentEntries) {
        if ([entry.path isEqualToString:path] ||
            [entry.path hasPrefix:dirPrefix]) {
            [toRemove addObject:entry];
        }
    }

    if (toRemove.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"No entry found at path: %@", path]}];
        }
        return NO;
    }

    [_currentEntries removeObjectsInArray:toRemove];

    UDArchiveMutation *mutation = [[UDArchiveMutation alloc]
        initWithKind:@"remove"
             payload:@{@"path": path}];
    [_pendingMutations addObject:mutation];

    return YES;
}

- (BOOL)moveNodeFromPath:(NSString *)fromPath
                  toPath:(NSString *)toPath
                   error:(NSError **)error {
    NSParameterAssert(fromPath.length > 0);
    NSParameterAssert(toPath.length > 0);

    UDArchiveEntry *entry = [self _entryAtPath:fromPath];
    if (!entry) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"No entry found at path: %@", fromPath]}];
        }
        return NO;
    }

    if ([self _entryAtPath:toPath]) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodeTargetPathExists
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Target path already exists: %@", toPath]}];
        }
        return NO;
    }

    NSUInteger idx = [_currentEntries indexOfObject:entry];
    UDArchiveEntry *moved = [[UDArchiveEntry alloc]
        initWithPath:toPath
                size:entry.size
         contentType:entry.contentType
          modifiedAt:entry.modifiedAt
              source:(entry.stagedSource ? entry.stagedSource : entry.source)];

    [_currentEntries replaceObjectAtIndex:idx withObject:moved];

    UDArchiveMutation *mutation = [[UDArchiveMutation alloc]
        initWithKind:@"move"
             payload:@{@"fromPath": fromPath, @"toPath": toPath}];
    [_pendingMutations addObject:mutation];

    return YES;
}

- (BOOL)replaceEntryAtPath:(NSString *)path
                withSource:(id<UDContentSource>)source
                     error:(NSError **)error {
    NSParameterAssert(path.length > 0);
    NSParameterAssert(source != nil);

    UDArchiveEntry *entry = [self _entryAtPath:path];
    if (!entry) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"No entry found at path: %@", path]}];
        }
        return NO;
    }

    entry.stagedSource = source;

    UDArchiveMutation *mutation = [[UDArchiveMutation alloc]
        initWithKind:@"replace"
             payload:@{@"path": path, @"source": source}];
    [_pendingMutations addObject:mutation];

    return YES;
}

/* ------------------------------------------------------------------ */
#pragma mark - Content access

- (nullable NSData *)contentForEntryAtPath:(NSString *)path
                                     range:(NSRange)range
                                     error:(NSError **)error {
    NSParameterAssert(path.length > 0);

    UDArchiveEntry *entry = [self _entryAtPath:path];
    if (!entry) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"No entry found at path: %@", path]}];
        }
        return nil;
    }

    id<UDContentSource> src = entry.stagedSource ? entry.stagedSource : entry.source;
    if (!src) {
        if (error) {
            *error = [NSError errorWithDomain:UDArchiveEditorErrorDomain
                                         code:UDArchiveEditorErrorCodePathNotFound
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"No content source for entry: %@", path]}];
        }
        return nil;
    }

    return [src readRange:range error:error];
}

/* ------------------------------------------------------------------ */
#pragma mark - Revert

- (void)revertAll {
    [_pendingMutations removeAllObjects];
    [_currentEntries removeAllObjects];
    [_currentEntries addObjectsFromArray:_archive.entries];
}

@end
