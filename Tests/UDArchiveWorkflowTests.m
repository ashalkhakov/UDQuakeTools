#import <XCTest/XCTest.h>
#import <Foundation/Foundation.h>
#include <zip.h>
#include <stdint.h>

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDContentSource.h"
#import "UDDaikatanaPAKCodec.h"
#import "UDPAK2Codec.h"
#import "UDPAKCodec.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"

@interface UDInMemoryWorkflowSource : NSObject <UDContentSource>
@property (nonatomic, strong, readonly) NSData *data;
- (instancetype)initWithData:(NSData *)data;
@end

@implementation UDInMemoryWorkflowSource

@synthesize data = _data;

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
            *error = [NSError errorWithDomain:@"UDInMemoryWorkflowSource"
                                         code:1
                                     userInfo:@{NSLocalizedDescriptionKey: @"Range out of bounds."}];
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

@interface UDArchiveWorkflowTests : XCTestCase
@end

@implementation UDArchiveWorkflowTests

- (NSURL *)writeTempFileWithData:(NSData *)data suffix:(NSString *)suffix {
    NSString *name = [NSString stringWithFormat:@"udquake-workflow-%@-%@",
                      [[NSUUID UUID] UUIDString], suffix];
    NSURL *url = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:name]];
    NSError *err = nil;
    if (![data writeToURL:url options:NSDataWritingAtomic error:&err]) {
        return nil;
    }
    return url;
}

- (NSData *)makeQuakePAKData {
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
    uint32_t fileOffset = 12;
    uint32_t fileSize = 4;
    memcpy(entry + 56, &fileOffset, 4);
    memcpy(entry + 60, &fileSize, 4);
    [data appendBytes:entry length:64];
    return data;
}

- (NSData *)makeDaikatanaPAKData {
    NSMutableData *data = [NSMutableData data];
    [data appendBytes:"PACK" length:4];

    const uint32_t headerSize = 12;
    const uint32_t compressedDataLength = 7;
    const uint32_t directoryOffset = headerSize + compressedDataLength;
    const uint32_t directorySize = 72;
    [data appendBytes:&directoryOffset length:4];
    [data appendBytes:&directorySize length:4];

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

- (NSData *)makeZIPData {
    zip_source_t *src = zip_source_buffer_create(NULL, 0, 0, NULL);
    if (!src) {
        return nil;
    }
    zip_t *za = zip_open_from_source(src, ZIP_TRUNCATE, NULL);
    if (!za) {
        zip_source_free(src);
        return nil;
    }

    const char *payload1 = "hello zip";
    zip_source_t *s1 = zip_source_buffer(za, payload1, strlen(payload1), 0);
    if (zip_file_add(za, "maps/q3dm1.bsp", s1, ZIP_FL_OVERWRITE) < 0) {
        zip_discard(za);
        return nil;
    }
    zip_set_file_compression(za, 0, ZIP_CM_DEFLATE, 0);

    const char *payload2 = "script data";
    zip_source_t *s2 = zip_source_buffer(za, payload2, strlen(payload2), 0);
    if (zip_file_add(za, "scripts/base.shader", s2, ZIP_FL_OVERWRITE) < 0) {
        zip_discard(za);
        return nil;
    }
    zip_set_file_compression(za, 1, ZIP_CM_STORE, 0);

    zip_source_keep(src);
    if (zip_close(za) != 0) {
        zip_source_free(src);
        return nil;
    }

    zip_source_open(src);
    zip_source_seek(src, 0, SEEK_END);
    zip_int64_t size = zip_source_tell(src);
    zip_source_seek(src, 0, SEEK_SET);
    if (size <= 0) {
        zip_source_free(src);
        return nil;
    }

    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)size];
    zip_source_read(src, data.mutableBytes, (zip_uint64_t)size);
    zip_source_close(src);
    zip_source_free(src);
    return data;
}

- (NSDictionary<NSString *, NSData *> *)payloadMapForArchive:(UDArchive *)archive {
    NSMutableDictionary<NSString *, NSData *> *map = [NSMutableDictionary dictionary];
    for (UDArchiveEntry *entry in archive.entries) {
        NSError *err = nil;
        NSData *data = nil;
        if ([entry.source respondsToSelector:@selector(readAll:)]) {
            data = [entry.source readAll:&err];
        } else {
            data = [entry.source readRange:NSMakeRange(0, (NSUInteger)entry.size) error:&err];
        }
        XCTAssertNil(err);
        XCTAssertNotNil(data);
        if (data) {
            [map setObject:data forKey:entry.path];
        }
    }
    return map;
}

- (NSDictionary<NSString *, NSData *> *)payloadMapForEditor:(UDArchiveEditor *)editor {
    NSMutableDictionary<NSString *, NSData *> *map = [NSMutableDictionary dictionary];
    for (UDArchiveEntry *entry in editor.currentEntries) {
        NSError *err = nil;
        NSData *data = [editor contentForEntryAtPath:entry.path
                                               range:NSMakeRange(0, (NSUInteger)entry.size)
                                               error:&err];
        XCTAssertNil(err);
        XCTAssertNotNil(data);
        if (data) {
            [map setObject:data forKey:entry.path];
        }
    }
    return map;
}

- (void)assertCanReadPackageWithCodec:(id<UDArchiveCodec>)codec
                             data:(NSData *)data
                           suffix:(NSString *)suffix
                     expectedPath:(NSString *)expectedPath
                  expectedPayload:(NSString *)expectedPayload {
    NSURL *url = [self writeTempFileWithData:data suffix:suffix];
    XCTAssertNotNil(url);
    XCTAssertTrue([codec canReadURL:url]);

    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:url error:&readError];
    XCTAssertNil(readError);
    XCTAssertNotNil(archive);
    if (!archive) {
        return;
    }

    NSDictionary<NSString *, NSData *> *payloads = [self payloadMapForArchive:archive];
    NSData *payloadData = [payloads objectForKey:expectedPath];
    XCTAssertNotNil(payloadData);
    NSString *payloadText = [[NSString alloc] initWithData:payloadData encoding:NSASCIIStringEncoding];
    XCTAssertEqualObjects(payloadText, expectedPayload);
}

- (void)assertCreateWriteReadForCodec:(id<UDArchiveCodec>)codec suffix:(NSString *)suffix {
    NSData *a = [@"alpha" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *b = [@"beta" dataUsingEncoding:NSASCIIStringEncoding];

    UDArchiveEntry *e1 = [[UDArchiveEntry alloc] initWithPath:@"dir1/a.txt"
                                                         size:a.length
                                                  contentType:@"text/plain"
                                                   modifiedAt:[NSDate date]
                                                       source:[[UDInMemoryWorkflowSource alloc] initWithData:a]];
    UDArchiveEntry *e2 = [[UDArchiveEntry alloc] initWithPath:@"dir2/b.txt"
                                                         size:b.length
                                                  contentType:@"text/plain"
                                                   modifiedAt:[NSDate date]
                                                       source:[[UDInMemoryWorkflowSource alloc] initWithData:b]];
    UDArchive *newArchive = [[UDArchive alloc] initWithDisplayName:[NSString stringWithFormat:@"created.%@", suffix]
                                                            entries:@[e1, e2]
                                                           metadata:@{}];

    NSURL *outURL = [self writeTempFileWithData:[NSData data] suffix:[NSString stringWithFormat:@"created.%@", suffix]];
    XCTAssertNotNil(outURL);
    if (!outURL) {
        return;
    }

    NSError *writeError = nil;
    BOOL wrote = [codec writeArchive:newArchive toURL:outURL error:&writeError];
    XCTAssertTrue(wrote);
    XCTAssertNil(writeError);

    NSError *readError = nil;
    UDArchive *reloaded = [codec readArchiveFromURL:outURL error:&readError];
    XCTAssertNotNil(reloaded);
    XCTAssertNil(readError);
    if (!reloaded) {
        return;
    }

    NSDictionary<NSString *, NSData *> *actual = [self payloadMapForArchive:reloaded];
    XCTAssertEqual(actual.count, 2U);
    XCTAssertEqualObjects([[NSString alloc] initWithData:[actual objectForKey:@"dir1/a.txt"] encoding:NSASCIIStringEncoding], @"alpha");
    XCTAssertEqualObjects([[NSString alloc] initWithData:[actual objectForKey:@"dir2/b.txt"] encoding:NSASCIIStringEncoding], @"beta");
}

- (void)assertEditProjectedStateAndWriteForCodec:(id<UDArchiveCodec>)codec
                                            data:(NSData *)seedData
                                          suffix:(NSString *)suffix
                                         oldPath:(NSString *)oldPath
                                     replaceWith:(NSString *)replacementText {
    NSURL *inURL = [self writeTempFileWithData:seedData suffix:[NSString stringWithFormat:@"seed.%@", suffix]];
    XCTAssertNotNil(inURL);
    if (!inURL) {
        return;
    }

    NSError *readError = nil;
    UDArchive *archive = [codec readArchiveFromURL:inURL error:&readError];
    XCTAssertNotNil(archive);
    XCTAssertNil(readError);
    if (!archive) {
        return;
    }

    UDArchiveEditor *editor = [[UDArchiveEditor alloc] initWithArchive:archive];

    NSData *replacementData = [replacementText dataUsingEncoding:NSASCIIStringEncoding];
    NSData *addedData = [@"new-file" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *dirData = [@"dir-file" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *removeA = [@"remove-a" dataUsingEncoding:NSASCIIStringEncoding];
    NSData *removeB = [@"remove-b" dataUsingEncoding:NSASCIIStringEncoding];

    NSError *err = nil;
    XCTAssertTrue([editor replaceEntryAtPath:oldPath
                                  withSource:[[UDInMemoryWorkflowSource alloc] initWithData:replacementData]
                                       error:&err]);
    XCTAssertNil(err);

    err = nil;
    XCTAssertTrue([editor addSource:[[UDInMemoryWorkflowSource alloc] initWithData:addedData]
                              atPath:@"added/new.txt"
                               error:&err]);
    XCTAssertNil(err);

    err = nil;
    XCTAssertTrue([editor addSource:[[UDInMemoryWorkflowSource alloc] initWithData:dirData]
                              atPath:@"newdir/sub/inside.txt"
                               error:&err]);
    XCTAssertNil(err);

    err = nil;
    XCTAssertTrue([editor addSource:[[UDInMemoryWorkflowSource alloc] initWithData:removeA]
                              atPath:@"toremove/sub/a.txt"
                               error:&err]);
    XCTAssertNil(err);

    err = nil;
    XCTAssertTrue([editor addSource:[[UDInMemoryWorkflowSource alloc] initWithData:removeB]
                              atPath:@"toremove/sub/b.txt"
                               error:&err]);
    XCTAssertNil(err);

    err = nil;
    XCTAssertTrue([editor removeNodeAtPath:@"toremove" error:&err]);
    XCTAssertNil(err);

    NSDictionary<NSString *, NSData *> *projected = [self payloadMapForEditor:editor];
    XCTAssertEqualObjects([[NSString alloc] initWithData:[projected objectForKey:oldPath] encoding:NSASCIIStringEncoding], replacementText);
    XCTAssertEqualObjects([[NSString alloc] initWithData:[projected objectForKey:@"added/new.txt"] encoding:NSASCIIStringEncoding], @"new-file");
    XCTAssertEqualObjects([[NSString alloc] initWithData:[projected objectForKey:@"newdir/sub/inside.txt"] encoding:NSASCIIStringEncoding], @"dir-file");
    XCTAssertNil([projected objectForKey:@"toremove/sub/a.txt"]);
    XCTAssertNil([projected objectForKey:@"toremove/sub/b.txt"]);

    NSURL *outURL = [self writeTempFileWithData:[NSData data] suffix:[NSString stringWithFormat:@"edited.%@", suffix]];
    XCTAssertNotNil(outURL);
    if (!outURL) {
        return;
    }

    NSError *writeError = nil;
    XCTAssertTrue([codec writeEditedArchive:editor toURL:outURL error:&writeError]);
    XCTAssertNil(writeError);

    NSError *verifyError = nil;
    UDArchive *saved = [codec readArchiveFromURL:outURL error:&verifyError];
    XCTAssertNotNil(saved);
    XCTAssertNil(verifyError);
    if (!saved) {
        return;
    }

    NSDictionary<NSString *, NSData *> *actual = [self payloadMapForArchive:saved];
    XCTAssertEqual(actual.count, projected.count);
    for (NSString *path in projected) {
        NSData *expectedData = [projected objectForKey:path];
        NSData *actualData = [actual objectForKey:path];
        XCTAssertEqualObjects(actualData, expectedData, @"Saved archive should match in-memory projected state for %@", path);
    }
}

- (void)testReadExistingPackagesAllCodecs {
    UDPAKCodec *pak = [[UDPAKCodec alloc] init];
    [self assertCanReadPackageWithCodec:pak
                                   data:[self makeQuakePAKData]
                                 suffix:@"quake.pak"
                           expectedPath:@"maps/e1m1.bsp"
                        expectedPayload:@"ABCD"];

    UDPAK2Codec *pak2 = [[UDPAK2Codec alloc] init];
    [self assertCanReadPackageWithCodec:pak2
                                   data:[self makeQuakePAKData]
                                 suffix:@"quake2.pak"
                           expectedPath:@"maps/e1m1.bsp"
                        expectedPayload:@"ABCD"];

    UDDaikatanaPAKCodec *dk = [[UDDaikatanaPAKCodec alloc] init];
    [self assertCanReadPackageWithCodec:dk
                                   data:[self makeDaikatanaPAKData]
                                 suffix:@"daikatana.pak"
                           expectedPath:@"textures/test.txt"
                        expectedPayload:@"HELLO"];

    UDPK3Codec *pk3 = [[UDPK3Codec alloc] init];
    [self assertCanReadPackageWithCodec:pk3
                                   data:[self makeZIPData]
                                 suffix:@"quake3.pk3"
                           expectedPath:@"maps/q3dm1.bsp"
                        expectedPayload:@"hello zip"];

    UDPK4Codec *pk4 = [[UDPK4Codec alloc] init];
    [self assertCanReadPackageWithCodec:pk4
                                   data:[self makeZIPData]
                                 suffix:@"doom3.pk4"
                           expectedPath:@"maps/q3dm1.bsp"
                        expectedPayload:@"hello zip"];

    /* Quake 4 uses PK4 too; verify open path for that package naming as well. */
    [self assertCanReadPackageWithCodec:pk4
                                   data:[self makeZIPData]
                                 suffix:@"quake4.pk4"
                           expectedPath:@"maps/q3dm1.bsp"
                        expectedPayload:@"hello zip"];
}

- (void)testCreateNewPackageWritingAllCodecs {
    [self assertCreateWriteReadForCodec:[[UDPAKCodec alloc] init] suffix:@"pak"];
    [self assertCreateWriteReadForCodec:[[UDPAK2Codec alloc] init] suffix:@"pak"];
    [self assertCreateWriteReadForCodec:[[UDDaikatanaPAKCodec alloc] init] suffix:@"pak"];
    [self assertCreateWriteReadForCodec:[[UDPK3Codec alloc] init] suffix:@"pk3"];
    [self assertCreateWriteReadForCodec:[[UDPK4Codec alloc] init] suffix:@"pk4"];
}

- (void)testEditExistingPackageProjectedStateMatchesSavedArchiveAllCodecs {
    [self assertEditProjectedStateAndWriteForCodec:[[UDPAKCodec alloc] init]
                                              data:[self makeQuakePAKData]
                                            suffix:@"pak"
                                           oldPath:@"maps/e1m1.bsp"
                                       replaceWith:@"WXYZ"];

    [self assertEditProjectedStateAndWriteForCodec:[[UDPAK2Codec alloc] init]
                                              data:[self makeQuakePAKData]
                                            suffix:@"pak"
                                           oldPath:@"maps/e1m1.bsp"
                                       replaceWith:@"WXYZ"];

    [self assertEditProjectedStateAndWriteForCodec:[[UDDaikatanaPAKCodec alloc] init]
                                              data:[self makeDaikatanaPAKData]
                                            suffix:@"pak"
                                           oldPath:@"textures/test.txt"
                                       replaceWith:@"WORLD"];

    [self assertEditProjectedStateAndWriteForCodec:[[UDPK3Codec alloc] init]
                                              data:[self makeZIPData]
                                            suffix:@"pk3"
                                           oldPath:@"maps/q3dm1.bsp"
                                       replaceWith:@"UPDATED"];

    [self assertEditProjectedStateAndWriteForCodec:[[UDPK4Codec alloc] init]
                                              data:[self makeZIPData]
                                            suffix:@"pk4"
                                           oldPath:@"maps/q3dm1.bsp"
                                       replaceWith:@"UPDATED"];
}

@end
