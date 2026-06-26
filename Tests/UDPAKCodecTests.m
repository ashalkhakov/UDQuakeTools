#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDCodecRegistry.h"
#import "UDPAKCodec.h"
#import "UDPAKEntrySource.h"

@interface UDPAKCodecTests : XCTestCase
@end

@implementation UDPAKCodecTests

- (NSURL *)writeTemporaryFileWithData:(NSData *)data suffix:(NSString *)suffix {
    NSString *tempFileName = [NSString stringWithFormat:@"udquake-%@-%@", [[NSUUID UUID] UUIDString], suffix];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:tempFileName];
    NSURL *url = [NSURL fileURLWithPath:path];
    NSError *writeError = nil;
    BOOL wrote = [data writeToURL:url options:0 error:&writeError];
    if (!wrote || writeError) {
        return nil;
    }
    return url;
}

- (NSData *)quakePAKDataWithEntries {
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"PACK" length:4];

    uint32_t directoryOffset = 16;
    uint32_t directorySize = 64;
    [data appendBytes:&directoryOffset length:4];
    [data appendBytes:&directorySize length:4];

    [data appendBytes:"ABCD" length:4];

    uint8_t entry[64] = {0};
    const char *name = "maps/e1m1.bsp";
    memcpy(entry, name, strlen(name));

    /* First payload starts immediately after 12-byte PAK header. */
    uint32_t fileOffset = 12;
    uint32_t fileSize = 4;
    memcpy(entry + 56, &fileOffset, 4);
    memcpy(entry + 60, &fileSize, 4);

    [data appendBytes:entry length:64];
    return data;
}

- (void)testPAKCodec {
    UDPAKCodec *codec = [[UDPAKCodec alloc] init];

    NSData *pakData = [self quakePAKDataWithEntries];
    NSURL *sigURL = [self writeTemporaryFileWithData:pakData suffix:@"sample.dat"];
    XCTAssertNotNil(sigURL, @"Test setup should create temp file");
    XCTAssertTrue([codec canReadURL:sigURL], @"UDPAKCodec should recognize PACK signature");

    NSURL *pakURL = [self writeTemporaryFileWithData:pakData suffix:@"sample.pak"];
    XCTAssertNotNil(pakURL, @"Test setup should create PAK file");
    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:pakURL error:&readError];
    XCTAssertNil(readError, @"UDPAKCodec should parse valid archive");
    XCTAssertNotNil(archive, @"UDPAKCodec should return archive");
    XCTAssertTrue([archive.displayName hasSuffix:@"sample.pak"], @"UDArchive displayName should match filename suffix");
    XCTAssertEqual(archive.entries.count, 1U, @"Parsed archive should contain one entry");

    UDArchiveEntry *entry = archive.entries.firstObject;
    XCTAssertEqualObjects(entry.path, @"maps/e1m1.bsp", @"Entry path should match directory record");
    XCTAssertEqualObjects(entry.name, @"e1m1.bsp", @"Entry name should be basename");
    XCTAssertEqual(entry.size, 4ULL, @"Entry size should match directory record");

    NSError *payloadError = nil;
    NSData *payload = [entry.source readAll:&payloadError];
    NSString *payloadText = [[NSString alloc] initWithData:payload encoding:NSASCIIStringEncoding];
    XCTAssertNil(payloadError, @"Entry source should read payload");
    XCTAssertEqualObjects(payloadText, @"ABCD", @"Entry payload should match source file bytes");

    NSMutableData *invalidMagicData = [NSMutableData dataWithData:pakData];
    [invalidMagicData replaceBytesInRange:NSMakeRange(0, 4) withBytes:"NOPE"];
    NSURL *invalidMagicURL = [self writeTemporaryFileWithData:invalidMagicData suffix:@"bad.pak"];
    NSError *invalidMagicError = nil;
    UDArchive *invalidMagicArchive = [codec readArchiveFromURL:invalidMagicURL error:&invalidMagicError];
    XCTAssertNil(invalidMagicArchive, @"Invalid signature should fail");
    XCTAssertNotNil(invalidMagicError, @"Invalid signature should set error");

    NSMutableData *invalidDirData = [NSMutableData dataWithData:pakData];
    uint32_t invalidSize = 63;
    [invalidDirData replaceBytesInRange:NSMakeRange(8, 4) withBytes:&invalidSize];
    NSURL *invalidDirURL = [self writeTemporaryFileWithData:invalidDirData suffix:@"bad-size.pak"];
    NSError *invalidDirError = nil;
    UDArchive *invalidDirArchive = [codec readArchiveFromURL:invalidDirURL error:&invalidDirError];
    XCTAssertNil(invalidDirArchive, @"Invalid directory size should fail");
    XCTAssertNotNil(invalidDirError, @"Invalid directory size should set error");

    UDPAKEntrySource *source = [[UDPAKEntrySource alloc] initWithFileURL:pakURL offset:12 length:4];
    NSError *sliceError = nil;
    /* Entry length is 4 bytes; reading from 3 for 2 bytes crosses the boundary. */
    NSData *slice = [source readRange:NSMakeRange(3, 2) error:&sliceError];
    XCTAssertNil(slice, @"Out of bounds range should fail");
    XCTAssertNotNil(sliceError, @"Out of bounds range should set error");

    UDCodecRegistry *registry = [[UDCodecRegistry alloc] init];
    [registry registerCodec:codec];
    id resolvedCodec = [registry codecForFormatIdentifier:@"com.udquake.pak"];
    XCTAssertEqual(resolvedCodec, codec, @"Registry should resolve codec by identifier");
}

@end

