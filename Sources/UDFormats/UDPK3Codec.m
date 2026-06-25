#import "UDPK3Codec.h"

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDPK3ZIPEntrySource.h"

#include <zip.h>

static NSString *const UDPK3CodecErrorDomain = @"com.udquake.error.pk3-codec";

typedef NS_ENUM(NSInteger, UDPK3CodecErrorCode) {
    UDPK3CodecErrorCodeOpenFailed      = 1,
    UDPK3CodecErrorCodeNotImplemented  = 2,
};

@implementation UDPK3Codec

- (NSString *)formatIdentifier {
    return @"com.udquake.pk3";
}

/** The file extension this codec claims ownership of during auto-detection. */
- (NSString *)fileExtension {
    return @"pk3";
}

/** The game tag written into UDArchive metadata. */
- (NSString *)gameTag {
    return @"quake3";
}

- (BOOL)canReadURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    NSString *ext = [url.pathExtension lowercaseString];

    if ([ext isEqualToString:self.fileExtension]) {
        return YES;
    }

    /* For files with a recognised game-archive extension that belongs to a
     * different codec, do not claim ownership — extension takes precedence
     * over magic to avoid pk3 vs pk4 ambiguity. */
    static NSArray *knownExtensions = nil;
    if (!knownExtensions) {
        knownExtensions = @[@"pak", @"pk3", @"pk4"];
    }
    if ([knownExtensions containsObject:ext]) {
        return NO;
    }

    /* Unknown extension: fall back to ZIP magic PK (0x50 0x4B). */
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (!handle) {
        return NO;
    }
    NSData *magic = [handle readDataOfLength:2];
    [handle closeFile];
    if (magic.length < 2) {
        return NO;
    }
    const uint8_t *b = magic.bytes;
    return (b[0] == 0x50 && b[1] == 0x4B);
}

- (nullable UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error {
    int zerr = ZIP_ER_OK;
    zip_t *za = zip_open(url.path.fileSystemRepresentation, ZIP_RDONLY, &zerr);
    if (!za) {
        if (error) {
            zip_error_t ze;
            zip_error_init_with_code(&ze, zerr);
            NSString *desc = [NSString stringWithFormat:@"Could not open ZIP archive: %s",
                              zip_error_strerror(&ze)];
            zip_error_fini(&ze);
            *error = [NSError errorWithDomain:UDPK3CodecErrorDomain
                                         code:UDPK3CodecErrorCodeOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return nil;
    }

    zip_int64_t numEntries = zip_get_num_entries(za, 0);
    NSMutableArray *entries = [NSMutableArray array];
    NSDate *defaultModifiedAt = [NSDate dateWithTimeIntervalSince1970:0];

    for (zip_int64_t i = 0; i < numEntries; i++) {
        zip_stat_t st;
        if (zip_stat_index(za, (zip_uint64_t)i, 0, &st) != 0) {
            continue;
        }

        /* Skip entries whose stat does not include name or size. */
        if (!(st.valid & ZIP_STAT_NAME) || !(st.valid & ZIP_STAT_SIZE)) {
            continue;
        }

        NSString *entryName = [NSString stringWithUTF8String:st.name];
        if (!entryName || entryName.length == 0) {
            continue;
        }

        /* Skip directory entries (trailing slash). */
        if ([entryName hasSuffix:@"/"]) {
            continue;
        }

        /* Normalise backslashes (rare but possible). */
        entryName = [entryName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

        uint64_t uncompressedSize = (uint64_t)st.size;

        UDPK3ZIPEntrySource *source = [[UDPK3ZIPEntrySource alloc]
                                        initWithFileURL:url
                                             entryIndex:(uint64_t)i
                                       uncompressedSize:uncompressedSize];

        NSDate *modifiedAt = defaultModifiedAt;
        if (st.valid & ZIP_STAT_MTIME) {
            modifiedAt = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)st.mtime];
        }

        UDArchiveEntry *entry = [[UDArchiveEntry alloc]
                                  initWithPath:entryName
                                          size:uncompressedSize
                                   contentType:@"application/octet-stream"
                                    modifiedAt:modifiedAt
                                        source:source];
        [entries addObject:entry];
    }

    zip_close(za);

    NSDictionary *metadata = @{
        @"formatIdentifier": self.formatIdentifier,
        @"game": self.gameTag,
        @"entryCount": @(entries.count),
    };

    return [[UDArchive alloc] initWithDisplayName:url.lastPathComponent
                                          entries:entries
                                         metadata:metadata];
}

- (BOOL)writeArchive:(UDArchive *)archive toURL:(NSURL *)url error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:UDPK3CodecErrorDomain
                                     code:UDPK3CodecErrorCodeNotImplemented
                                 userInfo:@{NSLocalizedDescriptionKey: @"PK3/PK4 writing is not implemented yet."}];
    }
    return NO;
}

- (BOOL)writeEditedArchive:(UDArchiveEditor *)editor toURL:(NSURL *)url error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:UDPK3CodecErrorDomain
                                     code:UDPK3CodecErrorCodeNotImplemented
                                 userInfo:@{NSLocalizedDescriptionKey: @"PK3/PK4 edited-archive writing is not implemented yet."}];
    }
    return NO;
}

@end
