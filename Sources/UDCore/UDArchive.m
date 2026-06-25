#import "UDArchive.h"

@implementation UDArchive

@synthesize displayName = _displayName;
@synthesize entries = _entries;
@synthesize metadata = _metadata;

- (instancetype)initWithDisplayName:(NSString *)displayName
                            entries:(NSArray *)entries
                           metadata:(NSDictionary *)metadata {
    NSParameterAssert(displayName.length > 0);
    NSParameterAssert(entries != nil);
    NSParameterAssert(metadata != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _displayName = [displayName copy];
    _entries = [entries copy];
    _metadata = [metadata copy];

    return self;
}

@end
