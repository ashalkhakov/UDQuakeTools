#import "UDCodecRegistry.h"

@interface UDCodecRegistry ()
@property (nonatomic, strong) NSMutableArray<id<UDArchiveCodec>> *codecs;
 - (void)appendCodecIfNeeded:(id<UDArchiveCodec>)candidate toArray:(NSMutableArray<id<UDArchiveCodec>> *)ordered;
@end

@implementation UDCodecRegistry

@synthesize codecs = _codecs;

+ (instancetype)sharedRegistry {
    static UDCodecRegistry * __strong registry;
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

- (void)appendCodecIfNeeded:(id<UDArchiveCodec>)candidate toArray:(NSMutableArray<id<UDArchiveCodec>> *)ordered {
    if (!candidate) {
        return;
    }
    if ([ordered containsObject:candidate]) {
        return;
    }
    [ordered addObject:candidate];
}

- (NSArray<id<UDArchiveCodec>> *)codecCandidatesForURL:(NSURL *)url typeName:(NSString *)typeName {
    NSMutableArray<id<UDArchiveCodec>> *ordered = [NSMutableArray array];

    if (typeName.length > 0) {
        [self appendCodecIfNeeded:[self codecForFormatIdentifier:typeName] toArray:ordered];
    }

    NSString *path = url.path.lowercaseString;
    NSString *parentDir = [[path stringByDeletingLastPathComponent] lastPathComponent];
    BOOL isPakFile = [url.pathExtension.lowercaseString isEqualToString:@"pak"];

    if (isPakFile) {
        if ([parentDir isEqualToString:@"data"] || [path containsString:@"/daikatana/"]) {
            [self appendCodecIfNeeded:[self codecForFormatIdentifier:@"com.udquake.daikatana-pak"] toArray:ordered];
        }

        if ([parentDir isEqualToString:@"baseq2"] ||
            [parentDir isEqualToString:@"rogue"] ||
            [parentDir isEqualToString:@"xatrix"] ||
            [path containsString:@"/quake2/"]) {
            [self appendCodecIfNeeded:[self codecForFormatIdentifier:@"com.udquake.pak2"] toArray:ordered];
        }
    }

    for (id<UDArchiveCodec> codec in self.codecs) {
        if ([codec canReadURL:url]) {
            [self appendCodecIfNeeded:codec toArray:ordered];
        }
    }

    return [ordered copy];
}

- (id<UDArchiveCodec>)codecForURL:(NSURL *)url typeName:(NSString *)typeName {
    NSArray<id<UDArchiveCodec>> *candidates = [self codecCandidatesForURL:url typeName:typeName];
    if (candidates.count > 0) {
        return [candidates objectAtIndex:0];
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
