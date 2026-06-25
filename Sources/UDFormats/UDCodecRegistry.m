#import "UDCodecRegistry.h"

@interface UDCodecRegistry ()
@property (nonatomic, strong) NSMutableArray<id<UDArchiveCodec>> *codecs;
@end

@implementation UDCodecRegistry

@synthesize codecs = _codecs;

+ (instancetype)sharedRegistry {
    static UDCodecRegistry *registry;
    @synchronized (self) {
        if (!registry) {
            registry = [[self alloc] init];
        }
        return registry;
    }
}

- (instancetype)init {
    self = [super init];
    if (!self) {
        return nil;
    }

    _codecs = [NSMutableArray array];
    return self;
}

- (void)registerCodec:(id<UDArchiveCodec>)codec {
    if (!codec) {
        return;
    }

    id<UDArchiveCodec> existing = [self codecForFormatIdentifier:codec.formatIdentifier];
    if (!existing) {
        [self.codecs addObject:codec];
    }
}

- (id<UDArchiveCodec>)codecForURL:(NSURL *)url typeName:(NSString *)typeName {
    if (typeName.length > 0) {
        id<UDArchiveCodec> byID = [self codecForFormatIdentifier:typeName];
        if (byID) {
            return byID;
        }
    }

    for (id<UDArchiveCodec> codec in self.codecs) {
        if ([codec canReadURL:url]) {
            return codec;
        }
    }

    return nil;
}

- (id<UDArchiveCodec>)codecForFormatIdentifier:(NSString *)formatIdentifier {
    if (formatIdentifier.length == 0) {
        return nil;
    }

    for (id<UDArchiveCodec> codec in self.codecs) {
        if ([codec.formatIdentifier caseInsensitiveCompare:formatIdentifier] == NSOrderedSame) {
            return codec;
        }
    }

    return nil;
}

@end
