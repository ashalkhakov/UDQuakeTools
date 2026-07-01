#import "UDAssetIndex.h"

static NSString *const UDDeclParserErrorDomain = @"com.udquake.error.declparser";

static NSSet<NSString *> *UDIndexedAssetExtensions(void) {
    static NSSet<NSString *> *extensions = nil;
    if (!extensions) {
        extensions = [NSSet setWithObjects:@"def", @"mtr", @"skin", @"sndshd", @"fx", @"prt", @"xdata", @"pda", @"af", @"gui", @"script", nil];
    }
    return extensions;
}

static UDAssetKind UDAssetKindForExtension(NSString *fileExtension) {
    NSString *lowerExtension = fileExtension.lowercaseString;
    if ([lowerExtension isEqualToString:@"def"] ||
        [lowerExtension isEqualToString:@"mtr"] ||
        [lowerExtension isEqualToString:@"skin"] ||
        [lowerExtension isEqualToString:@"sndshd"] ||
        [lowerExtension isEqualToString:@"fx"] ||
        [lowerExtension isEqualToString:@"prt"] ||
        [lowerExtension isEqualToString:@"xdata"] ||
        [lowerExtension isEqualToString:@"pda"] ||
        [lowerExtension isEqualToString:@"af"]) {
        return UDAssetKindDecl;
    }
    if ([lowerExtension isEqualToString:@"gui"]) {
        return UDAssetKindGUI;
    }
    if ([lowerExtension isEqualToString:@"script"]) {
        return UDAssetKindScript;
    }
    return UDAssetKindUnknown;
}

static NSString *UDDefaultDeclTypeForSourceVirtualPath(NSString *sourceVirtualPath) {
    NSString *extension = sourceVirtualPath.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"mtr"]) {
        return @"material";
    }
    if ([extension isEqualToString:@"skin"]) {
        return @"skin";
    }
    if ([extension isEqualToString:@"sndshd"]) {
        return @"sound";
    }
    if ([extension isEqualToString:@"fx"]) {
        return @"fx";
    }
    if ([extension isEqualToString:@"prt"]) {
        return @"particle";
    }
    if ([extension isEqualToString:@"xdata"]) {
        return @"xdata";
    }
    if ([extension isEqualToString:@"pda"]) {
        return @"pda";
    }
    if ([extension isEqualToString:@"af"]) {
        return @"articulatedFigure";
    }
    return @"decl";
}

static NSString *UDCanonicalDeclType(NSString *declType) {
    NSString *lower = declType.lowercaseString;
    if ([lower isEqualToString:@"entitydef"]) {
        return @"entityDef";
    }
    if ([lower isEqualToString:@"articulatedfigure"]) {
        return @"articulatedFigure";
    }
    if ([lower isEqualToString:@"modeldef"]) {
        return @"modelDef";
    }
    if ([lower isEqualToString:@"sound"]) {
        return @"sound";
    }
    if ([lower isEqualToString:@"material"]) {
        return @"material";
    }
    if ([lower isEqualToString:@"particle"]) {
        return @"particle";
    }
    if ([lower isEqualToString:@"skin"]) {
        return @"skin";
    }
    if ([lower isEqualToString:@"fx"]) {
        return @"fx";
    }
    if ([lower isEqualToString:@"xdata"]) {
        return @"xdata";
    }
    if ([lower isEqualToString:@"pda"]) {
        return @"pda";
    }
    return declType;
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
    UDIdParser *parser = [[UDIdParser alloc] initWithText:text];

    while (YES) {
        UDIdToken *first = [parser readToken];
        if (first.kind == UDIdTokenKindEOF) {
            break;
        }

        if (first.kind != UDIdTokenKindIdentifier && first.kind != UDIdTokenKindString) {
            continue;
        }

        NSString *declType = first.text;
        NSString *declName = nil;
        UDIdToken *openBrace = nil;

        UDIdToken *second = [parser readToken];
        if (second.kind == UDIdTokenKindPunctuation && [second.text isEqualToString:@"{"]) {
            // Single-token headers (e.g., many .mtr entries): token is the name.
            declName = declType;
            declType = UDDefaultDeclTypeForSourceVirtualPath(sourceVirtualPath);
            openBrace = second;
        } else if (second.kind == UDIdTokenKindIdentifier || second.kind == UDIdTokenKindString) {
            declName = second.text;
            UDIdToken *third = [parser peekToken];
            if (third.kind == UDIdTokenKindPunctuation && [third.text isEqualToString:@"{"]) {
                [parser expectPunctuation:@"{"];
                openBrace = third;
            } else {
                [parser skipUntilPunctuation:@"}"];
                continue;
            }
        } else {
            [parser skipUntilPunctuation:@"}"];
            continue;
        }

        NSInteger braceDepth = 1;
        UDIdToken *closingBrace = nil;
        while (braceDepth > 0) {
            UDIdToken *token = [parser readToken];
            if (token.kind == UDIdTokenKindEOF) {
                break;
            }

            if (token.kind == UDIdTokenKindPunctuation) {
                if ([token.text isEqualToString:@"{"]) {
                    braceDepth++;
                } else if ([token.text isEqualToString:@"}"]) {
                    braceDepth--;
                    if (braceDepth == 0) {
                        closingBrace = token;
                    }
                }
            }
        }

        if (!closingBrace) {
            // Preserve parser resilience: skip malformed trailing decl and keep already parsed entries.
            break;
        }

        NSUInteger bodyStart = openBrace.end;
        NSUInteger bodyEnd = closingBrace.start;
        if (bodyEnd < bodyStart || bodyStart > text.length || bodyEnd > text.length) {
            continue;
        }

        NSString *body = [text substringWithRange:NSMakeRange(bodyStart, bodyEnd - bodyStart)];
        if (declType.length == 0 || declName.length == 0) {
            continue;
        }

        NSString *canonicalType = UDCanonicalDeclType(declType);
        UDDeclDefinition *definition = [[UDDeclDefinition alloc] initWithDeclType:canonicalType
                                                                          declName:declName
                                                                              body:body
                                                                 sourceVirtualPath:sourceVirtualPath];
        [definitions addObject:definition];
    }

    if (error) {
        *error = nil;
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
    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    return [declManager buildDeclModelFromAssetIndex:assetIndex
                                  persistenceAdapter:persistenceAdapter
                                                error:error];
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
    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    return [declManager rebuildDeclModelByApplyingWriteNotification:notification
                                                    toExistingModel:existingModel
                                                         assetIndex:assetIndex
                                                 persistenceAdapter:persistenceAdapter
                                                              error:error];
}

@end
