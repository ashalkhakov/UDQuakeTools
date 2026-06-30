/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDArchiveDocument.h"
#import "UDArchiveBrowserController.h"
#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveCodec.h"
#import "UDCodecRegistry.h"

@implementation UDArchiveDocument

@synthesize archive = _archive;
@synthesize editor  = _editor;
@synthesize codec   = _codec;

static NSString *UDArchiveTypeDisplayName(NSString *typeName) {
    if ([typeName isEqualToString:@"com.udquake.pak"]) {
        return @"Quake PAK Archive";
    }
    if ([typeName isEqualToString:@"com.udquake.pak2"]) {
        return @"Quake II PAK Archive";
    }
    if ([typeName isEqualToString:@"com.udquake.daikatana-pak"]) {
        return @"Daikatana PAK Archive";
    }
    if ([typeName isEqualToString:@"com.udquake.pk3"]) {
        return @"Quake III PK3 Archive";
    }
    if ([typeName isEqualToString:@"com.udquake.pk4"]) {
        return @"Doom 3 / Quake 4 PK4 Archive";
    }
    return nil;
}

static NSString *UDArchiveTypeExtension(NSString *typeName) {
    if ([typeName isEqualToString:@"com.udquake.pak"] ||
        [typeName isEqualToString:@"com.udquake.pak2"] ||
        [typeName isEqualToString:@"com.udquake.daikatana-pak"]) {
        return @"pak";
    }
    if ([typeName isEqualToString:@"com.udquake.pk3"]) {
        return @"pk3";
    }
    if ([typeName isEqualToString:@"com.udquake.pk4"]) {
        return @"pk4";
    }
    return nil;
}

static NSString *UDArchiveCanonicalTypeName(NSString *typeName) {
    if (typeName.length == 0) {
        return nil;
    }

    if ([typeName hasPrefix:@"com.udquake."]) {
        return typeName;
    }

    if ([typeName isEqualToString:@"Quake PAK Archive"]) {
        return @"com.udquake.pak";
    }
    if ([typeName isEqualToString:@"Quake II PAK Archive"]) {
        return @"com.udquake.pak2";
    }
    if ([typeName isEqualToString:@"Daikatana PAK Archive"]) {
        return @"com.udquake.daikatana-pak";
    }
    if ([typeName isEqualToString:@"Quake III PK3 Archive"]) {
        return @"com.udquake.pk3";
    }
    if ([typeName isEqualToString:@"Doom 3 / Quake 4 PK4 Archive"] ||
        [typeName isEqualToString:@"Doom 3 PK4 Archive"]) {
        return @"com.udquake.pk4";
    }

    return nil;
}

static NSURL *UDWritableFileURLFromURL(NSURL *url) {
    if (!url) {
        return nil;
    }

    if ([url isFileURL] && url.path.length > 0) {
        return url;
    }

    NSString *path = url.path;
    if (path.length == 0) {
        NSString *absolute = url.absoluteString;
        if ([absolute hasPrefix:@"file://"]) {
            path = [absolute substringFromIndex:7];
            NSString *decoded = [path stringByRemovingPercentEncoding];
            if (decoded.length > 0) {
                path = decoded;
            }
        }
    }

    if (path.length == 0) {
        return nil;
    }

    return [NSURL fileURLWithPath:path];
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _archive = [[UDArchive alloc] initWithDisplayName:@"Untitled"
                                               entries:@[]
                                              metadata:@{}];
    _editor = [[UDArchiveEditor alloc] initWithArchive:_archive];
    return self;
}

/* ------------------------------------------------------------------ */
#pragma mark - NSDocument overrides

- (void)makeWindowControllers {
    UDArchiveBrowserController *wc =
        [[UDArchiveBrowserController alloc] initWithDocument:self];
    [self addWindowController:wc];
}

- (NSUndoManager *)undoManager {
    if (self.editor) {
        return self.editor.undoManager;
    }
    return [super undoManager];
}

- (NSArray<NSString *> *)readableTypes {
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    NSMutableArray<NSString *> *types = [NSMutableArray array];
    for (id<UDArchiveCodec> codec in [reg allCodecs]) {
        if (![types containsObject:codec.formatIdentifier]) {
            [types addObject:codec.formatIdentifier];
        }
    }
    return (types.count > 0) ? [types copy] : @[@"com.udquake.pak", @"com.udquake.pk3", @"com.udquake.pk4"];
}

- (NSArray<NSString *> *)writableTypes {
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    NSMutableArray<NSString *> *types = [NSMutableArray array];
    for (id<UDArchiveCodec> codec in [reg allCodecs]) {
        if (![types containsObject:codec.formatIdentifier]) {
            [types addObject:codec.formatIdentifier];
        }
    }
    if (types.count == 0) {
        types = [@[@"com.udquake.pak", @"com.udquake.pk3", @"com.udquake.pk4"] mutableCopy];
    }
#ifdef GNUSTEP
    /* GNUstep shows the writableTypes strings verbatim in the save panel
     * format popup — it does not call displayNameForType: like macOS does.
     * Return display names so the user sees "Quake PAK Archive" etc. instead
     * of raw UTI identifiers. writeToURL:ofType: handles both forms via
     * UDArchiveCanonicalTypeName. */
    NSMutableArray<NSString *> *displayNames = [NSMutableArray arrayWithCapacity:types.count];
    for (NSString *identifier in types) {
        NSString *display = UDArchiveTypeDisplayName(identifier);
        [displayNames addObject:display ? display : identifier];
    }
    return displayNames;
#else
    return [types copy];
#endif
}

- (NSArray<NSString *> *)writableTypesForSaveOperation:(NSSaveOperationType)saveOperation {
    (void)saveOperation;
    return [self writableTypes];
}

- (NSString *)displayNameForType:(NSString *)typeName {
    NSString *display = UDArchiveTypeDisplayName(typeName);
    return display ? display : typeName;
}

- (NSString *)fileNameExtensionForType:(NSString *)typeName
                         saveOperation:(NSSaveOperationType)saveOperation {
    (void)saveOperation;
    NSString *canonical = UDArchiveCanonicalTypeName(typeName);
    NSString *ext = UDArchiveTypeExtension(canonical ? canonical : typeName);
    return ext ? ext : @"pak";
}

- (BOOL)readFromURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    (void)typeName;
    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];

    NSArray<id<UDArchiveCodec>> *candidates = [reg allCodecs];
    if (candidates.count == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"not supported"}];
        }
        return NO;
    }

    NSError *lastReadError = nil;
    UDArchive *archive = nil;
    id<UDArchiveCodec> selectedCodec = nil;

    for (id<UDArchiveCodec> candidate in candidates) {
        NSError *candidateError = nil;
        archive = [candidate readArchiveFromURL:url error:&candidateError];
        if (archive) {
            selectedCodec = candidate;
            break;
        }
        if (candidateError) {
            lastReadError = candidateError;
        }
    }

    if (!archive || !selectedCodec) {
        if (error) {
            (void)lastReadError;
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileReadUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"This file format is not supported."}];
        }
        return NO;
    }

    _codec   = selectedCodec;
    _archive = archive;
    _editor  = [[UDArchiveEditor alloc] initWithArchive:archive];
    return YES;
}

- (BOOL)writeToURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)error {
    NSURL *inputURL = url;
    url = UDWritableFileURLFromURL(url);

    if (!url || ![url isFileURL] || url.path.length == 0) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileWriteUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey: @"No writable file path was selected for save."}];
        }
        NSLog(@"Save failed before write: rawURL='%@' normalizedURL='%@'", inputURL, url);
        return NO;
    }

    UDCodecRegistry *reg = [UDCodecRegistry sharedRegistry];
    NSString *canonicalType = UDArchiveCanonicalTypeName(typeName);

    /* Always prefer the user-selected save type when available. */
    if (canonicalType.length > 0) {
        _codec = [reg codecForFormatIdentifier:canonicalType];
    }

    if (!_codec) {
        _codec = [reg codecForURL:url typeName:canonicalType ?: typeName];
    }

    if (!_codec) {
        if (error) {
            *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                         code:NSFileWriteUnknownError
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"No codec available for writing this file type."}];
        }
        return NO;
    }

    NSURL *parentDir = [url URLByDeletingLastPathComponent];
    if (parentDir.path.length > 0) {
        NSError *mkdirError = nil;
        BOOL made = [[NSFileManager defaultManager]
            createDirectoryAtURL:parentDir
      withIntermediateDirectories:YES
                       attributes:nil
                            error:&mkdirError];
        if (!made) {
            if (error) {
                *error = mkdirError;
            }
            return NO;
        }
    }

    if (!_editor) {
        _editor = [[UDArchiveEditor alloc] initWithArchive:_archive];
    }

    NSError *writeError = nil;
    BOOL wrote = [_codec writeEditedArchive:_editor toURL:url error:&writeError];
    if (!wrote) {
        if (!writeError) {
            writeError = [NSError errorWithDomain:NSCocoaErrorDomain
                                             code:NSFileWriteUnknownError
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Failed to write archive using codec %@.", _codec.formatIdentifier ?: @"(unknown)"]}];
        }
        if (error) {
            *error = writeError;
        }
        NSLog(@"Save failed: type='%@' canonical='%@' codec='%@' url='%@' error='%@'",
              typeName,
              canonicalType,
              _codec.formatIdentifier,
              url.path,
              writeError);
        return NO;
    }

    return YES;
}

- (BOOL)prepareSavePanel:(NSSavePanel *)savePanel {
    BOOL ok = [super prepareSavePanel:savePanel];
    if (!ok) {
        return NO;
    }

    NSString *suggestedName = self.fileURL.lastPathComponent;
    if (suggestedName.length == 0) {
        suggestedName = _archive.displayName;
    }

    if (suggestedName.length > 0) {
        [savePanel setNameFieldStringValue:suggestedName];
    }

    return YES;
}

@end
