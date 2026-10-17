#import "UDZipWriter.h"

#include <time.h>
#include <zlib.h>

NSString *const UDZipWriterErrorDomain = @"com.udquake.error.zip-writer";

enum {
    UDZipLocalHeaderSignature      = 0x04034b50,
    UDZipCentralHeaderSignature    = 0x02014b50,
    UDZipEndOfCentralDirSignature  = 0x06054b50,
    UDZipVersionNeeded             = 20,          /* 2.0: deflate */
    UDZipVersionMadeBy             = (3 << 8) | 20, /* host: Unix, spec 2.0 */
    UDZipFlagUTF8Names             = 0x0800,
    UDZipMaxEntries                = 0xFFFF,
};

static void UDZipAppend16(NSMutableData *data, uint16_t value) {
    uint8_t bytes[2] = { (uint8_t)value, (uint8_t)(value >> 8) };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static void UDZipAppend32(NSMutableData *data, uint32_t value) {
    uint8_t bytes[4] = { (uint8_t)value, (uint8_t)(value >> 8),
                         (uint8_t)(value >> 16), (uint8_t)(value >> 24) };
    [data appendBytes:bytes length:sizeof(bytes)];
}

static NSError *UDZipError(NSString *description) {
    return [NSError errorWithDomain:UDZipWriterErrorDomain
                               code:1
                           userInfo:@{NSLocalizedDescriptionKey: description}];
}

/* MS-DOS date and time, in local time like every other ZIP tool. */
static void UDZipDOSDateTime(NSDate *date, uint16_t *dosDate, uint16_t *dosTime) {
    time_t seconds = (time_t)(date ?: [NSDate date]).timeIntervalSince1970;
    struct tm local;
    localtime_r(&seconds, &local);
    if (local.tm_year < 80) {
        *dosDate = (1 << 5) | 1; /* 1980-01-01 */
        *dosTime = 0;
        return;
    }
    *dosDate = (uint16_t)(((local.tm_year - 80) << 9) | ((local.tm_mon + 1) << 5) | local.tm_mday);
    *dosTime = (uint16_t)((local.tm_hour << 11) | (local.tm_min << 5) | (local.tm_sec / 2));
}

/* Raw deflate (no zlib header), as ZIP method 8 requires. */
static NSData *UDZipDeflate(NSData *input) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        return nil;
    }
    NSMutableData *output = [NSMutableData dataWithLength:deflateBound(&stream, (uLong)input.length)];
    stream.next_in = (Bytef *)input.bytes;
    stream.avail_in = (uInt)input.length;
    stream.next_out = output.mutableBytes;
    stream.avail_out = (uInt)output.length;
    int status = deflate(&stream, Z_FINISH);
    output.length = stream.total_out;
    deflateEnd(&stream);
    return status == Z_STREAM_END ? output : nil;
}

@implementation UDZipWriter {
    NSMutableData *_body;             /* local headers + entry data */
    NSMutableData *_centralDirectory;
    NSUInteger _entryCount;
}

@synthesize entryCount = _entryCount;

- (instancetype)init {
    self = [super init];
    if (self) {
        _body = [NSMutableData data];
        _centralDirectory = [NSMutableData data];
    }
    return self;
}

- (BOOL)addEntryWithPath:(NSString *)path
                    data:(NSData *)data
                  method:(UDZipCompressionMethod)method
        modificationDate:(NSDate *)modificationDate
                   error:(NSError **)error {
    NSData *name = [path dataUsingEncoding:NSUTF8StringEncoding];
    if (name.length == 0 || name.length > 0xFFFF) {
        if (error) *error = UDZipError([NSString stringWithFormat:@"Invalid ZIP entry name: %@", path]);
        return NO;
    }
    if (_entryCount >= UDZipMaxEntries || data.length > UINT32_MAX) {
        if (error) *error = UDZipError([NSString stringWithFormat:@"%@ would need ZIP64, which is not supported.", path]);
        return NO;
    }

    NSData *payload = data;
    uint16_t zipMethod = UDZipCompressionMethodStored;
    if (method != UDZipCompressionMethodStored) {
        NSData *deflated = UDZipDeflate(data);
        if (deflated == nil) {
            if (error) *error = UDZipError([NSString stringWithFormat:@"Could not deflate %@.", path]);
            return NO;
        }
        if (method == UDZipCompressionMethodDeflated || deflated.length < data.length) {
            payload = deflated;
            zipMethod = UDZipCompressionMethodDeflated;
        }
    }

    uint64_t offset = _body.length;
    if (offset > UINT32_MAX || offset + 30 + name.length + payload.length > UINT32_MAX) {
        if (error) *error = UDZipError(@"The archive would exceed 4 GiB, which needs ZIP64 (not supported).");
        return NO;
    }

    uint32_t crc = (uint32_t)crc32(crc32(0L, Z_NULL, 0), data.bytes, (uInt)data.length);
    uint16_t dosDate, dosTime;
    UDZipDOSDateTime(modificationDate, &dosDate, &dosTime);

    UDZipAppend32(_body, UDZipLocalHeaderSignature);
    UDZipAppend16(_body, UDZipVersionNeeded);
    UDZipAppend16(_body, UDZipFlagUTF8Names);
    UDZipAppend16(_body, zipMethod);
    UDZipAppend16(_body, dosTime);
    UDZipAppend16(_body, dosDate);
    UDZipAppend32(_body, crc);
    UDZipAppend32(_body, (uint32_t)payload.length);
    UDZipAppend32(_body, (uint32_t)data.length);
    UDZipAppend16(_body, (uint16_t)name.length);
    UDZipAppend16(_body, 0);                       /* extra field length */
    [_body appendData:name];
    [_body appendData:payload];

    UDZipAppend32(_centralDirectory, UDZipCentralHeaderSignature);
    UDZipAppend16(_centralDirectory, UDZipVersionMadeBy);
    UDZipAppend16(_centralDirectory, UDZipVersionNeeded);
    UDZipAppend16(_centralDirectory, UDZipFlagUTF8Names);
    UDZipAppend16(_centralDirectory, zipMethod);
    UDZipAppend16(_centralDirectory, dosTime);
    UDZipAppend16(_centralDirectory, dosDate);
    UDZipAppend32(_centralDirectory, crc);
    UDZipAppend32(_centralDirectory, (uint32_t)payload.length);
    UDZipAppend32(_centralDirectory, (uint32_t)data.length);
    UDZipAppend16(_centralDirectory, (uint16_t)name.length);
    UDZipAppend16(_centralDirectory, 0);           /* extra field length */
    UDZipAppend16(_centralDirectory, 0);           /* comment length */
    UDZipAppend16(_centralDirectory, 0);           /* disk number start */
    UDZipAppend16(_centralDirectory, 0);           /* internal attributes */
    UDZipAppend32(_centralDirectory, 0100644u << 16); /* external: -rw-r--r-- */
    UDZipAppend32(_centralDirectory, (uint32_t)offset);
    [_centralDirectory appendData:name];

    _entryCount++;
    return YES;
}

- (NSData *)archiveData {
    NSMutableData *archive = [_body mutableCopy];
    [archive appendData:_centralDirectory];
    UDZipAppend32(archive, UDZipEndOfCentralDirSignature);
    UDZipAppend16(archive, 0);                     /* this disk */
    UDZipAppend16(archive, 0);                     /* disk with the central directory */
    UDZipAppend16(archive, (uint16_t)_entryCount); /* entries on this disk */
    UDZipAppend16(archive, (uint16_t)_entryCount); /* entries in total */
    UDZipAppend32(archive, (uint32_t)_centralDirectory.length);
    UDZipAppend32(archive, (uint32_t)_body.length);
    UDZipAppend16(archive, 0);                     /* comment length */
    return archive;
}

- (BOOL)writeToURL:(NSURL *)url error:(NSError **)error {
    if ((uint64_t)_body.length + _centralDirectory.length + 22 > UINT32_MAX) {
        if (error) *error = UDZipError(@"The archive would exceed 4 GiB, which needs ZIP64 (not supported).");
        return NO;
    }
    return [[self archiveData] writeToURL:url options:NSDataWritingAtomic error:error];
}

@end
