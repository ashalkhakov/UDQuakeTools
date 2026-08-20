#import "UDToken.h"

@interface UDIdLexer : NSObject

- (instancetype)initWithText:(NSString *)text NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;
- (UDIdToken *)nextToken;

@end
