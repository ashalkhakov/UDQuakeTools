#import "UDAssetIndex.h"

static NSString *const UDDeclParserErrorDomain = @"com.udquake.error.declparser";

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

static BOOL UDDeclIsTokenCharacter(unichar character) {
    if ([[NSCharacterSet alphanumericCharacterSet] characterIsMember:character]) {
        return YES;
    }

    switch (character) {
        case '_':
        case '/':
        case '.':
        case ':':
        case '-':
            return YES;
        default:
            return NO;
    }
}

static void UDSkipDeclWhitespaceAndComments(NSString *text, NSUInteger *indexRef) {
    NSUInteger length = text.length;
    NSUInteger index = *indexRef;

    while (index < length) {
        unichar ch = [text characterAtIndex:index];
        if ([[NSCharacterSet whitespaceAndNewlineCharacterSet] characterIsMember:ch]) {
            index++;
            continue;
        }

        if (ch == '/' && (index + 1) < length) {
            unichar next = [text characterAtIndex:(index + 1)];
            if (next == '/') {
                index += 2;
                while (index < length && [text characterAtIndex:index] != '\n') {
                    index++;
                }
                continue;
            }

            if (next == '*') {
                index += 2;
                while ((index + 1) < length) {
                    if ([text characterAtIndex:index] == '*' && [text characterAtIndex:(index + 1)] == '/') {
                        index += 2;
                        break;
                    }
                    index++;
                }
                continue;
            }
        }

        break;
    }

    *indexRef = index;
}

static NSString *UDReadDeclToken(NSString *text, NSUInteger *indexRef) {
    NSUInteger length = text.length;
    NSUInteger index = *indexRef;
    if (index >= length) {
        return nil;
    }

    if (!UDDeclIsTokenCharacter([text characterAtIndex:index])) {
        return nil;
    }

    NSUInteger start = index;
    while (index < length && UDDeclIsTokenCharacter([text characterAtIndex:index])) {
        index++;
    }

    *indexRef = index;
    return [text substringWithRange:NSMakeRange(start, index - start)];
}

static NSComparisonResult UDCompareAssetEntries(id leftObject, id rightObject, void *context) {
    (void)context;
    UDAssetIndexEntry *left = (UDAssetIndexEntry *)leftObject;
    UDAssetIndexEntry *right = (UDAssetIndexEntry *)rightObject;
    return [left.virtualPath compare:right.virtualPath options:NSCaseInsensitiveSearch];
}

static NSComparisonResult UDCompareDeclDefinitions(id leftObject, id rightObject, void *context) {
    (void)context;
    UDDeclDefinition *left = (UDDeclDefinition *)leftObject;
    UDDeclDefinition *right = (UDDeclDefinition *)rightObject;

    NSComparisonResult typeResult = [left.declType compare:right.declType options:NSCaseInsensitiveSearch];
    if (typeResult != NSOrderedSame) {
        return typeResult;
    }

    NSComparisonResult nameResult = [left.declName compare:right.declName options:NSCaseInsensitiveSearch];
    if (nameResult != NSOrderedSame) {
        return nameResult;
    }

    return [left.sourceVirtualPath compare:right.sourceVirtualPath options:NSCaseInsensitiveSearch];
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

@implementation UDDeclDefinition

@synthesize declType = _declType;
@synthesize declName = _declName;
@synthesize body = _body;
@synthesize sourceVirtualPath = _sourceVirtualPath;

- (instancetype)initWithDeclType:(NSString *)declType
                        declName:(NSString *)declName
                            body:(NSString *)body
               sourceVirtualPath:(NSString *)sourceVirtualPath {
    NSParameterAssert(declType.length > 0);
    NSParameterAssert(declName.length > 0);
    NSParameterAssert(body != nil);
    NSParameterAssert(sourceVirtualPath.length > 0);

    self = [super init];
    if (!self) {
        return nil;
    }

    _declType = [declType copy];
    _declName = [declName copy];
    _body = [body copy];
    _sourceVirtualPath = [sourceVirtualPath copy];
    return self;
}

@end

@implementation UDDeclModel

@synthesize definitions = _definitions;

- (instancetype)initWithDefinitions:(NSArray<UDDeclDefinition *> *)definitions {
    NSParameterAssert(definitions != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _definitions = [definitions copy];
    return self;
}

- (NSArray<UDDeclDefinition *> *)definitionsOfType:(NSString *)declType {
    NSMutableArray<UDDeclDefinition *> *results = [NSMutableArray array];
    for (UDDeclDefinition *definition in self.definitions) {
        if ([definition.declType caseInsensitiveCompare:declType] == NSOrderedSame) {
            [results addObject:definition];
        }
    }
    return results;
}

- (nullable UDDeclDefinition *)definitionWithType:(NSString *)declType name:(NSString *)declName {
    for (UDDeclDefinition *definition in self.definitions) {
        if ([definition.declType caseInsensitiveCompare:declType] == NSOrderedSame &&
            [definition.declName caseInsensitiveCompare:declName] == NSOrderedSame) {
            return definition;
        }
    }
    return nil;
}

@end

@implementation UDDeclParser

- (NSArray<UDDeclDefinition *> *)parseDefinitionsFromText:(NSString *)text
                                         sourceVirtualPath:(NSString *)sourceVirtualPath
                                                     error:(NSError **)error {
    NSParameterAssert(text != nil);
    NSParameterAssert(sourceVirtualPath.length > 0);

    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray array];
    NSUInteger index = 0;
    NSUInteger length = text.length;

    while (index < length) {
        UDSkipDeclWhitespaceAndComments(text, &index);
        if (index >= length) {
            break;
        }

        NSString *declType = UDReadDeclToken(text, &index);
        if (!declType) {
            index++;
            continue;
        }

        UDSkipDeclWhitespaceAndComments(text, &index);
        NSString *declName = UDReadDeclToken(text, &index);
        if (!declName) {
            if (error) {
                *error = [NSError errorWithDomain:UDDeclParserErrorDomain
                                             code:1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Malformed decl: missing name token."}];
            }
            return nil;
        }

        UDSkipDeclWhitespaceAndComments(text, &index);
        if (index >= length || [text characterAtIndex:index] != '{') {
            if (error) {
                *error = [NSError errorWithDomain:UDDeclParserErrorDomain
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: @"Malformed decl: missing opening brace."}];
            }
            return nil;
        }

        NSUInteger bodyStart = index + 1;
        NSUInteger cursor = bodyStart;
        NSInteger braceDepth = 1;
        BOOL inDoubleQuote = NO;
        BOOL inSingleQuote = NO;

        while (cursor < length && braceDepth > 0) {
            unichar ch = [text characterAtIndex:cursor];

            if (!inDoubleQuote && !inSingleQuote && ch == '/' && (cursor + 1) < length) {
                unichar next = [text characterAtIndex:(cursor + 1)];
                if (next == '/') {
                    cursor += 2;
                    while (cursor < length && [text characterAtIndex:cursor] != '\n') {
                        cursor++;
                    }
                    continue;
                }
                if (next == '*') {
                    cursor += 2;
                    while ((cursor + 1) < length) {
                        if ([text characterAtIndex:cursor] == '*' && [text characterAtIndex:(cursor + 1)] == '/') {
                            cursor += 2;
                            break;
                        }
                        cursor++;
                    }
                    continue;
                }
            }

            if (!inSingleQuote && ch == '"') {
                BOOL escaped = (cursor > bodyStart && [text characterAtIndex:(cursor - 1)] == '\\');
                if (!escaped) {
                    inDoubleQuote = !inDoubleQuote;
                }
                cursor++;
                continue;
            }

            if (!inDoubleQuote && ch == '\'') {
                BOOL escaped = (cursor > bodyStart && [text characterAtIndex:(cursor - 1)] == '\\');
                if (!escaped) {
                    inSingleQuote = !inSingleQuote;
                }
                cursor++;
                continue;
            }

            if (!inDoubleQuote && !inSingleQuote) {
                if (ch == '{') {
                    braceDepth++;
                } else if (ch == '}') {
                    braceDepth--;
                }
            }

            cursor++;
        }

        if (braceDepth != 0) {
            if (error) {
                *error = [NSError errorWithDomain:UDDeclParserErrorDomain
                                             code:3
                                         userInfo:@{NSLocalizedDescriptionKey: @"Malformed decl: unmatched braces."}];
            }
            return nil;
        }

        NSUInteger bodyEnd = cursor - 1;
        NSString *body = @"";
        if (bodyEnd >= bodyStart) {
            body = [text substringWithRange:NSMakeRange(bodyStart, bodyEnd - bodyStart)];
        }

        NSString *trimmedBody = [body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        UDDeclDefinition *definition = [[UDDeclDefinition alloc] initWithDeclType:declType
                                                                          declName:declName
                                                                              body:trimmedBody
                                                                 sourceVirtualPath:sourceVirtualPath];
        [definitions addObject:definition];

        index = cursor;
    }

    return definitions;
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

- (UDDeclModel *)buildDeclModelFromAssetIndex:(UDAssetIndex *)assetIndex
                             virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                         error:(NSError **)error {
    NSParameterAssert(assetIndex != nil);
    NSParameterAssert(virtualFileSystem != nil);

    UDDeclParser *parser = [[UDDeclParser alloc] init];
    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray array];

    for (UDAssetIndexEntry *entry in [assetIndex entriesOfKind:UDAssetKindDecl]) {
        NSError *readError = nil;
        NSData *data = [virtualFileSystem readFileAtPath:entry.virtualPath error:&readError];
        if (!data) {
            if (error) {
                *error = readError;
            }
            return nil;
        }

        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text) {
            text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        }
        if (!text) {
            if (error) {
                *error = [NSError errorWithDomain:UDDeclParserErrorDomain
                                             code:4
                                         userInfo:@{NSLocalizedDescriptionKey: @"Unable to decode decl file."}];
            }
            return nil;
        }

        NSError *parseError = nil;
        NSArray<UDDeclDefinition *> *parsed = [parser parseDefinitionsFromText:text
                                                              sourceVirtualPath:entry.virtualPath
                                                                          error:&parseError];
        if (!parsed) {
            if (error) {
                *error = parseError;
            }
            return nil;
        }

        [definitions addObjectsFromArray:parsed];
    }

    [definitions sortUsingFunction:UDCompareDeclDefinitions context:NULL];

    if (error) {
        *error = nil;
    }
    return [[UDDeclModel alloc] initWithDefinitions:definitions];
}

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                              toExistingModel:(UDDeclModel *)existingModel
                                                   assetIndex:(UDAssetIndex *)assetIndex
                                            virtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem
                                                        error:(NSError **)error {
    NSParameterAssert(notification != nil);
    NSParameterAssert(existingModel != nil);
    NSParameterAssert(assetIndex != nil);
    NSParameterAssert(virtualFileSystem != nil);

    NSString *virtualPath = [notification.userInfo objectForKey:UDVFSNotificationVirtualPathKey];
    if (virtualPath.length == 0 || [virtualPath.pathExtension.lowercaseString isEqualToString:@"def"] == NO) {
        return existingModel;
    }

    NSString *normalizedPath = [virtualPath stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
    while ([normalizedPath hasPrefix:@"/"]) {
        normalizedPath = [normalizedPath substringFromIndex:1];
    }

    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray arrayWithCapacity:existingModel.definitions.count + 8];
    for (UDDeclDefinition *definition in existingModel.definitions) {
        if (![definition.sourceVirtualPath isEqualToString:normalizedPath]) {
            [definitions addObject:definition];
        }
    }

    UDAssetIndexEntry *entry = [assetIndex entryForVirtualPath:normalizedPath];
    if (entry && entry.kind == UDAssetKindDecl) {
        UDAssetIndex *singleFileIndex = [[UDAssetIndex alloc] initWithEntries:@[entry]];
        UDDeclModel *singleFileModel = [self buildDeclModelFromAssetIndex:singleFileIndex
                                                         virtualFileSystem:virtualFileSystem
                                                                     error:error];
        if (!singleFileModel) {
            return nil;
        }
        [definitions addObjectsFromArray:singleFileModel.definitions];
    }

    [definitions sortUsingFunction:UDCompareDeclDefinitions context:NULL];

    if (error) {
        *error = nil;
    }
    return [[UDDeclModel alloc] initWithDefinitions:definitions];
}

@end
