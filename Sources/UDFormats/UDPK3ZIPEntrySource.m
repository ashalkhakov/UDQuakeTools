#import "UDPK3ZIPEntrySource.h"

#include <zip.h>

static NSString *const UDPK3ZIPEntrySourceErrorDomain = @"com.udquake.error.pk3-zip-entry-source";

typedef NS_ENUM(NSInteger, UDPK3ZIPEntrySourceErrorCode) {
    UDPK3ZIPEntrySourceErrorCodeOutOfBounds  = 1,
    UDPK3ZIPEntrySourceErrorCodeOpenFailed   = 2,
    UDPK3ZIPEntrySourceErrorCodeReadFailed   = 3,
};

@interface UDPK3ZIPEntrySource ()
@property (nonatomic, strong, readonly) NSURL *fileURL;
@property (nonatomic, readonly) uint64_t entryIndex;
@property (nonatomic, readonly) uint64_t uncompressedSize;
@end

@implementation UDPK3ZIPEntrySource

@synthesize fileURL = _fileURL;
@synthesize entryIndex = _entryIndex;
@synthesize uncompressedSize = _uncompressedSize;

- (instancetype)initWithFileURL:(NSURL *)fileURL
                     entryIndex:(uint64_t)entryIndex
               uncompressedSize:(uint64_t)uncompressedSize {
    NSParameterAssert(fileURL != nil);
    self = [super init];
    if (!self) {
        return nil;
    }
    _fileURL = fileURL;
    _entryIndex = entryIndex;
    _uncompressedSize = uncompressedSize;
    return self;
}

- (uint64_t)length {
    return self.uncompressedSize;
}

- (nullable NSData *)readAll:(NSError **)error {
    int zerr = ZIP_ER_OK;
    zip_t *za = zip_open(self.fileURL.path.fileSystemRepresentation, ZIP_RDONLY, &zerr);
    if (!za) {
        if (error) {
            zip_error_t ze;
            zip_error_init_with_code(&ze, zerr);
            NSString *desc = [NSString stringWithFormat:@"Could not open ZIP archive: %s",
                              zip_error_strerror(&ze)];
            zip_error_fini(&ze);
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        return nil;
    }

    zip_file_t *zf = zip_fopen_index(za, (zip_uint64_t)self.entryIndex, 0);
    if (!zf) {
        if (error) {
            NSString *desc = [NSString stringWithFormat:@"Could not open ZIP entry %llu: %s",
                              (unsigned long long)self.entryIndex,
                              zip_strerror(za)];
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeOpenFailed
                                     userInfo:@{NSLocalizedDescriptionKey: desc}];
        }
        zip_close(za);
        return nil;
    }

    NSUInteger totalSize = (NSUInteger)self.uncompressedSize;
    NSMutableData *data = [NSMutableData dataWithLength:totalSize];
    zip_int64_t nread = zip_fread(zf, data.mutableBytes, (zip_uint64_t)totalSize);
    zip_fclose(zf);
    zip_close(za);

    if (nread < 0 || (zip_uint64_t)nread != (zip_uint64_t)totalSize) {
        if (error) {
            *error = [NSError errorWithDomain:UDPK3ZIPEntrySourceErrorDomain
                                         code:UDPK3ZIPEntrySourceErrorCodeReadFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"ZIP entry read returned unexpected byte count."}];
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
