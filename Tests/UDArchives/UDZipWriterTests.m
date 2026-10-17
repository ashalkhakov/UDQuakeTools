#import <XCTest/XCTest.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDPK3Codec.h"
#import "UDZipWriter.h"

/* UDZipWriter is checked against the other half of the toolkit: everything
 * it writes is read back through UDPK3Codec, i.e. the minizip unzip.c the
 * Doom 3 file system uses. */
@interface UDZipWriterTests : XCTestCase
@property (nonatomic, strong) NSMutableArray<NSURL *> *temporaryURLs;
@end

@implementation UDZipWriterTests

- (void)setUp {
    [super setUp];
    self.temporaryURLs = [NSMutableArray array];
}

- (void)tearDown {
    for (NSURL *url in self.temporaryURLs) {
        [[NSFileManager defaultManager] removeItemAtURL:url error:NULL];
    }
    [super tearDown];
}

- (NSURL *)temporaryURLWithExtension:(NSString *)extension {
    NSString *name = [NSString stringWithFormat:@"udzipwriter-%@.%@", [[NSUUID UUID] UUIDString], extension];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    [self.temporaryURLs addObject:url];
    return url;
}

- (NSDictionary<NSString *, UDArchiveEntry *> *)entriesOfArchiveAtURL:(NSURL *)url {
    NSError *error = nil;
    UDArchive *archive = [[[UDPK3Codec alloc] init] readArchiveFromURL:url error:&error];
    XCTAssertNotNil(archive, @"the written archive should read back: %@", error);
    NSMutableDictionary *byPath = [NSMutableDictionary dictionary];
    for (UDArchiveEntry *entry in archive.entries) {
        byPath[entry.path] = entry;
    }
    return byPath;
}

- (void)testEveryMethodRoundTripsThroughTheDoom3Reader {
    NSMutableData *large = [NSMutableData data];
    for (int i = 0; i < 4096; i++) {
        [large appendData:[[NSString stringWithFormat:@"textures/base_wall/lfwall%d\n", i % 17]
                              dataUsingEncoding:NSUTF8StringEncoding]];
    }
    NSData *tiny = [@"x" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *empty = [NSData data];

    UDZipWriter *writer = [[UDZipWriter alloc] init];
    NSError *error = nil;
    XCTAssertTrue([writer addEntryWithPath:@"stored.txt" data:large method:UDZipCompressionMethodStored modificationDate:nil error:&error], @"%@", error);
    XCTAssertTrue([writer addEntryWithPath:@"deflated.txt" data:large method:UDZipCompressionMethodDeflated modificationDate:nil error:&error], @"%@", error);
    XCTAssertTrue([writer addEntryWithPath:@"auto/tiny.txt" data:tiny method:UDZipCompressionMethodAutomatic modificationDate:nil error:&error], @"%@", error);
    XCTAssertTrue([writer addEntryWithPath:@"empty.txt" data:empty method:UDZipCompressionMethodDeflated modificationDate:nil error:&error], @"%@", error);
    XCTAssertTrue([writer addEntryWithPath:@"guis/ünïcode.gui" data:tiny method:UDZipCompressionMethodStored modificationDate:nil error:&error], @"%@", error);
    XCTAssertEqual(writer.entryCount, 5U);

    NSURL *url = [self temporaryURLWithExtension:@"pk4"];
    XCTAssertTrue([writer writeToURL:url error:&error], @"%@", error);

    NSDictionary<NSString *, UDArchiveEntry *> *entries = [self entriesOfArchiveAtURL:url];
    XCTAssertEqual(entries.count, 5U);

    NSDictionary *expected = @{ @"stored.txt": large, @"deflated.txt": large,
                                @"auto/tiny.txt": tiny, @"empty.txt": empty,
                                @"guis/ünïcode.gui": tiny };
    for (NSString *path in expected) {
        UDArchiveEntry *entry = entries[path];
        XCTAssertNotNil(entry, @"%@ should be in the archive", path);
        NSError *readError = nil;
        NSData *data = [entry.source readAll:&readError];
        XCTAssertEqualObjects(data, expected[path], @"%@ should read back intact (%@)", path, readError);
        XCTAssertEqual(entry.size, (uint64_t)[expected[path] length]);
    }
}

- (void)testAutomaticMethodOnlyDeflatesWhenThatShrinksTheEntry {
    NSData *repetitive = [[@"" stringByPaddingToLength:2000 withString:@"abc" startingAtIndex:0]
                             dataUsingEncoding:NSUTF8StringEncoding];
    NSData *tiny = [@"ok" dataUsingEncoding:NSUTF8StringEncoding];

    UDZipWriter *writer = [[UDZipWriter alloc] init];
    XCTAssertTrue([writer addEntryWithPath:@"a" data:repetitive method:UDZipCompressionMethodAutomatic modificationDate:nil error:NULL]);
    NSUInteger afterFirst = [writer archiveData].length;
    XCTAssertTrue([writer addEntryWithPath:@"b" data:tiny method:UDZipCompressionMethodAutomatic modificationDate:nil error:NULL]);
    NSData *archive = [writer archiveData];

    // Local header of entry "a" starts at 0; its method is at offset 8.
    const uint8_t *bytes = archive.bytes;
    XCTAssertEqual(bytes[8] | (bytes[9] << 8), 8, @"repetitive text should be deflated");
    XCTAssertLessThan(afterFirst, repetitive.length, @"and the archive should be smaller than the text");

    // Entry "b" follows "a"'s header (30 + name) and its compressed payload.
    NSUInteger compressedA = bytes[18] | (bytes[19] << 8) | (bytes[20] << 16) | ((NSUInteger)bytes[21] << 24);
    NSUInteger headerB = 30 + 1 + compressedA;
    XCTAssertEqual(bytes[headerB + 8] | (bytes[headerB + 9] << 8), 0, @"two bytes should be stored, not deflated");
}

- (void)testModificationDateSurvivesToTwoSecondPrecision {
    NSDateComponents *components = [[NSDateComponents alloc] init];
    components.year = 2004; components.month = 8; components.day = 3;
    components.hour = 14; components.minute = 25; components.second = 37;
    NSDate *date = [[NSCalendar currentCalendar] dateFromComponents:components];

    UDZipWriter *writer = [[UDZipWriter alloc] init];
    XCTAssertTrue([writer addEntryWithPath:@"maps/delta1.map" data:[NSData data] method:UDZipCompressionMethodStored modificationDate:date error:NULL]);
    NSURL *url = [self temporaryURLWithExtension:@"pk4"];
    XCTAssertTrue([writer writeToURL:url error:NULL]);

    UDArchiveEntry *entry = [self entriesOfArchiveAtURL:url][@"maps/delta1.map"];
    XCTAssertEqualWithAccuracy(entry.modifiedAt.timeIntervalSince1970, date.timeIntervalSince1970 - 1, 0.01,
                               @"DOS time keeps even seconds, so :37 is stored as :36");
}

- (void)testCorruptedPayloadFailsTheCRCCheck {
    NSData *payload = [@"pda admin_moses { name \"Jonathan Moses\" }" dataUsingEncoding:NSUTF8StringEncoding];
    UDZipWriter *writer = [[UDZipWriter alloc] init];
    XCTAssertTrue([writer addEntryWithPath:@"newpdas/admin_moses.pda" data:payload method:UDZipCompressionMethodStored modificationDate:nil error:NULL]);
    NSMutableData *archive = [[writer archiveData] mutableCopy];

    // Flip one byte of the stored payload (after the 30-byte header and the name).
    NSUInteger payloadStart = 30 + [@"newpdas/admin_moses.pda" length];
    ((uint8_t *)archive.mutableBytes)[payloadStart + 5] ^= 0xFF;

    NSURL *url = [self temporaryURLWithExtension:@"pk4"];
    XCTAssertTrue([archive writeToURL:url atomically:YES]);

    UDArchiveEntry *entry = [self entriesOfArchiveAtURL:url][@"newpdas/admin_moses.pda"];
    NSError *error = nil;
    XCTAssertNil([entry.source readAll:&error], @"a corrupted entry must not read back");
    XCTAssertNotNil(error);
}

@end
