#import <Foundation/Foundation.h>
#import "UDContentSource.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDArchiveEntry : NSObject {
    NSString *_path;
    NSString *_name;
    uint64_t _size;
    NSString *_contentType;
    NSDate *_modifiedAt;
    id<UDContentSource> _source;
    id<UDContentSource> _stagedSource;
}

@property (nonatomic, readonly, copy) NSString *path;
@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) uint64_t size;
@property (nonatomic, readonly, copy) NSString *contentType;
@property (nonatomic, readonly, copy) NSDate *modifiedAt;
@property (nonatomic, strong, nullable) id<UDContentSource> source;
@property (nonatomic, strong, nullable) id<UDContentSource> stagedSource;

- (instancetype)initWithPath:(NSString *)path
                        size:(uint64_t)size
                 contentType:(NSString *)contentType
                  modifiedAt:(NSDate *)modifiedAt
                      source:(nullable id<UDContentSource>)source NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
