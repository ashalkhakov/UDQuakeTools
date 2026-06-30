/*
 * SPDX-License-Identifier: GPL-2.0-or-later
 */

#import "UDStagedFileSource.h"

static NSString *const UDStagedFileSourceErrorDomain = @"com.udquake.error.staged-file-source";

typedef NS_ENUM(NSInteger, UDStagedFileSourceErrorCode) {
    UDStagedFileSourceErrorCodeUnreadable = 1,
    UDStagedFileSourceErrorCodeOutOfBounds = 2,
};

@implementation UDStagedFileSource

- (instancetype)initWithFileURL:(NSURL *)fileURL {
    NSParameterAssert(fileURL != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _fileURL      = [fileURL copy];
    _cachedLength = 0;
    _lengthLoaded = NO;
    return self;
}

/* ------------------------------------------------------------------ */
#pragma mark - UDContentSource

- (uint64_t)length {
    if (!_lengthLoaded) {
        NSDictionary *attrs = [[NSFileManager defaultManager]
                                attributesOfItemAtPath:_fileURL.path
                                                error:NULL];
        _cachedLength = [[attrs objectForKey:NSFileSize] unsignedLongLongValue];
        _lengthLoaded = YES;
    }
    return _cachedLength;
}

- (nullable NSData *)readRange:(NSRange)range error:(NSError **)error {
    if (range.length == 0) {
        return [NSData data];
    }

    /* Validate the full range against the file size before doing any I/O. */
    uint64_t fileLen = self.length;
    if ((uint64_t)range.location + (uint64_t)range.length > fileLen) {
        if (error) {
            *error = [NSError errorWithDomain:UDStagedFileSourceErrorDomain
                                         code:UDStagedFileSourceErrorCodeOutOfBounds
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Requested range is beyond staged file bounds."}];
        }
        return nil;
    }

    NSFileHandle *handle = [NSFileHandle fileHandleForReadingAtPath:_fileURL.path];
    if (!handle) {
        if (error) {
            *error = [NSError errorWithDomain:UDStagedFileSourceErrorDomain
                                         code:UDStagedFileSourceErrorCodeUnreadable
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Unable to open staged file for reading."}];
        }
        return nil;
    }

    [handle seekToFileOffset:(unsigned long long)range.location];
    NSData *data = [handle readDataOfLength:range.length];
    [handle closeFile];

    return data;
}

- (nullable NSData *)readAll:(NSError **)error {
#ifdef GNUSTEP
    NSData *data = [NSData dataWithContentsOfFile:_fileURL.path];
    if (!data && error) {
        *error = [NSError errorWithDomain:UDStagedFileSourceErrorDomain
                                     code:UDStagedFileSourceErrorCodeUnreadable
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                @"Unable to open staged file for reading."}];
    }
#else
    NSData *data = [NSData dataWithContentsOfFile:_fileURL.path
                                          options:0
                                            error:error];
#endif
    return data;
}

@end
