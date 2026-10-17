#import "UDPK3ZIPEntrySource.h"

#include "unzip.h"

static NSString *const UDPK3ZIPEntrySourceErrorDomain = @"com.udquake.error.pk3-zip-entry-source";

typedef NS_ENUM(NSInteger, UDPK3ZIPEntrySourceErrorCode) {
    UDPK3ZIPEntrySourceErrorCodeOutOfBounds  = 1,
    UDPK3ZIPEntrySourceErrorCodeOpenFailed   = 2,
    UDPK3ZIPEntrySourceErrorCodeReadFailed   = 3,
};

@interface UDPK3ZIPEntrySource ()
@property (nonatomic, strong, readonly) NSURL *fileURL;
@property (nonatomic, readonly) unsigned long centralDirectoryPosition;
@property (nonatomic, readonly) uint64_t uncompressedSize;
@end

@implementation UDPK3ZIPEntrySource

@synthesize fileURL = _fileURL;
@synthesize centralDirectoryPosition = _centralDirectoryPosition;
@synthesize uncompressedSize = _uncompressedSize;

- (instancetype)initWithFileURL:(NSURL *)fileURL
       centralDirectoryPosition:(unsigned long)centralDirectoryPosition
               uncompressedSize:(uint64_t)uncompressedSize {
    NSParameterAssert(fileURL != nil);
    self = [super init];
    if (!self) {
        return nil;
    }
    _fileURL = fileURL;
    _centralDirectoryPosition = centralDirectoryPosition;
    _uncompressedSize = uncompressedSize;
    return self;
}

- (uint64_t)length {
    return self.uncompressedSize;
}

- (nullable NSData *)readAll:(NSError **)error {
    unzFile uf = unzOpen(self.fileURL.path.fileSystemRepresentation);
    if (!uf) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Could not open ZIP archive: %@", self.fileURL.path];
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return nil;
    }

    unzSetCurrentFileInfoPosition(uf, self.centralDirectoryPosition);
    if (unzOpenCurrentFile(uf) != UNZ_OK) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Could not open the ZIP entry at central directory offset %lu of %@",
                              self.centralDirectoryPosition, self.fileURL.path];
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        unzClose(uf);
        return nil;
    }

    NSUInteger totalSize = (NSUInteger)self.uncompressedSize;
    NSMutableData *data = [NSMutableData dataWithLength:totalSize];
    NSUInteger filled = 0;
    int nread = 0;
    while (filled < totalSize) {
        unsigned chunk = (unsigned)MIN(totalSize - filled, (NSUInteger)(1u << 30));
        nread = unzReadCurrentFile(uf, (uint8_t *)data.mutableBytes + filled, chunk);
        if (nread <= 0) {
            break;
        }
        filled += (NSUInteger)nread;
    }
    /* unzCloseCurrentFile reports a CRC mismatch once the entry is fully read. */
    int closeStatus = unzCloseCurrentFile(uf);
    unzClose(uf);

    if (nread < 0 || filled != totalSize || closeStatus != UNZ_OK) {
        if (error) {
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeReadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"ZIP entry is truncated or fails its CRC check."}];
        }
        return nil;
    }

    return data;
}

- (nullable NSData *)readRange:(NSRange)range error:(NSError **)error {
    uint64_t rangeStart = (uint64_t)range.location;
    uint64_t rangeLength = (uint64_t)range.length;

    if (rangeStart > UINT64_MAX - rangeLength) {
        if (error) {
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range would overflow."}];
        }
        return nil;
    }

    if (rangeStart + rangeLength > self.uncompressedSize) {
        if (error) {
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range is outside entry bounds."}];
        }
        return nil;
    }

    /* Decompress the whole entry then slice — ZIP DEFLATE streams are not
     * seekable, so there is no cheaper way without caching. */
    NSData *all = [self readAll:error];
    if (!all) {
        return nil;
    }

    return [all subdataWithRange:range];
}

@end
