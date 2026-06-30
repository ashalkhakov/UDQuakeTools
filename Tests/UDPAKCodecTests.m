#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDCodecRegistry.h"
#import "UDDaikatanaPAKCodec.h"
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

- (NSData *)daikatanaPAKDataWithCompressedEntry {
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"PACK" length:4];

    const uint32_t headerSize = 12;
    const uint32_t compressedDataLength = 7;
    const uint32_t directoryOffset = headerSize + compressedDataLength;
    const uint32_t directorySize = 72;

    [data appendBytes:&directoryOffset length:4];
    [data appendBytes:&directorySize length:4];

    /* Daikatana compressed stream that expands to "HELLO".
       0x04 => copy next 5 bytes literally, 0xFF => terminate. */
    const uint8_t compressedPayload[] = { 0x04, 'H', 'E', 'L', 'L', 'O', 0xFF };
    [data appendBytes:compressedPayload length:sizeof(compressedPayload)];

    uint8_t entry[72] = {0};
    const char *name = "textures/test.txt";
    memcpy(entry, name, strlen(name));

    uint32_t fileOffset = headerSize;
    uint32_t fileLength = 5;
    uint32_t compressedLength = (uint32_t)sizeof(compressedPayload);
    uint32_t isCompressed = 1;
    memcpy(entry + 56, &fileOffset, 4);
    memcpy(entry + 60, &fileLength, 4);
    memcpy(entry + 64, &compressedLength, 4);
    memcpy(entry + 68, &isCompressed, 4);

    [data appendBytes:entry length:sizeof(entry)];
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

- (void)testDaikatanaCompressedEntryDecoding {
    UDDaikatanaPAKCodec *codec = [[UDDaikatanaPAKCodec alloc] init];

    NSData *pakData = [self daikatanaPAKDataWithCompressedEntry];
    NSURL *pakURL = [self writeTemporaryFileWithData:pakData suffix:@"dk-test.pak"];
    XCTAssertNotNil(pakURL, @"Test setup should create Daikatana PAK file");

    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:pakURL error:&readError];
    XCTAssertNil(readError, @"Daikatana codec should parse DK archive");
    XCTAssertNotNil(archive, @"Daikatana codec should return archive");
    XCTAssertEqual(archive.entries.count, 1U, @"DK archive should contain one entry");

    UDArchiveEntry *entry = archive.entries.firstObject;
    XCTAssertEqualObjects(entry.path, @"textures/test.txt", @"Entry path should match DK directory record");
    XCTAssertEqual(entry.size, 5ULL, @"Entry size should expose decompressed file length");

    NSError *payloadError = nil;
    NSData *payload = [entry.source readAll:&payloadError];
    NSString *payloadText = [[NSString alloc] initWithData:payload encoding:NSASCIIStringEncoding];
    XCTAssertNil(payloadError, @"Compressed DK entry should decode successfully");
    XCTAssertEqualObjects(payloadText, @"HELLO", @"Decoded DK payload should match expected text");
}

- (void)testWriteEditedPAKArchive {
    UDPAKCodec *codec = [[UDPAKCodec alloc] init];

    NSData *originalData = [self quakePAKDataWithEntries];
    NSURL *inputURL = [self writeTemporaryFileWithData:originalData suffix:@"editable.pak"];
    XCTAssertNotNil(inputURL, @"Test setup should create input PAK");

    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:inputURL error:&readError];
    XCTAssertNotNil(archive, @"Input PAK should load");
    XCTAssertNil(readError, @"Input PAK load should not error");
    if (!archive) {
        return;
    }

    UDArchiveEditor *editor = [[UDArchiveEditor alloc] initWithArchive:archive];

    NSData *replacementData = [@"WXYZ" dataUsingEncoding:NSASCIIStringEncoding];
    NSURL *replacementURL = [self writeTemporaryFileWithData:replacementData suffix:@"replacement.bin"];
    XCTAssertNotNil(replacementURL, @"Test setup should create replacement data source");

    NSData *addedData = [@"README" dataUsingEncoding:NSASCIIStringEncoding];
    NSURL *addedURL = [self writeTemporaryFileWithData:addedData suffix:@"added.bin"];
    XCTAssertNotNil(addedURL, @"Test setup should create added data source");
    if (!replacementURL || !addedURL) {
        return;
    }

    NSError *editError = nil;
    BOOL replaced = [editor replaceEntryAtPath:@"maps/e1m1.bsp"
                                    withSource:[[UDPAKEntrySource alloc] initWithFileURL:replacementURL offset:0 length:replacementData.length]
                                         error:&editError];
    XCTAssertTrue(replaced, @"replace should succeed");
    XCTAssertNil(editError, @"replace should not set error");

    editError = nil;
    BOOL added = [editor addSource:[[UDPAKEntrySource alloc] initWithFileURL:addedURL offset:0 length:addedData.length]
                            atPath:@"docs/readme.txt"
                             error:&editError];
    XCTAssertTrue(added, @"add should succeed");
    XCTAssertNil(editError, @"add should not set error");

    NSURL *outputURL = [self writeTemporaryFileWithData:[NSData data] suffix:@"out-edited.pak"];
    XCTAssertNotNil(outputURL, @"Test setup should create output path");
    if (!outputURL) {
        return;
    }

    NSError *writeError = nil;
    BOOL wrote = [codec writeEditedArchive:editor toURL:outputURL error:&writeError];
    XCTAssertTrue(wrote, @"writing edited PAK should succeed");
    XCTAssertNil(writeError, @"writing edited PAK should not set error");

    NSError *verifyReadError = nil;
    UDArchive *savedArchive = [codec readArchiveFromURL:outputURL error:&verifyReadError];
    XCTAssertNotNil(savedArchive, @"saved PAK should load");
    XCTAssertNil(verifyReadError, @"saved PAK should load without error");
    if (!savedArchive) {
        return;
    }

    XCTAssertEqual(savedArchive.entries.count, 2U, @"saved PAK should contain replaced and added entry");

    NSMutableDictionary<NSString *, UDArchiveEntry *> *entryMap = [NSMutableDictionary dictionary];
    for (UDArchiveEntry *entry in savedArchive.entries) {
        [entryMap setObject:entry forKey:entry.path];
    }

    UDArchiveEntry *replacedEntry = [entryMap objectForKey:@"maps/e1m1.bsp"];
    UDArchiveEntry *addedEntry = [entryMap objectForKey:@"docs/readme.txt"];
    XCTAssertNotNil(replacedEntry, @"saved PAK should contain replaced entry");
    XCTAssertNotNil(addedEntry, @"saved PAK should contain added entry");

    NSError *payloadError = nil;
    NSData *replacedPayload = [replacedEntry.source readAll:&payloadError];
    XCTAssertNil(payloadError, @"replaced payload should be readable");
    XCTAssertEqualObjects([[NSString alloc] initWithData:replacedPayload encoding:NSASCIIStringEncoding],
                          @"WXYZ",
                          @"replaced payload should match");

    payloadError = nil;
    NSData *addedPayload = [addedEntry.source readAll:&payloadError];
    XCTAssertNil(payloadError, @"added payload should be readable");
    XCTAssertEqualObjects([[NSString alloc] initWithData:addedPayload encoding:NSASCIIStringEncoding],
                          @"README",
                          @"added payload should match");
}

@end

