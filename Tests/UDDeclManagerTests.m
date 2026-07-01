#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDCodecRegistry.h"
#import "UDContentSource.h"
#import "UDDeclManager.h"
#import "UDDeclModel.h"
#import "UDDeclParser.h"
#import "UDDeclType.h"
#import "UDPAKCodec.h"
#import "UDPK4Codec.h"

@interface UDDeclTestContentSource : NSObject <UDContentSource>
@property (nonatomic, strong, readonly) NSData *data;
- (instancetype)initWithData:(NSData *)data;
@end

@implementation UDDeclTestContentSource

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
            *error = [NSError errorWithDomain:@"UDDeclTestContentSource"
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

@interface UDDeclManagerTests : XCTestCase
@end

@implementation UDDeclManagerTests

- (UDCodecRegistry *)makeRegistry {
    UDCodecRegistry *registry = [[UDCodecRegistry alloc] init];
    [registry registerCodec:[[UDPAKCodec alloc] init]];
    [registry registerCodec:[[UDPK4Codec alloc] init]];
    return registry;
}

- (NSString *)tempDirectoryPath {
    NSString *name = [NSString stringWithFormat:@"uddecl-tests-%@", NSUUID.UUID.UUIDString];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (NSURL *)writeArchiveUsingCodec:(id<UDArchiveCodec>)codec
                          entries:(NSDictionary<NSString *, NSString *> *)entries
                           suffix:(NSString *)suffix {
    NSMutableArray<UDArchiveEntry *> *archiveEntries = [NSMutableArray arrayWithCapacity:entries.count];
    NSDate *now = [NSDate date];

    for (NSString *path in entries) {
        NSData *data = [[entries objectForKey:path] dataUsingEncoding:NSUTF8StringEncoding];
        UDDeclTestContentSource *source = [[UDDeclTestContentSource alloc] initWithData:data];
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

    NSString *fileName = [NSString stringWithFormat:@"uddecl-%@-%@", NSUUID.UUID.UUIDString, archive.displayName];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSURL *url = [NSURL fileURLWithPath:filePath];

    NSError *writeError = nil;
    XCTAssertTrue([codec writeArchive:archive toURL:url error:&writeError]);
    XCTAssertNil(writeError);
    return url;
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
    XCTAssertEqualObjects(first.body,
                          @"entityDef monster_zombie {\n"
                           "  \"editor_usage\" \"Unit test\"\n"
                           "}");

    UDDeclDefinition *second = [definitions objectAtIndex:1];
    XCTAssertEqualObjects(second.declType, @"material");
    XCTAssertEqualObjects(second.declName, @"textures/stone");
    XCTAssertEqualObjects(second.body,
                          @"material textures/stone {\n"
                           "  { blend add }\n"
                           "}");
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

- (void)testDeclManagerBuildsDeclModelFromVirtualFileSystem {
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

    NSError *modelError = nil;
    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    UDDeclModel *declModel = [declManager buildDeclModelFromVirtualFileSystem:vfs error:&modelError];
    XCTAssertNotNil(declModel);
    XCTAssertNil(modelError);
    XCTAssertNotNil([declModel definitionWithType:@"entityDef" name:@"loose_decl"]);
    XCTAssertNil([declModel definitionWithType:@"entityDef" name:@"archive_decl"]);
    XCTAssertNotNil([declModel definitionWithType:@"entityDef" name:@"weapon_shotgun"]);

    UDDeclDefinition *loadedLooseDecl = [declModel definitionWithType:@"entityDef" name:@"loose_decl"];
    XCTAssertTrue([loadedLooseDecl.body hasPrefix:@"entityDef loose_decl {"]);
    XCTAssertTrue([loadedLooseDecl.body hasSuffix:@"}"]);

    NSArray<UDDeclDefinition *> *entityDefs = [declModel definitionsOfType:@"entityDef"];
    XCTAssertEqual(entityDefs.count, 2U);

    NSArray<UDDeclDefinition *> *nameMatches = [declModel definitionsWithNameContaining:@"weapon"];
    XCTAssertEqual(nameMatches.count, 1U);
    XCTAssertEqualObjects([[nameMatches objectAtIndex:0] declName], @"weapon_shotgun");

    NSArray<UDDeclDefinition *> *sourceMatches = [declModel definitionsFromSourceVirtualPath:@"def/weapons.def"];
    XCTAssertEqual(sourceMatches.count, 1U);
    XCTAssertEqualObjects([[sourceMatches objectAtIndex:0] declName], @"weapon_shotgun");
}

- (void)testDeclManagerBuildsQuake3DeclTypesFromVirtualFileSystem {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"scripts"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"models/players/sarge"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"sound"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *shaderText =
        @"textures/common/clip {\n"
         "    qer_editorimage textures/common/clip\n"
         "}\n";
    NSString *skinText =
        @"head,models/players/sarge/red_head\n"
         "upper,models/players/sarge/red_upper\n";
    NSString *soundText =
        @"ambient/intro\n"
         "ambient/loop\n";

    XCTAssertTrue([shaderText writeToFile:[gameDirPath stringByAppendingPathComponent:@"scripts/base.shader"]
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&mkdirError]);
    XCTAssertNil(mkdirError);
    XCTAssertTrue([skinText writeToFile:[gameDirPath stringByAppendingPathComponent:@"models/players/sarge/default.skin"]
                             atomically:YES
                               encoding:NSUTF8StringEncoding
                                  error:&mkdirError]);
    XCTAssertNil(mkdirError);
    XCTAssertTrue([soundText writeToFile:[gameDirPath stringByAppendingPathComponent:@"sound/intro.sounds"]
                              atomically:YES
                                encoding:NSUTF8StringEncoding
                                   error:&mkdirError]);
    XCTAssertNil(mkdirError);

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeQuake3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath]
                                identifier:@"gamedir"
                               virtualRoot:nil
                                  priority:0
                                     error:&mountError]);
    XCTAssertNil(mountError);

    NSError *modelError = nil;
    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    UDDeclModel *declModel = [declManager buildDeclModelFromVirtualFileSystem:vfs error:&modelError];
    XCTAssertNotNil(declModel);
    XCTAssertNil(modelError);

    UDDeclDefinition *shaderDecl = [declModel definitionWithType:@"shader" name:@"textures/common/clip"];
    XCTAssertNotNil(shaderDecl);
    XCTAssertEqualObjects(shaderDecl.sourceVirtualPath, @"scripts/base.shader");
    XCTAssertTrue([shaderDecl.body hasPrefix:@"textures/common/clip {"]);

    UDDeclDefinition *skinDecl = [declModel definitionWithType:@"skin" name:@"default"];
    XCTAssertNotNil(skinDecl);
    XCTAssertEqualObjects(skinDecl.sourceVirtualPath, @"models/players/sarge/default.skin");
    XCTAssertTrue([skinDecl.body hasPrefix:@"head,models/players/sarge/red_head"]);

    UDDeclDefinition *soundDecl = [declModel definitionWithType:@"sound" name:@"intro"];
    XCTAssertNotNil(soundDecl);
    XCTAssertEqualObjects(soundDecl.sourceVirtualPath, @"sound/intro.sounds");
    XCTAssertTrue([soundDecl.body hasPrefix:@"ambient/intro"]);

    NSArray<UDDeclDefinition *> *shaderDefs = [declModel definitionsOfType:@"shader"];
    NSArray<UDDeclDefinition *> *skinDefs = [declModel definitionsOfType:@"skin"];
    NSArray<UDDeclDefinition *> *soundDefs = [declModel definitionsOfType:@"sound"];
    XCTAssertEqual(shaderDefs.count, 1U);
    XCTAssertEqual(skinDefs.count, 1U);
    XCTAssertEqual(soundDefs.count, 1U);
}

- (void)testDeclRegistryScopesExtensionsByGameType {
    NSSet<NSString *> *quake3Extensions = [UDDeclTypeRegistry sourceFileExtensionsForGameType:UDGameTypeQuake3];
    NSSet<NSString *> *doom3Extensions = [UDDeclTypeRegistry sourceFileExtensionsForGameType:UDGameTypeDoom3];

    XCTAssertTrue([quake3Extensions containsObject:@"shader"]);
    XCTAssertTrue([quake3Extensions containsObject:@"skin"]);
    XCTAssertTrue([quake3Extensions containsObject:@"sounds"]);
    XCTAssertFalse([quake3Extensions containsObject:@"mtr"]);
    XCTAssertFalse([quake3Extensions containsObject:@"sndshd"]);

    XCTAssertTrue([doom3Extensions containsObject:@"mtr"]);
    XCTAssertTrue([doom3Extensions containsObject:@"skin"]);
    XCTAssertTrue([doom3Extensions containsObject:@"sndshd"]);
    XCTAssertFalse([doom3Extensions containsObject:@"shader"]);
    XCTAssertFalse([doom3Extensions containsObject:@"sounds"]);
}

- (void)testDeclManagerIgnoresQuake3OnlyDeclsInDoom3Mode {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[gameDirPath stringByAppendingPathComponent:@"scripts"]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *shaderText = @"textures/common/clip { qer_editorimage textures/common/clip }\n";
    XCTAssertTrue([shaderText writeToFile:[gameDirPath stringByAppendingPathComponent:@"scripts/base.shader"]
                               atomically:YES
                                 encoding:NSUTF8StringEncoding
                                    error:&mkdirError]);
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

    NSError *modelError = nil;
    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    UDDeclModel *declModel = [declManager buildDeclModelFromVirtualFileSystem:vfs error:&modelError];
    XCTAssertNotNil(declModel);
    XCTAssertNil(modelError);
    XCTAssertNil([declModel definitionWithType:@"shader" name:@"base"]);
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

- (void)testDeclManagerRebuildUpdatesOnlyChangedDeclSource {
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

    NSError *modelError = nil;
    UDDeclManager *declManager = [[UDDeclManager alloc] init];
    UDDeclModel *declModel = [declManager buildDeclModelFromVirtualFileSystem:vfs error:&modelError];
    XCTAssertNotNil(declModel);
    XCTAssertNil(modelError);
    XCTAssertNotNil([declModel definitionWithType:@"entityDef" name:@"monster_zombie"]);

    NSData *updatedDeclData = [@"entityDef monster_imp { \"editor_usage\" \"i\" }\nentityDef monster_boss { \"editor_usage\" \"b\" }" dataUsingEncoding:NSUTF8StringEncoding];
    XCTAssertTrue([vfs writeFileAtPath:@"def/monster.def" data:updatedDeclData error:&writeError]);
    XCTAssertNil(writeError);

    NSNotification *notification = [NSNotification notificationWithName:UDVFSDidWriteFileNotification
                                                                 object:vfs
                                                               userInfo:@{UDVFSNotificationVirtualPathKey: @"def/monster.def"}];
    UDDeclModel *updatedModel = [declManager rebuildDeclModelByApplyingWriteNotification:notification
                                                                          toExistingModel:declModel
                                                                       virtualFileSystem:vfs
                                                                                   error:&modelError];
    XCTAssertNotNil(updatedModel);
    XCTAssertNil(modelError);
    XCTAssertNil([updatedModel definitionWithType:@"entityDef" name:@"monster_zombie"]);
    XCTAssertNotNil([updatedModel definitionWithType:@"entityDef" name:@"monster_imp"]);
    XCTAssertNotNil([updatedModel definitionWithType:@"entityDef" name:@"monster_boss"]);
}

@end
