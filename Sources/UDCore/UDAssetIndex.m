/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 * UDAssetIndex.m — Asset inventory index implementation.
 */

#import "UDAssetIndex.h"
#import "UDDeclType.h"

// Non-decl extensions the indexer also tracks (GUI scripts, game scripts).
static NSSet<NSString *> *UDIndexedNonDeclExtensions(void) {
    static NSSet<NSString *> *extensions = nil;
    if (!extensions) {
        extensions = [NSSet setWithObjects:@"gui", @"script", nil];
    }
    return extensions;
}

static NSSet<NSString *> *UDIndexedAssetExtensions(void) {
    static NSSet<NSString *> *extensions = nil;
    if (!extensions) {
        NSMutableSet<NSString *> *mutable = [[UDDeclTypeRegistry allSourceFileExtensions] mutableCopy];
        [mutable unionSet:UDIndexedNonDeclExtensions()];
        extensions = [mutable copy];
    }
    return extensions;
}

static UDAssetKind UDAssetKindForExtension(NSString *fileExtension) {
    NSString *lower = fileExtension.lowercaseString;
    if ([[UDDeclTypeRegistry allSourceFileExtensions] containsObject:lower]) {
        return UDAssetKindDecl;
    }
    if ([lower isEqualToString:@"gui"]) {
        return UDAssetKindGUI;
    }
    if ([lower isEqualToString:@"script"]) {
        return UDAssetKindScript;
    }
    return UDAssetKindUnknown;
}

static NSComparisonResult UDCompareAssetEntries(id leftObject, id rightObject, void *context) {
    (void)context;
    UDAssetIndexEntry *left = (UDAssetIndexEntry *)leftObject;
    UDAssetIndexEntry *right = (UDAssetIndexEntry *)rightObject;
    return [left.virtualPath compare:right.virtualPath options:NSCaseInsensitiveSearch];
}

static UDAssetIndexEntry *UDAssetEntryFromResolvedFile(UDVFSResolvedFile *resolved) {
    NSString *fileExtension = resolved.virtualPath.pathExtension.lowercaseString;
    UDAssetKind kind = UDAssetKindForExtension(fileExtension);
    if (kind == UDAssetKindUnknown) {
        return nil;
    }

    NSURL *sourceURL = resolved.fileURL ? resolved.fileURL : resolved.mount.sourceURL;
    NSString *name = resolved.virtualPath.lastPathComponent.stringByDeletingPathExtension;
    return [[UDAssetIndexEntry alloc] initWithVirtualPath:resolved.virtualPath
                                                     name:name
                                            fileExtension:fileExtension
                                                     kind:kind
                                          mountIdentifier:resolved.mount.identifier
                                                sourceURL:sourceURL
                                               sourcePath:resolved.sourcePath
                                            archiveBacked:(resolved.mount.kind == UDVFSMountKindArchive)];
}

@implementation UDAssetIndexEntry

@synthesize virtualPath = _virtualPath;
@synthesize name = _name;
@synthesize fileExtension = _fileExtension;
@synthesize kind = _kind;
@synthesize mountIdentifier = _mountIdentifier;
@synthesize sourceURL = _sourceURL;
@synthesize sourcePath = _sourcePath;
@synthesize archiveBacked = _archiveBacked;

- (nullable UDDeclTypeDescriptor *)primaryDeclTypeDescriptor {
    return [UDDeclTypeRegistry exclusiveDescriptorForFileExtension:_fileExtension];
}

- (instancetype)initWithVirtualPath:(NSString *)virtualPath
                               name:(NSString *)name
                      fileExtension:(NSString *)fileExtension
                               kind:(UDAssetKind)kind
                    mountIdentifier:(NSString *)mountIdentifier
                          sourceURL:(NSURL *)sourceURL
                         sourcePath:(NSString *)sourcePath
                      archiveBacked:(BOOL)archiveBacked {
    NSParameterAssert(virtualPath.length > 0);
    NSParameterAssert(name.length > 0);
    NSParameterAssert(fileExtension.length > 0);
    NSParameterAssert(mountIdentifier.length > 0);
    NSParameterAssert(sourceURL != nil);
    NSParameterAssert(sourcePath.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _virtualPath = [virtualPath copy];
    _name = [name copy];
    _fileExtension = [fileExtension copy];
    _kind = kind;
    _mountIdentifier = [mountIdentifier copy];
    _sourceURL = sourceURL;
    _sourcePath = [sourcePath copy];
    _archiveBacked = archiveBacked;
    return self;
}

@end

@implementation UDAssetIndex

@synthesize entries = _entries;

- (instancetype)initWithEntries:(NSArray<UDAssetIndexEntry *> *)entries {
    NSParameterAssert(entries != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _entries = [entries copy];

    NSMutableDictionary<NSString *, UDAssetIndexEntry *> *entriesByVirtualPath = [NSMutableDictionary dictionaryWithCapacity:_entries.count];
    NSMutableDictionary<NSNumber *, NSMutableArray<UDAssetIndexEntry *> *> *entriesByKind = [NSMutableDictionary dictionary];
    for (UDAssetIndexEntry *entry in _entries) {
        [entriesByVirtualPath setObject:entry forKey:entry.virtualPath];

        NSNumber *kindKey = [NSNumber numberWithInteger:entry.kind];
        NSMutableArray<UDAssetIndexEntry *> *bucket = [entriesByKind objectForKey:kindKey];
        if (!bucket) {
            bucket = [NSMutableArray array];
            [entriesByKind setObject:bucket forKey:kindKey];
        }
        [bucket addObject:entry];
    }

    NSMutableDictionary<NSNumber *, NSArray<UDAssetIndexEntry *> *> *frozenByKind = [NSMutableDictionary dictionaryWithCapacity:entriesByKind.count];
    for (NSNumber *kindKey in entriesByKind) {
        [frozenByKind setObject:[[entriesByKind objectForKey:kindKey] copy] forKey:kindKey];
    }

    _entriesByVirtualPath = [entriesByVirtualPath copy];
    _entriesByKind = [frozenByKind copy];
    return self;
}

- (NSArray<UDAssetIndexEntry *> *)entriesOfKind:(UDAssetKind)kind {
    NSArray<UDAssetIndexEntry *> *entries = [_entriesByKind objectForKey:[NSNumber numberWithInteger:kind]];
    return entries ?: @[];
}

- (nullable UDAssetIndexEntry *)entryForVirtualPath:(NSString *)virtualPath {
    return [_entriesByVirtualPath objectForKey:virtualPath];
}

@end

@implementation UDAssetIndexer

- (UDAssetIndex *)buildIndexFromVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                            error:(NSError **)error {
    NSParameterAssert(virtualFileSystem != nil);

    NSArray<UDVFSResolvedFile *> *visibleFiles = [virtualFileSystem visibleFilesWithExtensions:UDIndexedAssetExtensions()
                                                                                          error:error];
    NSMutableArray<UDAssetIndexEntry *> *entries = [NSMutableArray arrayWithCapacity:visibleFiles.count];
    for (UDVFSResolvedFile *resolved in visibleFiles) {
        UDAssetIndexEntry *entry = UDAssetEntryFromResolvedFile(resolved);
        if (entry) {
            [entries addObject:entry];
        }
    }

    [entries sortUsingFunction:UDCompareAssetEntries context:NULL];
    return [[UDAssetIndex alloc] initWithEntries:entries];
}

- (UDAssetIndex *)rebuildIndexByApplyingWriteNotification:(NSNotification *)notification
                                           toExistingIndex:(UDAssetIndex *)existingIndex
                                         virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                     error:(NSError **)error {
    NSParameterAssert(notification != nil);
    NSParameterAssert(existingIndex != nil);
    NSParameterAssert(virtualFileSystem != nil);

    NSString *virtualPath = [notification.userInfo objectForKey:UDVFSNotificationVirtualPathKey];
    if (virtualPath.length == 0) {
        return existingIndex;
    }

    NSString *normalizedPath = [virtualPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }

    NSMutableArray<UDAssetIndexEntry *> *entries = [NSMutableArray arrayWithCapacity:existingIndex.entries.count + 1];
    for (UDAssetIndexEntry *entry in existingIndex.entries) {
        if (![entry.virtualPath isEqualToString:normalizedPath]) {
            [entries addObject:entry];
        }
    }

    NSString *extension = normalizedPath.pathExtension.lowercaseString;
    if ([UDIndexedAssetExtensions() containsObject:extension]) {
        UDVFSResolvedFile *resolved = [virtualFileSystem resolvedFileAtPath:normalizedPath error:nil];
        if (resolved) {
            UDAssetIndexEntry *updatedEntry = UDAssetEntryFromResolvedFile(resolved);
            if (updatedEntry) {
                [entries addObject:updatedEntry];
            }
        }
    }

    [entries sortUsingFunction:UDCompareAssetEntries context:NULL];

    if (error) {
        *error = nil;
    }
    return [[UDAssetIndex alloc] initWithEntries:entries];
}

@end
