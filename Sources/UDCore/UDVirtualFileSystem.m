#import "UDVirtualFileSystem.h"

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "../UDFormats/UDCodecRegistry.h"
#import "../UDFormats/UDArchiveCodec.h"

NSString *const UDVFSDidWriteFileNotification = @"UDVFSDidWriteFileNotification";
NSString *const UDVFSNotificationVirtualPathKey = @"virtualPath";
NSString *const UDVFSNotificationFileURLKey = @"fileURL";
NSString *const UDVFSNotificationMountIdentifierKey = @"mountIdentifier";

static NSString *const UDVFSErrorDomain = @"com.udquake.error.vfs";

@class UDVirtualFileSystem;
@class UDVFSResolvedFile;

@interface UDVirtualFileSystem ()
- (BOOL)mount:(UDVFSMount *)a shouldSortBefore:(UDVFSMount *)b;
- (NSComparisonResult)compareArchiveMountPrecedence:(UDVFSMount *)a other:(UDVFSMount *)b;
- (BOOL)shouldUseNumberedPakOrdering;
- (BOOL)shouldUseLexicalArchiveOrdering;
- (NSInteger)numberedPakPriorityDeltaForURL:(NSURL *)url;
- (BOOL)isKnownArchiveFileNameForCurrentGame:(NSString *)fileName;
- (NSString *)mountIdentifierForDiscoveredArchiveURL:(NSURL *)archiveURL;
@end

static NSComparisonResult UDVFSCompareArchiveURLs(id leftObject, id rightObject, void *context) {
    (void)context;
    NSString *leftName = [(NSURL *)leftObject lastPathComponent];
    NSString *rightName = [(NSURL *)rightObject lastPathComponent];
    return [leftName compare:rightName options:NSCaseInsensitiveSearch];
}

static NSComparisonResult UDVFSCompareResolvedFiles(id leftObject, id rightObject, void *context) {
    (void)context;
    NSString *leftPath = [(UDVFSResolvedFile *)leftObject virtualPath];
    NSString *rightPath = [(UDVFSResolvedFile *)rightObject virtualPath];
    return [leftPath compare:rightPath options:NSCaseInsensitiveSearch];
}

typedef NS_ENUM(NSInteger, UDVFSErrorCode) {
    UDVFSErrorCodeInvalidPath = 1,
    UDVFSErrorCodeMountFailed = 2,
    UDVFSErrorCodeNotFound = 3,
    UDVFSErrorCodeReadOnlyPath = 4,
    UDVFSErrorCodeWriteFailed = 5,
};

@protocol UDVFSMountAdapter <NSObject>
- (nullable UDVFSResolvedFile *)resolvedFileForVirtualPath:(NSString *)virtualPath
                                                     mount:(UDVFSMount *)mount
                                                     error:(NSError **)error;
- (NSArray<NSString *> *)allRelativePaths:(NSError **)error;
@end

@interface UDVFSLooseFileSource : NSObject <UDContentSource> {
    NSURL *_fileURL;
    uint64_t _lengthValue;
}

- (instancetype)initWithFileURL:(NSURL *)fileURL length:(uint64_t)length;

@end

@interface UDVFSDirectoryMountAdapter : NSObject <UDVFSMountAdapter> {
    NSURL *_directoryURL;
}

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL;
- (nullable NSURL *)fileURLForVirtualPath:(NSString *)virtualPath mount:(UDVFSMount *)mount;

@end

@interface UDVFSArchiveMountAdapter : NSObject <UDVFSMountAdapter> {
    UDArchive *_archive;
    NSDictionary<NSString *, UDArchiveEntry *> *_entryByPath;
}

- (instancetype)initWithArchive:(UDArchive *)archive;

@end

@interface UDVFSResolvedFile ()
@property (nonatomic, readwrite, copy) NSString *virtualPath;
@property (nonatomic, readwrite, strong) UDVFSMount *mount;
@property (nonatomic, readwrite, strong) id<UDContentSource> contentSource;
@property (nonatomic, readwrite) uint64_t length;
@property (nonatomic, readwrite, copy) NSString *sourcePath;
@property (nonatomic, readwrite, nullable, strong) NSURL *fileURL;
@end

@implementation UDVFSResolvedFile

@synthesize virtualPath = _virtualPath;
@synthesize mount = _mount;
@synthesize contentSource = _contentSource;
@synthesize length = _length;
@synthesize sourcePath = _sourcePath;
@synthesize fileURL = _fileURL;

- (instancetype)initWithVirtualPath:(NSString *)virtualPath
                              mount:(UDVFSMount *)mount
                      contentSource:(id<UDContentSource>)contentSource
                             length:(uint64_t)length
                         sourcePath:(NSString *)sourcePath
                            fileURL:(NSURL *)fileURL {
    NSParameterAssert(virtualPath.length > 0);
    NSParameterAssert(mount != nil);
    NSParameterAssert(contentSource != nil);
    NSParameterAssert(sourcePath.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _virtualPath = [virtualPath copy];
    _mount = mount;
    _contentSource = contentSource;
    _length = length;
    _sourcePath = [sourcePath copy];
    _fileURL = fileURL;
    return self;
}

@end

@implementation UDVFSLooseFileSource

- (instancetype)initWithFileURL:(NSURL *)fileURL length:(uint64_t)length {
    NSParameterAssert(fileURL != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _fileURL = fileURL;
    _lengthValue = length;
    return self;
}

- (uint64_t)length {
    return _lengthValue;
}

- (NSData *)readRange:(NSRange)range error:(NSError **)error {
    uint64_t rangeStart = (uint64_t)range.location;
    uint64_t rangeLength = (uint64_t)range.length;
    if (rangeStart > UINT64_MAX - rangeLength || rangeStart + rangeLength > self.length) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range is outside file bounds."}];
        }
        return nil;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:_fileURL.path];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeNotFound
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read loose file from mounted directory."}];
        }
        return nil;
    }

    if (rangeStart > NSUIntegerMax || rangeLength > NSUIntegerMax) {
        [handle closeFile];
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range exceeds platform limits."}];
        }
        return nil;
    }

    [handle seekToFileOffset:(NSUInteger)rangeStart];
    NSData *slice = [handle readDataOfLength:(NSUInteger)rangeLength];
    [handle closeFile];
    return slice;
}

- (NSData *)readAll:(NSError **)error {
    return [self readRange:NSMakeRange(0, (NSUInteger)self.length) error:error];
}

@end

@implementation UDVFSDirectoryMountAdapter

- (instancetype)initWithDirectoryURL:(NSURL *)directoryURL {
    NSParameterAssert(directoryURL != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _directoryURL = directoryURL;
    return self;
}

- (nullable NSURL *)fileURLForVirtualPath:(NSString *)virtualPath mount:(UDVFSMount *)mount {
    NSString *mountRoot = mount.virtualRoot;
    NSString *relativePath = virtualPath;

    if (mountRoot.length > 0) {
        NSString *prefix = [mountRoot stringByAppendingString:@"/"];
        if ([virtualPath isEqualToString:mountRoot]) {
            relativePath = @"";
        } else if ([virtualPath hasPrefix:prefix]) {
            relativePath = [virtualPath substringFromIndex:prefix.length];
        } else {
            return nil;
        }
    }

    if (relativePath.length == 0) {
        return nil;
    }

    return [_directoryURL URLByAppendingPathComponent:relativePath];
}

- (NSArray<NSString *> *)allRelativePaths:(NSError **)error {
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:_directoryURL
                                                             includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                                                                                options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                           errorHandler:nil];
    if (!enumerator) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeMountFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to enumerate mounted directory."}];
        }
        return @[];
    }

    NSString *basePath = [[_directoryURL.path stringByStandardizingPath] stringByResolvingSymlinksInPath];
    NSString *basePrefix = [basePath stringByAppendingString:@"/"];

    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSURL *fileURL in enumerator) {
        NSNumber *isRegularFile = nil;
        [fileURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }

        NSString *filePath = [[fileURL.path stringByStandardizingPath] stringByResolvingSymlinksInPath];
        if (![filePath hasPrefix:basePrefix]) {
            continue;
        }

        NSString *relativePath = [filePath substringFromIndex:basePrefix.length];
        relativePath = [relativePath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        if (relativePath.length > 0) {
            [paths addObject:relativePath];
        }
    }

    NSUInteger count = paths.count;
    for (NSUInteger i = 0; i < count; i++) {
        for (NSUInteger j = i + 1; j < count; j++) {
            NSString *left = [paths objectAtIndex:i];
            NSString *right = [paths objectAtIndex:j];
            if ([left compare:right options:NSCaseInsensitiveSearch] != NSOrderedDescending) {
                continue;
            }
            [paths exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
    }

    return paths;
}

- (nullable UDVFSResolvedFile *)resolvedFileForVirtualPath:(NSString *)virtualPath
                                                     mount:(UDVFSMount *)mount
                                                     error:(NSError **)error {
    NSURL *fileURL = [self fileURLForVirtualPath:virtualPath mount:mount];
    if (!fileURL) {
        return nil;
    }

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:fileURL.path isDirectory:&isDirectory] || isDirectory) {
        return nil;
    }

    NSError *attrsError = nil;
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fileURL.path error:&attrsError];
    if (!attrs) {
        if (error) {
            *error = attrsError;
        }
        return nil;
    }

    uint64_t length = (uint64_t)[attrs fileSize];
    UDVFSLooseFileSource *source = [[UDVFSLooseFileSource alloc] initWithFileURL:fileURL length:length];
    return [[UDVFSResolvedFile alloc] initWithVirtualPath:virtualPath
                                                    mount:mount
                                            contentSource:source
                                                   length:length
                                               sourcePath:[virtualPath isEqualToString:mount.virtualRoot] ? @"" : [virtualPath hasPrefix:[mount.virtualRoot stringByAppendingString:@"/"]] ? [virtualPath substringFromIndex:(mount.virtualRoot.length + 1)] : virtualPath
                                                  fileURL:fileURL];
}

@end

@implementation UDVFSArchiveMountAdapter

- (instancetype)initWithArchive:(UDArchive *)archive {
    NSParameterAssert(archive != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _archive = archive;

    NSMutableDictionary<NSString *, UDArchiveEntry *> *index = [NSMutableDictionary dictionary];
    for (UDArchiveEntry *entry in archive.entries) {
        if (entry.path.length == 0) {
            continue;
        }
        NSString *normalized = [entry.path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        [index setObject:entry forKey:normalized];
    }
    _entryByPath = [index copy];
    return self;
}

- (NSArray<NSString *> *)allRelativePaths:(NSError **)error {
    (void)error;
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithArray:[_entryByPath allKeys]];
    NSUInteger count = paths.count;
    for (NSUInteger i = 0; i < count; i++) {
        for (NSUInteger j = i + 1; j < count; j++) {
            NSString *left = [paths objectAtIndex:i];
            NSString *right = [paths objectAtIndex:j];
            if ([left compare:right options:NSCaseInsensitiveSearch] != NSOrderedDescending) {
                continue;
            }
            [paths exchangeObjectAtIndex:i withObjectAtIndex:j];
        }
    }
    return paths;
}

- (nullable UDVFSResolvedFile *)resolvedFileForVirtualPath:(NSString *)virtualPath
                                                     mount:(UDVFSMount *)mount
                                                     error:(NSError **)error {
    (void)error;

    NSString *mountRoot = mount.virtualRoot;
    NSString *relativePath = virtualPath;

    if (mountRoot.length > 0) {
        NSString *prefix = [mountRoot stringByAppendingString:@"/"];
        if ([virtualPath isEqualToString:mountRoot]) {
            relativePath = @"";
        } else if ([virtualPath hasPrefix:prefix]) {
            relativePath = [virtualPath substringFromIndex:prefix.length];
        } else {
            return nil;
        }
    }

    if (relativePath.length == 0) {
        return nil;
    }

    UDArchiveEntry *entry = [_entryByPath objectForKey:relativePath];
    if (!entry || !entry.contentSource) {
        return nil;
    }

    return [[UDVFSResolvedFile alloc] initWithVirtualPath:virtualPath
                                                    mount:mount
                                            contentSource:entry.contentSource
                                                   length:entry.size
                                               sourcePath:relativePath
                                                  fileURL:nil];
}

@end

@interface UDVirtualFileSystem ()
@property (nonatomic, readwrite) UDGameType gameType;
@property (nonatomic, readwrite, nullable, strong) NSURL *gameDirectoryURL;
- (BOOL)isKnownArchiveFileNameForCurrentGame:(NSString *)fileName;
- (NSString *)mountIdentifierForDiscoveredArchiveURL:(NSURL *)archiveURL;
@end

@implementation UDVirtualFileSystem

@synthesize gameType = _gameType;
@synthesize gameDirectoryURL = _gameDirectoryURL;

+ (NSString *)normalizeVirtualPath:(NSString *)path {
    if (path.length == 0) {
        return @"";
    }

    NSString *normalized = [path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([normalized hasPrefix:@"/"]) {
        normalized = [normalized substringFromIndex:1];
    }

    NSArray<NSString *> *parts = [normalized componentsSeparatedByString:@"/"];
    NSMutableArray<NSString *> *clean = [NSMutableArray arrayWithCapacity:parts.count];
    for (NSString *part in parts) {
        if (part.length == 0 || [part isEqualToString:@"."]) {
            continue;
        }
        if ([part isEqualToString:@".."] || [part rangeOfString:@":"].location != NSNotFound) {
            return @"";
        }
        [clean addObject:part];
    }

    return [clean componentsJoinedByString:@"/"];
}

- (instancetype)init {
    return [self initWithCodecRegistry:[UDCodecRegistry sharedRegistry]];
}

- (instancetype)initWithCodecRegistry:(UDCodecRegistry *)codecRegistry {
    NSParameterAssert(codecRegistry != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _codecRegistry = codecRegistry;
    _mounts = [NSMutableArray array];
    _mountAdapters = [NSMutableDictionary dictionary];
    _nextMountOrder = 0;
    _gameType = UDGameTypeUnknown;
    _gameDirectoryURL = nil;
    return self;
}

- (NSArray<UDVFSMount *> *)mounts {
    return [_mounts copy];
}

- (void)configureWithGameType:(UDGameType)gameType
             gameDirectoryURL:(NSURL *)gameDirectoryURL {
    _gameType = gameType;
    _gameDirectoryURL = gameDirectoryURL;
}

- (nullable UDVFSMount *)mountDirectoryURL:(NSURL *)directoryURL
                                identifier:(NSString *)identifier
                               virtualRoot:(NSString *)virtualRoot
                                  priority:(NSInteger)priority
                                     error:(NSError **)error {
    if (!directoryURL || identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeMountFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Directory mount requires URL and identifier."}];
        }
        return nil;
    }

    BOOL isDirectory = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:directoryURL.path isDirectory:&isDirectory] || !isDirectory) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeMountFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Directory mount path does not exist."}];
        }
        return nil;
    }

    NSString *normalizedRoot = [[self class] normalizeVirtualPath:virtualRoot ?: @""];
    UDVFSMount *mount = [[UDVFSMount alloc] initWithIdentifier:identifier
                                                          kind:UDVFSMountKindDirectory
                                                     sourceURL:directoryURL
                                                   virtualRoot:normalizedRoot
                                                      priority:priority
                                                    mountOrder:_nextMountOrder++];

    UDVFSDirectoryMountAdapter *adapter = [[UDVFSDirectoryMountAdapter alloc] initWithDirectoryURL:directoryURL];
    [_mounts addObject:mount];
    [_mountAdapters setObject:adapter forKey:identifier];
    return mount;
}

- (nullable UDVFSMount *)mountArchiveURL:(NSURL *)archiveURL
                              identifier:(NSString *)identifier
                             virtualRoot:(NSString *)virtualRoot
                                priority:(NSInteger)priority
                                typeName:(NSString *)typeName
                                   error:(NSError **)error {
    if (!archiveURL || identifier.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeMountFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Archive mount requires URL and identifier."}];
        }
        return nil;
    }

    id<UDArchiveCodec> codec = [_codecRegistry codecForURL:archiveURL typeName:typeName];
    if (!codec) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeMountFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"No archive codec found for mount URL."}];
        }
        return nil;
    }

    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:archiveURL error:&readError];
    if (!archive) {
        if (error) {
            *error = readError ?: [NSError errorWithDomain:UDVFSErrorDomain
                                                      code:UDVFSErrorCodeMountFailed
                                                  userInfo:@{NSLocalizedDescriptionKey: @"Failed to read mounted archive."}];
        }
        return nil;
    }

    NSInteger effectivePriority = priority;
    if ([self shouldUseNumberedPakOrdering]) {
        effectivePriority += [self numberedPakPriorityDeltaForURL:archiveURL];
    }

    NSString *normalizedRoot = [[self class] normalizeVirtualPath:virtualRoot ?: @""];
    UDVFSMount *mount = [[UDVFSMount alloc] initWithIdentifier:identifier
                                                          kind:UDVFSMountKindArchive
                                                     sourceURL:archiveURL
                                                   virtualRoot:normalizedRoot
                                                      priority:effectivePriority
                                                    mountOrder:_nextMountOrder++];

    UDVFSArchiveMountAdapter *adapter = [[UDVFSArchiveMountAdapter alloc] initWithArchive:archive];
    [_mounts addObject:mount];
    [_mountAdapters setObject:adapter forKey:identifier];
    return mount;
}

- (NSArray<UDVFSMount *> *)mountDiscoveredArchivesInGameDirectory:(NSError **)error {
    if (!self.gameDirectoryURL) {
        return @[];
    }

    NSError *dirError = nil;
    NSArray<NSURL *> *contents = [[NSFileManager defaultManager]
        contentsOfDirectoryAtURL:self.gameDirectoryURL
      includingPropertiesForKeys:@[NSURLIsRegularFileKey]
                         options:NSDirectoryEnumerationSkipsHiddenFiles
                           error:&dirError];
    if (!contents) {
        if (error) {
            *error = dirError;
        }
        return @[];
    }

    NSMutableSet<NSString *> *mountedArchivePaths = [NSMutableSet set];
    for (UDVFSMount *mount in self.mounts) {
        if (mount.kind != UDVFSMountKindArchive) {
            continue;
        }
        [mountedArchivePaths addObject:mount.sourceURL.path.stringByStandardizingPath];
    }

    NSMutableArray<NSURL *> *candidates = [NSMutableArray array];
    for (NSURL *entryURL in contents) {
        NSNumber *isRegularFile = nil;
        [entryURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:nil];
        if (![isRegularFile boolValue]) {
            continue;
        }

        NSString *standardPath = entryURL.path.stringByStandardizingPath;
        if ([mountedArchivePaths containsObject:standardPath]) {
            continue;
        }

        if (![self isKnownArchiveFileNameForCurrentGame:entryURL.lastPathComponent.lowercaseString]) {
            continue;
        }

        [candidates addObject:entryURL];
    }

    [candidates sortUsingFunction:UDVFSCompareArchiveURLs context:NULL];

    NSMutableArray<UDVFSMount *> *mounted = [NSMutableArray arrayWithCapacity:candidates.count];
    NSError *lastMountError = nil;
    for (NSURL *archiveURL in candidates) {
        NSError *mountError = nil;
        UDVFSMount *mount = [self mountArchiveURL:archiveURL
                                       identifier:[self mountIdentifierForDiscoveredArchiveURL:archiveURL]
                                      virtualRoot:nil
                                         priority:0
                                         typeName:nil
                                            error:&mountError];
        if (mount) {
            [mounted addObject:mount];
        } else if (mountError) {
            lastMountError = mountError;
        }
    }

    if (error && lastMountError) {
        *error = lastMountError;
    }

    return [mounted copy];
}

- (BOOL)unmountIdentifier:(NSString *)identifier {
    if (identifier.length == 0) {
        return NO;
    }

    UDVFSMount *matched = nil;
    for (UDVFSMount *mount in _mounts) {
        if ([mount.identifier isEqualToString:identifier]) {
            matched = mount;
            break;
        }
    }

    if (!matched) {
        return NO;
    }

    [_mounts removeObject:matched];
    [_mountAdapters removeObjectForKey:identifier];
    return YES;
}

- (BOOL)fileExistsAtPath:(NSString *)virtualPath {
    return ([self resolvedFileAtPath:virtualPath error:nil] != nil);
}

- (nullable UDVFSResolvedFile *)resolvedFileAtPath:(NSString *)virtualPath error:(NSError **)error {
    NSString *normalizedPath = [[self class] normalizeVirtualPath:virtualPath];
    if (normalizedPath.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Invalid virtual path."}];
        }
        return nil;
    }

    UDVFSResolvedFile *bestResolved = nil;
    for (UDVFSMount *mount in _mounts) {
        id<UDVFSMountAdapter> adapter = [_mountAdapters objectForKey:mount.identifier];
        if (!adapter) {
            continue;
        }

        UDVFSResolvedFile *resolved = [adapter resolvedFileForVirtualPath:normalizedPath mount:mount error:error];
        if (!resolved) {
            continue;
        }

        if (!bestResolved || [self mount:mount shouldSortBefore:bestResolved.mount]) {
            bestResolved = resolved;
        }
    }

    if (bestResolved) {
        return bestResolved;
    }

    if (error) {
        *error = [NSError errorWithDomain:UDVFSErrorDomain
                                     code:UDVFSErrorCodeNotFound
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"No mounted file found for path: %@", normalizedPath]}];
    }
    return nil;
}

- (NSArray<UDVFSResolvedFile *> *)visibleFilesWithExtensions:(NSSet<NSString *> *)extensions error:(NSError **)error {
    NSSet<NSString *> *normalizedExtensions = nil;
    if (extensions.count > 0) {
        NSMutableSet<NSString *> *lowercased = [NSMutableSet setWithCapacity:extensions.count];
        for (NSString *extension in extensions) {
            if (extension.length > 0) {
                [lowercased addObject:extension.lowercaseString];
            }
        }
        normalizedExtensions = [lowercased copy];
    }

    NSMutableSet<NSString *> *seenPaths = [NSMutableSet set];
    NSMutableArray<UDVFSResolvedFile *> *visibleFiles = [NSMutableArray array];
    NSError *lastError = nil;
    NSArray<UDVFSMount *> *orderedMounts = [self sortedMountsForResolution];

    for (UDVFSMount *mount in orderedMounts) {
        id<UDVFSMountAdapter> adapter = [_mountAdapters objectForKey:mount.identifier];
        if (!adapter) {
            continue;
        }

        NSError *enumerationError = nil;
        NSArray<NSString *> *relativePaths = [adapter allRelativePaths:&enumerationError];
        if (!relativePaths) {
            if (enumerationError) {
                lastError = enumerationError;
            }
            continue;
        }

        for (NSString *relativePath in relativePaths) {
            NSString *virtualPath = relativePath;
            if (mount.virtualRoot.length > 0) {
                virtualPath = [mount.virtualRoot stringByAppendingPathComponent:relativePath];
                virtualPath = [virtualPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
            }

            NSString *normalizedVirtualPath = [[self class] normalizeVirtualPath:virtualPath];
            if (normalizedVirtualPath.length == 0 || [seenPaths containsObject:normalizedVirtualPath]) {
                continue;
            }

            if (normalizedExtensions) {
                NSString *extension = normalizedVirtualPath.pathExtension.lowercaseString;
                if (![normalizedExtensions containsObject:extension]) {
                    continue;
                }
            }

            UDVFSResolvedFile *resolved = [adapter resolvedFileForVirtualPath:normalizedVirtualPath mount:mount error:nil];
            if (!resolved) {
                continue;
            }

            [seenPaths addObject:normalizedVirtualPath];
            [visibleFiles addObject:resolved];
        }
    }

    [visibleFiles sortUsingFunction:UDVFSCompareResolvedFiles context:NULL];

    if (error && lastError) {
        *error = lastError;
    }
    return [visibleFiles copy];
}

- (nullable NSData *)readFileAtPath:(NSString *)virtualPath error:(NSError **)error {
    UDVFSResolvedFile *resolved = [self resolvedFileAtPath:virtualPath error:error];
    if (!resolved) {
        return nil;
    }

    if ([resolved.contentSource respondsToSelector:@selector(readAll:)]) {
        NSData *all = [resolved.contentSource readAll:error];
        if (all) {
            return all;
        }
    }

    if (resolved.length > NSUIntegerMax) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Mounted file exceeds platform limits."}];
        }
        return nil;
    }

    return [resolved.contentSource readRange:NSMakeRange(0, (NSUInteger)resolved.length) error:error];
}

- (BOOL)writeFileAtPath:(NSString *)virtualPath data:(NSData *)data error:(NSError **)error {
    NSString *normalizedPath = [[self class] normalizeVirtualPath:virtualPath];
    if (normalizedPath.length == 0 || !data) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeInvalidPath
                                     userInfo:@{NSLocalizedDescriptionKey: @"Transactional write requires a valid virtual path and data."}];
        }
        return NO;
    }

    UDVFSMount *targetMount = nil;
    UDVFSDirectoryMountAdapter *targetAdapter = nil;
    NSURL *targetURL = nil;
    for (UDVFSMount *mount in _mounts) {
        if (mount.kind != UDVFSMountKindDirectory) {
            continue;
        }

        id adapter = [_mountAdapters objectForKey:mount.identifier];
        if (![adapter isKindOfClass:[UDVFSDirectoryMountAdapter class]]) {
            continue;
        }

        NSURL *candidateURL = [(UDVFSDirectoryMountAdapter *)adapter fileURLForVirtualPath:normalizedPath mount:mount];
        if (!candidateURL) {
            continue;
        }

        if (!targetMount || [self mount:mount shouldSortBefore:targetMount]) {
            targetMount = mount;
            targetAdapter = (UDVFSDirectoryMountAdapter *)adapter;
            targetURL = candidateURL;
        }
    }

    if (!targetMount || !targetAdapter || !targetURL) {
        if (error) {
            *error = [NSError errorWithDomain:UDVFSErrorDomain
                                         code:UDVFSErrorCodeReadOnlyPath
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"No writable directory mount available for path: %@", normalizedPath]}];
        }
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSURL *parentURL = [targetURL URLByDeletingLastPathComponent];
    NSError *mkdirError = nil;
    if (![fm createDirectoryAtURL:parentURL
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&mkdirError]) {
        if (error) {
            *error = mkdirError;
        }
        return NO;
    }

    NSString *tempName = [NSString stringWithFormat:@".%@.%@.tmp",
                          targetURL.lastPathComponent,
                          NSUUID.UUID.UUIDString];
    NSURL *tempURL = [parentURL URLByAppendingPathComponent:tempName];

    NSError *writeError = nil;
    if (![data writeToURL:tempURL options:NSDataWritingAtomic error:&writeError]) {
        if (error) {
            *error = writeError;
        }
        return NO;
    }

    NSError *replaceError = nil;
    if ([fm fileExistsAtPath:targetURL.path]) {
#ifdef GNUSTEP
        // Non-atomic replacement under GNUstep
        NSError *removeError = nil;
        if (![fm removeItemAtURL:targetURL error:&removeError]) {
            NSError *cleanupError = nil;
            if (![fm removeItemAtURL:tempURL error:&cleanupError]) {
                NSLog(@"UDVirtualFileSystem: Failed to clean up temporary file at %@: %@", tempURL, cleanupError);
            }
            if (error) {
                *error = removeError;
            }
            return NO;
        }
        if (![fm moveItemAtURL:tempURL toURL:targetURL error:&replaceError]) {
            NSError *cleanupError = nil;
            if (![fm removeItemAtURL:tempURL error:&cleanupError]) {
                NSLog(@"UDVirtualFileSystem: Failed to clean up temporary file at %@: %@", tempURL, cleanupError);
            }
            if (error) {
                *error = replaceError;
            }
            return NO;
        }
#else
        if (![fm replaceItemAtURL:targetURL
                    withItemAtURL:tempURL
                   backupItemName:nil
                          options:0
                 resultingItemURL:nil
                            error:&replaceError]) {
            [fm removeItemAtURL:tempURL error:nil];
            if (error) {
                *error = replaceError ?: [NSError errorWithDomain:UDVFSErrorDomain
                                                            code:UDVFSErrorCodeWriteFailed
                                                         userInfo:@{NSLocalizedDescriptionKey: @"Transactional replace failed."}];
            }
            return NO;
        }
#endif
    } else if (![fm moveItemAtURL:tempURL toURL:targetURL error:&replaceError]) {
        [fm removeItemAtURL:tempURL error:nil];
        if (error) {
            *error = replaceError;
        }
        return NO;
    }


    [[NSNotificationCenter defaultCenter] postNotificationName:UDVFSDidWriteFileNotification
                                                        object:self
                                                      userInfo:@{
                                                          UDVFSNotificationVirtualPathKey: normalizedPath,
                                                          UDVFSNotificationFileURLKey: targetURL,
                                                          UDVFSNotificationMountIdentifierKey: targetMount.identifier,
                                                      }];
    return YES;
}

- (NSArray<UDVFSMount *> *)sortedMountsForResolution {
    return [_mounts sortedArrayUsingComparator:^NSComparisonResult(UDVFSMount *left, UDVFSMount *right) {
        if ([self mount:left shouldSortBefore:right]) {
            return NSOrderedAscending;
        }
        if ([self mount:right shouldSortBefore:left]) {
            return NSOrderedDescending;
        }
        return NSOrderedSame;
    }];
}

- (BOOL)mount:(UDVFSMount *)a shouldSortBefore:(UDVFSMount *)b {
    if (a.priority != b.priority) {
        return (a.priority > b.priority);
    }

    if (a.kind != b.kind) {
        /* Loose files should override archives at the same priority. */
        return (a.kind == UDVFSMountKindDirectory);
    }

    if (a.kind == UDVFSMountKindArchive && b.kind == UDVFSMountKindArchive) {
        NSComparisonResult archiveCompare = [self compareArchiveMountPrecedence:a other:b];
        if (archiveCompare == NSOrderedAscending) {
            return YES;
        }
        if (archiveCompare == NSOrderedDescending) {
            return NO;
        }
    }

    if (a.mountOrder != b.mountOrder) {
        return (a.mountOrder > b.mountOrder);
    }

    return YES;
}

- (NSComparisonResult)compareArchiveMountPrecedence:(UDVFSMount *)a other:(UDVFSMount *)b {
    NSString *aName = a.sourceURL.lastPathComponent.lowercaseString;
    NSString *bName = b.sourceURL.lastPathComponent.lowercaseString;

    if ([self shouldUseNumberedPakOrdering]) {
        NSInteger aNum = [self pakNumberFromArchiveName:aName];
        NSInteger bNum = [self pakNumberFromArchiveName:bName];
        if (aNum != bNum) {
            return (aNum > bNum) ? NSOrderedAscending : NSOrderedDescending;
        }
    }

    if ([self shouldUseLexicalArchiveOrdering]) {
        NSComparisonResult cmp = [aName compare:bName options:NSCaseInsensitiveSearch];
        if (cmp != NSOrderedSame) {
            /* Later lexical names win in Q3/D3 style game dirs. */
            return (cmp == NSOrderedDescending) ? NSOrderedAscending : NSOrderedDescending;
        }
    }

    return NSOrderedSame;
}

- (BOOL)shouldUseNumberedPakOrdering {
    return (_gameType == UDGameTypeQuake1 ||
            _gameType == UDGameTypeQuake2 ||
            _gameType == UDGameTypeDaikatana);
}

- (BOOL)shouldUseLexicalArchiveOrdering {
    return (_gameType == UDGameTypeQuake3 ||
            _gameType == UDGameTypeDoom3);
}

- (NSInteger)pakNumberFromArchiveName:(NSString *)name {
    if (name.length < 8) {
        return -1;
    }

    if (![name hasPrefix:@"pak"] || ![name hasSuffix:@".pak"]) {
        return -1;
    }

    NSString *middle = [name substringWithRange:NSMakeRange(3, name.length - 7)];
    if (middle.length == 0) {
        return -1;
    }

    NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([middle rangeOfCharacterFromSet:nonDigits].location != NSNotFound) {
        return -1;
    }

    return middle.integerValue;
}

- (NSInteger)numberedPakPriorityDeltaForURL:(NSURL *)url {
    NSInteger pakNumber = [self pakNumberFromArchiveName:url.lastPathComponent.lowercaseString];
    if (pakNumber < 0) {
        return 0;
    }
    return pakNumber * 100;
}

- (BOOL)isKnownArchiveFileNameForCurrentGame:(NSString *)fileName {
    NSString *lowerName = fileName.lowercaseString;

    switch (self.gameType) {
        case UDGameTypeQuake1:
        case UDGameTypeQuake2:
        case UDGameTypeDaikatana:
            return ([self pakNumberFromArchiveName:lowerName] >= 0);
        case UDGameTypeQuake3:
            return [lowerName hasSuffix:@".pk3"];
        case UDGameTypeDoom3:
            return [lowerName hasSuffix:@".pk4"];
        case UDGameTypeUnknown:
        default:
            return ([lowerName hasSuffix:@".pak"] ||
                    [lowerName hasSuffix:@".pk3"] ||
                    [lowerName hasSuffix:@".pk4"]);
    }
}

- (NSString *)mountIdentifierForDiscoveredArchiveURL:(NSURL *)archiveURL {
    return [NSString stringWithFormat:@"archive:%@", archiveURL.lastPathComponent];
}

@end
