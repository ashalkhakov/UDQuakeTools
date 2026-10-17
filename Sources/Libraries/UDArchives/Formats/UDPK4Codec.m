#import "UDPK4Codec.h"

@implementation UDPK4Codec

- (NSString *)formatIdentifier {
    return @"com.udquake.pk4";
}

- (NSString *)fileExtension {
    return @"pk4";
}

- (NSString *)gameTag {
    return @"doom3";
}

@end
