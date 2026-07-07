#import "UDVFSMount.h"

@implementation UDVFSMount

- (instancetype)init {
    self = [self initWithIdentifier:@"empty" kind:UDVFSMountKindDirectory sourceURL:[NSURL fileURLWithPath:@"/dev/null"] virtualRoot:@"empty" priority:0 mountOrder:0];
    [self doesNotRecognizeSelector:_cmd];
    return nil;
}

@synthesize identifier = _identifier;
@synthesize kind = _kind;
@synthesize sourceURL = _sourceURL;
@synthesize virtualRoot = _virtualRoot;
@synthesize priority = _priority;
@synthesize mountOrder = _mountOrder;

- (instancetype)initWithIdentifier:(NSString *)identifier
                              kind:(UDVFSMountKind)kind
                         sourceURL:(NSURL *)sourceURL
                       virtualRoot:(NSString *)virtualRoot
                          priority:(NSInteger)priority
                        mountOrder:(NSUInteger)mountOrder {
    NSParameterAssert(identifier.length > 0);
    NSParameterAssert(sourceURL != nil);

    self = [super init];
    if (!self) {
        return nil;
    }

    _identifier = [identifier copy];
    _kind = kind;
    _sourceURL = sourceURL;
    _virtualRoot = [virtualRoot copy];
    _priority = priority;
    _mountOrder = mountOrder;
    return self;
}

@end
