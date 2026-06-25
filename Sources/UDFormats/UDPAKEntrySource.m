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
    if ((uint64_t)range.location > self.lengthValue || (uint64_t)range.length > self.lengthValue || ((uint64_t)range.location + (uint64_t)range.length) > self.lengthValue) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Requested range is outside entry bounds."}];
        }
        return nil;
    }

    NSData *fileData = [NSData dataWithContentsOfFile:self.fileURL.path];
    if (!fileData) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeUnreadableFile
                                     userInfo:@{NSLocalizedDescriptionKey: @"Unable to read archive file."}];
        }
        return nil;
    }

    NSUInteger readStart = (NSUInteger)(self.offset + (uint64_t)range.location);
    NSUInteger readLength = range.length;
    if (readStart > fileData.length || readLength > (fileData.length - readStart)) {
        if (error) {
            *error = [NSError errorWithDomain:UDPAKEntrySourceErrorDomain
                                         code:UDPAKEntrySourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey: @"Entry points outside archive file bounds."}];
        }
        return nil;
    }

    return [fileData subdataWithRange:NSMakeRange(readStart, readLength)];
}

- (NSData *)readAll:(NSError **)error {
    return [self readRange:NSMakeRange(0, (NSUInteger)self.lengthValue) error:error];
}

@end
