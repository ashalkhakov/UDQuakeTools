#import "UDPK3Codec.h"

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDPK3ZIPEntrySource.h"
#import "UDZipWriter.h"

#include <time.h>
#include "unzip.h"

static NSString *const UDPK3CodecErrorDomain = @"com.udquake.error.pk3-codec";

typedef NS_ENUM(NSInteger, UDPK3CodecErrorCode) {
    UDPK3CodecErrorCodeOpenFailed      = 1,
    UDPK3CodecErrorCodeWriteFailed     = 2,
};

static NSData *UDReadAllZIPContent(id<UDContentSource> source, NSError **error) {
    if ([source respondsToSelector:@selector(readAll:)]) {
        NSData *all = [source readAll:error];
        if (all) {
            return all;
        }
    }

    uint64_t len = [source length];
    if (len > NSUIntegerMax) {
        if (error) {
            *error = [NSError errorWithDomain:UDPK3CodecErrorDomain
                                         code:UDPK3CodecErrorCodeWriteFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Entry is too large to process on this platform."}];
        }
        return nil;
    }
    return [source readRange:NSMakeRange(0, (NSUInteger)len) error:error];
}

/* ZIP stores MS-DOS local time; unzip.c hands it over already split up. */
static NSDate *UDDateFromZIPDate(tm_unz date) {
    struct tm local;
    memset(&local, 0, sizeof(local));
    local.tm_year = (int)date.tm_year - 1900;
    local.tm_mon = (int)date.tm_mon;
    local.tm_mday = (int)date.tm_mday;
    local.tm_hour = (int)date.tm_hour;
    local.tm_min = (int)date.tm_min;
    local.tm_sec = (int)date.tm_sec;
    local.tm_isdst = -1;
    time_t seconds = mktime(&local);
    return [NSDate dateWithTimeIntervalSince1970:seconds == (time_t)-1 ? 0 : (NSTimeInterval)seconds];
}

@interface UDPK3Codec ()
- (BOOL)_writeEntries:(NSArray<UDArchiveEntry *> *)entries toURL:(NSURL *)url error:(NSError **)error;
@end

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
    static NSArray * __strong knownExtensions = nil;
    @synchronized ([UDPK3Codec class]) {
        if (!knownExtensions) {
            knownExtensions = [NSArray arrayWithObjects:@"pak", @"pk3", @"pk4", nil];
        }
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
    unzFile uf = unzOpen(url.path.UTF8String);
    unz_global_info globalInfo;
    if (!uf || unzGetGlobalInfo(uf, &globalInfo) != UNZ_OK) {
        if (uf) {
            unzClose(uf);
        }
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Could not open ZIP archive: %@", url.path];
            *error = [NSError errorWithDomain:UDPK3CodecErrorDomain
                                         code:UDPK3CodecErrorCodeOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return nil;
    }

    NSMutableArray *entries = [NSMutableArray array];

    int status = unzGoToFirstFile(uf);
    for (uLong i = 0; i < globalInfo.number_entry && status == UNZ_OK; i++, status = unzGoToNextFile(uf)) {
        unz_file_info info;
        char nameBuffer[1024];
        if (unzGetCurrentFileInfo(uf, &info, nameBuffer, sizeof(nameBuffer), NULL, 0, NULL, 0) != UNZ_OK) {
            continue;
        }

        /* Names are UTF-8 in practice (and by flag bit 11); anything that
         * is not valid UTF-8 is read as Latin-1 rather than dropped. */
        NSString *entryName = [NSString stringWithUTF8String:nameBuffer];
        if (!entryName) {
            entryName = [NSString stringWithCString:nameBuffer encoding:NSISOLatin1StringEncoding];
        }
        if (entryName.length == 0) {
            continue;
        }

        /* Skip directory entries (trailing slash). */
        if ([entryName hasSuffix:@"/"]) {
            continue;
        }

        /* Normalise backslashes (rare but possible). */
        entryName = [entryName stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

        unsigned long centralDirectoryPosition = 0;
        unzGetCurrentFileInfoPosition(uf, &centralDirectoryPosition);

        uint64_t uncompressedSize = (uint64_t)info.uncompressed_size;

        UDPK3ZIPEntrySource *source = [[UDPK3ZIPEntrySource alloc]
                                        initWithFileURL:url
                               centralDirectoryPosition:centralDirectoryPosition
                                       uncompressedSize:uncompressedSize];

        UDArchiveEntry *entry = [[UDArchiveEntry alloc]
                                  initWithPath:entryName
                                          size:uncompressedSize
                                   contentType:@"application/octet-stream"
                                    modifiedAt:UDDateFromZIPDate(info.tmu_date)
                                        source:source];
        [entries addObject:entry];
    }

    unzClose(uf);

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
    return [self _writeEntries:archive.entries toURL:url error:error];
}

- (BOOL)writeEditedArchive:(UDArchiveEditor *)editor toURL:(NSURL *)url error:(NSError **)error {
    NSArray *diff = editor.currentDiff;
    NSLog(@"ZIP write plan for %@: %lu net mutation(s)", self.formatIdentifier, (unsigned long)diff.count);
    if (diff.count == 0) {
        return [self writeArchive:editor.archive toURL:url error:error];
    }
    return [self _writeEntries:editor.currentEntries toURL:url error:error];
}

- (BOOL)_writeEntries:(NSArray<UDArchiveEntry *> *)entries toURL:(NSURL *)url error:(NSError **)error {
    /* Every payload is read and the archive assembled in memory before url
     * is touched, and the file is then replaced atomically — so saving over
     * the archive the entries are still being read from is safe. */
    UDZipWriter *writer = [[UDZipWriter alloc] init];

    for (UDArchiveEntry *entry in entries) {
        id<UDContentSource> source = entry.contentSource;
        if (!source) {
            if (error) {
                *error = [NSError errorWithDomain:UDPK3CodecErrorDomain
                                             code:UDPK3CodecErrorCodeWriteFailed
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Entry has no content source: %@", entry.path]}];
            }
            return NO;
        }

        NSError *readError = nil;
        NSData *payload = UDReadAllZIPContent(source, &readError);
        if (!payload) {
            if (error) {
                *error = readError;
            }
            return NO;
        }

        if (![writer addEntryWithPath:entry.path
                                 data:payload
                               method:UDZipCompressionMethodAutomatic
                     modificationDate:entry.modifiedAt
                                error:error]) {
            return NO;
        }
    }

    return [writer writeToURL:url error:error];
}

@end
