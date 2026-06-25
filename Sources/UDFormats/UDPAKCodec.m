#import "UDPAKCodec.h"

#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDPAKEntrySource.h"

static NSString *const UDPAKCodecErrorDomain = @"com.udquake.error.pak-codec";

typedef NS_ENUM(NSInteger, UDPAKCodecErrorCode) {
    UDPAKCodecErrorCodeInvalidHeader = 1,
    UDPAKCodecErrorCodeUnsupportedSignature = 2,
    UDPAKCodecErrorCodeCorruptDirectory = 3,
};

static uint32_t UDReadLEUInt32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0]) | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

@interface UDPAKCodec ()
- (nullable UDArchive *)archiveFromData:(NSData *)data sourceURL:(NSURL *)sourceURL error:(NSError **)error;
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

    NSData *headerData = [NSData dataWithContentsOfFile:url.path];
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
    if (error) {
        *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                     code:NSFeatureUnsupportedError
                                 userInfo:@{NSLocalizedDescriptionKey: @"PAK writing is not implemented yet."}];
    }
    return NO;
}

- (BOOL)writeEditedArchive:(UDArchiveEditor *)editor toURL:(NSURL *)url error:(NSError **)error {
    if (error) {
        *error = [NSError errorWithDomain:UDPAKCodecErrorDomain
                                     code:NSFeatureUnsupportedError
                                 userInfo:@{NSLocalizedDescriptionKey: @"PAK edited-archive writing is not implemented yet."}];
    }
    return NO;
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
    NSDate *now = [NSDate date];

    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger rowOffset = (NSUInteger)directoryOffset + index * 64;
        const uint8_t *entryBytes = bytes + rowOffset;

        NSData *nameData = [NSData dataWithBytes:entryBytes length:56];
        NSString *name = [[NSString alloc] initWithData:nameData encoding:NSASCIIStringEncoding];
        if (!name) {
            name = @"";
        }

        NSRange nulRange = [name rangeOfString:@"\0"];
        if (nulRange.location != NSNotFound) {
            name = [name substringToIndex:nulRange.location];
        }

        name = [[name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];

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
                                                          modifiedAt:now
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
