#import <Foundation/Foundation.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDCodecRegistry.h"
#import "UDPAKCodec.h"
#import "UDPAKEntrySource.h"

static BOOL UDCheck(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        return NO;
    }
    return YES;
}

static NSURL *UDWriteTemporaryFileWithData(NSData *data, NSString *suffix) {
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

static NSData *UDQuakePAKDataWithEntries(void) {
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

BOOL UDRunPAKCodecTests(void) {
    BOOL ok = YES;

    UDPAKCodec *codec = [[UDPAKCodec alloc] init];

    NSData *pakData = UDQuakePAKDataWithEntries();
    NSURL *sigURL = UDWriteTemporaryFileWithData(pakData, @"sample.dat");
    ok = UDCheck(sigURL != nil, @"Test setup should create temp file") && ok;
    ok = UDCheck([codec canReadURL:sigURL], @"UDPAKCodec should recognize PACK signature") && ok;

    NSURL *pakURL = UDWriteTemporaryFileWithData(pakData, @"sample.pak");
    ok = UDCheck(pakURL != nil, @"Test setup should create PAK file") && ok;
    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:pakURL error:&readError];
    ok = UDCheck(readError == nil, @"UDPAKCodec should parse valid archive") && ok;
    ok = UDCheck(archive != nil, @"UDPAKCodec should return archive") && ok;
    ok = UDCheck([archive.displayName hasSuffix:@"sample.pak"], @"UDArchive displayName should match filename suffix") && ok;
    ok = UDCheck(archive.entries.count == 1, @"Parsed archive should contain one entry") && ok;

    UDArchiveEntry *entry = archive.entries.firstObject;
    ok = UDCheck([entry.path isEqualToString:@"maps/e1m1.bsp"], @"Entry path should match directory record") && ok;
    ok = UDCheck([entry.name isEqualToString:@"e1m1.bsp"], @"Entry name should be basename") && ok;
    ok = UDCheck(entry.size == 4ULL, @"Entry size should match directory record") && ok;

    NSError *payloadError = nil;
    NSData *payload = [entry.source readAll:&payloadError];
    NSString *payloadText = [[NSString alloc] initWithData:payload encoding:NSASCIIStringEncoding];
    ok = UDCheck(payloadError == nil, @"Entry source should read payload") && ok;
    ok = UDCheck([payloadText isEqualToString:@"ABCD"], @"Entry payload should match source file bytes") && ok;

    NSMutableData *invalidMagicData = [NSMutableData dataWithData:pakData];
    [invalidMagicData replaceBytesInRange:NSMakeRange(0, 4) withBytes:"NOPE"];
    NSURL *invalidMagicURL = UDWriteTemporaryFileWithData(invalidMagicData, @"bad.pak");
    NSError *invalidMagicError = nil;
    UDArchive *invalidMagicArchive = [codec readArchiveFromURL:invalidMagicURL error:&invalidMagicError];
    ok = UDCheck(invalidMagicArchive == nil, @"Invalid signature should fail") && ok;
    ok = UDCheck(invalidMagicError != nil, @"Invalid signature should set error") && ok;

    NSMutableData *invalidDirData = [NSMutableData dataWithData:pakData];
    uint32_t invalidSize = 63;
    [invalidDirData replaceBytesInRange:NSMakeRange(8, 4) withBytes:&invalidSize];
    NSURL *invalidDirURL = UDWriteTemporaryFileWithData(invalidDirData, @"bad-size.pak");
    NSError *invalidDirError = nil;
    UDArchive *invalidDirArchive = [codec readArchiveFromURL:invalidDirURL error:&invalidDirError];
    ok = UDCheck(invalidDirArchive == nil, @"Invalid directory size should fail") && ok;
    ok = UDCheck(invalidDirError != nil, @"Invalid directory size should set error") && ok;

    UDPAKEntrySource *source = [[UDPAKEntrySource alloc] initWithFileURL:pakURL offset:12 length:4];
    NSError *sliceError = nil;
    /* Entry length is 4 bytes; reading from 3 for 2 bytes crosses the boundary. */
    NSData *slice = [source readRange:NSMakeRange(3, 2) error:&sliceError];
    ok = UDCheck(slice == nil, @"Out of bounds range should fail") && ok;
    ok = UDCheck(sliceError != nil, @"Out of bounds range should set error") && ok;

    UDCodecRegistry *registry = [[UDCodecRegistry alloc] init];
    [registry registerCodec:codec];
    id resolvedCodec = [registry codecForFormatIdentifier:@"com.udquake.pak"];
    ok = UDCheck(resolvedCodec == codec, @"Registry should resolve codec by identifier") && ok;

    if (ok) {
        printf("UDPAKCodecTests passed.\n");
    }

    return ok;
}
