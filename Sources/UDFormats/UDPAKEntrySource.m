#import "UDPAKEntrySource.h"

static NSString *const UDPAKEntrySourceErrorDomain = @"com.udquake.error.pak-entry-source";

typedef NS_ENUM(NSInteger, UDPAKEntrySourceErrorCode) {
    UDPAKEntrySourceErrorCodeOutOfBounds = 1,
    UDPAKEntrySourceErrorCodeUnreadableFile = 2,
};

@interface UDPAKEntrySource ()
@property (nonatomic, strong) NSURL *fileURL;
@property (nonatomic, readonly) uint64_t offset;
@property (nonatomic, readonly) uint64_t lengthValue;
@end

@implementation UDPAKEntrySource

@synthesize fileURL = _fileURL;
@synthesize offset = _offset;
@synthesize lengthValue = _lengthValue;

- (instancetype)initWithFileURL:(NSURL *)fileURL
                         offset:(uint64_t)offset
                         length:(uint64_t)length {
    NSParameterAssert(fileURL != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _fileURL = fileURL;
    _offset = offset;
    _lengthValue = length;
    return self;
}

- (uint64_t)length {
    return self.lengthValue;
}

- (NSData *)readRange:(NSRange)range error:(NSError **)error {
    uint64_t rangeStart = (uint64_t)range.location;
    uint64_t rangeLength = (uint64_t)range.length;
    if (rangeStart > UINT64_MAX - rangeLength) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range is outside entry bounds."}];
        }
        return nil;
    }
    uint64_t rangeEnd = rangeStart + rangeLength;
    if (rangeEnd > self.lengthValue) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range is outside entry bounds."}];
        }
        return nil;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:self.fileURL.path];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeUnreadableFile
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read archive file."}];
        }
        return nil;
    }

    if (self.offset > UINT64_MAX - rangeStart) {
        [handle closeFile];
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range exceeds platform limits."}];
        }
        return nil;
    }

    uint64_t absoluteReadStart = self.offset + rangeStart;
    if (absoluteReadStart > NSUIntegerMax || rangeLength > NSUIntegerMax) {
        [handle closeFile];
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range exceeds platform limits."}];
        }
        return nil;
    }

    NSUInteger readStart = (NSUInteger)absoluteReadStart;
    NSUInteger readLength = (NSUInteger)rangeLength;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.fileURL.path error:NULL];
    uint64_t fileLength = [[attributes objectForKey:NSFileSize] unsignedLongLongValue];
    if (readStart > fileLength || readLength > (fileLength - readStart)) {
        [handle closeFile];
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Entry points outside archive file bounds."}];
        }
        return nil;
    }

    [handle seekToFileOffset:readStart];
    NSData *slice = [handle readDataOfLength:readLength];
    [handle closeFile];
    return slice;
}

- (NSData *)readAll:(NSError **)error {
    return [self readRange:NSMakeRange(0, (NSUInteger)self.lengthValue) error:error];
}

@end
