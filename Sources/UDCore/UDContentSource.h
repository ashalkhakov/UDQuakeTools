#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@protocol UDContentSource <NSObject>
- (uint64_t)length;
- (nullable NSData *)readRange:(NSRange)range error:(NSError **)error;
@optional
- (nullable NSData *)readAll:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
