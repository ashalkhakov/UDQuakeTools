#import "UDDaikatanaPAKCodec.h"
#import "UDArchive.h"
#import "UDArchiveEntry.h"
#import "UDContentSource.h"
#import "UDPAKEntrySource.h"

static NSString *const UDDaikatanaPAKCodecErrorDomain = @"com.udquake.error.daikatana-pak-codec";

typedef NS_ENUM(NSInteger, UDDaikatanaPAKCodecErrorCode) {
    UDDaikatanaPAKCodecErrorCodeInvalidHeader = 1,
    UDDaikatanaPAKCodecErrorCodeUnsupportedSignature = 2,
    UDDaikatanaPAKCodecErrorCodeCorruptDirectory = 3,
    UDDaikatanaPAKCodecErrorCodeCorruptCompressedData = 4,
};

/* Reads a 32-bit unsigned integer in little-endian byte order. */
static uint32_t UDDKReadLEUInt32(const uint8_t *bytes) {
    return ((uint32_t)bytes[0]) | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

@interface UDDaikatanaCompressedSource : NSObject <UDContentSource>

- (instancetype)initWithFileURL:(NSURL *)fileURL
                         offset:(uint64_t)offset
               compressedLength:(uint32_t)compressedLength
             decompressedLength:(uint32_t)decompressedLength NS_DESIGNATED_INITIALIZER;

@end

@interface UDDaikatanaCompressedSource ()

@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, readonly) uint64_t offset;
@property (nonatomic, readonly) uint32_t compressedLength;
@property (nonatomic, readonly) uint32_t decompressedLength;
@property (nonatomic, strong, nullable) NSData *cachedDecodedData;

@end

@implementation UDDaikatanaCompressedSource

@synthesize fileURL = _fileURL;
@synthesize offset = _offset;
@synthesize compressedLength = _compressedLength;
@synthesize decompressedLength = _decompressedLength;
@synthesize cachedDecodedData = _cachedDecodedData;

- (instancetype)initWithFileURL:(NSURL *)fileURL
                         offset:(uint64_t)offset
               compressedLength:(uint32_t)compressedLength
             decompressedLength:(uint32_t)decompressedLength {
    NSParameterAssert(fileURL != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _fileURL = fileURL;
    _offset = offset;
    _compressedLength = compressedLength;
    _decompressedLength = decompressedLength;
    return self;
}

- (uint64_t)length {
    return self.decompressedLength;
}

- (NSData *)readAll:(NSError **)error {
    if (self.cachedDecodedData) {
        return self.cachedDecodedData;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:self.fileURL.path];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read archive file."}];
        }
        return nil;
    }

    [handle seekToFileOffset:(NSUInteger)self.offset];
    NSData *compressedData = [handle readDataOfLength:self.compressedLength];
    [handle closeFile];

    if (compressedData.length != self.compressedLength) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Could not read full compressed Daikatana entry."}];
        }
        return nil;
    }

    NSMutableData *outData = [NSMutableData dataWithLength:self.decompressedLength];
    const uint8_t *inBytes = compressedData.bytes;
    uint8_t *outBytes = outData.mutableBytes;

    NSUInteger read = 0;
    NSUInteger written = 0;

    while (read < compressedData.length) {
        uint8_t x = inBytes[read++];

        if (x < 64) {
            NSUInteger count = (NSUInteger)x + 1;
            if (read + count > compressedData.length || written + count > outData.length) {
                if (error) {
                    *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                                 code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Daikatana compressed stream is malformed."}];
                }
                return nil;
            }
            memcpy(outBytes + written, inBytes + read, count);
            read += count;
            written += count;
        } else if (x < 128) {
            NSUInteger count = (NSUInteger)x - 62;
            if (written + count > outData.length) {
                if (error) {
                    *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                                 code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Daikatana compressed stream overruns output."}];
                }
                return nil;
            }
            memset(outBytes + written, 0, count);
            written += count;
        } else if (x < 192) {
            NSUInteger count = (NSUInteger)x - 126;
            if (read >= compressedData.length || written + count > outData.length) {
                if (error) {
                    *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                                 code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Daikatana compressed stream is malformed."}];
                }
                return nil;
            }
            memset(outBytes + written, inBytes[read], count);
            read += 1;
            written += count;
        } else if (x < 254) {
            NSUInteger count = (NSUInteger)x - 190;
            if (read >= compressedData.length || written + count > outData.length) {
                if (error) {
                    *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                                 code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Daikatana compressed stream is malformed."}];
                }
                return nil;
            }
            NSUInteger back = (NSUInteger)inBytes[read] + 2;
            if (back > written) {
                if (error) {
                    *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                                 code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                             userInfo:@{NSLocalizedDescriptionKey: @"Daikatana back-reference points before output start."}];
                }
                return nil;
            }
            memmove(outBytes + written, outBytes + written - back, count);
            read += 1;
            written += count;
        } else if (x == 255) {
            break;
        }
    }

    if (written != outData.length) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Daikatana compressed stream ended with unexpected output size."}];
        }
        return nil;
    }

    self.cachedDecodedData = outData;
    return self.cachedDecodedData;
}

- (NSData *)readRange:(NSRange)range error:(NSError **)error {
    uint64_t rangeStart = (uint64_t)range.location;
    uint64_t rangeLen = (uint64_t)range.length;
    uint64_t totalLen = self.decompressedLength;

    if (rangeStart > UINT64_MAX - rangeLen || (rangeStart + rangeLen) > totalLen) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeCorruptCompressedData
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range is outside entry bounds."}];
        }
        return nil;
    }

    NSData *all = [self readAll:error];
    if (!all) {
        return nil;
    }
    return [all subdataWithRange:range];
}

@end

@implementation UDDaikatanaPAKCodec

- (NSString *)formatIdentifier {
    return @"com.udquake.daikatana-pak";
}

- (UDArchive *)readArchiveFromURL:(NSURL *)url error:(NSError **)error {
    NSData *data = [NSData dataWithContentsOfFile:url.path];
    if (!data) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read archive file."}];
        }
        return nil;
    }

    if (data.length < 12) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeInvalidHeader
                                     userInfo:@{NSLocalizedDescriptionKey: @"PAK header is too short."}];
        }
        return nil;
    }

    const uint8_t *bytes = data.bytes;
    if (memcmp(bytes, "PACK", 4) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeUnsupportedSignature
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unsupported archive signature."}];
        }
        return nil;
    }

    uint32_t directoryOffset = UDDKReadLEUInt32(bytes + 4);
    uint32_t directorySize = UDDKReadLEUInt32(bytes + 8);
    const uint32_t entrySize = 72;
    const uint32_t nameSize = 56;

    if ((directorySize % entrySize) != 0) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeCorruptDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"Daikatana PAK directory entry size is invalid."}];
        }
        return nil;
    }

    uint64_t directoryEnd = (uint64_t)directoryOffset + (uint64_t)directorySize;
    if (directoryEnd > data.length) {
        if (error) {
            *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                         code:UDDaikatanaPAKCodecErrorCodeCorruptDirectory
                                     userInfo:@{NSLocalizedDescriptionKey: @"PAK directory points outside file bounds."}];
        }
        return nil;
    }

    NSMutableArray<UDArchiveEntry *> *entries = [NSMutableArray array];
    NSUInteger count = directorySize / entrySize;
    NSDate *defaultModifiedAt = [NSDate dateWithTimeIntervalSince1970:0];

    for (NSUInteger index = 0; index < count; index++) {
        NSUInteger rowOffset = (NSUInteger)directoryOffset + index * entrySize;
        const uint8_t *entryBytes = bytes + rowOffset;

        NSData *nameData = [NSData dataWithBytes:entryBytes length:nameSize];
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

        uint32_t fileOffset = UDDKReadLEUInt32(entryBytes + 56);
        uint32_t fileLength = UDDKReadLEUInt32(entryBytes + 60);
        uint32_t compressedLength = UDDKReadLEUInt32(entryBytes + 64);
        uint32_t isCompressed = UDDKReadLEUInt32(entryBytes + 68);

        uint32_t storedLength = isCompressed ? compressedLength : fileLength;
        uint64_t fileEnd = (uint64_t)fileOffset + (uint64_t)storedLength;
        if (fileEnd > data.length) {
            if (error) {
                *error = [NSError errorWithDomain:UDDaikatanaPAKCodecErrorDomain
                                             code:UDDaikatanaPAKCodecErrorCodeCorruptDirectory
                                         userInfo:@{NSLocalizedDescriptionKey: @"PAK entry points outside file bounds."}];
            }
            return nil;
        }

        id<UDContentSource> source = nil;
        if (isCompressed) {
            source = [[UDDaikatanaCompressedSource alloc] initWithFileURL:url
                                                                   offset:fileOffset
                                                         compressedLength:compressedLength
                                                       decompressedLength:fileLength];
        } else {
            source = [[UDPAKEntrySource alloc] initWithFileURL:url offset:fileOffset length:fileLength];
        }

        UDArchiveEntry *entry = [[UDArchiveEntry alloc] initWithPath:name
                                                                size:fileLength
                                                         contentType:@"application/octet-stream"
                                                          modifiedAt:defaultModifiedAt
                                                              source:source];
        [entries addObject:entry];
    }

    NSMutableDictionary<NSString *, id> *meta = [NSMutableDictionary dictionary];
    [meta setObject:self.formatIdentifier forKey:@"formatIdentifier"];
    [meta setObject:@"daikatana" forKey:@"game"];
    [meta setObject:@(entries.count) forKey:@"entryCount"];

    return [[UDArchive alloc] initWithDisplayName:url.lastPathComponent
                                          entries:entries
                                         metadata:meta];
}

@end
