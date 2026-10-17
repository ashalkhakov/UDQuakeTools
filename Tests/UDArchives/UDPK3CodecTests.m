#import <XCTest/XCTest.h>
#import "UDZipFixture.h"

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDPAKEntrySource.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"
#import "UDPK3ZIPEntrySource.h"

@interface UDPK3CodecTests : XCTestCase
@end

@implementation UDPK3CodecTests

/* Write data to a temporary file and return its URL. */
- (NSURL *)writeTempFileWithData:(NSData *)data suffix:(NSString *)suffix {
    NSString *name = [NSString stringWithFormat:@"udquake-ziptest-%@-%@",
                      [[NSUUID UUID] UUIDString], suffix];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *err = nil;
    if (![data writeToURL:url options:0 error:&err]) {
        return nil;
    }
    return url;
}

/* Build a minimal ZIP archive in memory with two entries.
 *
 * Entry 1: "maps/q3dm1.bsp"   content: "hello pk3"  (DEFLATED)
 * Entry 2: "scripts/base.shader"  content: "nolightmap" (STORED)
 *
 * UDZipWriter builds it in memory, so the test does not
 * depend on an external tool. */
- (NSData *)makeTestZIPData {
    return UDZipFixtureData(@[
        @[@"maps/q3dm1.bsp", @"hello pk3", @(UDZipCompressionMethodDeflated)],
        @[@"scripts/base.shader", @"nolightmap", @(UDZipCompressionMethodStored)],
    ]);
}

- (void)testPK3Codec {
    NSData *zipData = [self makeTestZIPData];
    XCTAssertNotNil(zipData, @"Test setup: ZIP data should be created");
    if (!zipData) {
        return;
    }

    /* ---- PK3 ---- */
    NSURL *pk3URL = [self writeTempFileWithData:zipData suffix:@"sample.pk3"];
    XCTAssertNotNil(pk3URL, @"Test setup: PK3 temp file should be created");

    UDPK3Codec *pk3Codec = [[UDPK3Codec alloc] init];
    XCTAssertTrue([pk3Codec canReadURL:pk3URL], @"UDPK3Codec should recognise .pk3 extension");

    NSError *err = nil;
    UDArchive *pk3Archive = [pk3Codec readArchiveFromURL:pk3URL error:&err];
    XCTAssertNil(err,        @"UDPK3Codec should parse valid PK3 without error");
    XCTAssertNotNil(pk3Archive, @"UDPK3Codec should return an archive");

    if (pk3Archive) {
        XCTAssertTrue([pk3Archive.displayName hasSuffix:@"sample.pk3"],
                        @"PK3 archive displayName should match filename");
        XCTAssertEqual(pk3Archive.entries.count, 2U,
                        @"PK3 archive should contain 2 entries");

        NSString *game = [pk3Archive.metadata objectForKey:@"game"];
        XCTAssertEqualObjects(game, @"quake3",
                        @"PK3 archive metadata game should be quake3");

        /* Find entries by path. */
        UDArchiveEntry *bspEntry = nil;
        UDArchiveEntry *shaderEntry = nil;
        for (UDArchiveEntry *e in pk3Archive.entries) {
            if ([e.path isEqualToString:@"maps/q3dm1.bsp"]) {
                bspEntry = e;
            } else if ([e.path isEqualToString:@"scripts/base.shader"]) {
                shaderEntry = e;
            }
        }

        XCTAssertNotNil(bspEntry,    @"PK3 should have maps/q3dm1.bsp entry");
        XCTAssertNotNil(shaderEntry, @"PK3 should have scripts/base.shader entry");

        if (bspEntry) {
            XCTAssertEqual(bspEntry.size, 9ULL,
                            @"PK3 bsp entry size should be 9");
            XCTAssertEqualObjects(bspEntry.name, @"q3dm1.bsp",
                            @"PK3 bsp entry name should be q3dm1.bsp");

            NSError *readErr = nil;
            NSData *payload = [bspEntry.source readAll:&readErr];
            XCTAssertNil(readErr, @"PK3 bsp entry readAll should succeed");
            XCTAssertNotNil(payload, @"PK3 bsp entry readAll should return data");
            if (payload) {
                NSString *text = [[NSString alloc] initWithData:payload
                                                       encoding:NSASCIIStringEncoding];
                XCTAssertEqualObjects(text, @"hello pk3",
                                @"PK3 bsp entry payload should match");
            }

            /* readRange: slice test. */
            NSError *sliceErr = nil;
            NSData *slice = [bspEntry.source readRange:NSMakeRange(0, 5) error:&sliceErr];
            XCTAssertNil(sliceErr, @"PK3 bsp entry readRange should succeed");
            if (slice) {
                NSString *sliceText = [[NSString alloc] initWithData:slice
                                                            encoding:NSASCIIStringEncoding];
                XCTAssertEqualObjects(sliceText, @"hello",
                                @"PK3 bsp entry readRange(0,5) should return 'hello'");
            }

            /* Out-of-bounds range. */
            NSError *oobErr = nil;
            NSData *oob = [bspEntry.source readRange:NSMakeRange(8, 5) error:&oobErr];
            XCTAssertNil(oob,    @"PK3 out-of-bounds readRange should return nil");
            XCTAssertNotNil(oobErr, @"PK3 out-of-bounds readRange should set error");
        }
    }

    /* ---- PK4 ---- */
    NSURL *pk4URL = [self writeTempFileWithData:zipData suffix:@"sample.pk4"];
    XCTAssertNotNil(pk4URL, @"Test setup: PK4 temp file should be created");

    UDPK4Codec *pk4Codec = [[UDPK4Codec alloc] init];
    XCTAssertTrue([pk4Codec canReadURL:pk4URL],
                    @"UDPK4Codec should recognise .pk4 extension");
    XCTAssertFalse([pk3Codec canReadURL:pk4URL],
                    @"UDPK3Codec should NOT claim a .pk4 file");

    NSError *pk4Err = nil;
    UDArchive *pk4Archive = [pk4Codec readArchiveFromURL:pk4URL error:&pk4Err];
    XCTAssertNil(pk4Err,        @"UDPK4Codec should parse valid PK4 without error");
    XCTAssertNotNil(pk4Archive,    @"UDPK4Codec should return an archive");

    if (pk4Archive) {
        NSString *game = [pk4Archive.metadata objectForKey:@"game"];
        XCTAssertEqualObjects(game, @"doom3",
                        @"PK4 archive metadata game should be doom3");
        XCTAssertEqual(pk4Archive.entries.count, 2U,
                        @"PK4 archive should contain 2 entries");
    }

    /* ---- Error case: bad file ---- */
    NSData *junk = [@"not a zip" dataUsingEncoding:NSASCIIStringEncoding];
    NSURL *badURL = [self writeTempFileWithData:junk suffix:@"bad.pk3"];
    NSError *badErr = nil;
    UDArchive *badArchive = [pk3Codec readArchiveFromURL:badURL error:&badErr];
    XCTAssertNil(badArchive, @"UDPK3Codec should return nil for corrupt file");
    XCTAssertNotNil(badErr,     @"UDPK3Codec should set error for corrupt file");
}

- (void)testWriteEditedPK3Archive {
    NSData *zipData = [self makeTestZIPData];
    XCTAssertNotNil(zipData, @"Test setup: ZIP data should be created");
    if (!zipData) {
        return;
    }

    NSURL *inputURL = [self writeTempFileWithData:zipData suffix:@"editable.pk3"];
    XCTAssertNotNil(inputURL, @"Test setup: input PK3 should be created");
    if (!inputURL) {
        return;
    }

    UDPK3Codec *codec = [[UDPK3Codec alloc] init];
    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:inputURL error:&readError];
    XCTAssertNotNil(archive, @"Input PK3 should load");
    XCTAssertNil(readError, @"Input PK3 should load without error");
    if (!archive) {
        return;
    }

    UDArchiveEditor *editor = [[UDArchiveEditor alloc] initWithArchive:archive];

    NSData *updatedData = [@"UPDATED" dataUsingEncoding:NSASCIIStringEncoding];
    NSURL *updatedURL = [self writeTempFileWithData:updatedData suffix:@"updated.bin"];
    XCTAssertNotNil(updatedURL, @"Test setup: updated payload source should be created");
    if (!updatedURL) {
        return;
    }

    NSError *editError = nil;
    BOOL replaced = [editor replaceEntryAtPath:@"maps/q3dm1.bsp"
                                    withSource:[[UDPAKEntrySource alloc] initWithFileURL:updatedURL offset:0 length:updatedData.length]
                                         error:&editError];
    XCTAssertTrue(replaced, @"replace should succeed");
    XCTAssertNil(editError, @"replace should not set error");

    editError = nil;
    BOOL removed = [editor removeNodeAtPath:@"scripts/base.shader" error:&editError];
    XCTAssertTrue(removed, @"remove should succeed");
    XCTAssertNil(editError, @"remove should not set error");

    NSURL *outputURL = [self writeTempFileWithData:[NSData data] suffix:@"edited.pk3"];
    XCTAssertNotNil(outputURL, @"Test setup: output PK3 should be created");
    if (!outputURL) {
        return;
    }

    NSError *writeError = nil;
    BOOL wrote = [codec writeEditedArchive:editor toURL:outputURL error:&writeError];
    XCTAssertTrue(wrote, @"writing edited PK3 should succeed");
    XCTAssertNil(writeError, @"writing edited PK3 should not set error");

    NSError *verifyError = nil;
    UDArchive *saved = [codec readArchiveFromURL:outputURL error:&verifyError];
    XCTAssertNotNil(saved, @"saved PK3 should be readable");
    XCTAssertNil(verifyError, @"saved PK3 should be readable without error");
    if (!saved) {
        return;
    }

    XCTAssertEqual(saved.entries.count, 1U, @"saved PK3 should contain only remaining entry");

    UDArchiveEntry *entry = saved.entries.firstObject;
    XCTAssertEqualObjects(entry.path, @"maps/q3dm1.bsp", @"remaining entry should be the replaced bsp");

    NSError *payloadError = nil;
    NSData *payload = [entry.source readAll:&payloadError];
    XCTAssertNil(payloadError, @"reloaded payload should be readable");
    XCTAssertEqualObjects([[NSString alloc] initWithData:payload encoding:NSASCIIStringEncoding],
                          @"UPDATED",
                          @"reloaded payload should match replacement content");
}

@end

