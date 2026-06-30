#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDAssetIndex.h"
#import "UDCodecRegistry.h"
#import "UDContentSource.h"
#import "UDPAKCodec.h"
#import "UDPK4Codec.h"

@interface UDAssetIndexTestContentSource : NSObject <UDContentSource>
@property (nonatomic, strong, readonly) NSData *data;
- (instancetype)initWithData:(NSData *)data;
@end

@implementation UDAssetIndexTestContentSource

- (instancetype)initWithData:(NSData *)data {
    NSParameterAssert(data != nil);
    self = [super init];
    if (!self) {
        return nil;
    }
    _data = data;
    return self;
}

- (uint64_t)length {
    return (uint64_t)self.data.length;
}

- (NSData *)readRange:(NSRange)range error:(NSError **)error {
    if (range.location > self.data.length || range.length > (self.data.length - range.location)) {
        if (error) {
            *error = [NSError errorWithDomain:@"UDAssetIndexTestContentSource"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Out of bounds."}];
        }
        return nil;
    }
    return [self.data subdataWithRange:range];
}

- (NSData *)readAll:(NSError **)error {
    (void)error;
    return self.data;
}

@end

@interface UDAssetIndexTests : XCTestCase
@end

@implementation UDAssetIndexTests

- (UDCodecRegistry *)makeRegistry {
    UDCodecRegistry *registry = [[UDCodecRegistry alloc] init];
    [registry registerCodec:[[UDPAKCodec alloc] init]];
    [registry registerCodec:[[UDPK4Codec alloc] init]];
    return registry;
}

- (NSString *)tempDirectoryPath {
    NSString *name = [NSString stringWithFormat:@"udasset-tests-%@", NSUUID.UUID.UUIDString];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (NSURL *)writeArchiveUsingCodec:(id<UDArchiveCodec>)codec
                          entries:(NSDictionary<NSString *, NSString *> *)entries
                           suffix:(NSString *)suffix {
    NSMutableArray<UDArchiveEntry *> *archiveEntries = [NSMutableArray arrayWithCapacity:entries.count];
    NSDate *now = [NSDate date];

    for (NSString *path in entries) {
        NSData *data = [[entries objectForKey:path] dataUsingEncoding:NSUTF8StringEncoding];
        UDAssetIndexTestContentSource *source = [[UDAssetIndexTestContentSource alloc] initWithData:data];
        UDArchiveEntry *entry = [[UDArchiveEntry alloc] initWithPath:path
                                                                size:data.length
                                                         contentType:@"text/plain"
                                                          modifiedAt:now
                                                              source:source];
        [archiveEntries addObject:entry];
    }

    UDArchive *archive = [[UDArchive alloc] initWithDisplayName:[NSString stringWithFormat:@"test.%@", suffix]
                                                         entries:archiveEntries
                                                        metadata:@{}];

    NSString *fileName = [NSString stringWithFormat:@"udasset-%@-%@", NSUUID.UUID.UUIDString, archive.displayName];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSURL *url = [NSURL fileURLWithPath:filePath];

    NSError *writeError = nil;
    XCTAssertTrue([codec writeArchive:archive toURL:url error:&writeError]);
    XCTAssertNil(writeError);
    return url;
}

- (void)testAssetIndexerBuildsVisibleTypedIndex {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"materials"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"guis"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *looseMaterialPath = [gameDirPath stringByAppendingPathComponent:@"materials/test.mtr"];
    NSString *looseGUIPath = [gameDirPath stringByAppendingPathComponent:@"guis/main.gui"];
    XCTAssertTrue([[@"material" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:looseMaterialPath atomically:YES]);
    XCTAssertTrue([[@"gui" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:looseGUIPath atomically:YES]);

    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                             entries:@{
                                                 @"materials/test.mtr": @"archive-material",
                                                 @"def/monster.def": @"decl",
                                                 @"script/game.script": @"script",
                                                 @"docs/readme.txt": @"ignored"
                                             }
                                              suffix:@"pk4"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:archiveURL
                              identifier:@"archive"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath]
                                identifier:@"gamedir"
                               virtualRoot:nil
                                  priority:0
                                     error:&mountError]);
    XCTAssertNil(mountError);

    UDAssetIndexer *indexer = [[UDAssetIndexer alloc] init];
    NSError *indexError = nil;
    UDAssetIndex *index = [indexer buildIndexFromVirtualFileSystem:vfs error:&indexError];
    XCTAssertNotNil(index);
    XCTAssertNil(indexError);
    XCTAssertEqual(index.entries.count, 4U);

    UDAssetIndexEntry *materialEntry = [index entryForVirtualPath:@"materials/test.mtr"];
    XCTAssertNotNil(materialEntry);
    XCTAssertEqual(materialEntry.kind, UDAssetKindMaterial);
    XCTAssertFalse(materialEntry.isArchiveBacked);
    XCTAssertEqualObjects(materialEntry.mountIdentifier, @"gamedir");
    XCTAssertEqualObjects(materialEntry.sourceURL.path, looseMaterialPath);
    XCTAssertEqualObjects(materialEntry.sourcePath, @"materials/test.mtr");

    UDAssetIndexEntry *declEntry = [index entryForVirtualPath:@"def/monster.def"];
    XCTAssertNotNil(declEntry);
    XCTAssertEqual(declEntry.kind, UDAssetKindDecl);
    XCTAssertTrue(declEntry.isArchiveBacked);
    XCTAssertEqualObjects(declEntry.mountIdentifier, @"archive");
    XCTAssertEqualObjects(declEntry.sourceURL.path, archiveURL.path);
    XCTAssertEqualObjects(declEntry.sourcePath, @"def/monster.def");

    UDAssetIndexEntry *guiEntry = [index entryForVirtualPath:@"guis/main.gui"];
    XCTAssertNotNil(guiEntry);
    XCTAssertEqual(guiEntry.kind, UDAssetKindGUI);

    UDAssetIndexEntry *scriptEntry = [index entryForVirtualPath:@"script/game.script"];
    XCTAssertNotNil(scriptEntry);
    XCTAssertEqual(scriptEntry.kind, UDAssetKindScript);

    XCTAssertEqual([index entriesOfKind:UDAssetKindMaterial].count, 1U);
    XCTAssertEqual([index entriesOfKind:UDAssetKindDecl].count, 1U);
    XCTAssertEqual([index entriesOfKind:UDAssetKindGUI].count, 1U);
    XCTAssertEqual([index entriesOfKind:UDAssetKindScript].count, 1U);
}

- (void)testVisibleFilesEnumerationRespectsPrecedenceAndExtensionFilter {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"materials"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *looseMaterialPath = [gameDirPath stringByAppendingPathComponent:@"materials/test.mtr"];
    XCTAssertTrue([[@"material" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:looseMaterialPath atomically:YES]);

    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                             entries:@{
                                                 @"materials/test.mtr": @"archive-material",
                                                 @"script/game.script": @"script"
                                             }
                                              suffix:@"pk4"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:archiveURL
                              identifier:@"archive"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath]
                                identifier:@"gamedir"
                               virtualRoot:nil
                                  priority:0
                                     error:&mountError]);
    XCTAssertNil(mountError);

    NSError *visibleError = nil;
    NSSet *extensions = [NSSet setWithObjects:@"mtr", nil];
    NSArray<UDVFSResolvedFile *> *visibleFiles = [vfs visibleFilesWithExtensions:extensions error:&visibleError];
    XCTAssertNil(visibleError);
    XCTAssertEqual(visibleFiles.count, 1U);

    UDVFSResolvedFile *resolved = [visibleFiles objectAtIndex:0];
    XCTAssertEqualObjects(resolved.virtualPath, @"materials/test.mtr");
    XCTAssertEqualObjects(resolved.mount.identifier, @"gamedir");
    XCTAssertEqualObjects(resolved.fileURL.path, looseMaterialPath);
    XCTAssertEqualObjects(resolved.sourcePath, @"materials/test.mtr");
}

- (void)testDeclParserBuildsStructuredDefinitions {
    NSString *declText =
        @"// comment\n"
         "entityDef monster_zombie {\n"
         "  \"editor_usage\" \"Unit test\"\n"
         "}\n"
         "material textures/stone {\n"
         "  { blend add }\n"
         "}\n";

    UDDeclParser *parser = [[UDDeclParser alloc] init];
    NSError *parseError = nil;
    NSArray<UDDeclDefinition *> *definitions = [parser parseDefinitionsFromText:declText
                                                               sourceVirtualPath:@"def/monster.def"
                                                                           error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertEqual(definitions.count, 2U);

    UDDeclDefinition *first = [definitions objectAtIndex:0];
    XCTAssertEqualObjects(first.declType, @"entityDef");
    XCTAssertEqualObjects(first.declName, @"monster_zombie");
    XCTAssertEqualObjects(first.sourceVirtualPath, @"def/monster.def");
    XCTAssertTrue([first.body containsString:@"editor_usage"]);

    UDDeclDefinition *second = [definitions objectAtIndex:1];
    XCTAssertEqualObjects(second.declType, @"material");
    XCTAssertEqualObjects(second.declName, @"textures/stone");
    XCTAssertTrue([second.body containsString:@"blend add"]);
}

- (void)testDeclParserRoundTripsBodyFormatting {
    NSString *declText =
        @"entityDef monster_zombie {\n"
         "    // preserve indentation and comments\n"
         "    \"editor_usage\"\t\"Unit test\"\n"
         "}\n\n"
         "material textures/stone {\n"
         "\t{ blend add }\n"
         "}";

    UDDeclParser *parser = [[UDDeclParser alloc] init];
    NSError *parseError = nil;
    NSArray<UDDeclDefinition *> *definitions = [parser parseDefinitionsFromText:declText
                                                               sourceVirtualPath:@"def/monster.def"
                                                                           error:&parseError];
    XCTAssertNil(parseError);
    XCTAssertEqual(definitions.count, 2U);

    NSString *serialized = [parser serializeDefinitions:definitions];
    NSString *expected =
        @"entityDef monster_zombie {\n"
         "    // preserve indentation and comments\n"
         "    \"editor_usage\"\t\"Unit test\"\n"
         "}\n\n"
         "material textures/stone {\n"
         "\t{ blend add }\n"
         "}";
    XCTAssertEqualObjects(serialized, expected);
}

- (void)testDeclModelUsesAssetIndexDiscoveryLayer {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"def"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *looseDeclPath = [gameDirPath stringByAppendingPathComponent:@"def/monster.def"];
    NSString *looseDecl = @"entityDef loose_decl { \"editor_usage\" \"loose\" }\n";
    XCTAssertTrue([looseDecl writeToFile:looseDeclPath atomically:YES encoding:NSUTF8StringEncoding error:&mkdirError]);
    XCTAssertNil(mkdirError);

    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                             entries:@{
                                                 @"def/monster.def": @"entityDef archive_decl { \"editor_usage\" \"archive\" }",
                                                 @"def/weapons.def": @"entityDef weapon_shotgun { \"editor_usage\" \"archive\" }"
                                             }
                                              suffix:@"pk4"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:archiveURL identifier:@"archive" virtualRoot:nil priority:0 typeName:nil error:&mountError]);
    XCTAssertNil(mountError);
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath] identifier:@"gamedir" virtualRoot:nil priority:0 error:&mountError]);
    XCTAssertNil(mountError);

    UDAssetIndexer *indexer = [[UDAssetIndexer alloc] init];
    NSError *indexError = nil;
    UDAssetIndex *assetIndex = [indexer buildIndexFromVirtualFileSystem:vfs error:&indexError];
    XCTAssertNotNil(assetIndex);
    XCTAssertNil(indexError);

    NSError *modelError = nil;
    UDDeclModel *declModel = [indexer buildDeclModelFromAssetIndex:assetIndex virtualFileSystem:vfs error:&modelError];
    XCTAssertNotNil(declModel);
    XCTAssertNil(modelError);
    XCTAssertNotNil([declModel definitionWithType:@"entityDef" name:@"loose_decl"]);
    XCTAssertNil([declModel definitionWithType:@"entityDef" name:@"archive_decl"]);
    XCTAssertNotNil([declModel definitionWithType:@"entityDef" name:@"weapon_shotgun"]);

    NSArray<UDDeclDefinition *> *entityDefs = [declModel definitionsOfType:@"entityDef"];
    XCTAssertEqual(entityDefs.count, 2U);

    NSArray<UDDeclDefinition *> *nameMatches = [declModel definitionsWithNameContaining:@"weapon"];
    XCTAssertEqual(nameMatches.count, 1U);
    XCTAssertEqualObjects([[nameMatches objectAtIndex:0] declName], @"weapon_shotgun");

    NSArray<UDDeclDefinition *> *sourceMatches = [declModel definitionsFromSourceVirtualPath:@"def/weapons.def"];
    XCTAssertEqual(sourceMatches.count, 1U);
    XCTAssertEqualObjects([[sourceMatches objectAtIndex:0] declName], @"weapon_shotgun");
}

- (void)testDeclQueryServiceFiltersSortsAndLimits {
    UDDeclDefinition *a = [[UDDeclDefinition alloc] initWithDeclType:@"entityDef"
                                                            declName:@"monster_imp"
                                                                body:@"\"editor_usage\" \"imp\""
                                                   sourceVirtualPath:@"def/monster.def"];
    UDDeclDefinition *b = [[UDDeclDefinition alloc] initWithDeclType:@"entityDef"
                                                            declName:@"monster_boss"
                                                                body:@"\"editor_usage\" \"boss\""
                                                   sourceVirtualPath:@"def/monster.def"];
    UDDeclDefinition *c = [[UDDeclDefinition alloc] initWithDeclType:@"material"
                                                            declName:@"textures/stone"
                                                                body:@"{ blend add }"
                                                   sourceVirtualPath:@"materials/stone.def"];
    UDDeclDefinition *d = [[UDDeclDefinition alloc] initWithDeclType:@"entityDef"
                                                            declName:@"weapon_shotgun"
                                                                body:@"\"editor_usage\" \"weapon\""
                                                   sourceVirtualPath:@"def/weapons.def"];

    UDDeclModel *model = [[UDDeclModel alloc] initWithDefinitions:@[a, b, c, d]];
    UDDeclQueryService *service = [[UDDeclQueryService alloc] init];

    UDDeclQueryRequest *request = [[UDDeclQueryRequest alloc] init];
    request.declType = @"entityDef";
    request.searchText = @"monster";
    request.sortField = UDDeclQuerySortFieldName;
    request.ascending = NO;

    NSArray<UDDeclDefinition *> *results = [service queryDefinitionsInModel:model request:request];
    XCTAssertEqual(results.count, 2U);
    XCTAssertEqualObjects([[results objectAtIndex:0] declName], @"monster_imp");
    XCTAssertEqualObjects([[results objectAtIndex:1] declName], @"monster_boss");

    request.searchText = nil;
    request.declType = nil;
    request.sourceVirtualPath = @"def/monster.def";
    request.sortField = UDDeclQuerySortFieldType;
    request.ascending = YES;
    request.maxResults = 1;

    NSArray<UDDeclDefinition *> *limited = [service queryDefinitionsInModel:model request:request];
    XCTAssertEqual(limited.count, 1U);
    XCTAssertEqualObjects([[limited objectAtIndex:0] sourceVirtualPath], @"def/monster.def");
}

- (void)testNotificationHookPerformsPartialAssetIndexRefresh {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"guis"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *looseGUIPath = [gameDirPath stringByAppendingPathComponent:@"guis/main.gui"];
    XCTAssertTrue([[@"windowDef Test {}" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:looseGUIPath atomically:YES]);

    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                             entries:@{
                                                 @"materials/test.mtr": @"archive-material",
                                                 @"script/game.script": @"script"
                                             }
                                              suffix:@"pk4"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:archiveURL identifier:@"archive" virtualRoot:nil priority:0 typeName:nil error:&mountError]);
    XCTAssertNil(mountError);
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath] identifier:@"gamedir" virtualRoot:nil priority:0 error:&mountError]);
    XCTAssertNil(mountError);

    UDAssetIndexer *indexer = [[UDAssetIndexer alloc] init];
    NSError *indexError = nil;
    UDAssetIndex *initialIndex = [indexer buildIndexFromVirtualFileSystem:vfs error:&indexError];
    XCTAssertNotNil(initialIndex);
    XCTAssertNil(indexError);
    XCTAssertEqual(initialIndex.entries.count, 3U);

    NSError *writeError = nil;
    NSData *materialData = [@"loose-material" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([vfs writeFileAtPath:@"materials/test.mtr" data:materialData error:&writeError]);
    XCTAssertNil(writeError);

    NSNotification *notification = [NSNotification notificationWithName:UDVFSDidWriteFileNotification
                                                                 object:vfs
                                                               userInfo:@{UDVFSNotificationVirtualPathKey: @"materials/test.mtr"}];
    UDAssetIndex *updatedIndex = [indexer rebuildIndexByApplyingWriteNotification:notification
                                                                   toExistingIndex:initialIndex
                                                                 virtualFileSystem:vfs
                                                                             error:&indexError];
    XCTAssertNotNil(updatedIndex);
    XCTAssertNil(indexError);
    XCTAssertEqual(updatedIndex.entries.count, 3U);

    UDAssetIndexEntry *materialEntry = [updatedIndex entryForVirtualPath:@"materials/test.mtr"];
    XCTAssertNotNil(materialEntry);
    XCTAssertFalse(materialEntry.isArchiveBacked);
    XCTAssertEqualObjects(materialEntry.mountIdentifier, @"gamedir");
}

- (void)testNotificationHookPerformsPartialDeclModelRefresh {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"def"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath]
                                identifier:@"gamedir"
                               virtualRoot:nil
                                  priority:0
                                     error:&mountError]);
    XCTAssertNil(mountError);

    NSData *initialDeclData = [@"entityDef monster_zombie { \"editor_usage\" \"z\" }" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *writeError = nil;
    XCTAssertTrue([vfs writeFileAtPath:@"def/monster.def" data:initialDeclData error:&writeError]);
    XCTAssertNil(writeError);

    UDAssetIndexer *indexer = [[UDAssetIndexer alloc] init];
    NSError *indexError = nil;
    UDAssetIndex *assetIndex = [indexer buildIndexFromVirtualFileSystem:vfs error:&indexError];
    XCTAssertNotNil(assetIndex);
    XCTAssertNil(indexError);

    NSError *modelError = nil;
    UDDeclModel *declModel = [indexer buildDeclModelFromAssetIndex:assetIndex virtualFileSystem:vfs error:&modelError];
    XCTAssertNotNil(declModel);
    XCTAssertNil(modelError);
    XCTAssertNotNil([declModel definitionWithType:@"entityDef" name:@"monster_zombie"]);

    NSData *updatedDeclData = [@"entityDef monster_imp { \"editor_usage\" \"i\" }\nentityDef monster_boss { \"editor_usage\" \"b\" }" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([vfs writeFileAtPath:@"def/monster.def" data:updatedDeclData error:&writeError]);
    XCTAssertNil(writeError);

    NSNotification *notification = [NSNotification notificationWithName:UDVFSDidWriteFileNotification
                                                                 object:vfs
                                                               userInfo:@{UDVFSNotificationVirtualPathKey: @"def/monster.def"}];
    UDAssetIndex *updatedIndex = [indexer rebuildIndexByApplyingWriteNotification:notification
                                                                   toExistingIndex:assetIndex
                                                                 virtualFileSystem:vfs
                                                                             error:&indexError];
    XCTAssertNotNil(updatedIndex);
    XCTAssertNil(indexError);

    UDDeclModel *updatedModel = [indexer rebuildDeclModelByApplyingWriteNotification:notification
                                                                       toExistingModel:declModel
                                                                            assetIndex:updatedIndex
                                                                     virtualFileSystem:vfs
                                                                                 error:&modelError];
    XCTAssertNotNil(updatedModel);
    XCTAssertNil(modelError);
    XCTAssertNil([updatedModel definitionWithType:@"entityDef" name:@"monster_zombie"]);
    XCTAssertNotNil([updatedModel definitionWithType:@"entityDef" name:@"monster_imp"]);
    XCTAssertNotNil([updatedModel definitionWithType:@"entityDef" name:@"monster_boss"]);
}

@end