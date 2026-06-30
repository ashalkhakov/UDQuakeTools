#import "UDAssetIndex.h"

static NSSet<NSString *> *UDIndexedAssetExtensions(void) {
    static NSSet<NSString *> *extensions = nil;
    if (!extensions) {
        extensions = [NSSet setWithObjects:@"def", @"mtr", @"gui", @"script", nil];
    }
    return extensions;
}

static UDAssetKind UDAssetKindForExtension(NSString *fileExtension) {
    NSString *lowerExtension = fileExtension.lowercaseString;
    if ([lowerExtension isEqualToString:@"def"]) {
        return UDAssetKindDecl;
    }
    if ([lowerExtension isEqualToString:@"mtr"]) {
        return UDAssetKindMaterial;
    }
    if ([lowerExtension isEqualToString:@"gui"]) {
        return UDAssetKindGUI;
    }
    if ([lowerExtension isEqualToString:@"script"]) {
        return UDAssetKindScript;
    }
    return UDAssetKindUnknown;
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
    return self;
}

- (NSArray<UDAssetIndexEntry *> *)entriesOfKind:(UDAssetKind)kind {
    NSMutableArray<UDAssetIndexEntry *> *results = [NSMutableArray array];
    for (UDAssetIndexEntry *entry in self.entries) {
        if (entry.kind == kind) {
            [results addObject:entry];
        }
    }
    return results;
}

- (nullable UDAssetIndexEntry *)entryForVirtualPath:(NSString *)virtualPath {
    for (UDAssetIndexEntry *entry in self.entries) {
        if ([entry.virtualPath isEqualToString:virtualPath]) {
            return entry;
        }
    }
    return nil;
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
        NSString *fileExtension = resolved.virtualPath.pathExtension.lowercaseString;
        UDAssetKind kind = UDAssetKindForExtension(fileExtension);
        if (kind == UDAssetKindUnknown) {
            continue;
        }

        NSURL *sourceURL = resolved.fileURL ? resolved.fileURL : resolved.mount.sourceURL;
        NSString *name = resolved.virtualPath.lastPathComponent.stringByDeletingPathExtension;
        UDAssetIndexEntry *entry = [[UDAssetIndexEntry alloc] initWithVirtualPath:resolved.virtualPath
                                                                             name:name
                                                                    fileExtension:fileExtension
                                                                             kind:kind
                                                                  mountIdentifier:resolved.mount.identifier
                                                                        sourceURL:sourceURL
                                                                       sourcePath:resolved.sourcePath
                                                                    archiveBacked:(resolved.mount.kind == UDVFSMountKindArchive)];
        [entries addObject:entry];
    }

    return [[UDAssetIndex alloc] initWithEntries:entries];
}

@end