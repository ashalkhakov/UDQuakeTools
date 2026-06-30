#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDCodecRegistry.h"
#import "UDContentSource.h"
#import "UDDaikatanaPAKCodec.h"
#import "UDPAK2Codec.h"
#import "UDPAKCodec.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"
#import "UDVirtualFileSystem.h"

@interface UDVFSTestContentSource : NSObject <UDContentSource>
@property (nonatomic, strong, readonly) NSData *data;
- (instancetype)initWithData:(NSData *)data;
@end

@implementation UDVFSTestContentSource

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
            *error = [NSError errorWithDomain:@"UDVFSTestContentSource"
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

@interface UDVirtualFileSystemTests : XCTestCase
@property (nonatomic, strong, nullable) NSDictionary *capturedNotificationUserInfo;
@end

@implementation UDVirtualFileSystemTests

@synthesize capturedNotificationUserInfo = _capturedNotificationUserInfo;

- (void)handleVFSWriteNotification:(NSNotification *)notification {
    self.capturedNotificationUserInfo = notification.userInfo;
}

- (UDCodecRegistry *)makeRegistry {
    UDCodecRegistry *registry = [[UDCodecRegistry alloc] init];
    [registry registerCodec:[[UDPAKCodec alloc] init]];
    [registry registerCodec:[[UDPAK2Codec alloc] init]];
    [registry registerCodec:[[UDDaikatanaPAKCodec alloc] init]];
    [registry registerCodec:[[UDPK3Codec alloc] init]];
    [registry registerCodec:[[UDPK4Codec alloc] init]];
    return registry;
}

- (NSString *)tempDirectoryPath {
    NSString *name = [NSString stringWithFormat:@"udvfs-tests-%@", NSUUID.UUID.UUIDString];
    return [NSTemporaryDirectory() stringByAppendingPathComponent:name];
}

- (NSURL *)writeArchiveUsingCodec:(id<UDArchiveCodec>)codec
                          entries:(NSDictionary<NSString *, NSString *> *)entries
                           suffix:(NSString *)suffix {
    NSMutableArray<UDArchiveEntry *> *archiveEntries = [NSMutableArray arrayWithCapacity:entries.count];
    NSDate *now = [NSDate date];

    for (NSString *path in entries) {
        NSString *text = [entries objectForKey:path];
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        UDVFSTestContentSource *source = [[UDVFSTestContentSource alloc] initWithData:data];
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

    NSString *fileName = [NSString stringWithFormat:@"udvfs-%@-%@", NSUUID.UUID.UUIDString, archive.displayName];
    NSString *filePath = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
    NSURL *url = [NSURL fileURLWithPath:filePath];

    NSError *writeError = nil;
    BOOL wrote = [codec writeArchive:archive toURL:url error:&writeError];
    XCTAssertTrue(wrote, @"test fixture archive should write");
    XCTAssertNil(writeError, @"test fixture archive should write without error");

    return url;
}

- (void)testLooseFilesOverrideArchiveAtSamePriority {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSString *looseDirPath = [gameDirPath stringByAppendingPathComponent:@"base"]; 
    NSString *docsDirPath = [looseDirPath stringByAppendingPathComponent:@"docs"];

    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:docsDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSString *loosePath = [docsDirPath stringByAppendingPathComponent:@"readme.txt"];
    NSData *looseData = [@"LOOSE" dataUsingEncoding:NSUTF8StringEncoding];
    [looseData writeToFile:loosePath atomically:YES];

    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPAKCodec alloc] init]
                                             entries:@{@"docs/readme.txt": @"ARCHIVE"}
                                              suffix:@"pak"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeQuake1 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:archiveURL
                              identifier:@"archive"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:looseDirPath]
                                identifier:@"loose"
                               virtualRoot:nil
                                  priority:0
                                     error:&mountError]);
    XCTAssertNil(mountError);

    NSError *readError = nil;
    NSData *data = [vfs readFileAtPath:@"docs/readme.txt" error:&readError];
    XCTAssertNotNil(data);
    XCTAssertNil(readError);

    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    XCTAssertEqualObjects(text, @"LOOSE", @"Loose files should override archive entries at same priority");
}

- (void)testQuakeStyleNumberedPaksUsePakNumberPrecedence {
    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeQuake1 gameDirectoryURL:nil];

    NSString *fixtureDir = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:fixtureDir
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSURL *pak0URL = [self writeArchiveUsingCodec:[[UDPAKCodec alloc] init]
                                          entries:@{@"maps/test.map": @"ZERO"}
                                           suffix:@"pak"];
    NSURL *pak9URL = [self writeArchiveUsingCodec:[[UDPAKCodec alloc] init]
                                          entries:@{@"maps/test.map": @"NINE"}
                                           suffix:@"pak"];

    NSString *pak0Path = [fixtureDir stringByAppendingPathComponent:@"pak0.pak"];
    NSString *pak9Path = [fixtureDir stringByAppendingPathComponent:@"pak9.pak"];

    [[NSFileManager defaultManager] moveItemAtPath:pak0URL.path toPath:pak0Path error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:pak9URL.path toPath:pak9Path error:nil];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:[NSURL fileURLWithPath:pak0Path]
                              identifier:@"pak0"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    XCTAssertNotNil([vfs mountArchiveURL:[NSURL fileURLWithPath:pak9Path]
                              identifier:@"pak9"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    NSError *readError = nil;
    NSData *data = [vfs readFileAtPath:@"maps/test.map" error:&readError];
    XCTAssertNotNil(data);
    XCTAssertNil(readError);
    XCTAssertEqualObjects([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], @"NINE");
}

- (void)testDoom3StyleArchiveNamesUseLexicalPrecedence {
    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:nil];

    NSURL *aURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                       entries:@{@"materials/test.mtr": @"A"}
                                        suffix:@"pk4"];
    NSURL *zURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                       entries:@{@"materials/test.mtr": @"Z"}
                                        suffix:@"pk4"];

    NSString *aPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"a_base_%@.pk4", NSUUID.UUID.UUIDString]];
    NSString *zPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"z_override_%@.pk4", NSUUID.UUID.UUIDString]];
    [[NSFileManager defaultManager] moveItemAtPath:aURL.path toPath:aPath error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:zURL.path toPath:zPath error:nil];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:[NSURL fileURLWithPath:aPath]
                              identifier:@"a"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    XCTAssertNotNil([vfs mountArchiveURL:[NSURL fileURLWithPath:zPath]
                              identifier:@"z"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    NSError *readError = nil;
    NSData *data = [vfs readFileAtPath:@"materials/test.mtr" error:&readError];
    XCTAssertNotNil(data);
    XCTAssertNil(readError);
    XCTAssertEqualObjects([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], @"Z");
}

- (void)testTransactionalWriteCreatesLooseOverrideForArchivePath {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:gameDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPAKCodec alloc] init]
                                             entries:@{@"docs/readme.txt": @"ARCHIVE"}
                                              suffix:@"pak"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeQuake1 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

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

    NSData *replacement = [@"LOOSE-OVERRIDE" dataUsingEncoding:NSUTF8StringEncoding];
    NSError *writeError = nil;
    XCTAssertTrue([vfs writeFileAtPath:@"docs/readme.txt" data:replacement error:&writeError]);
    XCTAssertNil(writeError);

    NSError *readError = nil;
    NSData *data = [vfs readFileAtPath:@"docs/readme.txt" error:&readError];
    XCTAssertNotNil(data);
    XCTAssertNil(readError);
    XCTAssertEqualObjects([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], @"LOOSE-OVERRIDE");

    NSString *loosePath = [gameDirPath stringByAppendingPathComponent:@"docs/readme.txt"];
    NSData *diskData = [NSData dataWithContentsOfFile:loosePath];
    XCTAssertEqualObjects([[NSString alloc] initWithData:diskData encoding:NSUTF8StringEncoding], @"LOOSE-OVERRIDE");
}

- (void)testTransactionalWriteReplacesExistingLooseFile {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSString *loosePath = [gameDirPath stringByAppendingPathComponent:@"materials/test.mtr"];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:[loosePath stringByDeletingLastPathComponent]
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);
    XCTAssertTrue([[@"old" dataUsingEncoding:NSUTF8StringEncoding] writeToFile:loosePath atomically:YES]);

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountDirectoryURL:[NSURL fileURLWithPath:gameDirPath]
                                identifier:@"gamedir"
                               virtualRoot:nil
                                  priority:0
                                     error:&mountError]);
    XCTAssertNil(mountError);

    NSError *writeError = nil;
    XCTAssertTrue([vfs writeFileAtPath:@"materials/test.mtr"
                                  data:[@"new" dataUsingEncoding:NSUTF8StringEncoding]
                                 error:&writeError]);
    XCTAssertNil(writeError);

    NSData *diskData = [NSData dataWithContentsOfFile:loosePath];
    XCTAssertEqualObjects([[NSString alloc] initWithData:diskData encoding:NSUTF8StringEncoding], @"new");
}

- (void)testTransactionalWriteFailsWithoutDirectoryMount {
    NSURL *archiveURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                             entries:@{@"materials/test.mtr": @"ARCHIVE"}
                                              suffix:@"pk4"];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:nil];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:archiveURL
                              identifier:@"archive"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    NSError *writeError = nil;
    XCTAssertFalse([vfs writeFileAtPath:@"materials/test.mtr"
                                   data:[@"LOOSE" dataUsingEncoding:NSUTF8StringEncoding]
                                  error:&writeError]);
    XCTAssertNotNil(writeError);
}

- (void)testDiscoveredSiblingArchivesUseGameSpecificPrecedence {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:gameDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSURL *aURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                       entries:@{@"materials/test.mtr": @"A"}
                                        suffix:@"pk4"];
    NSURL *zURL = [self writeArchiveUsingCodec:[[UDPK4Codec alloc] init]
                                       entries:@{@"materials/test.mtr": @"Z"}
                                        suffix:@"pk4"];

    NSString *aPath = [gameDirPath stringByAppendingPathComponent:@"a_base.pk4"];
    NSString *zPath = [gameDirPath stringByAppendingPathComponent:@"z_override.pk4"];
    [[NSFileManager defaultManager] moveItemAtPath:aURL.path toPath:aPath error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:zURL.path toPath:zPath error:nil];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeDoom3 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    NSArray<UDVFSMount *> *mounts = [vfs mountDiscoveredArchivesInGameDirectory:&mountError];
    XCTAssertNil(mountError);
    XCTAssertEqual(mounts.count, 2U);

    NSError *readError = nil;
    NSData *data = [vfs readFileAtPath:@"materials/test.mtr" error:&readError];
    XCTAssertNotNil(data);
    XCTAssertNil(readError);
    XCTAssertEqualObjects([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], @"Z");
}

- (void)testArchiveDiscoverySkipsAlreadyMountedArchive {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:gameDirPath
                              withIntermediateDirectories:YES
                                               attributes:nil
                                                    error:&mkdirError];
    XCTAssertNil(mkdirError);

    NSURL *pak0URL = [self writeArchiveUsingCodec:[[UDPAKCodec alloc] init]
                                          entries:@{@"maps/test.map": @"ZERO"}
                                           suffix:@"pak"];
    NSURL *pak1URL = [self writeArchiveUsingCodec:[[UDPAKCodec alloc] init]
                                          entries:@{@"maps/test.map": @"ONE"}
                                           suffix:@"pak"];
    NSString *pak0Path = [gameDirPath stringByAppendingPathComponent:@"pak0.pak"];
    NSString *pak1Path = [gameDirPath stringByAppendingPathComponent:@"pak1.pak"];
    [[NSFileManager defaultManager] moveItemAtPath:pak0URL.path toPath:pak0Path error:nil];
    [[NSFileManager defaultManager] moveItemAtPath:pak1URL.path toPath:pak1Path error:nil];

    UDVirtualFileSystem *vfs = [[UDVirtualFileSystem alloc] initWithCodecRegistry:[self makeRegistry]];
    [vfs configureWithGameType:UDGameTypeQuake1 gameDirectoryURL:[NSURL fileURLWithPath:gameDirPath]];

    NSError *mountError = nil;
    XCTAssertNotNil([vfs mountArchiveURL:[NSURL fileURLWithPath:pak0Path]
                              identifier:@"archive"
                             virtualRoot:nil
                                priority:0
                                typeName:nil
                                   error:&mountError]);
    XCTAssertNil(mountError);

    NSArray<UDVFSMount *> *mounts = [vfs mountDiscoveredArchivesInGameDirectory:&mountError];
    XCTAssertNil(mountError);
    XCTAssertEqual(mounts.count, 1U);
    XCTAssertEqual(vfs.mounts.count, 2U);

    NSError *readError = nil;
    NSData *data = [vfs readFileAtPath:@"maps/test.map" error:&readError];
    XCTAssertNotNil(data);
    XCTAssertNil(readError);
    XCTAssertEqualObjects([[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding], @"ONE");
}

- (void)testTransactionalWritePostsChangeNotification {
    NSString *gameDirPath = [self tempDirectoryPath];
    NSError *mkdirError = nil;
    [[NSFileManager defaultManager] createDirectoryAtPath:gameDirPath
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

    self.capturedNotificationUserInfo = nil;
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleVFSWriteNotification:)
                                                 name:UDVFSDidWriteFileNotification
                                               object:vfs];

    NSError *writeError = nil;
    XCTAssertTrue([vfs writeFileAtPath:@"materials/test.mtr"
                                  data:[@"new" dataUsingEncoding:NSUTF8StringEncoding]
                                 error:&writeError]);
    XCTAssertNil(writeError);

        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                                                                        name:UDVFSDidWriteFileNotification
                                                                                                    object:vfs];
        XCTAssertNotNil(self.capturedNotificationUserInfo);
        XCTAssertEqualObjects([self.capturedNotificationUserInfo objectForKey:UDVFSNotificationVirtualPathKey], @"materials/test.mtr");
        XCTAssertEqualObjects([self.capturedNotificationUserInfo objectForKey:UDVFSNotificationMountIdentifierKey], @"gamedir");
        XCTAssertNotNil([self.capturedNotificationUserInfo objectForKey:UDVFSNotificationFileURLKey]);
}

@end
