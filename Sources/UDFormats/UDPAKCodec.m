#import "UDPAKCodec.h"

#import "UDArchive.h"
#import "UDArchiveEditor.h"
#import "UDArchiveEntry.h"
#import "UDPAKEntrySource.h"

static NSString *const UDPAKCodecErrorDomain = @"com.udquake.error.pak-codec";

typedef NS_ENUM(NSInteger, UDPAKCodecErrorCode) {
    UDPAKCodecErrorCodeInvalidHeader = 1,
    UDPAKCodecErrorCodeUnsupportedSignature = 2,
    UDPAKCodecErrorCodeCorruptDirectory = 3,
};

/* Reads a 32-bit unsigned integer in little-endian byte order. */
static uint32_t UDReadLEUInt32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0]) | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

/* Writes a 32-bit unsigned integer in little-endian byte order. */
static void UDAppendLEUInt32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4];
    bytes[0] = (uint8_t)(value & 0xFFu);
    bytes[1] = (uint8_t)((value >> 8) & 0xFFu);
    bytes[2] = (uint8_t)((value >> 16) & 0xFFu);
    bytes[3] = (uint8_t)((value >> 24) & 0xFFu);
    [data appendBytes:bytes length:4];
}

static NSData *UDReadAllContent(id<UDContentSource> source, NSError **error) {
    if ([source respondsToSelector:@selector(readAll:)]) {
        NSData *data = [source readAll:error];
        if (data) {
            return data;
        }
    }

    uint64_t len = [source length];
    if (len > NSUIntegerMax) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeCorruptDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"Entry is too large to process on this platform."}];
        }
        return nil;
    }
    return [source readRange:NSMakeRange(0, (NSUInteger)len) error:error];
}

@interface UDPAKCodec ()
- (nullable UDArchive *)archiveFromData:(NSData *)data sourceURL:(NSURL *)sourceURL error:(NSError **)error;
- (BOOL)_writeEntries:(NSArray<UDArchiveEntry *> *)entries toURL:(NSURL *)url error:(NSError **)error;
@end

@implementation UDPAKCodec

- (NSString *)formatIdentifier {
    return @"com.udquake.pak";
}

- (BOOL)canReadURL:(NSURL *)url {
    if (!url) {
        return NO;
    }

    if ([[url.pathExtension lowercaseString] isEqualToString:@"pak"]) {
        return YES;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:url.path];
    if (!handle) {
        return NO;
    }

    NSData *headerData = [handle readDataOfLength:4];
    [handle closeFile];
    if (headerData.length < 4) {
        return NO;
    }

    return (memcmp(headerData.bytes, "PACK", 4) == 0);
}

- (UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:url.path];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read archive file."}];
        }
        return nil;
    }

    return [self archiveFromData:data sourceURL:url error:error];
}

- (BOOL)writeArchive:(UDArchive *)archive toURL:(NSURL *)url error:(NSError **)error {
    return [self _writeEntries:archive.entries toURL:url error:error];
}

- (BOOL)writeEditedArchive:(UDArchiveEditor *)editor toURL:(NSURL *)url error:(NSError **)error {
    return [self _writeEntries:editor.currentEntries toURL:url error:error];
}

- (BOOL)_writeEntries:(NSArray<UDArchiveEntry *> *)entries toURL:(NSURL *)url error:(NSError **)error {
    NSMutableArray<NSData *> *payloads = [NSMutableArray arrayWithCapacity:entries.count];
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:entries.count];
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithCapacity:entries.count];
    NSMutableArray<NSNumber *> *sizes = [NSMutableArray arrayWithCapacity:entries.count];

    uint64_t dataOffset = 12;
    for (UDArchiveEntry *entry in entries) {
        NSString *path = [entry.path stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
        NSData *pathData = [path dataUsingEncoding:NSASCIIStringEncoding];
        if (!pathData || pathData.length > 55) {
            if (error) {
                NSString *reason = pathData
                    ? [NSString stringWithFormat:@"entry path exceeds 55 ASCII bytes (%lu)", (unsigned long)pathData.length]
                    : @"entry path contains non-ASCII characters";
                *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                             code:UDPAKCodecErrorCodeCorruptDirectory
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Cannot save as classic PAK: %@: %@", reason, path]}];
            }
            return NO;
        }

        id<UDContentSource> source = entry.stagedSource ? entry.stagedSource : entry.source;
        if (!source) {
            if (error) {
                *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                             code:UDPAKCodecErrorCodeCorruptDirectory
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Entry has no content source: %@", path]}];
            }
            return NO;
        }

        NSError *readError = nil;
        NSData *payload = UDReadAllContent(source, &readError);
        if (!payload) {
            if (error) {
                *error = readError;
            }
            return NO;
        }

        if (dataOffset > UINT32_MAX || payload.length > UINT32_MAX || dataOffset + payload.length > UINT32_MAX) {
            if (error) {
                *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                             code:UDPAKCodecErrorCodeCorruptDirectory
                                         userInfo:@{NSLocalizedDescriptionKey: @"Archive exceeds classic PAK 4GB limits."}];
            }
            return NO;
        }

        [payloads addObject:payload];
        [paths addObject:path];
        [offsets addObject:@((uint32_t)dataOffset)];
        [sizes addObject:@((uint32_t)payload.length)];
        dataOffset += payload.length;
    }

    uint64_t directoryOffset = dataOffset;
    uint64_t directorySize = (uint64_t)entries.count * 64;
    if (directoryOffset > UINT32_MAX || directorySize > UINT32_MAX) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeCorruptDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"Archive exceeds classic PAK directory limits."}];
        }
        return NO;
    }

    NSMutableData *pakData = [NSMutableData data];
    [pakData appendBytes:"PACK" length:4];
    UDAppendLEUInt32(pakData, (uint32_t)directoryOffset);
    UDAppendLEUInt32(pakData, (uint32_t)directorySize);

    for (NSData *payload in payloads) {
        [pakData appendData:payload];
    }

    for (NSUInteger i = 0; i < paths.count; i++) {
        uint8_t record[64] = {0};
        NSData *pathData = [paths[i] dataUsingEncoding:NSASCIIStringEncoding];
        memcpy(record, pathData.bytes, pathData.length);

        uint32_t fileOffset = (uint32_t)offsets[i].unsignedIntValue;
        uint32_t fileSize = (uint32_t)sizes[i].unsignedIntValue;
        memcpy(record + 56, &fileOffset, 4);
        memcpy(record + 60, &fileSize, 4);
        [pakData appendBytes:record length:sizeof(record)];
    }

    return [pakData writeToURL:url options:NSDataWritingAtomic error:error];
}

- (UDArchive *)archiveFromData:(NSData *)data sourceURL:(NSURL *)sourceURL error:(NSError **)error {
    if (data.length < 12) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"PAK header is too short."}];
        }
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (memcmp(bytes, "PACK", 4) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeUnsupportedSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported archive signature."}];
        }
        return nil;
    }

    uint32_t directoryOffset = UDReadLEUInt32(bytes + 4);
    uint32_t directorySize = UDReadLEUInt32(bytes + 8);

    if ((directorySize % 64) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeCorruptDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"PAK directory size is not a multiple of entry size."}];
        }
        return nil;
    }

    uint64_t directoryEnd = (uint64_t)directoryOffset + (uint64_t)directorySize;
    if (directoryEnd > data.length) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                         code:UDPAKCodecErrorCodeCorruptDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"PAK directory points outside file bounds."}];
        }
        return nil;
    }

    NSMutableArray<UDArchiveEntry *> *entries = [NSMutableArray array];
    NSUInteger count = directorySize / 64;
    NSDate *defaultModifiedAt = [NSDate dateWithTimeIntervalSince1970:0];

    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger rowOffset = (NSUInteger)directoryOffset + index * 64;
        const uint8_t *entryBytes = bytes + rowOffset;

        NSData *nameData = [NSData dataWithBytes:entryBytes length:56];
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSASCIIStringEncoding];
        if (!name) {
            name = @"";
        }

        NSRange nullRange = [name rangeOfString:@"\0"];
        if (nullRange.location != NSNotFound) {
            name = [name substringToIndex:nullRange.location];
        }

        name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

        if (name.length == 0) {
            continue;
        }

        uint32_t fileOffset = UDReadLEUInt32(entryBytes + 56);
        uint32_t fileSize = UDReadLEUInt32(entryBytes + 60);
        uint64_t fileEnd = (uint64_t)fileOffset + (uint64_t)fileSize;
        if (fileEnd > data.length) {
            if (error) {
                *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                             code:UDPAKCodecErrorCodeCorruptDirectory
                                         userInfo:@{NSLocalizedDescriptionKey: @"PAK entry points outside file bounds."}];
            }
            return nil;
        }

        UDPAKEntrySource *source = [[UDPAKEntrySource alloc] initWithFileURL:sourceURL offset:fileOffset length:fileSize];
        UDArchiveEntry *entry = [[UDArchiveEntry alloc] initWithPath:name
                                                                size:fileSize
                                                         contentType:@"application/octet-stream"
                                                         modifiedAt:defaultModifiedAt
                                                              source:source];
        [entries addObject:entry];
    }

    return [[UDArchive alloc] initWithDisplayName:sourceURL.lastPathComponent
                                          entries:entries
                                         metadata:@{
        @"formatIdentifier": self.formatIdentifier,
        @"entryCount": @(entries.count)
    }];
}

@end
