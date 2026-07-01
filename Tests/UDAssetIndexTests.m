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
    XCTAssertEqual(materialEntry.kind, UDAssetKindDecl);
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

    XCTAssertEqual([index entriesOfKind:UDAssetKindMaterial].count, 0U);
    XCTAssertEqual([index entriesOfKind:UDAssetKindDecl].count, 2U);
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

@end