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

static NSComparisonResult UDCompareDeclDefinitionsForSortField(UDDeclDefinition *left,
                                                               UDDeclDefinition *right,
                                                               UDDeclQuerySortField sortField,
                                                               BOOL ascending) {
    NSComparisonResult primary = NSOrderedSame;
    switch (sortField) {
        case UDDeclQuerySortFieldType:
            primary = [left.declType compare:right.declType options:NSCaseInsensitiveSearch];
            break;
        case UDDeclQuerySortFieldSourcePath:
            primary = [left.sourceVirtualPath compare:right.sourceVirtualPath options:NSCaseInsensitiveSearch];
            break;
        case UDDeclQuerySortFieldName:
        default:
            primary = [left.declName compare:right.declName options:NSCaseInsensitiveSearch];
            break;
    }

    if (primary == NSOrderedSame) {
        primary = UDCompareDeclDefinitions(left, right, NULL);
    }

    if (!ascending) {
        if (primary == NSOrderedAscending) {
            return NSOrderedDescending;
        }
        if (primary == NSOrderedDescending) {
            return NSOrderedAscending;
        }
    }
    return primary;
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

- (NSArray<UDDeclDefinition *> *)definitionsWithNameContaining:(NSString *)nameFragment {
    if (nameFragment.length == 0) {
        return [self.definitions copy];
    }

    NSMutableArray<UDDeclDefinition *> *results = [NSMutableArray array];
    for (UDDeclDefinition *definition in self.definitions) {
        if ([definition.declName rangeOfString:nameFragment options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [results addObject:definition];
        }
    }
    return results;
}

- (NSArray<UDDeclDefinition *> *)definitionsFromSourceVirtualPath:(NSString *)sourceVirtualPath {
    NSMutableArray<UDDeclDefinition *> *results = [NSMutableArray array];
    for (UDDeclDefinition *definition in self.definitions) {
        if ([definition.sourceVirtualPath isEqualToString:sourceVirtualPath]) {
            [results addObject:definition];
        }
    }
    return results;
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

        UDDeclDefinition *definition = [[UDDeclDefinition alloc] initWithDeclType:declType
                                                                          declName:declName
                                                                              body:body
                                                                 sourceVirtualPath:sourceVirtualPath];
        [definitions addObject:definition];

        index = cursor;
    }

    return definitions;
}

- (NSString *)serializeDefinitions:(NSArray<UDDeclDefinition *> *)definitions {
    NSMutableString *text = [NSMutableString string];
    NSUInteger count = definitions.count;
    for (NSUInteger i = 0; i < count; i++) {
        UDDeclDefinition *definition = [definitions objectAtIndex:i];
        [text appendFormat:@"%@ %@ {%@}", definition.declType, definition.declName, definition.body ?: @""];
        if (i + 1 < count) {
            [text appendString:@"\n\n"];
        }
    }
    return text;
}

@end

@implementation UDVFSDeclPersistenceAdapter

@synthesize virtualFileSystem = _virtualFileSystem;

- (instancetype)initWithVirtualFileSystem:(UDVirtualFileSystem *)virtualFileSystem {
    NSParameterAssert(virtualFileSystem != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _virtualFileSystem = virtualFileSystem;
    return self;
}

- (nullable NSString *)readDeclTextAtVirtualPath:(NSString *)virtualPath
                                           error:(NSError **)error {
    NSData *data = [self.virtualFileSystem readFileAtPath:virtualPath error:error];
    if (!data) {
        return nil;
    }

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text) {
        text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
    }

    if (!text && error) {
        *error = [NSError errorWithDomain:UDDeclParserErrorDomain
                                     code:4
                                 userInfo:@{NSLocalizedDescriptionKey: @"Unable to decode decl file."}];
    }
    return text;
}

- (BOOL)writeDeclText:(NSString *)text
         toVirtualPath:(NSString *)virtualPath
                 error:(NSError **)error {
    NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
    return [self.virtualFileSystem writeFileAtPath:virtualPath data:data error:error];
}

@end

@implementation UDDeclQueryRequest

@synthesize searchText = _searchText;
@synthesize declType = _declType;
@synthesize sourceVirtualPath = _sourceVirtualPath;
@synthesize sortField = _sortField;
@synthesize ascending = _ascending;
@synthesize maxResults = _maxResults;

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _searchText = nil;
    _declType = nil;
    _sourceVirtualPath = nil;
    _sortField = UDDeclQuerySortFieldName;
    _ascending = YES;
    _maxResults = 0;
    return self;
}

@end

@implementation UDDeclQueryService

- (NSArray<UDDeclDefinition *> *)queryDefinitionsInModel:(UDDeclModel *)model
                                                  request:(UDDeclQueryRequest *)request {
    NSParameterAssert(model != nil);

    UDDeclQueryRequest *effectiveRequest = request ?: [[UDDeclQueryRequest alloc] init];
    NSMutableArray<UDDeclDefinition *> *filtered = [NSMutableArray array];

    for (UDDeclDefinition *definition in model.definitions) {
        if (effectiveRequest.declType.length > 0 &&
            [definition.declType caseInsensitiveCompare:effectiveRequest.declType] != NSOrderedSame) {
            continue;
        }

        if (effectiveRequest.sourceVirtualPath.length > 0 &&
            [definition.sourceVirtualPath caseInsensitiveCompare:effectiveRequest.sourceVirtualPath] != NSOrderedSame) {
            continue;
        }

        if (effectiveRequest.searchText.length > 0) {
            NSStringCompareOptions options = NSCaseInsensitiveSearch;
            BOOL matched = ([definition.declName rangeOfString:effectiveRequest.searchText options:options].location != NSNotFound ||
                            [definition.declType rangeOfString:effectiveRequest.searchText options:options].location != NSNotFound ||
                            [definition.sourceVirtualPath rangeOfString:effectiveRequest.searchText options:options].location != NSNotFound);
            if (!matched) {
                continue;
            }
        }

        [filtered addObject:definition];
    }

    [filtered sortUsingComparator:^NSComparisonResult(UDDeclDefinition *left, UDDeclDefinition *right) {
        return UDCompareDeclDefinitionsForSortField(left,
                                                    right,
                                                    effectiveRequest.sortField,
                                                    effectiveRequest.isAscending);
    }];

    if (effectiveRequest.maxResults > 0 && filtered.count > effectiveRequest.maxResults) {
        return [filtered subarrayWithRange:NSMakeRange(0, effectiveRequest.maxResults)];
    }

    return [filtered copy];
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
    UDVFSDeclPersistenceAdapter *adapter = [[UDVFSDeclPersistenceAdapter alloc] initWithVirtualFileSystem:virtualFileSystem];
    return [self buildDeclModelFromAssetIndex:assetIndex persistenceAdapter:adapter error:error];
}

- (UDDeclModel *)buildDeclModelFromAssetIndex:(UDAssetIndex *)assetIndex
                           persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                         error:(NSError **)error {
    NSParameterAssert(assetIndex != nil);
    NSParameterAssert(persistenceAdapter != nil);

    UDDeclParser *parser = [[UDDeclParser alloc] init];
    NSMutableArray<UDDeclDefinition *> *definitions = [NSMutableArray array];

    for (UDAssetIndexEntry *entry in [assetIndex entriesOfKind:UDAssetKindDecl]) {
        NSError *readError = nil;
        NSString *text = [persistenceAdapter readDeclTextAtVirtualPath:entry.virtualPath error:&readError];
        if (!text) {
            if (error) {
                *error = readError;
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
    UDVFSDeclPersistenceAdapter *adapter = [[UDVFSDeclPersistenceAdapter alloc] initWithVirtualFileSystem:virtualFileSystem];
    return [self rebuildDeclModelByApplyingWriteNotification:notification
                                    toExistingModel:existingModel
                                        assetIndex:assetIndex
                                 persistenceAdapter:adapter
                                            error:error];
}

- (UDDeclModel *)rebuildDeclModelByApplyingWriteNotification:(NSNotification *)notification
                                     toExistingModel:(UDDeclModel *)existingModel
                                         assetIndex:(UDAssetIndex *)assetIndex
                                  persistenceAdapter:(id<UDDeclPersistenceAdapter>)persistenceAdapter
                                             error:(NSError **)error {
    NSParameterAssert(notification != nil);
    NSParameterAssert(existingModel != nil);
    NSParameterAssert(assetIndex != nil);
    NSParameterAssert(persistenceAdapter != nil);

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
                                                       persistenceAdapter:persistenceAdapter
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
