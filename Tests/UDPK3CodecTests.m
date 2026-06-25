#import <Foundation/Foundation.h>
#include <zip.h>

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDPK3Codec.h"
#import "UDPK4Codec.h"
#import "UDPK3ZIPEntrySource.h"

static BOOL UDZIPCheck(BOOL condition, NSString *message) {
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message.UTF8String);
        return NO;
    }
    return YES;
}

/* Write data to a temporary file and return its URL. */
static NSURL *UDZIPWriteTempFile(NSData *data, NSString *suffix) {
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
 * We use libzip to create the in-memory archive so the test does not
 * depend on an external tool. */
static NSData *UDMakeTestZIPData(void) {
    zip_source_t *src = zip_source_buffer_create(NULL, 0, 0, NULL);
    if (!src) {
        return nil;
    }

    zip_t *za = zip_open_from_source(src, ZIP_TRUNCATE, NULL);
    if (!za) {
        zip_source_free(src);
        return nil;
    }

    const char *payload1 = "hello pk3";
    zip_source_t *s1 = zip_source_buffer(za, payload1, strlen(payload1), 0);
    if (zip_file_add(za, "maps/q3dm1.bsp", s1, ZIP_FL_OVERWRITE) < 0) {
        zip_discard(za);
        return nil;
    }
    zip_set_file_compression(za, 0, ZIP_CM_DEFLATE, 0);

    const char *payload2 = "nolightmap";
    zip_source_t *s2 = zip_source_buffer(za, payload2, strlen(payload2), 0);
    if (zip_file_add(za, "scripts/base.shader", s2, ZIP_FL_OVERWRITE) < 0) {
        zip_discard(za);
        return nil;
    }
    zip_set_file_compression(za, 1, ZIP_CM_STORE, 0);

    /* Keep the source alive so we can read it after zip_close. */
    zip_source_keep(src);

    if (zip_close(za) != 0) {
        zip_source_free(src);
        return nil;
    }

    /* Read the in-memory buffer. */
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

BOOL UDRunPK3CodecTests(void) {
    BOOL ok = YES;

    NSData *zipData = UDMakeTestZIPData();
    ok = UDZIPCheck(zipData != nil, @"Test setup: ZIP data should be created") && ok;
    if (!zipData) {
        return NO;
    }

    /* ---- PK3 ---- */
    NSURL *pk3URL = UDZIPWriteTempFile(zipData, @"sample.pk3");
    ok = UDZIPCheck(pk3URL != nil, @"Test setup: PK3 temp file should be created") && ok;

    UDPK3Codec *pk3Codec = [[UDPK3Codec alloc] init];
    ok = UDZIPCheck([pk3Codec canReadURL:pk3URL], @"UDPK3Codec should recognise .pk3 extension") && ok;

    NSError *err = nil;
    UDArchive *pk3Archive = [pk3Codec readArchiveFromURL:pk3URL error:&err];
    ok = UDZIPCheck(err == nil,        @"UDPK3Codec should parse valid PK3 without error") && ok;
    ok = UDZIPCheck(pk3Archive != nil, @"UDPK3Codec should return an archive") && ok;

    if (pk3Archive) {
        ok = UDZIPCheck([pk3Archive.displayName hasSuffix:@"sample.pk3"],
                        @"PK3 archive displayName should match filename") && ok;
        ok = UDZIPCheck(pk3Archive.entries.count == 2,
                        @"PK3 archive should contain 2 entries") && ok;

        NSString *game = [pk3Archive.metadata objectForKey:@"game"];
        ok = UDZIPCheck([game isEqualToString:@"quake3"],
                        @"PK3 archive metadata game should be quake3") && ok;

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

        ok = UDZIPCheck(bspEntry != nil,    @"PK3 should have maps/q3dm1.bsp entry") && ok;
        ok = UDZIPCheck(shaderEntry != nil, @"PK3 should have scripts/base.shader entry") && ok;

        if (bspEntry) {
            ok = UDZIPCheck(bspEntry.size == 9,
                            @"PK3 bsp entry size should be 9") && ok;
            ok = UDZIPCheck([bspEntry.name isEqualToString:@"q3dm1.bsp"],
                            @"PK3 bsp entry name should be q3dm1.bsp") && ok;

            NSError *readErr = nil;
            NSData *payload = [bspEntry.source readAll:&readErr];
            ok = UDZIPCheck(readErr == nil, @"PK3 bsp entry readAll should succeed") && ok;
            ok = UDZIPCheck(payload != nil, @"PK3 bsp entry readAll should return data") && ok;
            if (payload) {
                NSString *text = [[NSString alloc] initWithData:payload
                                                       encoding:NSASCIIStringEncoding];
                ok = UDZIPCheck([text isEqualToString:@"hello pk3"],
                                @"PK3 bsp entry payload should match") && ok;
            }

            /* readRange: slice test. */
            NSError *sliceErr = nil;
            NSData *slice = [bspEntry.source readRange:NSMakeRange(0, 5) error:&sliceErr];
            ok = UDZIPCheck(sliceErr == nil, @"PK3 bsp entry readRange should succeed") && ok;
            if (slice) {
                NSString *sliceText = [[NSString alloc] initWithData:slice
                                                            encoding:NSASCIIStringEncoding];
                ok = UDZIPCheck([sliceText isEqualToString:@"hello"],
                                @"PK3 bsp entry readRange(0,5) should return 'hello'") && ok;
            }

            /* Out-of-bounds range. */
            NSError *oobErr = nil;
            NSData *oob = [bspEntry.source readRange:NSMakeRange(8, 5) error:&oobErr];
            ok = UDZIPCheck(oob == nil,    @"PK3 out-of-bounds readRange should return nil") && ok;
            ok = UDZIPCheck(oobErr != nil, @"PK3 out-of-bounds readRange should set error") && ok;
        }
    }

    /* ---- PK4 ---- */
    NSURL *pk4URL = UDZIPWriteTempFile(zipData, @"sample.pk4");
    ok = UDZIPCheck(pk4URL != nil, @"Test setup: PK4 temp file should be created") && ok;

    UDPK4Codec *pk4Codec = [[UDPK4Codec alloc] init];
    ok = UDZIPCheck([pk4Codec canReadURL:pk4URL],
                    @"UDPK4Codec should recognise .pk4 extension") && ok;
    ok = UDZIPCheck(![pk3Codec canReadURL:pk4URL],
                    @"UDPK3Codec should NOT claim a .pk4 file") && ok;

    NSError *pk4Err = nil;
    UDArchive *pk4Archive = [pk4Codec readArchiveFromURL:pk4URL error:&pk4Err];
    ok = UDZIPCheck(pk4Err == nil,        @"UDPK4Codec should parse valid PK4 without error") && ok;
    ok = UDZIPCheck(pk4Archive != nil,    @"UDPK4Codec should return an archive") && ok;

    if (pk4Archive) {
        NSString *game = [pk4Archive.metadata objectForKey:@"game"];
        ok = UDZIPCheck([game isEqualToString:@"doom3"],
                        @"PK4 archive metadata game should be doom3") && ok;
        ok = UDZIPCheck(pk4Archive.entries.count == 2,
                        @"PK4 archive should contain 2 entries") && ok;
    }

    /* ---- Error case: bad file ---- */
    NSData *junk = [@"not a zip" dataUsingEncoding:NSASCIIStringEncoding];
    NSURL *badURL = UDZIPWriteTempFile(junk, @"bad.pk3");
    NSError *badErr = nil;
    UDArchive *badArchive = [pk3Codec readArchiveFromURL:badURL error:&badErr];
    ok = UDZIPCheck(badArchive == nil, @"UDPK3Codec should return nil for corrupt file") && ok;
    ok = UDZIPCheck(badErr != nil,     @"UDPK3Codec should set error for corrupt file") && ok;

    if (ok) {
        printf("UDPK3CodecTests passed.\n");
    }

    return ok;
}
