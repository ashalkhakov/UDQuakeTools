#import <Foundation/Foundation.h>
#import "UDArchiveCodec.h"

NS_ASSUME_NONNULL_BEGIN

@interface UDCodecRegistry : NSObject {
    NSMutableArray *_codecs;
}
+ (instancetype)sharedRegistry;
- (void)registerCodec:(id<UDArchiveCodec>)codec;
- (NSArray<id<UDArchiveCodec>> *)codecCandidatesForURL:(NSURL *)url typeName:(nullable NSString *)typeName;
- (nullable id<UDArchiveCodec>)codecForURL:(NSURL *)url typeName:(nullable NSString *)typeName;
- (nullable id<UDArchiveCodec>)codecForFormatIdentifier:(NSString *)formatIdentifier;
@end

NS_ASSUME_NONNULL_END
