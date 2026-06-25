#import <Foundation/Foundation.h>
#import "UDContentSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDPAKEntrySource : NSObject <UDContentSource> {
    NSURL *_fileURL;
    uint64_t _offset;
    uint64_t _lengthValue;
}

- (instancetype)init NS_UNAVAILABLE;
+ (instancetype)new NS_UNAVAILABLE;

- (instancetype)initWithFileURL:(NSURL *)fileURL
                         offset:(uint64_t)offset
                         length:(uint64_t)length NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
